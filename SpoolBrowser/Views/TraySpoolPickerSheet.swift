import SwiftUI

/// Sheet for linking a Spoolman spool to an AMS tray that has none bound.
/// Picking a spool activates it on the tray, which moves the Spoolman binding
/// and replaces the tray's settings on the printer with the spool's profile.
struct TraySpoolPickerSheet: View {
    let tray: AMSTray
    /// Trays that already hold a spool, keyed by spool id, shown as a warning
    /// because linking the spool here unlinks it from that tray.
    let boundTrayLabels: [Int: String]
    var spoolmanService: SpoolmanService
    var spoolHelperService: SpoolHelperService

    @Environment(\.dismiss) private var dismiss

    @State private var spools: [Spool] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var linkingSpoolId: Int?
    @State private var linkError: String?

    private var isLinking: Bool { linkingSpoolId != nil }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Link \(tray.label)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .disabled(isLinking)
                    }
                }
                .alert("Couldn't Link Spool", isPresented: Binding(
                    get: { linkError != nil },
                    set: { if !$0 { linkError = nil } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(linkError ?? "")
                }
        }
        .interactiveDismissDisabled(isLinking)
        .task { await loadSpools() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Loading spools...")
        } else if let loadError {
            ContentUnavailableView {
                Label("Error", systemImage: "exclamationmark.triangle")
            } description: {
                Text(loadError)
            } actions: {
                Button("Retry") { Task { await loadSpools() } }
            }
        } else {
            spoolList
        }
    }

    private var spoolList: some View {
        let sections = TraySpoolRanking.sections(
            for: TraySpoolRanking.filter(spools, searchText: searchText),
            tray: tray
        )

        return List {
            Section {
                ForEach(sections.suggested) { spoolRow($0) }
            } header: {
                if !sections.suggested.isEmpty { Text("Suggested") }
            }

            Section {
                ForEach(sections.others) { spoolRow($0) }
            } header: {
                if !sections.others.isEmpty { Text("Other Spools") }
            } footer: {
                Text("Linking also sends the spool's profile and color to the printer, replacing what \(tray.label) reports now.")
            }
        }
        .overlay {
            if sections.suggested.isEmpty && sections.others.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .searchable(text: $searchText, prompt: "Search spools")
    }

    private func spoolRow(_ spool: Spool) -> some View {
        let isLinkable = TraySpoolRanking.canActivate(spool)

        return Button {
            link(spool)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hex: spool.colorHex) ?? Color.clear)
                    .frame(width: 28, height: 28)
                    .overlay {
                        Circle().stroke(.secondary.opacity(0.3), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(spool.displayName)
                        .foregroundStyle(isLinkable ? .primary : .secondary)
                    Text(detailText(for: spool))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !isLinkable {
                        Text(spool.customInfo == nil
                            ? "No slicer profile. Link one from the spool's page first."
                            : "Slicer profile has no material type. Link it again from the spool's page.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if let label = boundTrayLabels[spool.id] {
                        Text("Currently in \(label). Linking here moves it.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Spacer()

                if linkingSpoolId == spool.id {
                    ProgressView()
                } else if let remaining = spool.remainingWeight {
                    Text("\(Int(remaining)) g")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(!isLinkable || isLinking)
    }

    private func detailText(for spool: Spool) -> String {
        let parts = [spool.displayNumber, spool.vendorName, spool.materialName]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    private func loadSpools() async {
        isLoading = true
        defer { isLoading = false }
        do {
            spools = try await spoolmanService.fetchSpools()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func link(_ spool: Spool) {
        linkingSpoolId = spool.id
        Task {
            do {
                _ = try await spoolHelperService.activate(spool: spool, tray: tray.tray)
                dismiss()
            } catch {
                linkError = error.localizedDescription
            }
            linkingSpoolId = nil
        }
    }
}

// MARK: - Ranking

/// Kept outside the view so the ranking isn't main-actor isolated.
enum TraySpoolRanking {
    struct Sections: Equatable {
        let suggested: [Spool]
        let others: [Spool]
    }

    /// Maximum RGB distance for a spool's color to count as the tray's color.
    /// Generous enough to absorb the difference between an RFID-reported color
    /// and a hand-entered Spoolman one.
    private static let colorMatchThreshold = 60.0

    /// Splits spools into those matching the tray's material and color, closest
    /// color first, and the rest with the tray's material first. Within each
    /// group, spools that can't be activated sort last.
    static func sections(for spools: [Spool], tray: AMSTray) -> Sections {
        let candidates = spools.filter { $0.archived != true }

        let suggested = candidates
            .filter { isSuggested($0, for: tray) }
            .sorted { lhs, rhs in
                let lhsKey = (canActivate(lhs) ? 0 : 1, colorDistance(lhs.colorHex, tray.trayColor) ?? .infinity)
                let rhsKey = (canActivate(rhs) ? 0 : 1, colorDistance(rhs.colorHex, tray.trayColor) ?? .infinity)
                return lhsKey < rhsKey
            }

        let others = candidates
            .filter { !isSuggested($0, for: tray) }
            .sorted { lhs, rhs in
                let lhsKey = (canActivate(lhs) ? 0 : 1, matchesMaterial(lhs, tray: tray) ? 0 : 1)
                let rhsKey = (canActivate(rhs) ? 0 : 1, matchesMaterial(rhs, tray: tray) ? 0 : 1)
                if lhsKey != rhsKey { return lhsKey < rhsKey }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }

        return Sections(suggested: suggested, others: others)
    }

    /// The helper's `/activate` needs both a filament id and a material type.
    static func canActivate(_ spool: Spool) -> Bool {
        guard let info = spool.customInfo else { return false }
        return !info.trayType.trimmingCharacters(in: .whitespaces).isEmpty
    }

    static func filter(_ spools: [Spool], searchText: String) -> [Spool] {
        let term = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !term.isEmpty else { return spools }
        return spools.filter { spool in
            [spool.displayName, spool.displayNumber, spool.vendorName, spool.materialName]
                .compactMap { $0?.lowercased() }
                .contains { $0.contains(term) }
        }
    }

    /// Euclidean RGB distance between two hex colors, ignoring any leading `#`
    /// or alpha suffix. Nil when either color can't be parsed.
    static func colorDistance(_ first: String?, _ second: String?) -> Double? {
        guard let first = rgbComponents(first), let second = rgbComponents(second) else { return nil }
        let red = first.0 - second.0
        let green = first.1 - second.1
        let blue = first.2 - second.2
        return (red * red + green * green + blue * blue).squareRoot()
    }

    private static func isSuggested(_ spool: Spool, for tray: AMSTray) -> Bool {
        guard matchesMaterial(spool, tray: tray),
              let distance = colorDistance(spool.colorHex, tray.trayColor) else { return false }
        return distance <= colorMatchThreshold
    }

    private static func matchesMaterial(_ spool: Spool, tray: AMSTray) -> Bool {
        let material = spool.customInfo?.trayType ?? spool.materialName ?? ""
        return !material.isEmpty && material.caseInsensitiveCompare(tray.trayType) == .orderedSame
    }

    private static func rgbComponents(_ hex: String?) -> (Double, Double, Double)? {
        guard let hex else { return nil }
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6 || cleaned.count == 8,
              let value = UInt64(cleaned.prefix(6), radix: 16) else { return nil }
        return (
            Double((value >> 16) & 0xFF),
            Double((value >> 8) & 0xFF),
            Double(value & 0xFF)
        )
    }
}
