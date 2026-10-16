# Architecture

Cicero is a SwiftPM package with two targets and a test target, which stays out of the public
repository. Its one dependency is Sparkle (a binary framework, used by the app target only) for updates.

```
Sources/CiceroCore   fonts, the library, activation, coverage, user data — no UI
Sources/Cicero       the app (SwiftUI); everything runs on the main actor by default
Tests/CiceroCoreTests
```

## CiceroCore

Plain Swift and CoreText, Swift 6 strict concurrency, every public type `Sendable`.

- **Model** (`Model/Font.swift`): `FontFace` (what a file says about one face), `LibraryFace` (a face's
  state in the library), `Family` (faces plus everything lists and filters need, computed once, the
  classification among them). `LetterShapes` (`Library/`) judges serif, sans serif or monospaced from the
  outlines and widths of a few letters when the scanner reads a face whose file doesn't say; the answer is
  cached with the face.
- **Library** (`Library/`): `LibraryScanner` finds font files (CoreText's active fonts, macOS's font folders,
  which CoreText's lists don't cover entirely, the Fonts folders, watched folders, files added one at a time, the Deactivated folder), reads new or changed files
  with a stamp-keyed cache, and builds an immutable `Library` snapshot off the main thread. A `fingerprint`
  lets the app skip rescans that changed nothing. `LibraryCache` saves each library a scan builds that differs from the
  last one saved, in the face cache's binary layout, and `savedLibrary` reads it back for the next launch's window. `FolderWatcher` (FSEvents) says when font files come or go
  in the scanned folders, and when an added file changes: it watches the file's folder, which then speaks
  only for that file.
- **Data** (`Data/`): `UserData` is everything the user set up (folders, added font files, sets, smart sets,
  tags and their colours, foundry names, character sets, sidebar choices, install method, activation records).
  `UserDataStore` saves it as JSON, coalesced and off the main thread, and imports the version 1 file once.
- **Activation** (`Activation/`): `ActivationEngine` copies, registers in place, registers for the
  session, deactivates and trashes. It takes and returns `ActivationRecords`, so the app owns the
  state and the engine stays testable; `FontRegistrar` hides CoreText so tests never touch the system.
  Every change goes through fontd and waits for it (copies are registered too, files are unregistered
  before they move), and a file only counts once fontd reports it active: when an operation returns,
  every app already has the result. `SystemActivationTests` (opt-in) checks that against the real system.
- **Signposts** (`Signposts.swift`): os_signpost intervals (subsystem com.maximilianinzinger.Cicero) for activation
  (copy, register, confirm), scans (find, parse, build, save cache), restoring the saved library, applying a library, and coverage,
  for timing them in Instruments.
- **Coverage** (`Coverage/`): `ScalarRanges` (characters a face has), `LanguageCatalog` (Hyperglot),
  `CharacterSetCatalog` (Latin S–XL, Adobe Latin, Google Fonts sets, custom sets), and
  `CoverageIndex`, which works out every family's coverage in the background and caches it on disk.
- **Rendering** (`Rendering/`): `FontLoader` makes CTFonts straight from files (so inactive fonts
  preview) and prefetches them after scans, four files at a time, what the browser shows first. It keeps
  the descriptors the scanner reads from new files, and coverage uses them too, so a file is read once.
  Feature groups, font info and glyph sections. `LigatureGroup` reads a face's ligatures from its GSUB table
  (`GSUBLigatures`, which checks every offset, so a damaged table gives fewer ligatures, never a crash) and maps
  their components back to characters through the cmap.
- **Documents** (`Documents/`): `DocumentFonts` reads the fonts a PDF (CGPDF), IDML (`unzip -p`), InDesign or
  Illustrator file (XMP) uses, trusting nothing in the file, and matches them to the library; `FontFileSearch`
  asks Spotlight for font files by PostScript name.
- **Problems**, **Caches**: finding conflicts, duplicates, missing and damaged files; clearing the
  font caches of macOS, Adobe apps and Microsoft Office. `SpareCopies` says whether files can go without
  taking a face's last copy with them; Problems offers to remove a file only then, and `moveToTrash`
  asks it again for those files right before trashing them.
- **AppLocation** (`AppLocation.swift`): whether a bundle is in an Applications folder, where a moved copy
  goes and what happens to the original (`move`), the path a translocated app was opened from
  (Security.framework SPI looked up with dlsym), and the copy that strips quarantine (`install`, whose
  Trash tests replace).
- **Backup** (`Backup/`): `FontExporter` copies families' files into a folder or a ZIP archive;
  `LibraryBackup` writes and reads `.cicerobackup` archives (manifest, user data, font files),
  puts fonts back without writing over anything, and merges activation records for this Mac.
  Restoring trusts nothing in the archive: only font files, only into font locations, and only
  records about those. Exports and backups are built in a private folder on the destination's disk
  and moved into place once complete (`ItemReplacement`), and never replace an item holding fonts
  Cicero uses. Both take URLs, so tests run in temporary folders; ZIPs are made and read with `ditto`.

## The app

- `AppModel` (`Model/`) holds the current `Library`, the `UserData` and what the windows show. It
  starts scans, applies results, and runs activation-type operations one at a time so their record
  changes never overwrite each other. Switches move when clicked (`expect`) and the scan an operation
  starts when it finishes confirms them; font-change notifications during an operation are left to
  that scan (or one right after the operation, when it starts none). It's made before the window, and restores
  the library the last scan saved and starts the first scan then, so the window opens with the fonts in it; `apply`
  always takes that first scan's library, whatever its fingerprint. Lists it hands to views (`visibleFamilies`, sidebar rows,
  character set lookups, custom character sets) are cached and keyed on the inputs they depend on. The
  sidebar's choices (open sections, order, hidden items) are user data that no list depends on, so changing
  them leaves `dataRevision`, and the browser's list, as they are.
- `ClassificationGuesser` (`Model/`) asks Apple Intelligence's on-device model to guess, from their names,
  the classification of families nothing in their files classifies, one at a time after scans, and keeps the
  answers in the caches. `classificationNamer` applies them below the user's choices; `guessRevision`, in
  `VisibleKey`, refills lists as they come.
- `PreviewSettings` holds sample text, size, weight, letter and line spacing and alignment; `Appearance` the
  light/dark choice. Line spacing is an exact line height (`.lineHeight(.exact(points:))`, macOS 26), which
  the font page's editor (`SampleEditor`, an NSTextView with the same line height) follows too, so its text
  and the hidden copy that sizes it agree. Not SwiftUI's `TextEditor`, which, like `Text`, cuts glyphs off at
  the font's ascent and descent: `SampleEditor`'s layout fragments (`UnclippedFragment`) widen their rendering
  surface to the glyphs' ink, and `FontText` draws through `UnclippedText`, a text renderer whose display
  padding gives room above and below. About one font in ten draws past its own descent.
- Files come in through `AppModel.open` (`Model/AppModel+Files.swift`): from the Finder (Info.plist declares the
  font types; the main window's scene handles external events, and SwiftUI gives its `onOpenURL` only the first of
  several files, `AppDelegate.application(_:open:)` the rest), from a drop on the browser or a font page, and from
  Add Fonts. It gathers URLs for a moment, adds folders and unlisted files to the user data, and shows
  their families once the scan it starts is done (`showOpenedFiles`, called as each scan ends).
- `TextEditingKeys` (`App/`) is a local key-down monitor: while an editable text view or field editor has the
  focus, it hands ⌫, ⌘⌫ and ⌘-arrows to it before the menus' shortcuts (Deactivate, Move to Trash, Open) can
  take them. In any window but the main one (its `mainWindow`, set by a `WindowReader` in `MainWindow`), it
  hands ⌫ and ⌘⌫ to that window, since the menus would act on the main window's selection.
- `QuickLook` (`Windows/QuickLook.swift`, owned by `AppModel` like `AppSetWatcher`) runs the Quick Look
  panel: a `QuickLookPanel`, an NSPanel that can't become key, hosting SwiftUI in an NSHostingView with the
  model and preview settings in its environment. The main window keeps the keyboard, so the browser's keys
  (`FamilyKeys` in `Browser/Selection.swift`: Space, Esc, ↩ and the arrows; the list keeps its own ↑/↓) go on
  moving the selection the panel shows. `QuickLookHost`, in the main window, hands it the window (centred over, closed
  with, out of the way of its sheets) and the selection's changes. The panel is made once, ordered out when
  closed, and draws nothing then; a font file nothing has read yet is read off the main thread first.
- `Updates` (`App/`) owns Sparkle's `SPUStandardUpdaterController` for Check for Updates and the
  automatic-check switch. It starts the updater only when Cicero runs from an .app bundle: a `swift run`
  binary has no Info.plist with the feed.
- `ApplicationsFolder` (`App/`) asks at launch to move Cicero into the Applications folder, and again
  instead of registering a login item from elsewhere (`LoginItem.set`). It finds disk images with
  DiskArbitration, moves through `AppLocation`, and relaunches the copy from a shell script that waits
  for Cicero to quit and detaches the image.
- The main window's detail column is a NavigationStack, and a stack in a split view's detail column swaps the
  whole column for a page pushed onto it, dropping whatever is wrapped around the stack. So the Info panel is an
  overlay on the split view (`InfoPanelOverlay`), and each page (the browser, a font page) makes room for it and
  takes dropped files itself (`DetailPage`).
- Views are grouped by window: `Sidebar/`, `Browser/` (list, grid, specimens), `FontPage/`, `Info/`,
  `Windows/` (Character Toolbox, Compare, Problems, Quick Look, sheets), `Settings/`. Shared pieces
  are in `Components/`.
- The sidebar is a SwiftUI `List`, so every row it shows is a hosting view of its own, about a millisecond
  each to make: `SidebarView` keeps its sections in a view apart from the list, so a change of selection
  doesn't remake them, only sets and foundries are drop targets (that alone makes a row a third slower to
  appear), and while the selection changes quickly the browser takes it only once it rests. SwiftUI's List
  is an NSOutlineView; a marker view behind the "Fonts" header finds it and sets its drop feedback to
  `.gap`, the one AppKit setting the sidebar changes. Everything else (selection, moves, menus, headers)
  stays SwiftUI's.

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
  Only rows of about one height go in a lazy stack: the page's header, type tester and styles sit in a
  plain stack above the lazy one, since a family's fifty styles, one 2,000 pt row of it, made the guesses
  swing the same way whenever the page was scrolled to its end.
- Sizes worked out from geometry (the font page's glyph columns, the list's column widths) come from a
  width that doesn't depend on them, so a layout settles in one pass.
- The only network access is Sparkle's: the appcast on GitHub and an update the user accepts. Nothing is
  uploaded. Files Cicero removes go to the Trash; it never deletes a user's only copy of a font. Everything that trashes takes the trash as a parameter (`trash` on the
  engine, exporter and backup, `using:` for app caches), so tests remove temporary files instead and
  never touch the user's Trash.

## Building and releasing

- `scripts/build-app.sh` builds `build/Cicero.app` from the release binary: Info.plist, resources, the
  compiled icon, and Sparkle.framework in Contents/Frameworks (the binary's rpath
  `@executable_path/../Frameworks` comes from Package.swift). Sparkle's XPC services are removed: they're
  for sandboxed apps, and Cicero isn't. Code is signed inside out, never with `--deep`: Sparkle's
  Autoupdate and Updater.app, the framework, then the app. Dev builds are signed ad hoc; with
  `SIGN_IDENTITY` (a Developer ID) every piece gets the hardened runtime and a secure timestamp.
  It hands the SDK to the link step as well (`-Xclang-linker -isysroot`): SwiftPM's build system leaves it
  out, so the binary would record the deployment target's SDK (26) and a newer macOS would treat Cicero as
  built for 26, with that release's behaviour. The script stops if the recorded SDK isn't the one it built with.
- `scripts/release.sh` signs with the Developer ID, notarizes and staples the app (nested Sparkle code
  included) and then the DMG made by `make-dmg.sh`.
- `scripts/publish.sh` runs `make-appcast.sh`, which signs the final DMG with the Sparkle EdDSA key (keychain
  account "cicero"; `SUPublicEDKey` is its public half) and writes `build/appcast.xml`, then uploads the DMG
  and the appcast to a new GitHub release. `SUFeedURL` points at the latest release's appcast.
