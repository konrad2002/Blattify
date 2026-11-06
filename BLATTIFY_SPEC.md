# Blattify – Implementation Specification

> Target audience: an AI coding agent implementing the app inside Xcode.
> Work phase by phase. Each phase must **build without errors and warnings** and meet its acceptance criteria before the next phase starts.

---

## 1. Product Summary

Blattify is an iPhone app for tracking houseplants in a room. Each plant gets a short unique code (`XX-XX`) and a printable QR label. Scanning the label (with the in-app scanner or the system Camera app) opens the plant's profile. On the profile, the user logs care events (watering, fertilizing, repotting, cuttings, new leaves, pest infestations), each with its date and history. Events are visualized in a GitHub-style yearly activity matrix. Data syncs via iCloud, can be exported and imported as a complete backup, and the app is localized in German and English.

---

## 2. Technical Baseline

| Topic | Decision |
|---|---|
| Platform | iPhone only (`TARGETED_DEVICE_FAMILY = 1`), portrait + landscape |
| Minimum OS | **iOS 26.0** (Liquid Glass available) |
| Language | Swift 6 language mode, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (already set) |
| UI | SwiftUI only, `NavigationStack`, Liquid Glass styling (system components first; use `glassEffect` APIs where custom chrome is needed – look up current API via `DocumentationSearch`) |
| Persistence | SwiftData |
| Sync | SwiftData + CloudKit private database (`ModelConfiguration(cloudKitDatabase: .private("iCloud.<bundle-id>"))`) |
| Concurrency | async/await only. **No Combine.** |
| QR generation | Core Image `CIFilter.qrCodeGenerator()` |
| QR scanning | VisionKit `DataScannerViewController` (wrapped via `UIViewControllerRepresentable`); check `isSupported`/`isAvailable` and show a fallback message otherwise |
| Notifications | `UserNotifications` local notifications |
| Archive format | Apple Archive (`AppleArchive` framework, LZFSE) with custom extension `.blattify` – no third-party dependencies |
| Localization | String Catalog (`Localizable.xcstrings`), development language **English**, plus **German** |
| Tests | Swift Testing (`import Testing`), only critical logic (see Phase 9) |
| Dependencies | **None.** Do not add Swift packages. |

### Agent working rules
- Use the `xcode-tools` MCP tools (`XcodeWrite`, `XcodeRead`, `BuildProject`, `XcodeRefreshCodeIssuesInFile`, `RenderPreview`, …) rather than shell commands.
- Use `DocumentationSearch` for any API you are not 100% sure about (especially Liquid Glass, SwiftData+CloudKit, VisionKit, iOS 26 SwiftUI changes).
- Every user-facing string must be localizable (use `String(localized:)` / `LocalizedStringResource` / `Text("key")` literals) – never hard-code display text in a non-localizable way.
- Provide `#Preview`s for all main views using an in-memory `ModelContainer` with sample data.
- Style: 4-space indentation, PascalCase types, camelCase members, `@State private var`, no force unwraps, short doc comments for non-obvious logic.

---

## 3. Data Model (SwiftData)

### CloudKit constraints (must be respected)
- **No** `@Attribute(.unique)` – uniqueness is enforced in app logic.
- Every stored property is optional **or** has a default value.
- All relationships are optional; delete rules only `.cascade` or `.nullify`.
- Enums are stored as raw `String` values with a computed typed accessor (robust against future cases and sync).
- Large binary data uses `@Attribute(.externalStorage)`.

### 3.1 `Plant`
| Property | Type | Notes |
|---|---|---|
| `id` | `UUID` | default `UUID()`, stable identity for import/export |
| `code` | `String` | default `""`, format `XX-XX`, uppercase |
| `name` | `String` | default `""` |
| `species` | `String` | "Pflanzenart", free text with autocomplete |
| `acquiredDate` | `Date?` | "when bought" – date only |
| `notes` | `String` | default `""` |
| `statusRaw` | `String` | `active` (default) / `givenAway` / `died` |
| `statusDate` | `Date?` | date of giving away / death |
| `wateringIntervalDays` | `Int?` | `nil` = reminder off |
| `profilePhoto` | `Data?` | `.externalStorage`, JPEG |
| `createdAt` | `Date` | default `.now` |
| `parent` | `Plant?` | inverse of `children`, `.nullify` |
| `children` | `[Plant]?` | cuttings made from this plant, `.nullify` |
| `events` | `[PlantEvent]?` | `.cascade` |
| `infestations` | `[PestInfestation]?` | `.cascade` |

Computed helpers (not stored): `status`, `lastWatering`, `lastNewLeaf`, `activeInfestations`, `isWateringDue(on:)`, `nextWateringDate`.

### 3.2 `PlantEvent`
One model for all dated care events.

| Property | Type | Notes |
|---|---|---|
| `id` | `UUID` | |
| `date` | `Date` | default `.now`, user can backdate |
| `kindRaw` | `String` | `watering`, `fertilizing`, `repotting`, `cutting`, `newLeaf` |
| `wateringKindRaw` | `String?` | only for watering: `soaked` (soil soaked), `wet` (soil just moistened), `shower` (showering) |
| `fertilizerName` | `String?` | only fertilizing; suggestions come from previously used names (distinct values across all events) |
| `fertilizerAmount` | `String?` | free text, e.g. "2 ml/L" |
| `potDiameterCm` | `Double?` | only repotting |
| `substrate` | `String?` | only repotting, free text (suggest previously used values) |
| `resultingPlantID` | `UUID?` | only cutting: plant created from this cutting |
| `note` | `String` | default `""`, available for every kind |
| `photos` | `[EventPhoto]?` | `.cascade` |
| `plant` | `Plant?` | inverse |

### 3.3 `PestInfestation`
| Property | Type | Notes |
|---|---|---|
| `id` | `UUID` | |
| `pestTypeRaw` | `String` | `spiderMites`, `thrips`, `fungusGnats`, `mealybugs`, `scale`, `aphids`, `whitefly`, `other` |
| `customPestName` | `String?` | used when type is `other` |
| `startDate` | `Date` | |
| `resolvedDate` | `Date?` | `nil` = active |
| `notes` | `String` | default `""`, treatments etc. |
| `photos` | `[EventPhoto]?` | `.cascade` |
| `plant` | `Plant?` | inverse |

### 3.4 `EventPhoto`
| Property | Type | Notes |
|---|---|---|
| `id` | `UUID` | |
| `imageData` | `Data?` | `.externalStorage`, JPEG |
| `createdAt` | `Date` | |
| `event` | `PlantEvent?` | inverse |
| `infestation` | `PestInfestation?` | inverse |

**Image handling:** All photos (profile + event) are downscaled to max. 2048 px on the longest side and stored as JPEG (quality ≈ 0.8) to limit iCloud storage. Use `PhotosPicker` for the library and a camera capture option.

### 3.5 `RetiredPlantCode`
Stores the codes of permanently deleted plants so they are never generated again.

| Property | Type | Notes |
|---|---|---|
| `code` | `String` | default `""` |
| `retiredAt` | `Date` | default `.now` |

### 3.6 Schema versioning
Wrap models in a `VersionedSchema` (`BlattifySchemaV1`) and a `SchemaMigrationPlan` from day one.

---

## 4. Plant Code

- Format: `XX-XX`, regex `^[A-HJKMNP-Z2-9]{2}-[A-HJKMNP-Z2-9]{2}$`.
- Alphabet: `A–Z` without `I`, `L`, `O` (23 letters) + `2–9` (8 digits) = **31 symbols**, 923,521 combinations.
- Generation: random with `SystemRandomNumberGenerator`. Retry until the code is not used by any plant in the store (including archived plants).
- Input is case-insensitive: trim whitespace, uppercase, and insert the dash automatically (`ab12` → `AB-12`). Reject characters outside the alphabet and show a hint.
- Codes are never reused, not even after a plant is deleted.
- Sync collision (very unlikely, two devices offline): if a lookup returns more than one plant for a code, show a picker and offer "Generate new code" for one of them.
- Implement in a pure, testable `PlantCode` value type (`generate(excluding:)`, `normalize(_:) -> String?`, `isValid(_:)`).

### Deep link / QR content
- QR payload: `blattify://plant/AB-12`
- Register URL scheme `blattify` (Info.plist `CFBundleURLTypes`).
- `.onOpenURL` → parse → navigate to the plant profile. Unknown code → alert "No plant with code AB-12" with the option "Create plant".
- The in-app scanner accepts both the URL format and a plain `AB-12` string.

---

## 5. Features & Screens

### 5.1 Home (`PlantListView`)
- Searchable (name, species, code) list of **active** plants, with a toggle between list and grid layouts (persisted via `@AppStorage`).
- Each row/card shows: photo thumbnail (or leaf placeholder), name, species, code (monospaced), "watered X days ago", a **watering-due** badge, and an **active pest** badge.
- Sorting menu: name, last watered, watering due first.
- Toolbar: **Scan QR**, **Enter code**, **+ New plant**, menu with **Archive** and **Settings**.
- Empty state (`ContentUnavailableView`) with a "Create first plant" button.

### 5.2 Code entry
- Sheet with one large monospaced text field, auto-formatting to `XX-XX`, auto-uppercase, `.keyboardType(.asciiCapable)`, no autocorrection.
- Opens the profile directly when the code is valid and found.

### 5.3 QR scanner
- Full-screen `DataScannerViewController` limited to QR codes, with a cutout overlay and haptic feedback on success.
- Needs `NSCameraUsageDescription` (localized).

### 5.4 Create / edit plant
- Form fields: photo, name (required), species (text field with suggestions from existing species), acquired date (optional toggle + `DatePicker`), parent plant (optional picker), watering reminder interval (off / 1–60 days), notes.
- A new code is generated and shown on creation. After saving, the QR label sheet opens.

### 5.5 QR label (`QRLabelView` + export)
- Rendered with `ImageRenderer` as a PNG (≈ 1024 px wide, scale 3):
  - QR code (error correction level `Q`, crisp nearest-neighbour scaling)
  - code `AB-12` in large bold monospaced font
  - plant name below
  - white background and a quiet zone, suitable for printing on a pot label
- Actions: `ShareLink` (Transferable PNG) and **Save to Photos** (add-only permission, `NSPhotoLibraryAddUsageDescription`).
- Reachable from the plant profile at any time.

### 5.6 Plant profile (`PlantDetailView`)
Sections from top to bottom:
1. **Header:** photo, name, species, code chip (tap → QR label), status badge (if archived), active pest badge.
2. **Quick actions** (prominent buttons): *Water* (menu: soaked / wet / shower), *Fertilize*, *Log new leaf*, *More…* (repot, cutting, pest).
   - Quick water logs immediately with date = now and offers an undo toast. Long press / "More" opens the full form for a different date, a note or photos.
3. **Key facts:** last watered (+ kind), next watering due, last fertilized, last repotted (pot size), latest new leaf, acquired date, age.
4. **Activity matrix** (see 5.7).
5. **Pest infestations:** active ones first, then resolved ones (type, start–end, notes, photos). Button "Mark as resolved".
6. **Family:** parent plant (link) and children/cuttings (links), shown as a small tree: parent → this plant → children. Archived relatives remain visible (greyed out).
7. **History:** chronological list of all events, filterable by kind; swipe to edit/delete; photos as thumbnails.
8. **Toolbar:** Edit, QR label, Archive (given away / died + date), Delete (destructive confirmation).

### 5.7 Activity matrix (`ActivityMatrixView`) – core feature
- **One combined matrix per plant** for a **calendar year** (Jan 1 – Dec 31) in a GitHub-contribution layout: columns = weeks, rows = weekdays (first weekday from `Calendar.current`), month labels above, weekday labels left.
- **Year navigation:** chevron buttons plus horizontal swipe; the title shows the year. The default year is the current one. The range is from the year of the plant's first event/creation to the current year.
- **Filter chips** above the matrix toggle event types on/off: Watering, Fertilizing, Repotting, Cutting, New leaf, Pest. All are on by default; the state is kept per session.
- **Cell rendering:**
  - Empty day: neutral subtle gray; future days are lighter; today has an outline.
  - A day with events is **split into up to 4 equal segments**, one per visible event type, in a fixed priority order: Watering → Fertilizing → Pest → Repotting → Cutting → New leaf. If more than 4 types occur, show the first 4 and add a small corner dot.
  - Watering segment color depends on the kind: **dark blue = soaked**, **light blue = wet**, **teal = shower**. If several waterings happen on one day, use soaked > shower > wet.
  - **Pest** is a range: every day from `startDate` to `resolvedDate` (or today) gets the pest segment (red/orange).
  - All colors are defined in the asset catalog with light/dark variants and sufficient contrast.
- **Legend** below the matrix (colors + labels).
- **Tap a day** to open a popover or sheet listing that day's events with their details, plus "Add event on this day".
- **Performance:** render with `Canvas` (≈ 371 cells), precompute a `[DayKey: Set<MatrixCategory>]` dictionary in a pure, testable `ActivityMatrixModel`, and map tap locations to days mathematically.
- **Accessibility:** expose an accessibility element per day that has events (label e.g. "3 March: watered (soaked), fertilized") and a summary per month.

### 5.8 Event forms
One `EventFormView` that adapts to the kind:
- all kinds: date + time (default now), note, photos (multiple)
- watering: kind picker (soaked / wet / shower)
- fertilizing: fertilizer name (with suggestions from previous entries), amount
- repotting: pot diameter (cm), substrate (suggestions)
- cutting: after saving, ask **"Create a plant from this cutting?"** → opens Create plant with a new code, parent set to this plant, species copied, name prefilled as "<Name> (cutting)", acquired date = event date; stores `resultingPlantID` on the event.
- new leaf: just date, note and photo
- pest: separate `InfestationFormView` (type picker, custom name for "other", start date, optional resolved date, notes, photos)

### 5.9 Archive
- Plants with status `givenAway` or `died` are hidden from Home and listed in an **Archive** screen, grouped by status, with an option to restore.
- They remain fully viewable and keep their place in family trees.
- Permanent delete is available from the profile (confirmation dialog that names the number of events that will be deleted). Children keep existing; their `parent` becomes `nil`.

### 5.10 Watering reminders
- Per plant `wateringIntervalDays`. Due date = last watering (any kind) + interval; if there has never been a watering, due date = creation + interval.
- A local notification fires on the due date at a global reminder time (Settings, default 09:00) with the text "Time to water <Name>" and `threadIdentifier` = "watering".
- Notifications are rescheduled whenever a watering is logged, the interval changes, the plant is archived or deleted, at app launch, and when remote changes arrive (observe `NSPersistentStoreRemoteChange` via `NotificationCenter.default.notifications(named:)` async sequence).
- Notification permission is requested only when the user first enables a reminder.
- Tapping a notification opens the plant profile.
- Badge on Home + profile when watering is due or overdue.

### 5.11 Settings
- Reminder time.
- iCloud status (account available / not signed in) using `CKContainer.accountStatus()`.
- **Export all data** / **Import data** (see section 6).
- Language hint: the app follows the system language, and the per-app language can be changed in iOS Settings (add a button that opens `UIApplication.openSettingsURLString`).
- About / version.

---

## 6. Export & Import

### 6.1 Format
- File: `Blattify-Backup-YYYY-MM-DD.blattify`, an **Apple Archive** (LZFSE) of a directory:
  ```
  data.json
  images/<photo-uuid>.jpg
  images/profile-<plant-uuid>.jpg
  ```
- Declare an exported UTType `de.schwimmteamerzgebirge.blattify.backup` (adjust to the final bundle ID prefix) with extension `blattify`, conforming to `public.data`. Register it as a document type so the app can open `.blattify` files from Files, AirDrop and Mail.
- `data.json` (ISO 8601 dates, sorted keys, pretty-printed):
  ```json
  {
    "formatVersion": 1,
    "exportedAt": "2026-11-06T10:00:00Z",
    "appVersion": "1.0",
    "plants": [
      {
        "id": "UUID", "code": "AB-12", "name": "…", "species": "…",
        "acquiredDate": "…|null", "notes": "", "status": "active",
        "statusDate": null, "wateringIntervalDays": 7,
        "parentID": "UUID|null", "profilePhotoFile": "images/profile-UUID.jpg|null",
        "createdAt": "…",
        "events": [ { "id": "…", "date": "…", "kind": "watering", "wateringKind": "soaked",
                      "fertilizerName": null, "fertilizerAmount": null,
                      "potDiameterCm": null, "substrate": null,
                      "resultingPlantID": null, "note": "",
                      "photoFiles": ["images/UUID.jpg"] } ],
        "infestations": [ { "id": "…", "pestType": "thrips", "customPestName": null,
                            "startDate": "…", "resolvedDate": null, "notes": "",
                            "photoFiles": [] } ]
      }
    ]
  }
  ```
- Use separate `Codable` DTO structs (`BackupDTO`, `PlantDTO`, …), never encode the `@Model` classes directly.

### 6.2 Export
- Runs off the main actor (build the DTOs on the main actor, then do file writing and compression in a `nonisolated` async function) and shows a progress indicator.
- Presented with `.fileExporter` or `ShareLink`.

### 6.3 Import (merge)
- `.fileImporter` for `.blattify`; decompress to a temporary directory; validate `formatVersion` (reject newer versions with a clear message).
- Merge rules:
  1. Match plants by `id`. If there is no match, match by `code`. If there is still no match, insert the plant.
  2. Matched plant: **local scalar values win**, except for local empty/nil fields, which are filled from the import.
  3. Events, infestations and photos are matched by `id`. Missing ones are added and existing ones are left untouched → no duplicates on repeated import.
  4. Parent relations are resolved after all plants are processed (via `parentID`).
  5. Code conflict (an imported plant with a new `id` uses a code that already belongs to a different local plant): the imported plant gets a newly generated code, and this is listed in the summary.
- Afterwards, show a summary: plants added/updated, events added, photos added, code conflicts.
- Clean up temporary files and reschedule notifications.

---

## 7. Localization

- `Localizable.xcstrings` with `en` (source) and `de`. Also localize `InfoPlist.xcstrings` (camera, photo permission texts, app name stays "Blattify").
- German terminology (use it consistently):

| English | German |
|---|---|
| Plant | Pflanze |
| Species | Pflanzenart |
| Watering | Gießen |
| Soaked | Durchdringend gegossen |
| Moistened (wet) | Leicht angefeuchtet |
| Shower | Abgeduscht |
| Fertilizing | Düngen |
| Repotting | Umtopfen |
| Cutting | Ableger / Steckling |
| New leaf | Neues Blatt |
| Pest infestation | Schädlingsbefall |
| Spider mites | Spinnmilben |
| Thrips | Thripse |
| Fungus gnats | Trauermücken |
| Mealybugs | Wollläuse |
| Scale insects | Schildläuse |
| Aphids | Blattläuse |
| Whitefly | Weiße Fliege |
| Acquired | Gekauft am |
| Given away / Died | Abgegeben / Eingegangen |
| Archive | Archiv |
| Parent plant | Mutterpflanze |

- Use `Text(date, format:)`, `.formatted()` and `RelativeDateTimeFormatter`-style APIs for all dates, numbers and units. Never build date strings manually.
- Use plural variations in the String Catalog for counts ("1 day ago" / "3 days ago").
- Use the `xcode-integration:translation-coordinator` skill to complete the German translations at the end.

---

## 8. Design Guidelines

- Clean, calm, plant-themed look: accent color = leaf green (asset catalog, light/dark), a lot of whitespace, system fonts, SF Symbols (`leaf`, `drop`, `drop.fill`, `shower`, `flask`, `square.stack.3d.up` for repotting, `scissors`, `ladybug`, `qrcode`, `qrcode.viewfinder`).
- Prefer standard components, which get Liquid Glass automatically on iOS 26 (toolbars, tab/nav bars, sheets, buttons with `.glass` / `.glassProminent` styles). Do not stack custom materials on top.
- Full Dynamic Type support, Dark Mode, VoiceOver labels on all icon-only buttons, and minimum 44 pt tap targets.
- Haptics (`.sensoryFeedback`) for logging events and successful scans.

---

## 9. Project Structure

```
Blattify/
├── App/            BlattifyApp.swift (rename MyApp.swift), AppRouter (deep links, navigation path)
├── Models/         Plant, PlantEvent, PestInfestation, EventPhoto, enums, Schema
├── Logic/          PlantCode, ActivityMatrixModel, ReminderScheduler, ImageProcessing
├── Backup/         BackupDTOs, BackupExporter, BackupImporter, UTType+Blattify
├── Views/
│   ├── Home/       PlantListView, PlantRow, PlantCard, CodeEntrySheet
│   ├── Scanner/    QRScannerView
│   ├── Plant/      PlantDetailView, PlantFormView, FamilySection, KeyFactsSection
│   ├── Events/     EventFormView, InfestationFormView, HistoryList, DayDetailView
│   ├── Matrix/     ActivityMatrixView, MatrixLegend, FilterChips
│   ├── QR/         QRLabelView, QRCodeGenerator
│   ├── Archive/    ArchiveView
│   └── Settings/   SettingsView
├── Resources/      Assets.xcassets, Localizable.xcstrings, InfoPlist.xcstrings
└── Preview Content/ SampleData.swift
BlattifyTests/      PlantCodeTests, BackupRoundTripTests, ImportMergeTests, ActivityMatrixModelTests
```

---

## 10. Build Phases

### Phase 0 – Project setup
- Set `IPHONEOS_DEPLOYMENT_TARGET = 26.0` (currently 27.2).
- Restrict to iPhone: `SUPPORTED_PLATFORMS = iphoneos iphonesimulator`, `TARGETED_DEVICE_FAMILY = 1` (it currently also includes iPad, Mac and visionOS).
- Set a real `PRODUCT_BUNDLE_IDENTIFIER` (currently `devplaceholder…`; **ask the user** for the final ID, e.g. `de.schwimmteamerzgebirge.blattify`). CloudKit requires it.
- Switch to the Swift 6 language mode.
- Capabilities: iCloud → CloudKit with container `iCloud.<bundle-id>`, Background Modes → Remote notifications. (Push Notifications entitlement is added automatically with CloudKit.)
- Info.plist: URL scheme `blattify`, `NSCameraUsageDescription`, `NSPhotoLibraryAddUsageDescription`, exported UTType + document type for `.blattify`.
- Add String Catalogs (`Localizable`, `InfoPlist`) with English + German. Set the accent color.
- Create the folder structure and a unit test target `BlattifyTests` (Swift Testing).
- ✅ *Acceptance:* the empty app builds and runs on the iOS 26 simulator. Entitlements are present.

### Phase 1 – Data layer & code logic
- Implement all models (section 3), the `VersionedSchema` and the `ModelContainer` with CloudKit config (in-memory variant for previews/tests).
- Implement `PlantCode` (section 4) and the computed plant helpers.
- Add `SampleData` for previews (5 plants, one cutting relation, events across 2 years, one active pest).
- Tests: `PlantCodeTests` (alphabet, format, normalization, rejection of invalid input, uniqueness against an existing set).
- ✅ *Acceptance:* build is green, tests pass, and the app launches with an empty store without crashing (CloudKit schema compatible).

### Phase 2 – Home, create plant, profile skeleton
- `PlantListView` with search, list/grid toggle, sorting and empty state.
- `PlantFormView` (create/edit, photo picker, species autocomplete, parent picker, interval).
- `CodeEntrySheet` with auto-formatting and lookup.
- `PlantDetailView` with header, key facts and toolbar (sections without matrix/history for now).
- `AppRouter` with a `NavigationPath`.
- ✅ *Acceptance:* the user can create a plant, see it in the list, open it by tapping or by entering its code, and edit it.

### Phase 3 – QR codes & deep links
- `QRCodeGenerator`, `QRLabelView`, PNG export via `ImageRenderer`, ShareLink and Save to Photos.
- `QRScannerView` (VisionKit) with overlay, haptics and an unsupported-device fallback.
- `.onOpenURL` handling for `blattify://plant/XX-XX`, plus the unknown-code alert.
- ✅ *Acceptance:* the label PNG looks correct, scanning the printed or on-screen label with the system Camera app opens the right profile, and the in-app scanner works on device.

### Phase 4 – Event logging & history
- Quick actions (water menu with undo, fertilize, new leaf).
- `EventFormView` for all kinds with suggestions (fertilizer, substrate) and multiple photos.
- History list with kind filter, edit and delete.
- Key facts are computed from events.
- ✅ *Acceptance:* every event kind can be created, backdated, edited and deleted, with photos. Key facts update immediately.

### Phase 5 – Activity matrix
- `ActivityMatrixModel` (pure logic: year grid, week/weekday mapping using the locale's first weekday, category set per day, pest ranges, watering priority).
- `ActivityMatrixView` with `Canvas`, split cells, filter chips, legend, year navigation and swipe, day detail on tap, and accessibility.
- Tests: `ActivityMatrixModelTests` (leap year, year boundaries, first-weekday Monday vs. Sunday, pest range spanning years, watering priority).
- ✅ *Acceptance:* the matrix renders smoothly, colors match the legend in light and dark mode, and tapping a day shows the correct events.

### Phase 6 – Pests, cuttings & family, archive
- `InfestationFormView`, the pest section on the profile, "Mark as resolved", and the active-pest badges in Home and on the profile.
- Cutting flow → create child plant (prefilled), `resultingPlantID`, and the family tree section.
- Archive status with date, `ArchiveView`, restore, and permanent delete with confirmation.
- ✅ *Acceptance:* a cutting creates a linked child plant in two taps, the family tree shows parent and children, and archived plants disappear from Home but stay in family trees.

### Phase 7 – Watering reminders
- `ReminderScheduler` (async, `UNUserNotificationCenter`) with all reschedule triggers from 5.10, the reminder time setting, permission flow and notification-tap deep link.
- Due badges in Home and on the profile.
- ✅ *Acceptance:* with a 1-day interval and a reminder time a few minutes ahead, the notification arrives, tapping it opens the plant, and logging a watering moves the next notification.

### Phase 8 – Export & import
- DTOs, `BackupExporter` (Apple Archive), `BackupImporter` (merge rules from 6.3), Settings UI, progress indicator and import summary.
- Opening `.blattify` files from Files or AirDrop triggers the import flow (with confirmation).
- Tests: `BackupRoundTripTests` (export → import into an empty in-memory store gives identical data including relations and photos) and `ImportMergeTests` (repeated import creates no duplicates, local values win, empty local fields get filled, code conflict gets a new code, newer `formatVersion` is rejected).
- ✅ *Acceptance:* all tests pass, and a backup exported on one device restores completely on a fresh install.

### Phase 9 – iCloud verification, localization & polish
- Verify sync between two devices or simulators signed into the same iCloud account (create, edit, delete, photos). Show the iCloud status in Settings.
- Complete the German translations (translation-coordinator skill). Check that no string is left untranslated and test both languages in the simulator.
- Accessibility pass (Dynamic Type at the largest sizes, VoiceOver, contrast). The `xcode-integration` accessibility skills may be used.
- App icon (leaf + QR motif, Icon Composer / Liquid Glass compatible), launch appearance, empty states, error messages.
- Final test run: all `BlattifyTests` green, build without warnings.
- ✅ *Acceptance:* the full checklist in section 11 passes.

---

## 11. Final Acceptance Checklist

- [ ] Plant can be created → unique `XX-XX` code generated (no I/L/O/0/1)
- [ ] QR label PNG with code + name can be shared and saved to Photos
- [ ] System Camera scan of a label opens the app on the plant profile
- [ ] In-app scanner and manual code entry (case-insensitive) open the profile
- [ ] Watering (soaked / wet / shower), fertilizing (name, amount), repotting (pot size, substrate), cutting, new leaf and pest episodes can be logged with date, note and photos
- [ ] History can be edited and deleted
- [ ] Combined yearly matrix with split cells, filter chips, legend, year navigation and day detail
- [ ] Cutting → child plant with parent link, and the family tree is visible
- [ ] Archive (given away / died) with restore; permanent delete
- [ ] Per-plant watering reminders with notifications and due badges
- [ ] Export `.blattify` (JSON + photos) and merge import without duplicates
- [ ] iCloud sync works between two devices
- [ ] Complete English and German UI, following the system language
- [ ] Dark Mode, Dynamic Type and VoiceOver work
- [ ] Unit tests for code logic, matrix model and backup pass

---

## 12. Out of Scope (v1)

Widgets, Apple Watch, iPad/Mac layouts, shared plants between iCloud users (CloudKit sharing), fertilizing reminders, plant identification / care databases, statistics beyond the matrix.
