import SwiftUI

struct AMSView: View {
    var spoolmanService: SpoolmanService
    var spoolHelperService: SpoolHelperService
    var labelPrinterService: LabelPrinterService

    @State private var amsState: AMSState?
    @State private var spoolsById: [Int: Spool] = [:]
    @State private var isLoading = false
    @State private var needsReload = false
    @State private var errorMessage: String?
    @State private var navigationPath = NavigationPath()
    @State private var trayToLink: AMSTray?

    /// Physical AMS Lite arrangement: A1 and A4 on top, A2 and A3 below.
    private static let slotOrder = [0, 3, 1, 2]

    var body: some View {
        NavigationStack(path: $navigationPath) {
            content
                .navigationTitle("AMS")
                .navigationDestination(for: Spool.self) { spool in
                    SpoolDetailView(
                        spool: spool,
                        spoolmanService: spoolmanService,
                        spoolHelperService: spoolHelperService,
                        labelPrinterService: labelPrinterService
                    )
                }
        }
        .task { await load() }
        // Reload however the sheet closes: a failed activation can still have
        // moved the Spoolman binding before the printer command was rejected.
        .sheet(item: $trayToLink, onDismiss: { Task { await load() } }) { tray in
            TraySpoolPickerSheet(
                tray: tray,
                boundTrayLabels: boundTrayLabels,
                spoolmanService: spoolmanService,
                spoolHelperService: spoolHelperService
            )
        }
    }

    private var boundTrayLabels: [Int: String] {
        var labels: [Int: String] = [:]
        for tray in amsState?.trays ?? [] {
            if let spoolId = tray.spoolId {
                labels[spoolId] = tray.label
            }
        }
        return labels
    }

    @ViewBuilder
    private var content: some View {
        if !spoolHelperService.isAvailable {
            ContentUnavailableView(
                "Spool Helper Not Configured",
                systemImage: "gear",
                description: Text("Set the bambu-spool-helper address in the Settings tab.")
            )
        } else if let errorMessage, amsState == nil {
            ContentUnavailableView {
                Label("Error", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Retry") { Task { await load() } }
            }
        } else if let amsState {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusLine(for: amsState)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(Self.slotOrder, id: \.self) { index in
                            if let tray = amsState.trays.first(where: { $0.tray == index }) {
                                slotCell(for: tray, in: amsState)
                            }
                        }
                    }

                    if let external = amsState.trays.first(where: \.isExternal), !external.empty {
                        Text("External")
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)

                        externalCell(for: external, in: amsState)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .refreshable { await load() }
        } else {
            ProgressView("Loading AMS...")
        }
    }

    private func statusLine(for state: AMSState) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.connected ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(statusText(for: state))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func statusText(for state: AMSState) -> String {
        guard state.connected else { return "Printer not reachable" }
        if let printerState = state.printerState, !printerState.isEmpty {
            return "Connected · \(printerState)"
        }
        return "Connected"
    }

    @ViewBuilder
    private func slotCell(for tray: AMSTray, in state: AMSState) -> some View {
        let spool = tray.spoolId.flatMap { spoolsById[$0] }
        let isActive = state.activeTray == tray.tray

        if let spool {
            Button {
                navigationPath.append(spool)
            } label: {
                AMSSlotCard(tray: tray, spool: spool, isActive: isActive)
            }
            .buttonStyle(.plain)
        } else if canLink(tray) {
            Button {
                trayToLink = tray
            } label: {
                AMSSlotCard(tray: tray, spool: nil, isActive: isActive)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Links a spool to this tray")
        } else {
            AMSSlotCard(tray: tray, spool: nil, isActive: isActive)
        }
    }

    @ViewBuilder
    private func externalCell(for tray: AMSTray, in state: AMSState) -> some View {
        let spool = tray.spoolId.flatMap { spoolsById[$0] }
        let isActive = state.activeTray == tray.tray

        if let spool {
            Button {
                navigationPath.append(spool)
            } label: {
                AMSExternalCard(tray: tray, spool: spool, isActive: isActive)
            }
            .buttonStyle(.plain)
        } else if canLink(tray) {
            Button {
                trayToLink = tray
            } label: {
                AMSExternalCard(tray: tray, spool: nil, isActive: isActive)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Links a spool to this tray")
        } else {
            AMSExternalCard(tray: tray, spool: nil, isActive: isActive)
        }
    }

    private func canLink(_ tray: AMSTray) -> Bool {
        // A bound tray whose spool hasn't resolved (still loading, or Spoolman
        // failed) must not offer linking: picking a spool would replace the binding.
        !tray.empty && tray.spoolId == nil && spoolmanService.isConfigured
    }

    private func load() async {
        guard spoolHelperService.isAvailable else { return }
        // An in-flight load may hold a snapshot from before a link, so run again
        // after it rather than dropping this request.
        guard !isLoading else {
            needsReload = true
            return
        }
        isLoading = true
        defer { isLoading = false }
        repeat {
            needsReload = false
            await fetchState()
        } while needsReload
    }

    private func fetchState() async {
        do {
            let state = try await spoolHelperService.fetchAMSState()
            amsState = state
            errorMessage = nil

            let boundIds = Set(state.trays.compactMap(\.spoolId))
            if !boundIds.isEmpty, spoolmanService.isConfigured {
                let spools = try await spoolmanService.fetchSpools()
                spoolsById = Dictionary(
                    uniqueKeysWithValues: spools.filter { boundIds.contains($0.id) }.map { ($0.id, $0) }
                )
            } else {
                spoolsById = [:]
            }
        } catch is CancellationError {
            // Tab switched away mid-load; the next appearance reloads.
        } catch let error as URLError where error.code == .cancelled {
            // Same as above — URLSession surfaces task cancellation this way.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Cards

private struct AMSSlotCard: View {
    let tray: AMSTray
    let spool: Spool?
    let isActive: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(tray.label)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(isActive ? Color.accentColor : Color(.tertiaryLabel))
                Spacer()
                if let spool {
                    HStack(spacing: 3) {
                        Image(systemName: "link")
                            .font(.system(size: 8))
                            .foregroundStyle(.blue)
                        Text(spool.displayNumber)
                            .foregroundStyle(.tertiary)
                    }
                    .font(.caption2)
                } else if !tray.empty {
                    Image(systemName: "link.slash")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            if tray.empty {
                Spacer()
                AMSSwatch(colorHex: nil, size: 52)
                Text("Empty")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            } else {
                AMSSwatch(colorHex: swatchHex, size: 52)

                // Reserve the name and vendor rows even when they're short or
                // missing so every card in the grid lays out identically.
                VStack(spacing: 1) {
                    Text(displayName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .lineLimit(2, reservesSpace: true)

                    Text(spool?.vendorName ?? " ")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !tray.trayType.isEmpty {
                    Text(tray.trayType)
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }

                AMSRemainBar(fraction: remainingFraction, colorHex: swatchHex)

                Text(remainingText)
                    .font(.caption2)
                    .foregroundStyle(spool == nil ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 160)
        .frame(maxHeight: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .amsActiveHighlight(isActive)
    }

    private var swatchHex: String? {
        spool?.colorHex ?? (tray.trayColor.isEmpty ? nil : tray.trayColor)
    }

    private var displayName: String {
        if let spool { return spool.displayName }
        if !tray.traySubBrands.isEmpty { return tray.traySubBrands }
        return tray.trayType
    }

    private var remainingFraction: Double? {
        if let spool, let remaining = spool.remainingWeight,
           let total = spool.filament?.weight, total > 0 {
            return min(max(remaining / total, 0), 1)
        }
        if tray.remain >= 0 {
            return Double(tray.remain) / 100
        }
        return nil
    }

    private var remainingText: String {
        if let spool {
            if let remaining = spool.remainingWeight {
                return "\(Int(remaining)) g left"
            }
            return " "
        }
        if tray.remain >= 0 {
            return "Not linked · \(tray.remain)%"
        }
        return "Not linked"
    }
}

private struct AMSExternalCard: View {
    let tray: AMSTray
    let spool: Spool?
    let isActive: Bool

    var body: some View {
        HStack(spacing: 10) {
            AMSSwatch(colorHex: swatchHex, size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.footnote)
                    .fontWeight(.semibold)
                if let vendor = spool?.vendorName {
                    Text(vendor)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    if !tray.trayType.isEmpty {
                        Text(tray.trayType)
                            .font(.caption2)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                    if let spool {
                        HStack(spacing: 3) {
                            Image(systemName: "link")
                                .font(.system(size: 8))
                                .foregroundStyle(.blue)
                            Text(spool.displayNumber)
                                .foregroundStyle(.tertiary)
                        }
                        .font(.caption2)
                    } else {
                        HStack(spacing: 3) {
                            Image(systemName: "link.slash")
                            Text("Not linked")
                        }
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            Text(remainingText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .amsActiveHighlight(isActive)
    }

    private var swatchHex: String? {
        spool?.colorHex ?? (tray.trayColor.isEmpty ? nil : tray.trayColor)
    }

    private var displayName: String {
        if let spool { return spool.displayName }
        if !tray.traySubBrands.isEmpty { return tray.traySubBrands }
        return tray.trayType.isEmpty ? "External Spool" : tray.trayType
    }

    private var remainingText: String {
        if let spool, let remaining = spool.remainingWeight {
            return "\(Int(remaining)) g"
        }
        if tray.remain >= 0 {
            return "\(tray.remain)%"
        }
        return ""
    }
}

// MARK: - Shared pieces

private struct AMSSwatch: View {
    let colorHex: String?
    let size: CGFloat

    var body: some View {
        if let color = Color(hex: colorHex) {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .overlay {
                    Circle().stroke(.secondary.opacity(0.3), lineWidth: 1)
                }
                .overlay {
                    Circle()
                        .fill(Color(.secondarySystemGroupedBackground))
                        .frame(width: size * 0.42, height: size * 0.42)
                        .overlay {
                            Circle().stroke(.secondary.opacity(0.25), lineWidth: 1)
                        }
                }
        } else {
            Circle()
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                .foregroundStyle(.tertiary)
                .frame(width: size, height: size)
        }
    }
}

private struct AMSRemainBar: View {
    let fraction: Double?
    let colorHex: String?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                if let fraction {
                    Capsule()
                        .fill(Color(hex: colorHex) ?? Color.accentColor)
                        .frame(width: max(geometry.size.width * fraction, 4))
                }
            }
        }
        .frame(height: 4)
    }
}

private struct AMSActiveHighlight: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.accentColor, lineWidth: 2)
                }
            }
            .overlay(alignment: .top) {
                if isActive {
                    Label("In Use", systemImage: "arrow.down.to.line")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                        .offset(y: -9)
                }
            }
    }
}

private extension View {
    func amsActiveHighlight(_ isActive: Bool) -> some View {
        modifier(AMSActiveHighlight(isActive: isActive))
    }
}
