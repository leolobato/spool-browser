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
