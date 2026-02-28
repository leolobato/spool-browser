import SwiftUI

@main
struct SpoolBrowserApp: App {
    @State private var spoolmanService = SpoolmanService()
    @State private var spoolHelperService = SpoolHelperService()
    @State private var labelPrinterService = LabelPrinterService()
    @State private var selectedTab = AppTab.spools
    @State private var navigationPath = NavigationPath()

    @AppStorage("spoolmanURL") private var spoolmanURL = ""

    var body: some Scene {
        WindowGroup {
            ContentView(
                spoolmanService: spoolmanService,
                spoolHelperService: spoolHelperService,
                labelPrinterService: labelPrinterService,
                selectedTab: $selectedTab,
                navigationPath: $navigationPath
            )
            .task {
                if !spoolmanURL.isEmpty {
                    spoolmanService.configure(baseURL: spoolmanURL)
                    await spoolmanService.checkConnection()
                }
                spoolHelperService.startBrowsing()
            }
            .onOpenURL { url in
                handleDeepLink(url)
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard let deepLink = DeepLinkHandler.parse(url: url) else { return }
        selectedTab = .spools
        navigationPath = NavigationPath()

        Task {
            switch deepLink {
            case .spool(let id):
                do {
                    let spool = try await spoolmanService.fetchSpool(id: id)
                    navigationPath.append(spool)
                } catch {
                    // Spool not found - silently fail
                }
            case .filament(let id):
                do {
                    let filament = try await spoolmanService.fetchFilament(id: id)
                    navigationPath.append(filament)
                } catch {
                    // Filament not found - silently fail
                }
            }
        }
    }
}
