import Foundation

enum DeepLink {
    case spool(Int)
    case filament(Int)
}

struct DeepLinkHandler {
    static func parse(url: URL) -> DeepLink? {
        guard url.scheme == "spoolbrowser" || url.scheme == "spoolman" else { return nil }

        let host = url.host()
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "spool":
            if let idString = pathComponents.first, let id = Int(idString) {
                return .spool(id)
            }
        case "filament":
            if let idString = pathComponents.first, let id = Int(idString) {
                return .filament(id)
            }
        default:
            break
        }

        return nil
    }
}
