import Foundation
import Testing
import UIKit
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

    @Test("Spool formats display number")
    func spoolDisplayNumber() {
        let spool = Spool(
            id: 42,
            filament: nil,
            remainingWeight: nil,
            usedWeight: nil,
            remainingLength: nil,
            usedLength: nil,
            location: nil,
            comment: nil,
            lotNr: nil,
            registeredDate: nil,
            firstUsedDate: nil,
            lastUsedDate: nil,
            archived: nil
        )

        #expect(spool.displayNumber == "#42")
    }

    @Test("Label renderer draws spool number on material bar")
    func labelRendererDrawsSpoolNumberOnMaterialBar() throws {
        let data = LabelData(
            brand: "Polymaker",
            material: "PLA",
            colorName: "Galaxy Black",
            colorHex: "#1A1A1A",
            nozzleTemp: "190-230\u{00B0}C",
            bedTemp: "55-65\u{00B0}C",
            qrContent: "https://spoolman.example/spool/show/42",
            spoolId: 42
        )

        let image = LabelRenderer.renderPreview(data: data)
        let rightBarTextArea = CGRect(x: 650, y: 140, width: 120, height: 60)

        #expect(try whitePixelCount(in: image, rect: rightBarTextArea) > 500)
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
                "bed_temp": "[55, 65]"
            }
        }
        """

        let data = json.data(using: .utf8)!
        let filament = try JSONDecoder().decode(Filament.self, from: data)
        let info = CustomFilamentInfo(filament: filament)

        #expect(info != nil)
        #expect(info?.amsFilamentId == "GFSA00")
        #expect(info?.nozzleTempMin == 190)
        #expect(info?.nozzleTempMax == 230)
        #expect(info?.trayType == "PLA")
        #expect(info?.bedTempMin == 55)
        #expect(info?.bedTempMax == 65)
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
        #expect(info?.amsFilamentId == "GFSA00")
        #expect(info?.nozzleTempMin == 190)
        #expect(info?.bedTempMin == nil)
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
        #expect(info?.amsFilamentId == "GFSA00")
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
        #expect(info?.amsFilamentId == "GFSA00")
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

private func whitePixelCount(in image: UIImage, rect: CGRect) throws -> Int {
    let cgImage = try #require(image.cgImage)
    let width = cgImage.width
    let height = cgImage.height
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    let context = try #require(CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ))
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    let scaleX = CGFloat(width) / image.size.width
    let scaleY = CGFloat(height) / image.size.height
    let pixelRect = CGRect(
        x: rect.minX * scaleX,
        y: rect.minY * scaleY,
        width: rect.width * scaleX,
        height: rect.height * scaleY
    ).integral

    var count = 0
    let minX = max(Int(pixelRect.minX), 0)
    let maxX = min(Int(pixelRect.maxX), width)
    let minY = max(Int(pixelRect.minY), 0)
    let maxY = min(Int(pixelRect.maxY), height)

    for y in minY..<maxY {
        for x in minX..<maxX {
            let index = y * bytesPerRow + x * bytesPerPixel
            let red = pixels[index]
            let green = pixels[index + 1]
            let blue = pixels[index + 2]

            if red > 220, green > 220, blue > 220 {
                count += 1
            }
        }
    }

    return count
}

@Suite("AMS State Decoding")
struct AMSStateDecodingTests {

    @Test("Decode full AMS snapshot")
    func decodeAMSState() throws {
        let json = """
        {
            "connected": true,
            "printer_state": "printing",
            "active_tray": 1,
            "trays": [
                {
                    "tray": 0,
                    "label": "A1",
                    "empty": false,
                    "tray_type": "PLA",
                    "tray_color": "#ECE9E2",
                    "filament_id": "GFA00",
                    "tray_sub_brands": "PLA Basic",
                    "remain": 71,
                    "nozzle_temp_min": 190,
                    "nozzle_temp_max": 230,
                    "bed_temp": 55,
                    "spool_id": 14
                },
                {
                    "tray": 4,
                    "label": "External Spool",
                    "empty": false,
                    "tray_type": "PLA",
                    "tray_color": "#0D9488",
                    "filament_id": "",
                    "tray_sub_brands": "",
                    "remain": -1,
                    "nozzle_temp_min": 0,
                    "nozzle_temp_max": 0,
                    "bed_temp": 0,
                    "spool_id": null
                }
            ]
        }
        """

        let state = try JSONDecoder().decode(AMSState.self, from: json.data(using: .utf8)!)

        #expect(state.connected)
        #expect(state.printerState == "printing")
        #expect(state.activeTray == 1)
        #expect(state.trays.count == 2)

        let a1 = state.trays[0]
        #expect(a1.label == "A1")
        #expect(!a1.empty)
        #expect(a1.trayType == "PLA")
        #expect(a1.trayColor == "#ECE9E2")
        #expect(a1.filamentId == "GFA00")
        #expect(a1.traySubBrands == "PLA Basic")
        #expect(a1.remain == 71)
        #expect(a1.spoolId == 14)
        #expect(!a1.isExternal)

        let external = state.trays[1]
        #expect(external.isExternal)
        #expect(external.spoolId == nil)
        #expect(external.remain == -1)
    }

    @Test("Decode idle AMS state with null active tray")
    func decodeIdleAMSState() throws {
        let json = """
        {
            "connected": false,
            "printer_state": null,
            "active_tray": null,
            "trays": [
                {"tray": 1, "label": "A2", "empty": true, "tray_type": "", "tray_color": "",
                 "filament_id": "", "tray_sub_brands": "", "remain": -1,
                 "nozzle_temp_min": 0, "nozzle_temp_max": 0, "bed_temp": 0, "spool_id": null}
            ]
        }
        """

        let state = try JSONDecoder().decode(AMSState.self, from: json.data(using: .utf8)!)

        #expect(!state.connected)
        #expect(state.printerState == nil)
        #expect(state.activeTray == nil)
        #expect(state.trays[0].empty)
    }
}

@Suite("Weigh Spool Math")
struct WeighSpoolMathTests {

    @Test("Parse weight accepts decimals and comma separators")
    func parseWeight() {
        #expect(WeighSpoolSheet.parseWeight("856") == 856)
        #expect(WeighSpoolSheet.parseWeight("856.5") == 856.5)
        #expect(WeighSpoolSheet.parseWeight("856,5") == 856.5)
        #expect(WeighSpoolSheet.parseWeight(" 212 ") == 212)
        #expect(WeighSpoolSheet.parseWeight("") == nil)
        #expect(WeighSpoolSheet.parseWeight("abc") == nil)
        #expect(WeighSpoolSheet.parseWeight("-5") == nil)
    }

    @Test("Format weight drops trailing zeros")
    func formatWeight() {
        #expect(WeighSpoolSheet.formatWeight(644) == "644")
        #expect(WeighSpoolSheet.formatWeight(644.0) == "644")
        #expect(WeighSpoolSheet.formatWeight(644.5) == "644.5")
        #expect(WeighSpoolSheet.formatWeight(0) == "0")
    }
}
