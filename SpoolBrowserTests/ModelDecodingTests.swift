import Foundation
import Testing
@testable import SpoolBrowser

@Suite("Model Decoding")
struct ModelDecodingTests {

    @Test("Decode Spool with nested Filament and Vendor")
    func decodeSpool() throws {
        let json = """
        {
            "id": 42,
            "filament": {
                "id": 10,
                "name": "eSUN PLA+ Black",
                "vendor": {
                    "id": 1,
                    "name": "eSUN"
                },
                "material": "PLA",
                "density": 1.24,
                "diameter": 1.75,
                "weight": 1000,
                "spool_weight": 200,
                "color_hex": "000000",
                "extra": {
                    "ams_filament_id": "\\"GFSA00\\"",
                    "ams_filament_type": "\\"PLA\\"",
                    "nozzle_temp": "[190, 230]"
                }
            },
            "remaining_weight": 850.5,
            "used_weight": 149.5,
            "location": "AMS Tray 1",
            "archived": false
        }
        """

        let data = json.data(using: .utf8)!
        let spool = try JSONDecoder().decode(Spool.self, from: data)

        #expect(spool.id == 42)
        #expect(spool.filament?.id == 10)
        #expect(spool.filament?.name == "eSUN PLA+ Black")
        #expect(spool.filament?.vendor?.name == "eSUN")
        #expect(spool.filament?.material == "PLA")
        #expect(spool.filament?.colorHex == "000000")
        #expect(spool.remainingWeight == 850.5)
        #expect(spool.location == "AMS Tray 1")
        #expect(spool.archived == false)
    }

    @Test("CustomFilamentInfo extracts linked fields")
    func customInfoLinked() throws {
        let json = """
        {
            "id": 10,
            "name": "Test Filament",
            "extra": {
                "ams_filament_id": "\\"GFSA00\\"",
                "ams_filament_type": "\\"PLA\\"",
                "nozzle_temp": "[190, 230]",
                "bed_temp": "[55, 65]",
                "drying_temperature": "[40, 55]",
                "drying_time": "8",
                "printing_speed": "[40, 100]"
            }
        }
        """

        let data = json.data(using: .utf8)!
        let filament = try JSONDecoder().decode(Filament.self, from: data)
        let info = CustomFilamentInfo(filament: filament)

        #expect(info != nil)
        #expect(info?.trayInfoIdx == "GFSA00")
        #expect(info?.nozzleTempMin == 190)
        #expect(info?.nozzleTempMax == 230)
        #expect(info?.trayType == "PLA")
        #expect(info?.bedTempMin == 55)
        #expect(info?.bedTempMax == 65)
        #expect(info?.dryingTempMin == 40)
        #expect(info?.dryingTempMax == 55)
        #expect(info?.dryingTime == 8)
        #expect(info?.printSpeedMin == 40)
        #expect(info?.printSpeedMax == 100)
    }

    @Test("CustomFilamentInfo returns nil when not linked")
    func customInfoUnlinked() throws {
        let json = """
        {
            "id": 10,
            "name": "Unlinked Filament",
            "extra": {}
        }
        """

        let data = json.data(using: .utf8)!
        let filament = try JSONDecoder().decode(Filament.self, from: data)
        let info = CustomFilamentInfo(filament: filament)

        #expect(info == nil)
    }

    @Test("CustomFilamentInfo works with minimal fields")
    func customInfoMinimal() throws {
        let json = """
        {
            "id": 10,
            "name": "Minimal Fields",
            "extra": {
                "ams_filament_id": "\\"GFSA00\\"",
                "ams_filament_type": "\\"PLA\\"",
                "nozzle_temp": "[190, 230]"
            }
        }
        """

        let data = json.data(using: .utf8)!
        let filament = try JSONDecoder().decode(Filament.self, from: data)
        let info = CustomFilamentInfo(filament: filament)

        #expect(info != nil)
        #expect(info?.trayInfoIdx == "GFSA00")
        #expect(info?.nozzleTempMin == 190)
        #expect(info?.bedTempMin == nil)
        #expect(info?.dryingTime == nil)
    }

    @Test("CustomFilamentInfo is linked with ID fields only")
    func customInfoLinkedWithoutTemps() throws {
        let json = """
        {
            "id": 10,
            "name": "Legacy Link",
            "material": "PLA",
            "extra": {
                "ams_filament_id": "\\"GFSA00\\""
            }
        }
        """

        let data = json.data(using: .utf8)!
        let filament = try JSONDecoder().decode(Filament.self, from: data)
        let info = CustomFilamentInfo(filament: filament)

        #expect(info != nil)
        #expect(info?.trayInfoIdx == "GFSA00")
        #expect(info?.trayType == "PLA")
        #expect(info?.nozzleTempMin == nil)
        #expect(info?.nozzleTempMax == nil)
    }

    @Test("CustomFilamentInfo is linked when only AMS Filament ID exists")
    func customInfoLinkedWithAmsFilamentIdOnly() throws {
        let json = """
        {
            "id": 10,
            "name": "AMS Filament-Only Link",
            "extra": {
                "ams_filament_id": "\\"GFSA00\\""
            }
        }
        """

        let data = json.data(using: .utf8)!
        let filament = try JSONDecoder().decode(Filament.self, from: data)
        let info = CustomFilamentInfo(filament: filament)

        #expect(info != nil)
        #expect(info?.trayInfoIdx == "GFSA00")
    }

    @Test("DeepLinkHandler parses spool URL")
    func deepLinkSpool() {
        let url = URL(string: "spoolbrowser://spool/42")!
        let link = DeepLinkHandler.parse(url: url)

        if case .spool(let id) = link {
            #expect(id == 42)
        } else {
            #expect(Bool(false), "Expected .spool deep link")
        }
    }

    @Test("DeepLinkHandler parses filament URL")
    func deepLinkFilament() {
        let url = URL(string: "spoolbrowser://filament/10")!
        let link = DeepLinkHandler.parse(url: url)

        if case .filament(let id) = link {
            #expect(id == 10)
        } else {
            #expect(Bool(false), "Expected .filament deep link")
        }
    }

    @Test("DeepLinkHandler parses spoolman:// spool URL")
    func deepLinkSpoolmanScheme() {
        let url = URL(string: "spoolman://spool/7")!
        let link = DeepLinkHandler.parse(url: url)

        if case .spool(let id) = link {
            #expect(id == 7)
        } else {
            #expect(Bool(false), "Expected .spool deep link from spoolman:// scheme")
        }
    }

}
