import SwiftUI

struct ProfilePickerSheet: View {
    let filamentId: Int
    var spoolmanService: SpoolmanService
    var spoolHelperService: SpoolHelperService
    var onLinked: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showManualEntry = false
    @State private var profiles: [FilamentProfile] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var isLinking = false
    @State private var linkError: String?

    // Manual entry fields
    @State private var manualAmsFilamentId = ""
    @State private var manualFilamentType = "PLA"
    @State private var manualTempMin = ""
    @State private var manualTempMax = ""

    private var helperAvailable: Bool {
        spoolHelperService.isAvailable
    }

    var body: some View {
        NavigationStack {
            Group {
                if showManualEntry || !helperAvailable {
                    manualEntryForm
                } else {
                    profileSearchList
                }
            }
            .navigationTitle("Link Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if helperAvailable {
                    ToolbarItem(placement: .primaryAction) {
                        Button(showManualEntry ? "Search" : "Manual") {
                            showManualEntry.toggle()
                        }
                    }
                }
            }
            .alert("Link Error", isPresented: Binding(
                get: { linkError != nil },
                set: { if !$0 { linkError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(linkError ?? "")
            }
        }
    }

    // MARK: - Search Mode

    private var profileSearchList: some View {
        List {
            if isLoading && profiles.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if let error = loadError {
                Text(error)
                    .foregroundStyle(.secondary)
            } else if profiles.isEmpty && !searchText.isEmpty {
                Text("No profiles found")
                    .foregroundStyle(.secondary)
            } else {
                let userProfiles = profiles.filter { $0.source == "user" }
                let systemProfiles = profiles.filter { $0.source != "user" }

                if !userProfiles.isEmpty {
                    Section("User Profiles") {
                        ForEach(userProfiles) { profile in
                            profileRow(profile)
                        }
                    }
                }

                if !systemProfiles.isEmpty {
                    Section("System Profiles") {
                        ForEach(systemProfiles) { profile in
                            profileRow(profile)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search profiles")
        .task { await loadProfiles() }
        .onChange(of: searchText) { _, _ in
            Task { await loadProfiles() }
        }
        .overlay {
            if isLinking {
                ProgressView("Linking…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func profileRow(_ profile: FilamentProfile) -> some View {
        Button {
            linkProfile(profile)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                HStack(spacing: 12) {
                    Text(profile.filamentType)
                    Text(profile.trayInfoIdx)
                    Text("Nozzle \(profile.nozzleTempMin)-\(profile.nozzleTempMax)\u{00B0}C")
                    if profile.bedTempMin > 0 {
                        Text("Bed \(profile.bedTempMin)-\(profile.bedTempMax)\u{00B0}C")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
        .disabled(isLinking)
    }

    // MARK: - Manual Entry Mode

    private var manualEntryForm: some View {
        Form {
            Section("Profile Fields") {
                TextField("AMS Filament ID", text: $manualAmsFilamentId)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("Filament Type (e.g. PLA)", text: $manualFilamentType)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                TextField("Nozzle Temp Min", text: $manualTempMin)
                    .keyboardType(.numberPad)
                TextField("Nozzle Temp Max", text: $manualTempMax)
                    .keyboardType(.numberPad)
            }

            Section {
                Button {
                    linkManual()
                } label: {
                    HStack {
                        Spacer()
                        if isLinking {
                            ProgressView()
                        } else {
                            Text("Link")
                        }
                        Spacer()
                    }
                }
                .disabled(!manualEntryValid || isLinking)
            }
        }
    }

    private var manualEntryValid: Bool {
        !manualAmsFilamentId.isEmpty
        && !manualFilamentType.isEmpty
        && Int(manualTempMin) != nil
        && Int(manualTempMax) != nil
    }

    // MARK: - Actions

    private func loadProfiles() async {
        isLoading = true
        loadError = nil
        do {
            profiles = try await spoolHelperService.fetchProfiles(search: searchText)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func linkProfile(_ profile: FilamentProfile) {
        isLinking = true
        Task {
            do {
                try await spoolmanService.ensureExtraFields()
                try await spoolmanService.linkFilament(id: filamentId, profile: profile)
                onLinked()
                dismiss()
            } catch {
                linkError = error.localizedDescription
            }
            isLinking = false
        }
    }

    private func linkManual() {
        guard let tempMin = Int(manualTempMin),
              let tempMax = Int(manualTempMax) else { return }
        isLinking = true
        Task {
            do {
                try await spoolmanService.ensureExtraFields()
                try await spoolmanService.linkFilamentManual(
                    id: filamentId,
                    amsFilamentId: manualAmsFilamentId,
                    nozzleTempMin: tempMin,
                    nozzleTempMax: tempMax,
                    filamentType: manualFilamentType
                )
                onLinked()
                dismiss()
            } catch {
                linkError = error.localizedDescription
            }
            isLinking = false
        }
    }
}
