# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build System

iOS app using **XcodeGen** to generate the Xcode project from `project.yml`.

```bash
# First-time setup: copy xcconfig and set your team ID
cp Local.xcconfig.example Local.xcconfig
# Edit Local.xcconfig to set DEVELOPMENT_TEAM

# Regenerate .xcodeproj (required after any project.yml change)
xcodegen generate

# Build
xcodebuild build -scheme SpoolBrowser -destination 'platform=iOS Simulator,name=iPhone 16'

# Run all tests
xcodebuild test -scheme SpoolBrowser -destination 'platform=iOS Simulator,name=iPhone 16'

# Run a single test
xcodebuild test -scheme SpoolBrowser -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:SpoolBrowserTests/ModelDecodingTests/decodeSpool
```

**Dependencies**: No external SPM packages.

**Targets**: iOS 18.0, iPhone only, Swift 6.0 with strict concurrency.

**xcconfig layering**: `Base.xcconfig` defines defaults (`APP_BUNDLE_ID=com.example.SpoolBrowser`, empty `DEVELOPMENT_TEAM`) and ends with `#include? "Local.xcconfig"` so a developer's gitignored `Local.xcconfig` overrides them. Both `PRODUCT_BUNDLE_IDENTIFIER` and the `CFBundleURLName` resolve from `$(APP_BUNDLE_ID)`.

**`AGENTS.md` is a symlink to `CLAUDE.md`** — edit `CLAUDE.md` and both stay in sync. Don't replace the symlink with a separate file.

## Architecture

MVVM with `@Observable` services (iOS 17+ Observation framework). All services are `@MainActor`-isolated.

- **Models/** — `Codable`, `Sendable` structs: `Spool`, `Filament`, `Vendor`, `FilamentProfile`, `CustomFilamentInfo`
- **Services/** — `SpoolmanService` (REST client), `SpoolHelperService` (HTTP), `LabelPrinterService` (CoreBluetooth/BLE)
- **Views/** — SwiftUI views rooted at `ContentView` (TabView with Spools, Scan, Settings tabs)
- **Utilities/** — `LabelRenderer` (label image + rasterization), `DeepLinkHandler`, `NFCWriter`, `NFCReader`, `Color+Hex`
- **Resources/Logos/** — ~340 vendor logo PNGs, included as a folder reference in `project.yml`. Looked up via `UIImage(named: "Logos/\(slug)")`.

Settings are stored via `@AppStorage`/UserDefaults.

**URL Schemes**: `spoolbrowser://` and `spoolman://` — handled by `DeepLinkHandler`, supports `spool/{id}` and `filament/{id}` paths.

**Branch note**: The `no-rfid` branch removes NFC entitlements for building with free developer accounts.

## Key Services

**SpoolmanService** — REST client for Spoolman API. Fetches spools/filaments, links filaments to Bambu Lab filament profiles, manages extra field creation via `ensureExtraFields()`.

**SpoolHelperService** — HTTP client for the [bambu-spool-helper](https://github.com/leolobato/bambu-spool-helper) companion service (FastAPI). The address is configured manually in Settings (stored under the `spoolHelperAddress` UserDefaults key). HTTP API for fetching Bambu Lab filament profiles (the helper sources them from `orcaslicer-cli`) and activating them on the printer's AMS via MQTT, with tray assignment (0–3 = AMS slots, 4 = external spool). The activation does NOT go through BambuStudio — bambu-spool-helper talks to the printer directly. The Swift type retains the `SpoolHelper` name for historical reasons.

**LabelPrinterService** — CoreBluetooth BLE wrapper for Phomemo thermal label printers. Scans by known name prefixes (`M02`, `Q1`, `T0`, etc. — M110S variants advertise as `Q199...` not `M110`) and by advertised service UUIDs (`FF00`, `FFE0`, `AE30`). Write characteristic `FF02`, notify `FF03`. ESC/POS raster protocol with 128-byte chunks.

## Label Rendering (LabelRenderer)

- Base: 320×240px at 203 DPI (40×30mm label)
- Preview: 2.5× scale (800×600)
- Brand logos loaded from `Resources/Logos/{slug}.png` via `brandToSlug()` (lowercase, spaces→dashes, alphanumeric only)
- Rasterization: 1-bit monochrome, MSB-first. 8-byte printhead offset + 40-byte image = 48-byte row width.

## Key Gotchas

- **SwiftUI Tab conflict**: iOS 18's `SwiftUI.Tab` conflicts with any custom `Tab` type. Use `AppTab` enum and qualify as `SwiftUI.Tab(...)`.
- **XcodeGen overwrites Info.plist**: Custom entries must go in `project.yml` under `info.properties`, not directly in Info.plist.
- **Logos folder reference**: The `Resources/Logos` directory is excluded from the main sources and re-added as `type: folder` in `project.yml` to preserve directory structure in the bundle.
- **Test target**: Requires `GENERATE_INFOPLIST_FILE: YES` in settings.
- **BLE delegate pattern**: `LabelPrinterService.BLEDelegate` uses `@unchecked Sendable` with `Task { @MainActor in }` dispatch for Swift 6 concurrency.

## Spoolman Extra Fields

Bambu Lab filament profile data (sourced from OrcaSlicer via bambu-spool-helper) stored in Spoolman filament extra fields:

| Key | Type | Format | Example |
|---|---|---|---|
| `ams_filament_id` | text | JSON-quoted string | `"GFSA00"` |
| `ams_filament_type` | text | JSON-quoted string | `"PLA"` |
| `nozzle_temp` | integer_range | `[min, max]` | `[190, 230]` |
| `bed_temp` | integer_range | `[min, max]` | `[55, 65]` |

- Text fields are JSON-encoded: the raw stored value for `"GFSA00"` is `"\"GFSA00\""`.
- `CustomFilamentInfo` reads these fields; `SpoolmanService.linkFilament` writes them.
- `SpoolmanService.ensureExtraFields()` creates missing fields via `POST /api/v1/field/filament/{key}`.

## Testing

Uses **Swift Testing** framework (`@Suite`, `@Test` macros) in `SpoolBrowserTests/ModelDecodingTests.swift`. Covers model decoding, CustomFilamentInfo extraction, and DeepLinkHandler parsing.
