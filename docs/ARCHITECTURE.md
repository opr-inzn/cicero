# Architecture

Cicero is a SwiftPM package with two targets and a test target.

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
- **Signposts** (`Signposts.swift`): os_signpost intervals (subsystem local.cicero.Cicero) for activation
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
- Views are grouped by window: `Sidebar/`, `Browser/` (list, grid, specimens), `FontPage/`, `Info/`,
  `Windows/` (Character Toolbox, Compare, Problems, sheets), `Settings/`. Shared pieces
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
- Cicero never connects to the internet. Files it removes go to the Trash; it never deletes a
  user's only copy of a font.
