import SwiftUI

struct FilamentDetailView: View {
    let filament: Filament
    var spoolmanService: SpoolmanService
    var spoolHelperService: SpoolHelperService

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    Circle()
                        .fill(Color(hex: filament.colorHex) ?? .gray)
                        .frame(width: 48, height: 48)
                        .overlay {
                            Circle().stroke(.secondary.opacity(0.3), lineWidth: 1)
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(filament.displayName)
                            .font(.title2)
                            .fontWeight(.semibold)

                        if let vendor = filament.vendor?.name {
                            Text(vendor)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Details") {
                if let material = filament.material {
                    LabeledContent("Material", value: material)
                }
                if let density = filament.density {
                    LabeledContent("Density", value: String(format: "%.2f g/cm\u{00B3}", density))
                }
                if let diameter = filament.diameter {
                    LabeledContent("Diameter", value: String(format: "%.2f mm", diameter))
                }
                if let weight = filament.weight {
                    LabeledContent("Spool Weight", value: "\(Int(weight))g")
                }
            }

            if let info = CustomFilamentInfo(filament: filament) {
                Section("BambuStudio Profile") {
                    LabeledContent("Filament ID", value: info.trayInfoIdx)
                    LabeledContent("Setting ID", value: info.settingId)
                    LabeledContent("Type", value: info.trayType)
                    LabeledContent("Nozzle Temp", value: "\(info.nozzleTempMin)-\(info.nozzleTempMax)\u{00B0}C")
                    if let min = info.bedTempMin, let max = info.bedTempMax {
                        LabeledContent("Bed Temp", value: "\(min)-\(max)\u{00B0}C")
                    }
                    if let min = info.dryingTempMin, let max = info.dryingTempMax {
                        LabeledContent("Drying Temp", value: "\(min)-\(max)\u{00B0}C")
                    }
                    if let dryTime = info.dryingTime {
                        LabeledContent("Drying Time", value: "\(dryTime)h")
                    }
                    if let min = info.printSpeedMin, let max = info.printSpeedMax {
                        LabeledContent("Print Speed", value: "\(min)-\(max) mm/s")
                    }
                }
            }
        }
        .navigationTitle("Filament #\(filament.id)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
