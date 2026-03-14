import SwiftUI

enum SpoolSortOption: String, CaseIterable {
    case vendor = "Vendor"
    case material = "Material"
    case colorName = "Color Name"
}

struct SpoolListView: View {
    var spoolmanService: SpoolmanService
    @Binding var navigationPath: NavigationPath

    @State private var spools: [Spool] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedVendor: String?
    @State private var selectedMaterial: String?
    @State private var sortOption: SpoolSortOption = .vendor
    @State private var showingFilterSheet = false

    private var availableVendors: [String] {
        Set(spools.compactMap(\.vendorName)).sorted()
    }

    private var availableMaterials: [String] {
        Set(spools.compactMap(\.materialName)).sorted()
    }

    private var hasActiveFilters: Bool {
        selectedVendor != nil || selectedMaterial != nil || sortOption != .vendor
    }

    var filteredSpools: [Spool] {
        var result = spools
        if let selectedVendor {
            result = result.filter { $0.vendorName == selectedVendor }
        }
        if let selectedMaterial {
            result = result.filter { $0.materialName == selectedMaterial }
        }
        if !searchText.isEmpty {
            let term = searchText.lowercased()
            result = result.filter { spool in
                (spool.displayName.lowercased().contains(term)) ||
                (spool.vendorName?.lowercased().contains(term) == true) ||
                (spool.materialName?.lowercased().contains(term) == true)
            }
        }
        switch sortOption {
        case .vendor:
            result.sort { ($0.vendorName ?? "") < ($1.vendorName ?? "") }
        case .material:
            result.sort { ($0.materialName ?? "") < ($1.materialName ?? "") }
        case .colorName:
            result.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }
        return result
    }

    var body: some View {
        Group {
            if !spoolmanService.isConfigured {
                ContentUnavailableView(
                    "Spoolman Not Configured",
                    systemImage: "gear",
                    description: Text("Set your Spoolman URL in the Settings tab.")
                )
            } else if isLoading && spools.isEmpty {
                ProgressView("Loading spools...")
            } else if let errorMessage, spools.isEmpty {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") { loadSpools() }
                }
            } else if spools.isEmpty {
                ContentUnavailableView(
                    "No Spools",
                    systemImage: "circle.slash",
                    description: Text("No spools found in Spoolman.")
                )
            } else {
                List(filteredSpools) { spool in
                    Button {
                        navigationPath.append(spool)
                    } label: {
                        SpoolRow(spool: spool)
                    }
                    .tint(.primary)
                }
                .searchable(text: $searchText, prompt: "Filter by name, vendor, or material")
                .refreshable { await refreshSpools() }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingFilterSheet = true
                        } label: {
                            Image(systemName: hasActiveFilters
                                  ? "line.3.horizontal.decrease.circle.fill"
                                  : "line.3.horizontal.decrease.circle")
                        }
                    }
                }
                .sheet(isPresented: $showingFilterSheet) {
                    NavigationStack {
                        Form {
                            Section("Sort By") {
                                Picker("Sort By", selection: $sortOption) {
                                    ForEach(SpoolSortOption.allCases, id: \.self) { option in
                                        Text(option.rawValue).tag(option)
                                    }
                                }
                                .pickerStyle(.inline)
                                .labelsHidden()
                            }
                            Section("Filter") {
                                Picker("Vendor", selection: $selectedVendor) {
                                    Text("All Vendors").tag(String?.none)
                                    ForEach(availableVendors, id: \.self) { vendor in
                                        Text(vendor).tag(Optional(vendor))
                                    }
                                }
                                Picker("Material", selection: $selectedMaterial) {
                                    Text("All Materials").tag(String?.none)
                                    ForEach(availableMaterials, id: \.self) { material in
                                        Text(material).tag(Optional(material))
                                    }
                                }
                            }
                        }
                        .navigationTitle("Sort & Filter")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Reset") {
                                    selectedVendor = nil
                                    selectedMaterial = nil
                                    sortOption = .vendor
                                }
                                .disabled(!hasActiveFilters)
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    showingFilterSheet = false
                                }
                            }
                        }
                    }
                    .presentationDetents([.medium])
                }
            }
        }
        .task { loadSpools() }
    }

    private func loadSpools() {
        guard spoolmanService.isConfigured else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                spools = try await spoolmanService.fetchSpools()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func refreshSpools() async {
        guard spoolmanService.isConfigured else { return }
        do {
            spools = try await spoolmanService.fetchSpools()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SpoolRow: View {
    let spool: Spool

    var body: some View {
        HStack(spacing: 12) {
            // Color swatch
            Circle()
                .fill(Color(hex: spool.colorHex) ?? .gray)
                .frame(width: 32, height: 32)
                .overlay {
                    Circle().stroke(.secondary.opacity(0.3), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(spool.displayName)
                        .font(.body)
                        .fontWeight(.medium)

                    if spool.customInfo != nil {
                        Image(systemName: "link")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }

                HStack(spacing: 8) {
                    if let vendor = spool.vendorName {
                        Text(vendor)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let material = spool.materialName {
                        Text(material)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            if let weight = spool.remainingWeight {
                Text("\(Int(weight))g")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
