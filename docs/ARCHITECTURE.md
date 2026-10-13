# Architecture

Cicero is a SwiftPM package with two targets and a test target. Its one dependency is Sparkle (a binary
framework, used by the app target only) for updates.

```
Sources/CiceroCore   fonts, the library, activation, coverage, user data — no UI
Sources/Cicero       the app (SwiftUI); everything runs on the main actor by default
Tests/CiceroCoreTests
```

## CiceroCore

Plain Swift and CoreText, Swift 6 strict concurrency, every public type `Sendable`.

- **Model** (`Model/Font.swift`): `FontFace` (what a file says about one face), `LibraryFace` (a face's
  state in the library), `Family` (faces plus everything lists and filters need, computed once).
- **Library** (`Library/`): `LibraryScanner` finds font files (CoreText's active fonts, the Fonts
  folders, watched folders, the Deactivated folder), reads new or changed files with a stamp-keyed
  cache, and builds an immutable `Library` snapshot off the main thread. A `fingerprint` lets the
  app skip rescans that changed nothing. `FolderWatcher` (FSEvents) says when font files come or go
  in the scanned folders.
- **Data** (`Data/`): `UserData` is everything the user set up (folders, sets, smart sets, tags,
  foundry names, character sets, sidebar choices, install method, activation records).
  `UserDataStore` saves it as JSON, coalesced and off the main thread, and imports the version 1 file once.
- **Activation** (`Activation/`): `ActivationEngine` copies, registers in place, registers for the
  session, deactivates and trashes. It takes and returns `ActivationRecords`, so the app owns the
  state and the engine stays testable; `FontRegistrar` hides CoreText so tests never touch the system.
  Every change goes through fontd and waits for it (copies are registered too, files are unregistered
  before they move), and a file only counts once fontd reports it active: when an operation returns,
  every app already has the result. `SystemActivationTests` (opt-in) checks that against the real system.
- **Signposts** (`Signposts.swift`): os_signpost intervals (subsystem com.maximilianinzinger.Cicero) for activation
  (copy, register, confirm), scans (find, parse, build, save cache), applying a library, and coverage,
  for timing them in Instruments.
- **Coverage** (`Coverage/`): `ScalarRanges` (characters a face has), `LanguageCatalog` (Hyperglot),
  `CharacterSetCatalog` (Latin S–XL, Adobe Latin, Google Fonts sets, custom sets), and
  `CoverageIndex`, which works out every family's coverage in the background and caches it on disk.
- **Rendering** (`Rendering/`): `FontLoader` makes CTFonts straight from files (so inactive fonts
  preview) and prefetches them after scans, four files at a time, what the browser shows first. It keeps
  the descriptors the scanner reads from new files, and coverage uses them too, so a file is read once.
  Feature groups, font info and glyph sections.
- **Problems**, **Caches**: finding conflicts, duplicates, missing and damaged files; clearing the
  font caches of macOS, Adobe apps and Microsoft Office.
- **AppLocation** (`AppLocation.swift`): whether a bundle is in an Applications folder, where a moved copy
  goes and what happens to the original (`move`), the path a translocated app was opened from
  (Security.framework SPI looked up with dlsym), and the copy that strips quarantine (`install`, whose
  Trash tests replace).
- **Backup** (`Backup/`): `FontExporter` copies families' files into a folder or a ZIP archive;
  `LibraryBackup` writes and reads `.cicerobackup` archives (manifest, user data, font files),
  puts fonts back without writing over anything, and merges activation records for this Mac.
  Both take URLs, so tests run in temporary folders; ZIPs are made and read with `ditto`.

## The app

- `AppModel` (`Model/`) holds the current `Library`, the `UserData` and what the windows show. It
  starts scans, applies results, and runs activation-type operations one at a time so their record
  changes never overwrite each other. Switches move when clicked (`expect`) and the scan an operation
  starts when it finishes confirms them; font-change notifications during an operation are left to
  that scan (or one right after the operation, when it starts none). Lists it hands to views (`visibleFamilies`, sidebar rows,
  character set lookups) are cached and keyed on the inputs they depend on.
- `PreviewSettings` holds sample text, size, weight and spacing; `Appearance` the light/dark choice.
- `TextEditingKeys` (`App/`) is a local key-down monitor: while an editable text view or field editor has the
  focus, it hands ⌘⌫ and ⌘-arrows to it before the menus' shortcuts (Deactivate, Open) can take them.
- `QuickLook` (`Windows/QuickLook.swift`, owned by `AppModel` like `AppSetWatcher`) runs the Quick Look
  panel: a `QuickLookPanel`, an NSPanel that can't become key, hosting SwiftUI in an NSHostingView with the
  model and preview settings in its environment. The main window keeps the keyboard, so the browser's keys
  (`FamilyKeys` in `Browser/Selection.swift`: Space, Esc, ↩ and the arrows; the list keeps its own ↑/↓) go on
  moving the selection the panel shows. `QuickLookHost`, in the main window, hands it the window (centred over, closed
  with, out of the way of its sheets) and the selection's changes. The panel is made once, ordered out when
  closed, and draws nothing then; a font file nothing has read yet is read off the main thread first.
- `Updates` (`App/`) owns Sparkle's `SPUStandardUpdaterController` for Check for Updates… and the
  automatic-check switch. It starts the updater only when Cicero runs from an .app bundle: a `swift run`
  binary has no Info.plist with the feed.
- `ApplicationsFolder` (`App/`) asks at launch to move Cicero into the Applications folder, and again
  instead of registering a login item from elsewhere (`LoginItem.set`). It finds disk images with
  DiskArbitration, moves through `AppLocation`, and relaunches the copy from a shell script that waits
  for Cicero to quit and detaches the image.
- Views are grouped by window: `Sidebar/`, `Browser/` (list, grid, specimens), `FontPage/`, `Info/`,
  `Windows/` (Character Toolbox, Compare, Problems, Quick Look, sheets), `Settings/`. Shared pieces
  are in `Components/`.

## Rules of thumb

- Views read precomputed values; anything that walks the whole library or reads files happens in
  CiceroCore, off the main thread, and only when its inputs change.
- Long lists of families are lazy stacks (`FontList`, `FamilyRowList`), never `Table` or `List`: AppKit's
  tables make every row whenever an accessibility client walks the window, which with a thousand
  families blocks the main thread for minutes. A lazy stack exposes only the rows on screen.
- No lazy stack or grid inside another one. The outer one guesses the height of what it hasn't placed
  from what it has; when that swings (a lazy grid of one row next to one of hundreds), every correction
  moves the content and changes what's placed, and the page can lay itself out again and again at full
  CPU. The font page's glyph blocks did that as `LazyVGrid`s in the page's `LazyVStack`; they're now rows
  of fixed-size cells in the page's own stack, so every row is one height, with one popover per row.
- Sizes worked out from geometry (the font page's glyph columns, the list's column widths) come from a
  width that doesn't depend on them, so a layout settles in one pass.
- The only network access is Sparkle's: the appcast on GitHub and an update the user accepts. Nothing is
  uploaded. Files Cicero removes go to the Trash; it never deletes a user's only copy of a font.

## Building and releasing

- `scripts/build-app.sh` builds `build/Cicero.app` from the release binary: Info.plist, resources, the
  compiled icon, and Sparkle.framework in Contents/Frameworks (the binary's rpath
  `@executable_path/../Frameworks` comes from Package.swift). Sparkle's XPC services are removed: they're
  for sandboxed apps, and Cicero isn't. Code is signed inside out, never with `--deep`: Sparkle's
  Autoupdate and Updater.app, the framework, then the app. Dev builds are signed ad hoc; with
  `SIGN_IDENTITY` (a Developer ID) every piece gets the hardened runtime and a secure timestamp.
- `scripts/release.sh` signs with the Developer ID, notarizes and staples the app (nested Sparkle code
  included) and then the DMG made by `make-dmg.sh`.
- `scripts/publish.sh` runs `make-appcast.sh`, which signs the final DMG with the Sparkle EdDSA key (keychain
  account "cicero"; `SUPublicEDKey` is its public half) and writes `build/appcast.xml`, then uploads the DMG
  and the appcast to a new GitHub release. `SUFeedURL` points at the latest release's appcast.
