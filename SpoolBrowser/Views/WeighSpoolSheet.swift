import SwiftUI

/// Sheet for updating a spool's remaining weight from a scale reading.
/// The user types the gross weight (filament + empty spool); the empty-spool
/// weight is subtracted live. All three values are editable — editing any one
/// keeps the others consistent.
struct WeighSpoolSheet: View {
    let spool: Spool
    var spoolmanService: SpoolmanService
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var grossText = ""
    @State private var emptyText: String
    @State private var remainingText = ""
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showSpoolWeightConfirm = false

    @FocusState private var focusedField: Field?

    private enum Field {
        case gross, empty, remaining
    }

    /// Typical empty-spool weights for quick entry.
    private static let spoolPresets: [(name: String, grams: Double)] = [
        ("Bambu Lab", 250),
        ("Sunlu", 135),
        ("eSun", 224),
    ]

    init(spool: Spool, spoolmanService: SpoolmanService, onSaved: @escaping () -> Void) {
        self.spool = spool
        self.spoolmanService = spoolmanService
        self.onSaved = onSaved
        if let spoolWeight = spool.filament?.spoolWeight {
            self._emptyText = State(initialValue: Self.formatWeight(spoolWeight))
        } else {
            self._emptyText = State(initialValue: "")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(hex: spool.colorHex) ?? .gray)
                            .frame(width: 34, height: 34)
                            .overlay {
                                Circle().stroke(.secondary.opacity(0.3), lineWidth: 1)
                            }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(spool.displayName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    weightRow("Weight with spool", text: $grossText, field: .gross)
                } header: {
                    Text("Scale Reading")
                } footer: {
                    Text("Place the whole spool on a scale and enter the total shown.")
                }

                Section {
                    HStack {
                        Text("Empty spool")
                            .foregroundStyle(.secondary)
                        if emptyValue == nil {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        weightField(text: $emptyText, field: .empty)
                    }

                    HStack(spacing: 8) {
                        ForEach(Self.spoolPresets, id: \.name) { preset in
                            Button {
                                applyPreset(preset.grams)
                            } label: {
                                Text("\(preset.name) \(Self.formatWeight(preset.grams))g")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                        }
                    }
                    .listRowSeparator(.hidden, edges: .top)

                    HStack {
                        Text("Filament remaining")
                            .fontWeight(.semibold)
                        weightField(text: $remainingText, field: .remaining)
                            .fontWeight(.semibold)
                            .foregroundStyle(remainingValue != nil ? Color.green : Color.primary)
                    }

                    if let change = changeText {
                        LabeledContent("Change", value: change)
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if grossBelowEmpty {
                            Text("Scale reading is less than the empty spool weight.")
                                .foregroundStyle(.red)
                        }
                        if let overfill = overfillWarning {
                            Text(overfill)
                                .foregroundStyle(.orange)
                        }
                        if emptyValue == nil {
                            Text("Empty spool weight is not set. Enter it or pick a preset to compute remaining filament from the scale reading.")
                        }
                        if let saveError {
                            Text(saveError)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("Weigh Spool")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { saveTapped() }
                            .fontWeight(.semibold)
                            .disabled(!canSave)
                    }
                }
            }
            .onChange(of: grossText) { syncFields(edited: .gross) }
            .onChange(of: emptyText) { syncFields(edited: .empty) }
            .onChange(of: remainingText) { syncFields(edited: .remaining) }
            .confirmationDialog(
                "Empty Spool Weight Changed",
                isPresented: $showSpoolWeightConfirm,
                titleVisibility: .visible
            ) {
                if remainingValue != nil {
                    Button("Save & Update Filament") { performSave(updateFilament: true) }
                    Button("Save, Keep Filament Unchanged") { performSave(updateFilament: false) }
                } else {
                    Button("Update Filament") { performSave(updateFilament: true) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(spoolWeightConfirmMessage)
            }
            .task { focusedField = .gross }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Rows

    private func weightRow(_ label: String, text: Binding<String>, field: Field) -> some View {
        HStack {
            Text(label)
            weightField(text: text, field: field)
        }
    }

    private func weightField(text: Binding<String>, field: Field) -> some View {
        HStack(spacing: 4) {
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($focusedField, equals: field)
            Text("g")
                .foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let vendor = spool.vendorName { parts.append(vendor) }
        if let material = spool.materialName { parts.append(material) }
        parts.append(spool.displayNumber)
        return parts.joined(separator: " · ")
    }

    // MARK: - Derived values

    private var grossValue: Double? { Self.parseWeight(grossText) }
    private var emptyValue: Double? { Self.parseWeight(emptyText) }
    private var remainingValue: Double? { Self.parseWeight(remainingText) }

    private var grossBelowEmpty: Bool {
        guard let gross = grossValue, let empty = emptyValue else { return false }
        return gross < empty
    }

    private var emptyChanged: Bool {
        emptyValue != spool.filament?.spoolWeight
    }

    private var overfillWarning: String? {
        guard let remaining = remainingValue,
              let net = spool.filament?.weight, net > 0, remaining > net
        else { return nil }
        return "More than the filament's net weight (\(Self.formatWeight(net)) g)."
    }

    private var changeText: String? {
        guard let remaining = remainingValue, let current = spool.remainingWeight else { return nil }
        let delta = remaining - current
        let sign = delta >= 0 ? "+" : "−"
        var text = "\(sign)\(Self.formatWeight(abs(delta))) g"
        if let net = spool.filament?.weight, net > 0 {
            text += " · \(Int((remaining / net * 100).rounded()))% of \(Self.formatWeight(net)) g"
        }
        return text
    }

    private var canSave: Bool {
        guard !isSaving, !grossBelowEmpty else { return false }
        if remainingValue != nil { return true }
        return emptyChanged && emptyValue != nil
    }

    // MARK: - Field synchronization

    /// Keeps gross − empty = remaining, propagating away from the field the
    /// user is editing. Guarded by focus so programmatic updates don't loop.
    private func syncFields(edited: Field) {
        guard focusedField == edited else { return }
        switch edited {
        case .gross, .empty:
            if let gross = grossValue, let empty = emptyValue {
                remainingText = gross >= empty ? Self.formatWeight(gross - empty) : ""
            } else if edited == .gross && grossText.isEmpty {
                remainingText = ""
            }
        case .remaining:
            if let remaining = remainingValue, let empty = emptyValue {
                grossText = Self.formatWeight(remaining + empty)
            } else if remainingText.isEmpty {
                grossText = ""
            }
        }
    }

    // MARK: - Presets

    /// Fills the empty-spool field and re-derives the dependent value directly
    /// (the focus-guarded onChange sync doesn't run for programmatic edits).
    private func applyPreset(_ grams: Double) {
        emptyText = Self.formatWeight(grams)
        if let gross = grossValue {
            remainingText = gross >= grams ? Self.formatWeight(gross - grams) : ""
        } else if let remaining = remainingValue {
            grossText = Self.formatWeight(remaining + grams)
        }
    }

    // MARK: - Saving

    private var spoolWeightConfirmMessage: String {
        let value = emptyValue.map(Self.formatWeight) ?? ""
        return "Update this filament's empty spool weight to \(value) g in Spoolman? "
            + "It applies to all spools of this filament. "
            + "Keep it unchanged if this filament just sits on a different physical spool (e.g. a refill)."
    }

    private func saveTapped() {
        guard canSave else { return }
        if emptyChanged, emptyValue != nil, spool.filament?.id != nil {
            showSpoolWeightConfirm = true
        } else {
            performSave(updateFilament: false)
        }
    }

    private func performSave(updateFilament: Bool) {
        isSaving = true
        saveError = nil
        Task {
            do {
                if let remaining = remainingValue {
                    try await spoolmanService.updateSpoolRemainingWeight(id: spool.id, remainingWeight: remaining)
                }
                if updateFilament, let empty = emptyValue, let filamentId = spool.filament?.id {
                    try await spoolmanService.updateFilamentSpoolWeight(id: filamentId, spoolWeight: empty)
                }
                onSaved()
                dismiss()
            } catch {
                saveError = error.localizedDescription
                isSaving = false
            }
        }
    }

    // MARK: - Parsing & formatting

    static func parseWeight(_ text: String) -> Double? {
        let normalized = text
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty, let value = Double(normalized), value.isFinite, value >= 0 else {
            return nil
        }
        return value
    }

    static func formatWeight(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}
