# Cicero — product spec for the clean rewrite

Cicero is a macOS 26 font manager (SwiftUI, Liquid Glass, Apple silicon only, never uses the network).
This is a ground-up rewrite: new code and architecture, same product. The user shaped every
behaviour below; keep them. Never mention or reference any other font manager app anywhere.

Writing rules for all UI text: macOS HIG — Title Case for menu items, buttons and window titles,
sentence case for descriptions; short plain words; typographic apostrophes (’) in every string;
ellipsis character (…) for items that ask for more input.

## Windows

1. **Main window** — sidebar | browser (or a font page pushed over it) | optional Info panel.
2. **Settings** — tabs General, Folders, Sidebar, Coverage (the character sets; a short name keeps the tabs evenly spaced).
3. **Character Toolbox** (⌥⌘T) — tabs Text and Languages.
4. **Compare** (⌥⌘C).

## Sidebar

- Header "Fonts" with an **Edit**/**Done** button. Edit mode shows a checkbox on every row and every
  section header; unchecked items are dimmed, and disappear when you click Done.
- Fixed rows: All Fonts (books.vertical), Activated (checkmark.circle), Not Activated (circle.dashed),
  System Fonts (apple.logo, only while system fonts are shown), Problems (exclamationmark.triangle, count badge).
- Sections, each collapsible and hideable:
  - **Folders** (+ adds folders). The folders Adobe apps load fonts from by themselves — /Library/Application Support/Adobe/Fonts, ~/Library/Application Support/Adobe/Fonts (all Adobe apps) and the Fonts folder next to any Adobe app, like /Applications/Adobe InDesign 2026/Fonts (that app only) — are one "Adobe Apps" item, shown while it has fonts (row menu: Reveal in Finder). They aren't in the user's folders: Settings → Folders → "Show fonts installed for Adobe apps" (on by default) switches them; adding one of them with + turns the switch on. Row menu for the user's folders: Reveal in Finder; "Fonts in This Folder" picker —
    "Not activated until you activate them" / "Active in Adobe apps" / a custom app name; Remove Folder from Library.
    Cicero's own Deactivated folder appears here when it has fonts.
  - **Sets** (+ menu: New Set…, New Smart Set…, New Application Set…). Sets (square.stack), application sets (app.badge.checkmark) and smart sets (gearshape). A set's menu has Activate with Apps… (Edit Apps… once it has some).
    Menus: Rename Set…, Delete Set; Edit Smart Set…, Delete Smart Set.
  - **Foundries**. Menu: Rename Foundry…
  - **Classifications** (Serif, Slab Serif, Sans Serif, Monospaced, Script, Ornamental, Symbol, Unclassified — only the ones present).
  - **Character Sets** (+ new custom set). Collapsible groups — Latin S–XL, Adobe Latin, Unicode Blocks, Google Fonts, Your Character Sets — with every set shown unless hidden (Edit, Settings). Unicode Blocks and Google Fonts start collapsed. Menu for custom: Edit Character Set…, Delete Character Set.
- The menus of sets, smart sets, folders, foundries, classifications and character sets also have Export Fonts… (that row's families, see Export and backup). Every row menu also has Hide from Sidebar and Edit Sidebar.
- Order: rows drag to a new place within their own section (character sets within their group, and the
  groups within Character Sets), never into another one. Section titles drag onto each other: the dragged
  section takes the other's place, which is highlighted. While a section is dragged its rows fold away
  under its title, so it moves as one (a list drags a header as a picture of it, with no custom preview),
  and come back when it's dropped. Items that are gone for now (System Fonts while
  system fonts are off, an empty Deactivated folder) keep their place; new items go last.
- Several rows of one section (or character set group) can be selected with ⌘- and ⇧-click and dragged
  together; the browser then shows the fonts in any of them. Selecting in another section starts over there.
- Dropping family names (drag from the browser) onto a set or foundry adds them.
- Creating a set or character set un-hides its section.
- Settings → Sidebar lists the same items, in the sidebar's order, as Finder-style checkboxes, with
  Reset Order and Show All.

## Browser

- Title = selected item's name (several: "Serif and Script"); subtitle "1.298 families · 716 activated" (or "… · checking characters, 400 of 1.298" while coverage is computed and the list depends on it).
- Toolbar, left to right with equal gaps (ToolbarSpacer(.fixed) between groups): view switcher
  [List list.bullet | Grid square.grid.2x2 | Specimens rectangle.grid.1x2] · [Preview Options textformat.size] · [Info info.circle] · native search field.
- **List** (rows under column headers in a lazy stack, like the grid: not a SwiftUI Table, which makes every
  row's cells whenever an accessibility client — a password manager's autofill, say — walks the window, and
  with a thousand families kept the app busy for minutes each time it came to the front): Status (switch) ·
  Name (+ status tag) · Preview (sample in the font, 17 pt) · Styles · Classification · Foundry · Latin S–XL
  (largest of Latin S/M/L/XL the family fully has) · Adobe Latin (shown as "AL 3") · Date Added (hidden) ·
  Format (hidden). Click a header to sort by it, again to reverse; right-click the headers to show or hide
  columns (Status, Name and Preview always show); drag a header's right edge to resize it (shown columns and
  widths saved). When the room runs short (the Info panel open), the preview gives way first, then the other
  columns down to their minimums. Selection as in the grid, plus ↑/↓ (⇧ extends).
- **Grid**: tiles — status tag + switch on top, big centered sample ("Aa Gg 123", or the sample
  text when set), name, and what the family's styles span, in Title Case, along the registered axes
  (MDN order: weight, width, italic, then optical size) and then the designer's own: "9 Weights · 3
  Widths · Italics", "8 Weights · Italics · 3 Optical Sizes · Grade". No axis ranges: a variable font's
  styles are its named instances, placed by their axis values; a static font's by its names and
  classes. Weights count the words in style names (Bold, Bd, U Lt…) first — many static files leave
  every class at 400 and variable fonts nudge instances off round values — then the axis value or
  OS/2 class. Widths: a variable instance's wdth value, with instances whose names write the same
  width words (Condensed, not XXX Condensed) counted once; a static font's OS/2 width class unless
  it's normal, then the name. Slanted or italic styles make "Italics" ("Italic" when all are). Optical
  sizes and custom axes (by the name the font gives them, else their tag) show when the styles step
  along them. A family with more styles than these tell apart (hidden axes, small caps cut as fonts of
  their own) adds "N Styles". The full caption is the tooltip. Tiles scale with the preview size.
- **Specimens**: rows — name, status tag, "Foundry · N styles", switch; the sample at preview size; up to 14 style names set in themselves (+N more).
- Selection: click, ⌘-click, ⇧-click, ⌘A, Esc clears, typing a letter jumps, Return or double-click opens the font page; rows are draggable as family names. Right-click → family menu.
- Empty states per selection (no folders → Add Folder…; nothing activated; empty set; smart set with no matches → Edit Smart Set…; character set still being checked; search with no results).
- A small glass capsule bottom-right while a scan takes longer than 0.4 s ("Finding fonts…", "Identifying fonts… 200 of 4000"); quicker scans show nothing.
- Selecting Problems shows the Problems view instead of a list.
- Status tags (small capsules): System; Partly active (orange); app name e.g. "Adobe" (red) for app-only; "Temporary" (blue) for temporarily active; "App Set" (blue) for on for an application set.
- Switches: a small switch drawn in SwiftUI (not a native NSSwitch per row — too slow), with tooltip
  ("Installed with macOS" / Activate / Deactivate) and VoiceOver toggle semantics. Families whose
  every face is in (or was moved out of) one app's own folder, like Adobe's, have three positions: on in
  that app only (knob halfway, track lightly tinted), on everywhere, off everywhere. Clicking goes
  app only → everywhere → off → app only; tooltips "On in Adobe apps only. Click to turn on in every
  app." / "On in every app. Click to turn off, Adobe apps included." / "Off. Click to turn on in Adobe
  apps only." The styles table's switches do the same per style.

## Font page (pushed over the browser; Esc or Back returns)

One scrolling page, top to bottom: header, text, styles, glyphs (no tabs).

- Toolbar: Preview Options · Info.
- Header: family name in its own regular face (34 pt), then "Foundry · OpenType PostScript · Variable · 2 styles · 1 activated" (no classification), and on the right Activate (prominent) / Deactivate; locked families get a disabled Deactivate with the reason as tooltip.
- **Text**: Style picker (Automatic = follows preview weight; or a specific style), Size slider 12–240 pt, alignment left/center, a big editable text (default "Sphinx of black quartz, judge my vow.") that grows with what's typed, remembered.
- **Styles** (only when the family has more than one style): laid out like a table — Preview, Style, Weight, Status (the style's switch and its state, e.g. "Active until Cicero quits"); right-click → style menu.
- **Glyphs**: heading with "404 characters" total and a filter field (character, Unicode name or U+ code), then one section per Unicode block with counts (Basic Latin, Latin-1 Supplement, Latin Extended-A, …), block headers pinned while scrolling, cells set in the font; click a cell for a popover with the character large, its name, code point.

## Info panel (a pane floating at the trailing edge like the sidebar and in its colour, 300 pt wide, starts below the toolbar, stays put when a font page opens, toggled by ⓘ / ⌘I)

- Family name; segmented Info | Features (no style picker: it describes the style being previewed).
- Info: Status, Family, Style, Full name, PostScript name, Version, Designer, Manufacturer, Weight, Variable weight, Glyphs, Format, Copyright, Languages ("213 languages, including English, German, …" + Show All popover grouped by script with search; full support marked), Character Sets (largest set per series the face has, e.g. "Latin S, Adobe Latin 3, GF Latin Core", plus "Latin M needs 12 more characters"), Location + Reveal in Finder, Other copies.
- Features: the face's OpenType features, a box of switches per feature like the system Typography panel (in a one-at-a-time feature, switching one on switches the others off; switching the chosen one off goes back to the default); chosen features apply to that family everywhere it's previewed (list, grid, specimens, font page).
- With nothing (or several fonts) selected: "No Selection" / "3 Fonts Selected".

## Preview Options (popover)

Sample field (placeholder "Font name"; empty = each family's name in list/specimens, "Aa Gg 123" in grid), Presets menu (Font Name; "Sphinx of black quartz, judge my vow."; "Hamburgefonstiv"; "0123456789 €$£¥ %&@"; "ÀÉÎÕÜ ñçß øæœ"), Size (8–160 pt), Weight (100–900, continuous for variable fonts), Spacing (−10…40 % of the em, 0.5 steps). Use custom-drawn sliders: system sliders lose their glass knob in toolbar popovers on macOS 26.

## Menus

- **File**: Add Folder… ⇧⌘O, New Set… ⇧⌘N, New Smart Set… ⌥⌘N | Export Fonts… ⇧⌘E | Back Up Library…, Restore Library….
- **View**: Edit Sidebar / Done Editing Sidebar.
- **Fonts**: Activate ⌘↩, Activate Temporarily ▸ (Until Cicero Quits ⌥⌘↩ / Until You Log Out), Deactivate ⌘⌫, Open ⌘↓ (one family selected), Show Info ⌘I, Reveal in Finder ⇧⌘R, Move to Trash…, Compare ⌥⌘C, Character Toolbox ⌥⌘T, Rescan Library ⌘R, Rebuild Font List, Clear Font Caches…
- **Family context menu**: "3 Families" header for multiple; a status note ("Available in Adobe apps only", "Installed with macOS"); Activate / Activate Remaining Styles / Activate in All Apps (app-folder fonts) (+ "…" when the install method is Ask); Use in Adobe Apps Only (app-folder fonts not already there); Activate Temporarily ▸ (hidden when everything is already on for good); Activate Permanently… (temporary fonts); Deactivate / Deactivate in All Apps (app-folder fonts on everywhere) / Deactivate in Adobe Apps (app-folder fonts on in Adobe apps only); Add to Set ▸ (checkmark toggles, New Set from Selection…); Reveal in Finder; Copy Family Name(s); Export…; Compare; Move to Trash…
- **Style menu**: status label, Activate Style…, Activate Temporarily ▸ (hidden when the style is already on for good), Deactivate Style, Reveal in Finder, Copy PostScript Name, Move Style to Trash…

## Library and fonts

- Sources: everything CoreText reports active (`CTFontManagerCopyAvailableFontURLs`), ~/Library/Fonts and /Library/Fonts, watched folders, Cicero's Deactivated folder (~/Library/Application Support/Cicero/Deactivated). A file in the Fonts folders is active when CoreText lists it, or, for the few it leaves out (fonts with hidden names), when `CTFontManagerGetScopeForURL` says so; otherwise it's not activated (Font Book turned it off, or macOS hasn't noticed it yet). Without a list from CoreText at all, files in the Fonts folders count as active. Files in watched folders that iCloud or another file provider has taken off the Mac (dataless) are skipped until they're downloaded: reading one would download it.
- Files: otf ttf ttc otc dfont woff woff2; each face read with CoreText (PostScript name, family, style, full name, OS/2 weight class (fallback from traits), OS/2 width class, italic, monospace, OS/2 family class, manufacturer, version, wght axis range, visible variation axes (tag, name — the tag when the font gives none — and the named instance's value on each)). Unreadable files are kept for Problems. Parsed faces are cached by path + modification date + size; Date Added (Finder's, fallback creation date) is cached with them.
- Families group faces by family name (hidden "."-prefixed families skipped). The same PostScript name in several files is one face: the active file wins, the others are "other copies"; Date Added is the earliest.
- Face state: active (from macOS / installed for all users / inside an app / Adobe Fonts (CoreSync) / your Fonts folder / used in place by Cicero / temporarily until quit or logout / another app), inactive, or "active in <App> apps" for watched folders marked app-only and the Adobe Apps folders.
- Family state: all active (system if all from macOS) / partly / inactive / app-only / system.
- Classification from OS/2 family class (1,2,3,7 serif; 4,5 slab; 8 sans; 9 ornamental; 10 script; 12 symbol), monospace first, then name hints (mono/code, slab, sans/grotesk/gothic, serif/garamond/antiqua, script/brush/hand).
- Foundry: manufacturer name trimmed of Inc./LLC/GmbH/…, URLs and copyright lines dropped, casing unified; user can rename a foundry or set a family's foundry (drop onto foundry).
- Rescan: on launch, right after activation changes, on CoreText's registered-fonts-changed notification (posted to the app's own notification center, for any app's changes; debounced; while an operation runs they wait for the scan it starts when it finishes, or one right after it when it starts none), when font files come or go in the scanned folders (FSEvents), and when the app becomes active after ≥60 s. An unchanged scan must cost almost nothing (fingerprint; no UI churn).
- Show system fonts (Settings → General) off hides system families everywhere, and the System Fonts item with them.

## Activation

- Install method (Settings → General → Activation): Ask each time / Copy into ~/Library/Fonts / Use the files where they are. "Ask" shows a sheet: Install a Copy, Use Files Where They Are, an Activate Temporarily pull-down, "Remember this choice (you can change it in Settings → General)".
- Every switch moves the moment it's clicked and stays there while the operation runs; the scan after it confirms or corrects it. A switch that's moving ignores clicks.
- Copy: copied into Cicero's staging folder (~/Library/Application Support/Cicero/Staging) and moved into ~/Library/Fonts, so macOS never sees a half-written file (unique name if needed; a file of the same name with the same contents counts as already there), then registered (persistent) so apps get it at once — macOS takes seconds to notice a new file by itself. Remembered as installed copy → origin. A copy macOS won't turn on is taken out again and the font counts as failed.
- In place: CoreText persistent registration, remembered.
- A font only counts as activated once macOS reports its file active (`CTFontManagerGetScopeForURL`). Registration waits for fontd, so when the toast says "Activated." the font is in every app's font list. A font in a Fonts folder that macOS has off (Font Book turned it off) is turned on where it is.
- Fonts from app-only folders (Adobe) are always used in place — never copied. Turning one off
  everywhere moves its file into Cicero's Deactivated folder (the app would load it otherwise) and
  records where it was (`appFolderOrigins`); it stays listed with that folder. Activating it, or Use in
  Adobe Apps Only, moves it back first (beside a newer file of the same name; fails if the folder is
  gone). Folders the user can't write to (InDesign's, owned by root) can't be turned off this way.
- Temporary: CoreText session registration in place (app-folder fonts too: on in every app for that long, then back to where they were); until Cicero quits (unregistered on quit; leftovers from a crash unregistered at launch) or until you log out (forgotten when the login session changes: audit session ID + boot time).
- Deactivate: installed copies go to the Trash when another copy exists (origin or other copy outside ~/Library/Fonts); otherwise the file moves to Cicero's Deactivated folder — ask first if Cicero didn't install it ("Deactivate fonts?" alert). Files in ~/Library/Fonts are unregistered before they move, so apps drop them at once; one that can't move is registered again. In-place/temporary → unregister (persistent, falling back to session). macOS, all-users, app and Adobe Fonts faces can't be turned off ("These fonts are managed by macOS or another app.").
- Activating permanently a temporarily active font ends the session registration first.
- Application sets: a set with apps (bundle ID, name, path). While one of its apps is open, its fonts that are off are registered for the session and confirmed active, like temporary activation (record scope `whileAppsRun`, with the bundle IDs of the open apps that want each file); when no open app wants a file any more it's unregistered. Fonts on for any other reason are never touched. `AppSetWatcher` follows `NSWorkspace.runningApplications` (it changes as an app starts launching, before it reads its fonts) and syncs when apps, sets, records or the library change; a font the user turns off, or on for good, while its app is open is left alone until the app quits. Registrations outlive Cicero quitting (the app may still be open) and are synced at the next launch; they end at logout anyway. Works only while Cicero is open: Settings → General has Open at login (SMAppService), and the apps sheet offers it too.
- Move to Trash (family or style): unregister (in-place files and files in ~/Library/Fonts; registered again if they can't be moved), trash every file including other copies; never touches /System, /Library/Application Support/Apple, /usr, /private, app bundles, Adobe CoreSync; collections that also contain other families are named in the alert; removes the family from sets, its saved tags and foundry overrides. Alert "Move “X” to the Trash?" with destructive Move to Trash.
- Short toasts at the bottom ("Activated.", "Deactivated.", "Moved to the Trash.", failures).

## Sets, smart sets, character sets

- Sets: ordered lists of family names, optionally with apps (application sets, see Activation). The apps sheet ("Activate “Name” with Apps"): the apps with their icons, "Open" next to running ones, − to remove, Add App… (an open panel in /Applications), and a line about opening Cicero at login. Tags (names; family → tags) are only kept in the saved data for now: no sidebar section, menu or new smart-set rules, but rules saved with one still work.
- Smart sets: name, match all/any, rules (field · comparison · value): Name (contains / doesn’t contain / begins with / is), Foundry (is / is not / contains), Classification, Set (is in / isn’t in), Folder (is in / isn’t in), Status (Activated / Partly Activated / Not Activated / Active in Apps Only / Installed with macOS), Kind (Variable / Monospaced / Has Italics), Format, Number of Styles (is / is more than / is less than), Language (is supported / isn’t supported; Hyperglot languages, searchable picker defaulting to the user's language), Character Set (is supported / isn’t), Date Added (is in the last / isn’t in the last N days). Editor sheet with live "N families match".
- Character sets: built-in from Resources/CharacterSets.json (Latin S–XL; Adobe Latin 1–5; 38 Unicode blocks such as Basic Latin, Latin-1 Supplement, Latin Extended-A/B/Additional, IPA Extensions, Greek and Coptic, Cyrillic, General Punctuation, Currency Symbols — only their assigned, visible characters; Google Fonts Latin Kernel/Core/Plus/African, Cyrillic Core/Plus/Pro, Greek Core/Plus/Pro); custom sets (name + characters typed or pasted, U+ codes, 0x codes, ranges U+0100–U+017F). A family "has" a set when its regular upright face covers every character.
- Settings → Coverage: groups with checkboxes (show in sidebar, all on by default), counts, summaries, credit links; "Your Character Sets" with + / − / Edit….

## Coverage and languages

- For each family's regular upright face: the Unicode scalars it covers (from CoreText's character set), cached on disk by file stamp, computed in the background at low priority after scans.
- Languages from Resources/Languages.json (Hyperglot 0.8.1, Apache 2.0): a language is supported when an orthography's base characters and required marks are all present, fully supported when its auxiliary characters are too. Character-coverage only (no shaping).

## Character Toolbox

- Text: a field; lists families with every character (sample = the text in each font), count, "Include fonts missing up to N" stepper, "Activated only"; shows missing characters per row; double-click opens the family in the main window.
- Languages: search (language, autonym or script), sort by speakers or name, list with speakers; selecting shows the language's characters and two sections: Fully Supported, Base Characters Only.

## Compare

Window "Compare", subtitle "3 families". Layouts Stacked (one row per font on a shared baseline, name + style + remove button under each) and Overlay (all samples drawn over each other in tints, x-height/cap-height ticks, legend chips with remove). Uses the preview sample (or "Hamburgefonstiv"), size, weight, spacing; Preview Options in its toolbar; drop families from the main window; choosing Compare again replaces the set. Content starts top-left.


## Problems

Sidebar item with badge; groups with a short explanation and fixes:
- Installed Twice: the same font (same family) active from more than one file. Per copy: version, modified date, where; Reveal; Remove Copy… / Deactivate when Cicero can.
- In every group but Shared Style Names, a problem's files that share a folder share one row: the folder, the files' version(s), modified dates and where, and "› 18 files" to show them (each with its own fixes). The row's Reveal selects them all; in Installed Twice it also has Remove Copies… / Deactivate when every file has it and every style keeps a copy outside the folder, and a green "Newest" tag marks the folder (or file) with the highest version when all the others are older.
- Shared Style Names (minor — not counted in the badge, collapsed at the bottom): different active families with faces that use the same PostScript name. Not name ID 6, which differs, but the names variable fonts give their named styles (fvar instances' postScriptNameID), usually when some are just "Bold" (not when every file comes with macOS). Families linked by a shared name, directly or through another family, are one card: title "A, B and C" (more than 4: "A, B, C and 2 more"); summary "Some of their styles have the same PostScript names: Light, Regular, Medium, Bold, Black, LightOblique and 4 more." (one name: "One style in each has the same PostScript name, AT-Realm-v08-Book."), then "macOS gives those names to Generator Variable and GT Maru Trial VF." when `CTFontCreateWithName` gives every one of them to a file in the card. Names go upright before italic, then by the weight the style name spells out. One row per file, not by folder: the family as title, the full path, the styles involved and where it is (no version or date), a Preferred tag on the files macOS gives names to (help lists them); per file Reveal and Deactivate (when Cicero can).
- Duplicates: same font more than once in your folders (inactive); Move Extra Copies to Trash… (keep the installed copy's origin, else newest).
- Missing files: in-place registrations whose file is gone (Forget + unregister), installed copies gone (Forget), set members no longer in the library (Remove from Set).
- Damaged or unreadable files (not WOFF/WOFF2): Reveal, Move to Trash…
- Fonts on external disks used in place: Install a Copy Instead.
- Empty state "No Problems". Never trash protected paths or a font's only copy.

## Font caches

Sheet "Clear Font Caches" (Fonts menu and Settings → General): checkboxes macOS (my account) [`atsutil databases -removeUser` + restart fontd], macOS (all users) [admin prompt via osascript; "Needs an administrator password"], Adobe apps [AdobeFnt*.lst and CT Font Cache locations; disabled with "Quit InDesign first" while an Adobe app runs; shows size], Microsoft Office [its containers are protected by macOS: never look inside until the user ticks it and clicks Clear; row says "macOS asks for permission"]. App caches go to the Trash. Afterwards rebuild Cicero's font list; offer "Restart Now…" only when macOS caches were cleared. Settings → General also has "Cicero’s font list: Rebuild".

## Settings

- General: Appearance (System / Light / Dark, applied app-wide via NSApp.appearance); Activation ("Activate fonts by" + explanation incl. app-only folders); "Open at login" (for application sets); "Show system fonts" (+ explanation); Font Caches (Rebuild, a red Clear); Backup (Back Up…, Restore…, one sentence on what a backup holds).
- Folders: list (+/−), each with a menu to mark it as loaded by an app.
- Sidebar: Finder-style checkboxes in the sidebar's order, Reset Order, Show All. Foundries only as a whole section; single foundries are hidden from the sidebar's Edit mode.
- Character Sets: as above.

## Export and backup

- **Export Fonts…** (File, ⇧⌘E; "Export…" in the family menu; "Export Fonts…" in the sidebar menu of a set, smart set, folder, foundry, classification or character set) copies the font files of the selected families — with none selected, of every family in the list; from a sidebar row, that row's families — into a folder or a ZIP archive, for sending them to someone or a printer. The save panel's name defaults to the row's name, the family's name for one family, or "N Families"; a Format picker in it chooses Folder or ZIP Archive. The folder holds one subfolder per family with its files; one family's files go straight into the folder. Each file is copied once (a collection shared by several faces, or families, once), only each face's own file, not its other copies. Files that come with macOS or an app, and Adobe Fonts, are left out and the toast says so: "Exported 12 families. Left out 3 fonts that come with macOS or an app." Files are copied with FileManager (APFS clones) off the main thread; a ZIP is staged in a temporary folder and made with `ditto -c -k --keepParent`. Replacing an item the save panel confirmed moves it to the Trash first, never writes over it. The result is revealed in Finder.
- **Back Up Library…** (File; Settings → General → Backup) writes a `.cicerobackup` archive (a ZIP made with ditto), named "Cicero Backup 2026-10-13.cicerobackup" by default. A sheet first says what it holds — sets, smart sets, character sets, folders, foundry names, the sidebar and settings — with a checkbox "Include font files" and their count and size ("3,812 files, 2.4 GB": every file in the library, other copies included, protected ones left out, sized off the main thread), then shows progress (a bar while copying, indeterminate while zipping) with Cancel, and reveals the file. Inside: `manifest.json` (format 1, created date, app version, the home folder, `includesFonts`, and every font with its path — the home folder written as "~" — its place in the archive (`Fonts/<n>/<file>`, so names never clash), size, and how it was active: in ~/Library/Fonts, in place, an installed copy with its origin, or not active), `user-data.json` exactly as the store writes it, and the files.
- **Restore Library…** (File; Settings → General) opens a `.cicerobackup`, unzips it to a temporary folder and asks "Restore the Backup from 13 October 2026?" with two checkboxes: "Sets, folders and settings" (what's inside: "4 sets, 2 smart sets, 3 folders and 1 character set"; replaces the current setup, which is saved first to ~/Library/Application Support/Cicero/Backups/Before Restore <date>.json — the sheet says so) and "Font files" (only when the backup has them: "Puts each font back where it was, unless a file is already there."). "~" means this account's home folder, so a backup moves between Macs and user names; the paths in the user data move with it. Nothing is ever written over: a file already at a path is left alone. Missing folders are made; a file that can't go back (no permission, or a folder next to an app that isn't installed, like /Applications/Adobe InDesign 2025/Fonts) goes into ~/Fonts Restored from Cicero/ keeping its path under it, and that folder is added to the watched folders. Records describe this Mac: the backup's installed copies count when both files exist, its temporary activations are dropped, its app-folder origins count when the file exists, its in-place registrations are activated again (in place, through the activation engine) once a scan has found the faces, and the current records stay where their files exist. Then a rescan and a toast: "Restored 4 sets and 3,790 fonts; 22 were already there." The file work runs off the main thread with progress and Cancel in the sheet; the records change is one queued operation, like an activation.

## Data and privacy

- Everything local: ~/Library/Application Support/Cicero (user data, Deactivated folder), ~/Library/Caches/Cicero (face and coverage caches). No network, no analytics.
- The rewrite reads the existing user data file (library.json, format described in the architecture doc) once and keeps working from its own file; the old file is never modified.
