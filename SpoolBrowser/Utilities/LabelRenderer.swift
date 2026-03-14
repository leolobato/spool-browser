import CoreImage
import UIKit

struct LabelData {
    let brand: String
    let material: String
    let colorName: String
    let colorHex: String
    let nozzleTemp: String?
    let bedTemp: String?
    let printSpeed: String?
    let drying: String?
    let qrContent: String
    let spoolId: Int
}

struct LabelRenderer {
    // Base label dimensions at 203 DPI (40x30mm)
    private static let baseWidth: CGFloat = 320
    private static let baseHeight: CGFloat = 240
    private static let scale: CGFloat = 2.5
    private static let previewWidth: CGFloat = 800  // 320 * 2.5
    private static let previewHeight: CGFloat = 600 // 240 * 2.5

    // Layout coordinates (base, will be scaled)
    private static let brandX: CGFloat = 10
    private static let brandY: CGFloat = 8
    private static let brandMaxW: CGFloat = 302
    private static let brandMaxH: CGFloat = 40

    private static let barX: CGFloat = 10
    private static let barY: CGFloat = 51
    private static let barW: CGFloat = 302
    private static let barH: CGFloat = 34
    private static let barTextPad: CGFloat = 5

    private static let colorNameX: CGFloat = 12
    private static let colorNameY: CGFloat = 90

    private static let hexX: CGFloat = 12
    private static let hexY: CGFloat = 112

    private static let propXLabel: CGFloat = 12
    private static let propXValue: CGFloat = 80
    private static let propYStart: CGFloat = 140
    private static let propLineH: CGFloat = 24

    private static let qrX: CGFloat = 200
    private static let qrY: CGFloat = 120
    private static let qrSize: CGFloat = 112

    // MARK: - Public API

    static func labelData(from spool: Spool, spoolmanURL: String) -> LabelData {
        let filament = spool.filament
        let brand = filament?.vendor?.name ?? "Unknown"
        let material = filament?.material ?? "Unknown"
        let colorName = filament?.name ?? material
        let rawHex = (filament?.colorHex ?? "000000").trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let extra = filament?.extra

        let nozzleTemp = formatRange(extra, key: "nozzle_temp", suffix: "\u{00B0}C")
        let bedTemp = formatRange(extra, key: "bed_temp", suffix: "\u{00B0}C")
        let printSpeed = formatRange(extra, key: "printing_speed", suffix: " mm/s")

        let dryingTemp = formatRange(extra, key: "drying_temperature", suffix: "\u{00B0}C")
        let dryingTime = extra?["drying_time"].flatMap { Int($0) }

        let drying: String?
        if let dt = dryingTemp, let dh = dryingTime {
            drying = "\(dt) / \(dh)h"
        } else if let dt = dryingTemp {
            drying = dt
        } else if let dh = dryingTime {
            drying = "\(dh)h"
        } else {
            drying = nil
        }

        let baseURL = spoolmanURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let qrContent = "\(baseURL)/spool/show/\(spool.id)"

        return LabelData(
            brand: brand,
            material: material,
            colorName: colorName,
            colorHex: "#\(rawHex.uppercased())",
            nozzleTemp: nozzleTemp,
            bedTemp: bedTemp,
            printSpeed: printSpeed,
            drying: drying,
            qrContent: qrContent,
            spoolId: spool.id
        )
    }

    static func renderPreview(data: LabelData) -> UIImage {
        let s = scale
        let size = CGSize(width: previewWidth, height: previewHeight)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { ctx in
            let gc = ctx.cgContext

            // White background
            UIColor.white.setFill()
            gc.fill(CGRect(origin: .zero, size: size))

            // Brand logo or name
            drawBrand(data.brand, in: gc, scale: s)

            // Material bar
            drawMaterialBar(data.material, in: gc, scale: s)

            // Color name
            drawText(
                data.colorName,
                at: CGPoint(x: colorNameX * s, y: colorNameY * s),
                font: font(bold: false, size: 20 * s),
                color: .black,
                in: gc
            )

            // Hex code
            drawText(
                data.colorHex,
                at: CGPoint(x: hexX * s, y: hexY * s),
                font: font(bold: false, size: 14 * s),
                color: .black,
                in: gc
            )

            // Properties
            drawProperties(data, in: gc, scale: s)

            // QR code
            if let qrImage = generateQRCode(data.qrContent, size: qrSize * s) {
                let qrRect = CGRect(x: qrX * s, y: qrY * s, width: qrSize * s, height: qrSize * s)
                qrImage.draw(in: qrRect)
            }
        }
    }

    /// Rasterize a preview image to 1-bit monochrome data for the M110 printer.
    /// Returns (rasterData, widthBytes, rows).
    static func rasterize(image: UIImage) -> (Data, Int, Int) {
        let printWidth = Int(baseWidth)   // 320
        let printHeight = Int(baseHeight) // 240

        // M110 printhead offset: the printhead sits ~8 bytes (64 dots) inward
        // from the left edge of the label. In phomymo this comes from centering
        // the 40-byte image in 48 bytes (+4) plus the LEFT_PAD_BYTES shift (+4).
        let paddingBytes = 8
        let imageWidthBytes = printWidth / 8 // 40
        // 8 padding + 40 image = 48 bytes per row (matches printer width)
        let widthBytes = 48

        // Scale image to print dimensions
        let scaledImage = scaleImage(image, to: CGSize(width: CGFloat(printWidth), height: CGFloat(printHeight)))

        // Get raw pixel data
        guard let cgImage = scaledImage.cgImage else {
            return (Data(count: widthBytes * printHeight), widthBytes, printHeight)
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width
        var grayPixels = [UInt8](repeating: 255, count: width * height)

        guard let context = CGContext(
            data: &grayPixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return (Data(count: widthBytes * printHeight), widthBytes, printHeight)
        }

        // Draw flipped since CGContext has origin at bottom-left
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Convert to 1-bit monochrome, packed MSB-first
        var rasterData = Data(count: widthBytes * printHeight)

        for row in 0..<printHeight {
            // M110 feeds label bottom-edge-first, so row 0 = bottom of label.
            // CGContext has Y=0 at bottom, so row 0 in the pixel buffer is
            // already the bottom of the image — no flip needed.
            let sourceRow = row

            for byteIdx in 0..<imageWidthBytes {
                var byte: UInt8 = 0
                for bit in 0..<8 {
                    let px = byteIdx * 8 + bit
                    guard px < width else { continue }
                    let pixelIndex = sourceRow * width + px
                    let gray = grayPixels[pixelIndex]
                    if gray < 128 {
                        byte |= (0x80 >> bit) // MSB-first: black pixel
                    }
                }
                rasterData[row * widthBytes + paddingBytes + byteIdx] = byte
            }
            // Padding bytes and trailing bytes remain 0x00
        }

        return (rasterData, widthBytes, printHeight)
    }

    // MARK: - Drawing Helpers

    private static func drawBrand(_ brand: String, in gc: CGContext, scale s: CGFloat) {
        let slug = brandToSlug(brand)
        if let logoImage = UIImage(named: "Logos/\(slug)") {
            let maxW = brandMaxW * s
            let maxH = brandMaxH * s
            let logoSize = logoImage.size
            let ratio = Swift.min(maxW / logoSize.width, maxH / logoSize.height)
            let drawW = ratio < 1 ? logoSize.width * ratio : logoSize.width
            let drawH = ratio < 1 ? logoSize.height * ratio : logoSize.height
            let logoRect = CGRect(x: brandX * s, y: brandY * s, width: drawW, height: drawH)
            logoImage.draw(in: logoRect)
        } else {
            let maxW = brandMaxW * s
            let autoFont = autoShrinkFont(
                text: brand,
                bold: true,
                maxWidth: maxW,
                startSize: 36 * s,
                minSize: 18 * s
            )
            drawText(brand, at: CGPoint(x: brandX * s, y: brandY * s), font: autoFont, color: .black, in: gc)
        }
    }

    private static func drawMaterialBar(_ text: String, in gc: CGContext, scale s: CGFloat) {
        let barRect = CGRect(x: barX * s, y: barY * s, width: barW * s, height: barH * s)

        gc.setFillColor(UIColor.black.cgColor)
        gc.fill(barRect)

        let interiorW = (barW - barTextPad * 2) * s
        let barFont = autoShrinkFont(text: text, bold: true, maxWidth: interiorW, startSize: 22 * s, minSize: 10 * s)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: barFont,
            .foregroundColor: UIColor.white,
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let textY = barY * s + (barH * s - textSize.height) / 2

        (text as NSString).draw(
            at: CGPoint(x: (barX + barTextPad) * s, y: textY),
            withAttributes: attrs
        )
    }

    private static func drawProperties(_ data: LabelData, in gc: CGContext, scale s: CGFloat) {
        let propFont = font(bold: false, size: 18 * s)
        var props: [(String, String)] = []

        if let nozzle = data.nozzleTemp {
            props.append(("Nozzle:", nozzle))
        }
        if let bed = data.bedTemp {
            props.append(("Bed:", bed))
        }
        if let speed = data.printSpeed {
            props.append(("Speed:", speed))
        }
        if let drying = data.drying {
            props.append(("Drying:", drying))
        }

        for (i, (label, value)) in props.enumerated() {
            let y = (propYStart + CGFloat(i) * propLineH) * s
            drawText(label, at: CGPoint(x: propXLabel * s, y: y), font: propFont, color: .black, in: gc)
            drawText(value, at: CGPoint(x: propXValue * s, y: y), font: propFont, color: .black, in: gc)
        }
    }

    private static func drawText(
        _ text: String,
        at point: CGPoint,
        font: UIFont,
        color: UIColor,
        in gc: CGContext
    ) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        (text as NSString).draw(at: point, withAttributes: attrs)
    }

    // MARK: - Font Helpers

    private static func font(bold: Bool, size: CGFloat) -> UIFont {
        let name = bold ? "Helvetica-Bold" : "Helvetica"
        return UIFont(name: name, size: size) ?? (bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size))
    }

    private static func autoShrinkFont(text: String, bold: Bool, maxWidth: CGFloat, startSize: CGFloat, minSize: CGFloat) -> UIFont {
        var size = startSize
        while size >= minSize {
            let f = font(bold: bold, size: size)
            let textWidth = (text as NSString).size(withAttributes: [.font: f]).width
            if textWidth <= maxWidth {
                return f
            }
            size -= 1
        }
        return font(bold: bold, size: minSize)
    }

    // MARK: - QR Code

    private static func generateQRCode(_ content: String, size: CGFloat) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(content.data(using: .utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else { return nil }

        let scaleX = size / ciImage.extent.width
        let scaleY = size / ciImage.extent.height
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }

        return UIImage(cgImage: cgImage)
    }

    // MARK: - Utilities

    private static func brandToSlug(_ name: String) -> String {
        var slug = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "_", with: "-")
        slug = slug.filter { $0.isLetter && $0.isASCII || $0.isNumber || $0 == "-" }
        return slug
    }

    private static func formatRange(_ extra: [String: String]?, key: String, suffix: String) -> String? {
        guard let value = extra?[key], !value.isEmpty,
              let data = value.data(using: .utf8),
              let arr = try? JSONDecoder().decode([Int].self, from: data),
              arr.count == 2
        else { return nil }
        return "\(arr[0])-\(arr[1])\(suffix)"
    }

    private static func scaleImage(_ image: UIImage, to targetSize: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
