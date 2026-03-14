import SwiftUI

struct ContentView: View {
    var spoolmanService: SpoolmanService
    var spoolHelperService: SpoolHelperService
    var labelPrinterService: LabelPrinterService

    @Binding var selectedTab: AppTab
    @Binding var navigationPath: NavigationPath

    var body: some View {
        TabView(selection: $selectedTab) {
            SwiftUI.Tab("Spools", systemImage: "circle.grid.3x3.fill", value: .spools) {
                NavigationStack(path: $navigationPath) {
                    SpoolListView(
                        spoolmanService: spoolmanService,
                        navigationPath: $navigationPath
                    )
                    .navigationTitle("Spools")
                    .navigationDestination(for: Spool.self) { spool in
                        SpoolDetailView(
                            spool: spool,
                            spoolmanService: spoolmanService,
                            spoolHelperService: spoolHelperService,
                            labelPrinterService: labelPrinterService
                        )
                    }
                    .navigationDestination(for: Filament.self) { filament in
                        FilamentDetailView(
                            filament: filament,
                            spoolmanService: spoolmanService,
                            spoolHelperService: spoolHelperService
                        )
                    }
                }
            }

            SwiftUI.Tab("Scan", systemImage: "camera.viewfinder", value: .scan) {
                QRScannerView(
                    spoolmanService: spoolmanService,
                    selectedTab: $selectedTab,
                    navigationPath: $navigationPath
                )
            }

            SwiftUI.Tab("Settings", systemImage: "gear", value: .settings) {
                SettingsView(spoolmanService: spoolmanService, spoolHelperService: spoolHelperService, labelPrinterService: labelPrinterService)
            }
        }
    }
}

enum AppTab: Hashable {
    case spools
    case scan
    case settings
}
