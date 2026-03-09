# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build System

iOS app using **XcodeGen** to generate the Xcode project from `project.yml`.

```bash
# Regenerate .xcodeproj (required after any project.yml change)
xcodegen generate

# Build
xcodebuild build -scheme SpoolBrowser -destination 'platform=iOS Simulator,name=iPhone 16'

# Run tests
xcodebuild test -scheme SpoolBrowser -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Dependencies**: No external SPM packages.

**Targets**: iOS 18.0, iPhone only, Swift 6.0 with strict concurrency.

## Architecture

MVVM with `@Observable` services (iOS 17+ Observation framework). All services are `@MainActor`-isolated.

- **Models/** — `Codable`, `Sendable` structs: `Spool`, `Filament`, `Vendor`, `FilamentProfile`, `CustomFilamentInfo`
- **Services/** — `SpoolmanService` (REST client), `SpoolHelperService` (Bonjour + HTTP), `LabelPrinterService` (CoreBluetooth/BLE)
- **Views/** — SwiftUI views rooted at `ContentView` (TabView with Spools, Scan, Settings tabs)
- **Utilities/** — `LabelRenderer` (label image + rasterization), `DeepLinkHandler`, `NFCWriter`, `NFCReader`, `Color+Hex`
- **Resources/Logos/** — ~340 vendor logo PNGs, included as a folder reference in `project.yml`. Looked up via `UIImage(named: "Logos/\(slug)")`.

Settings are stored via `@AppStorage`/UserDefaults.

## Key Services

**SpoolmanService** — REST client for Spoolman API. Fetches spools/filaments, links filaments to BambuStudio profiles, manages extra field creation via `ensureExtraFields()`.

**SpoolHelperService** — Discovers the companion macOS app (`spool-helper/` sibling directory) via Bonjour (`_spoolhelper._tcp`), with manual address fallback. HTTP API for fetching BambuStudio profiles and activating them with tray assignment.

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

BambuStudio profile data stored in Spoolman filament extra fields:

| Key | Type | Format | Example |
|---|---|---|---|
| `ams_filament_id` | text | JSON-quoted string | `"GFSA00"` |
| `ams_profile_filament_id` | text | JSON-quoted string | `"GFA00"` |
| `ams_filament_type` | text | JSON-quoted string | `"PLA"` |
| `nozzle_temp` | integer_range | `[min, max]` | `[190, 230]` |
| `bed_temp` | integer_range | `[min, max]` | `[55, 65]` |
| `drying_temperature` | integer_range | `[min, max]` | `[40, 55]` |
| `drying_time` | integer | plain number | `8` |
| `printing_speed` | integer_range | `[min, max]` | `[40, 100]` |

- Text fields are JSON-encoded: the raw stored value for `"GFSA00"` is `"\"GFSA00\""`.
- `CustomFilamentInfo` reads these fields; `SpoolmanService.linkFilament` writes them.
- `SpoolmanService.ensureExtraFields()` creates missing fields via `POST /api/v1/field/filament/{key}`.

## Testing

Uses **Swift Testing** framework (`@Suite`, `@Test` macros) in `SpoolBrowserTests/ModelDecodingTests.swift`. Covers model decoding, CustomFilamentInfo extraction, and DeepLinkHandler parsing.
