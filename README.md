# SpoolBrowser

iOS app for browsing [Spoolman](https://github.com/Donkie/Spoolman) filament spools with Bambu Lab printer and BLE label printer integration.

## Features

- Browse spools and filaments from a Spoolman server
- Link Bambu Lab filament profiles to Spoolman filaments via [bambu-spool-helper](https://github.com/leolobato/bambu-spool-helper)
- Activate filament profiles on a Bambu printer's AMS via bambu-spool-helper (MQTT)
- Print physical spool labels on a Phomemo M110 thermal label printer via Bluetooth
- Scan QR codes to look up spools
- Deep link support for `spoolbrowser://` and `spoolman://` URL schemes

<p align="center">
  <img src="screenshots/spool-list.png" width="250" alt="Spool list">
  <img src="screenshots/spool-detail.png" width="250" alt="Spool detail">
  <img src="screenshots/label-preview.png" width="250" alt="Label preview">
</p>

## Branch

This is the `no-rfid` branch, which removes all NFC tag reading/writing features so the app can be built without a paid Apple Developer Program membership. See the `main` branch for the full-featured version.

## Requirements

- iOS 18.0+
- A running [Spoolman](https://github.com/Donkie/Spoolman) server instance
- [bambu-spool-helper](https://github.com/leolobato/bambu-spool-helper) companion service (optional, for AMS filament activation and profile linking)
- Phomemo M110 label printer (optional, for physical label printing)

## Building

The project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project from `project.yml`.

To sign the app for a physical device, copy the example config and set your Apple Development Team ID:

```bash
cp Local.xcconfig.example Local.xcconfig
# Edit Local.xcconfig and replace YOUR_TEAM_ID_HERE with your team ID
xcodegen generate
```

`Local.xcconfig` is gitignored and won't be committed.

## Label Printing

SpoolBrowser can print spool information labels on [Phomemo M110](https://phomemo.com/en-de/products/m110-label-maker) thermal label printers over Bluetooth Low Energy. Labels include the vendor logo, material type, color name, printing parameters (nozzle/bed temps), and a QR code linking back to the spool in Spoolman.

The label format, layout, and vendor logos are based on [3dfilamentprofiles.com](https://3dfilamentprofiles.com) by [Mark's Maker Space](https://github.com/MarksMakerSpace/filament-profiles).

## URL Schemes

SpoolBrowser registers two URL schemes: `spoolbrowser://` and `spoolman://`.

| URL | Action |
|---|---|
| `spoolbrowser://spool/{id}` | Open spool detail view |
| `spoolbrowser://filament/{id}` | Open filament detail view |

## Spoolman Extra Fields

Bambu Lab filament profile data (sourced from OrcaSlicer via bambu-spool-helper) is stored as custom extra fields on Spoolman filaments:

| Key | Type | Format | Example |
|---|---|---|---|
| `ams_filament_id` | text | JSON-quoted string | `"GFSA00"` |
| `ams_filament_type` | text | JSON-quoted string | `"PLA"` |
| `nozzle_temp` | integer_range | `[min, max]` | `[190, 230]` |
| `bed_temp` | integer_range | `[min, max]` | `[55, 65]` |

## Credits

Vendor logos and label format: [3dfilamentprofiles.com](https://3dfilamentprofiles.com) by [Mark's Maker Space](https://github.com/MarksMakerSpace/filament-profiles)

## Related Projects

SpoolBrowser is the **phone client for Bambu Spool Helper** in a suite of self-hosted projects that together replace the Bambu Handy app for printers in **Developer Mode** — keeping everything on your LAN, with no Bambu cloud.

**Self-hosted services**

- **[bambu-gateway](https://github.com/leolobato/bambu-gateway)** — Printer control plane and slicing web app. Talks to printers over MQTT/FTPS to monitor status, send commands, and upload jobs. Slices and prints 3MF files from the browser using `orcaslicer-headless`.
- **[orcaslicer-headless](https://github.com/leolobato/orcaslicer-headless)** — Headless OrcaSlicer wrapped in a REST API. Owns the filament/process/machine profile catalog (including custom user profiles) and does the actual slicing. Other services in the suite call it for slicing and profile data.
- **[bambu-spool-helper](https://github.com/leolobato/bambu-spool-helper)** — Bridge between [Spoolman](https://github.com/Donkie/Spoolman) and the printer's AMS. Links real spools to Bambu filament profiles (via `orcaslicer-headless`) and pushes the settings to a chosen tray over MQTT.

**iOS apps**

- **[bambu-gateway-ios](https://github.com/leolobato/bambu-gateway-ios)** — Phone client for `bambu-gateway`. Browse printers, import 3MF files (including from MakerWorld), preview G-code, and start prints. Live Activities and push notifications for print state changes.
- **SpoolBrowser** — this project.

## License

SpoolBrowser is released under the [MIT License](LICENSE) — © 2025 Leonardo Lobato. You are free to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the software, provided the copyright notice and license text are retained. The software is provided "as is", without warranty of any kind.

## Disclaimer

This project was built almost entirely through agentic programming using [Claude Code](https://claude.ai/code). The architecture, implementation, and tests were generated through AI-assisted development with human guidance and review.
