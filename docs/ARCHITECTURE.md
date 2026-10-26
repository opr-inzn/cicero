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
  cached with the face. `LocalizedNames` (`Library/`) reads the family's names in other languages from the name
  table, all of them, cached with the face, and picks the one for the Mac's languages: a `Family`'s `name` is the
  one it shows, its `id` the fonts' own, which the user's data keys by.
- **Library** (`Library/`): `LibraryScanner` finds font files (CoreText's active fonts, macOS's font folders,
  which CoreText's lists don't cover entirely, the Fonts folders, watched folders (the sidebar's Locations), files added one at a time, the Inactive folder), reads new or changed files
  with a stamp-keyed cache, and builds an immutable `Library` snapshot off the main thread. Each file read goes into
  the cache at once, which is written every 2 s while reading goes on and by `flush` as the app quits, so neither a
  scan that's replaced nor quitting loses what was read; its progress says it updates rather than identifies when most
  of the files it reads are in the library on screen (the last one built, else the one restored at launch). A `fingerprint`
  lets the app skip rescans that changed nothing. `LibraryCache` saves each library a scan builds that differs from the
  last one saved, in the face cache's binary layout, and `savedLibrary` reads it back for the next launch's window. `FolderWatcher` (FSEvents) says when font files come or go
  in the scanned folders, and when an added file changes: it watches the file's folder, which then speaks
  only for that file.
- **Data** (`Data/`): `UserData` is everything the user set up (watched folders, added font files, sets and smart sets, which the
  UI calls folders and smart folders, tags (license tags to begin with) and their colours, ratings, notes, foundry names, character sets, sidebar choices, install method, activation records).
  `UserDataStore` saves it as JSON, coalesced and off the main thread, and imports the version 1 file once.
- **Activation** (`Activation/`): `ActivationEngine` copies, registers in place, registers for the
  session, deactivates and trashes. It takes and returns `ActivationRecords`, so the app owns the
  state and the engine stays testable; `FontRegistrar` hides CoreText so tests never touch the system.
  Every change goes through fontd and waits for it (copies are registered too; files in a Fonts folder
  are turned off there with `CTFontManagerEnableFontDescriptors`, as Font Book does, and others
  unregistered, also before they move), and a file only counts once fontd reports it active: when an operation returns,
  every app already has the result. `SystemActivationTests` (opt-in) checks that against the real system.
  The app's `engine` carries the Font Library (`fontLibrary`, from `UserData.fontLibraryPath`) and whether to install
  into it (`installsIntoFontLibrary`): copies then go into a folder for each family there and are registered where
  they are, recorded as installed copies and in place, and files in the library are only ever registered and
  unregistered (`FontLibrary.swift`: folder names, taking away folders left empty, moving the copies installed in
  ~/Library/Fonts before into the library, moving the library, and where it can't go).
- **Signposts** (`Signposts.swift`): os_signpost intervals (subsystem com.maximilianinzinger.Cicero) for activation
  (copy, register, confirm), scans (find, parse, build, save cache), restoring the saved library, applying a library, and coverage,
  for timing them in Instruments.
- **Coverage** (`Coverage/`): `ScalarRanges` (characters a face has), `LanguageCatalog` (Hyperglot),
  `CharacterSetCatalog` (Latin S–XL, Adobe Latin, Google Fonts sets, custom sets), and
  `CoverageIndex`, which works out every family's coverage in the background and caches it on disk.
- **Similarity** (`Similarity/`): `LetterMeasurements` measures a face's letters from their outlines (x-height,
  weight, contrast and stress, widths, spacing, slant, serifs, aperture, squareness, the a's and g's stories,
  monospacing), with `LetterShapes`' outline runs; `LetterImages` draws 16 of its letters small, on one baseline and
  x-height, with their advances, and `LetterEmbedding` turns them into 128 numbers with a small Core ML model
  learned from Google Fonts (Resources/LetterEmbedding.mlpackage, made by scripts/embedding), close together for
  faces that look alike;
  `MeasurementIndex` measures and embeds every family's regular style in the background after coverage and caches
  the results on disk, as `CoverageIndex` does; `SimilarFonts` ranks the families nearest one, measure by measure in
  fixed steps, weighted, and by the embedding's distance, leaving out the families the user marked not similar
  (`UserData.notSimilar`). The app keeps one `SimilarFonts` for the listed families and makes it again when the
  library, the measurements or the user's data change. `SimilarReport` is what a mark sends, the list by its names
  and numbers; `SimilarReports` (`App/`) sends it, as `UsageStatistics` sends its signal.
- **Rendering** (`Rendering/`): `FontLoader` makes CTFonts straight from files (so inactive fonts
  preview) and prefetches them after scans, four files at a time, what the browser shows first; specimens
  prefetch the styles of the cards around those coming into view. A prefetch has the whole file read ahead
  (`F_RDADVISE`), glyphs included, not just the tables a descriptor needs. It keeps
  the descriptors the scanner reads from new files, and coverage uses them too, so a file is read once.
  Feature groups, font info and glyph sections. `LigatureGroup` reads a face's ligatures from its GSUB table
  (`GSUBLigatures`, which checks every offset, so a damaged table gives fewer ligatures, never a crash) and maps
  their components back to characters through the cmap. `CharacterCodes` writes a character's U+ code and HTML
  entities for the glyph map; `KeyboardLayout` works out how the keyboard layout in use types each character, with
  UCKeyTranslate over the layout's data (Text Input Sources, on the main thread), once per layout.
- **Documents** (`Documents/`): `DocumentFonts` reads the fonts a PDF (CGPDF), IDML (`unzip -p`), InDesign or
  Illustrator file (XMP) or Photoshop file (text layers) uses, trusting nothing in the file, and matches them to the library with `FontMatcher`
  (`Library/`: by file, PostScript name, or family and style names); `FontFileSearch` asks Spotlight for font files
  by PostScript name.
- **Problems**, **Caches**: finding conflicts, duplicates, missing and damaged files; clearing the
  font caches of macOS, Adobe apps and Microsoft Office. `SpareCopies` says whether files can go without
  taking a face's last copy with them; Conflicts offers to remove a file only then, and `moveToTrash`
  asks it again for those files right before trashing them.
- **AppLocation** (`AppLocation.swift`): whether a bundle is in an Applications folder, where a moved copy
  goes and what happens to the original (`move`), the path a translocated app was opened from
  (Security.framework SPI looked up with dlsym), and the copy that strips quarantine (`install`, whose
  Trash tests replace).
- **Backup** (`Backup/`): `FontExporter` copies families' files into a folder or a ZIP archive; `FontListCSV` writes
  the font list as CSV;
  `LibraryBackup` writes and reads `.cicerobackup` archives (manifest, user data, font files),
  puts fonts back without writing over anything, and merges activation records for this Mac.
  Restoring trusts nothing in the archive: only font files, only into font locations, and only
  records about those. Exports and backups are built in a private folder on the destination's disk
  and moved into place once complete (`ItemReplacement`), and never replace an item holding fonts
  Cicero uses. Both take URLs, so tests run in temporary folders; ZIPs are made and read with `ditto`.
- **Import** (`Import/`): `FontExplorerImport` reads FontExplorer X Pro's SQLite database (a copy, opened read-only
  and immutable through `SQLiteFile`, the system's SQLite) or its backups, and `FontBookImport` Font Book's
  `.collection` archives (their font descriptors read as attributes, without AppKit), into an `ImportedLibrary`:
  fonts named by file, PostScript name or family and style, sets, smart sets with their rules already in Cicero's
  terms, labels as tags, ratings, comments, activation history. `LibraryImport` adds the other app's fonts to the user data,
  then, once a scan has read them, matches the rest to the library and adds it, only ever adding.

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
- `ClassificationGuesser` (`Model/`) asks Apple Intelligence's on-device model (macOS 26; its `availability` is
  `.unavailable` on macOS 15) to guess, from their names,
  the classification of families nothing in their files classifies, one at a time after scans, and keeps the
  answers in the caches. `letterGuesses` holds what `LetterEmbedding`'s model sees in their letters, as
  `MeasurementIndex` caches it. `classificationGuess` applies the name's guess, else the letters', below the user's
  choices and only while guessing is on; `guessRevision`, in `VisibleKey`, refills lists as they come.
- `PreviewSettings` holds sample text, size, weight, letter and line spacing and alignment; `Appearance` the
  light/dark choice. Line spacing is an exact line height (`.lineHeight(.exact(points:))` on macOS 26, extra
  `lineSpacing` on macOS 15: `lineHeight(_:natural:)`), which
  the font page's editor (`SampleEditor`, an NSTextView with the same line height) follows too, so its text
  and the hidden copy that sizes it agree. Not SwiftUI's `TextEditor`, which, like `Text`, cuts glyphs off at
  the font's ascent and descent: `SampleEditor`'s layout fragments (`UnclippedFragment`) widen their rendering
  surface to the glyphs' ink, and `FontText` draws through `UnclippedText`, a text renderer whose display
  padding gives room above and below. About one font in ten draws past its own descent.
- Files come in through `AppModel.open` (`Model/AppModel+Files.swift`): from the Finder (Info.plist declares the
  font types; the main window's scene handles external events, and SwiftUI gives its `onOpenURL` only the first of
  several files, `AppDelegate.application(_:open:)` the rest), from a drop on the browser or a font page, and from
  Add Fonts. It gathers URLs for a moment, adds folders and unlisted files to the user data, and shows
  their families once the scan it starts is done (`showOpenedFiles`, called as each scan ends). Unlisted files
  first go through `addCheckingDuplicates`, which reads their faces off the main thread and asks
  `AddedDuplicates` (CiceroCore) which families the library has from other files; the setting, or the
  `DuplicatesSheet`, says per family whether to skip, add or take over, and taking over is a `switchCopies`
  operation with the added faces as the new copies (`AddedDuplicates.replacement`).
- `TextEditingKeys` (`App/`) is a local key-down monitor: while an editable text view or field editor has the
  focus, it hands ⌫, ⌘⌫ and ⌘-arrows to it before the menus' shortcuts (Deactivate, Move to Trash, Open) can
  take them. In any window but the main one (its `mainWindow`, set by a `WindowReader` in `MainWindow`), it
  hands ⌫ and ⌘⌫ to that window, since the menus would act on the main window's selection.
- `SearchTokenTint` (`Browser/`) tints the search field's tokens with the highlight colour. SwiftUI's token cell
  is a subclass of AppKit's private `NSTokenAttachmentCell` that fills tokens grey in its own
  `drawTokenWithFrame:inView:`; AppKit's `drawWithFrame:inView:`, replaced at launch, gives that class AppKit's
  method back and a `tokenTintColor` the first time it draws one of its tokens. Without those classes and
  methods, the tokens stay SwiftUI's.
- `QuickLook` (`Windows/QuickLook.swift`, owned by `AppModel` like `AppSetWatcher`) runs the Quick Look
  panel: a `QuickLookPanel`, an NSPanel that can't become key, hosting SwiftUI in an NSHostingView with the
  model and preview settings in its environment. The main window keeps the keyboard, so the browser's keys
  (`FamilyKeys` in `Browser/Selection.swift`: Space, Esc, ↩ and the arrows; the list keeps its own ↑/↓) go on
  moving the selection the panel shows. `QuickLookHost`, in the main window, hands it the window (centred over, closed
  with, out of the way of its sheets) and the selection's changes. The panel is made once, ordered out when
  closed, and draws nothing then; a font file nothing has read yet is read off the main thread first.
- `Updates` (`App/`) owns Sparkle's `SPUStandardUpdaterController` for Check for Updates and the
  automatic-check switch. It starts the updater only when Cicero runs from an .app bundle: a `swift run`
  binary has no Info.plist with the feed. With the switch on, it checks right after starting the updater,
  before Sparkle's first scheduling pass, so Sparkle counts its day from that check.
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
  doesn't remake them, only sets (the Folders section) and foundries are drop targets (that alone makes a row a third slower to
  appear), and while the selection changes quickly the browser takes it only once it rests. SwiftUI's List
  is an NSOutlineView; a marker view behind the "Fonts" header finds it and sets its drop feedback to
  `.gap`, the one AppKit setting the sidebar changes. The gap comes with one question SwiftUI can't answer:
  as a drag leaves the list, AppKit asks its data source about a drop at child index -2, and SwiftUI looks up
  row -2 and crashes, so `SidebarDataSource` replaces that method in the data source's class and answers it
  with no drop, handing every other question on; without the method to replace, no gap. It also hands on
  the starts and ends of drags to `SidebarDrag`, which learns a drag's rows from each row's `itemProvider`
  (asked for as the drag starts, an empty item) and hides them when they're let go of outside the list, and
  puts `draggedImage:movedTo:` into the outline view's class, so each move sets Finder's × outside the list
  (a timer doesn't run during a drag on macOS 26), and `draggingSession:endedAtPoint:operation:`, which closes
  the gap without animating after a drop in the list. Dragged rows get pictures drawn by `SidebarDrag`.
  Everything else (selection, moves, menus, headers) stays SwiftUI's.
- The deployment target is macOS 15. What Cicero uses of macOS 26 (glass, bars over scroll views, exact line
  heights, drop sessions and configurations, the on-device language model) is behind `#available(macOS 26, *)`,
  mostly in small modifiers in `Components/Compatibility.swift` (`glass(in:)`, `topBar`, `drops(of:)`, …) that
  give macOS 15 what it has instead, so call sites read the same for both. The SPEC's "macOS 15" lists them.
- A soft top scroll edge on macOS 26 (AppKit's private `NSScrollPocket`, which samples the brightness under it)
  makes the toolbar's glass over it light or dark from what it sees. After a switch to Dark, AppKit set the
  toolbar view's appearance to VibrantDark and, half a second later, back to VibrantLight, and kept it until
  something scrolled; under a hard edge it never did. `toolbarGlassFollowsAppearance()` on the main
  window's split view turns the top edges hard for a tenth of a second as the colour scheme changes, which has
  AppKit make them afresh in the new appearance.

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
- A row of a lazy stack doesn't hold the whole list it's in. SwiftUI compares every row's inputs whenever
  it updates, and arrays of families compare every family in them unless they're the same array: the
  browser's tiles and rows hold a `FamilyOrder`, equal only to itself, for selecting ranges.
- Sizes worked out from geometry (the font page's glyph columns, the list's column widths) come from a
  width that doesn't depend on them, so a layout settles in one pass.
- No `ViewThatFits` around controls. It builds each of its choices again, AppKit views and menus included,
  whenever it weighs them, which is whenever anything in them changes: the font page's Style menu, sliders
  and alignment buttons in one made each letter typed and each step of a slider take a third of a second.
  They're a `Layout` of their own (`TesterControls`), which keeps both of a slider's labels, the word and the
  symbol, and shows the other one at no width.
- What changes with each keystroke isn't saved to `UserDefaults` as it's typed. SwiftUI draws every view
  with an `@AppStorage` again whenever anything is saved there, whatever the key: the browser behind a
  font page, Settings and the Compare window. The type tester's text is kept in memory and saved a second
  after typing stops, and at quit (`TesterTextStore`).
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
