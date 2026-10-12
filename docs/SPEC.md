# Point — product spec for the clean rewrite

Point is a macOS 26 font manager (SwiftUI, Liquid Glass, Apple silicon only, never uses the network).
This is a ground-up rewrite: new code and architecture, same product. The user shaped every
behaviour below; keep them. Never mention or reference any other font manager app anywhere.

Writing rules for all UI text: macOS HIG — Title Case for menu items, buttons and window titles,
sentence case for descriptions; short plain words; typographic apostrophes (’) in every string;
ellipsis character (…) for items that ask for more input.

## Windows

1. **Main window** — sidebar | browser (or a font page pushed over it) | optional Info panel.
2. **Settings** — tabs General, Folders, Sidebar, Character Sets.
3. **Character Toolbox** (⌥⌘T) — tabs Text and Languages.
4. **Compare** (⌥⌘C).

## Sidebar

- Header "Fonts" with an **Edit**/**Done** button. Edit mode shows a checkbox on every row and every
  section header; unchecked items are dimmed, and disappear when you click Done.
- Fixed rows: All Fonts (books.vertical), Activated (circle.inset.filled), Not Activated (circle),
  System Fonts (apple.logo), Problems (exclamationmark.triangle, count badge).
- Sections, each collapsible and hideable:
  - **Folders** (+ adds folders). Row menu: Reveal in Finder; "Fonts in This Folder" picker —
    "Not activated until you activate them" / "Active in Adobe apps" / a custom app name; Remove Folder from Library.
    Point's own Deactivated folder appears here when it has fonts.
  - **Sets** (+ menu: New Set…, New Smart Set…). Sets (square.stack) and smart sets (gearshape).
    Menus: Rename Set…, Delete Set; Edit Smart Set…, Delete Smart Set.
  - **Tags** (+). Menu: Rename Tag…, Delete Tag.
  - **Foundries**. Menu: Rename Foundry…
  - **Classifications** (Serif, Slab Serif, Sans Serif, Monospaced, Script, Ornamental, Symbol, Unclassified — only the ones present).
  - **Character Sets** (+ new custom set). Only sets switched on in Settings → Character Sets (default Latin S, M, L, XL) plus custom ones. Menu for custom: Edit Character Set…, Delete Character Set.
- Every row menu also has Hide from Sidebar and Edit Sidebar.
- Dropping family names (drag from the browser) onto a set, tag or foundry adds them.
- Creating a set, tag or character set un-hides its section.
- Settings → Sidebar lists the same items as Finder-style checkboxes, with Show All.

## Browser

- Title = selected item's name; subtitle "1.298 families · 716 activated" (or "… · checking characters, 400 of 1.298" while coverage is computed and the list depends on it).
- Toolbar, left to right with equal gaps (ToolbarSpacer(.fixed) between groups): view switcher
  [List list.bullet | Grid square.grid.2x2 | Specimens rectangle.grid.1x2] · [Preview Options textformat.size] · [Info info.circle] · native search field.
- **List** (SwiftUI Table, sortable, column customisation saved): Status (switch) · Name (+ status tag) ·
  Preview (sample in the font, 17 pt) · Styles · Classification · Foundry · Latin S–XL (largest of
  Latin S/M/L/XL the family fully has) · Adobe Latin (shown as "AL 3") · Date Added (hidden) · Format (hidden).
- **Grid**: tiles — status tag + switch on top, big centered sample ("Aa Gg 123", or the sample
  text when set), name, "N styles · Foundry". Tiles scale with the preview size.
- **Specimens**: rows — name, status tag, "Foundry · N styles", switch; the sample at preview size; up to 14 style names set in themselves (+N more).
- Selection: click, ⌘-click, ⇧-click, ⌘A, Esc clears, typing a letter jumps, Return or double-click opens the font page; rows are draggable as family names. Right-click → family menu.
- Empty states per selection (no folders → Add Folder…; nothing activated; empty set; no tagged fonts; smart set with no matches → Edit Smart Set…; character set still being checked; search with no results).
- A small glass capsule bottom-right while scanning ("Finding fonts…", "Identifying fonts… 200 of 4000").
- Selecting Problems shows the Problems view instead of a list.
- Status tags (small capsules): System; Partly active (orange); app name e.g. "Adobe" (red) for app-only; "Temporary" (blue) for temporarily active.
- Switches: a small switch drawn in SwiftUI (not a native NSSwitch per row — too slow), with tooltip
  ("Installed with macOS" / "On in Adobe apps only. Turn on to use it in every app." / Activate / Deactivate) and VoiceOver toggle semantics.

## Font page (pushed over the browser; Esc or Back returns)

- Toolbar: tabs [Text | Styles (only when the family has more than one style) | Glyphs] · Preview Options · Info.
- Header: family name in its own regular face (34 pt), then "Foundry · OpenType PostScript · Variable · 2 styles · 1 activated" (no classification), and on the right Activate (prominent) / Deactivate; locked families get a disabled Deactivate with the reason as tooltip.
- **Text**: Style picker (Automatic = follows preview weight; or a specific style), Size slider 12–240 pt, alignment left/center, a big editable text (default "Sphinx of black quartz, judge my vow."), remembered.
- **Styles**: table of styles — preview, style name, weight, Status (the style's switch and its state, e.g. "Active until Point quits"); right-click → style menu.
- **Glyphs**: filter field (character, Unicode name or U+ code), sections with counts (Latin, Numbers, Symbols & punctuation, other scripts…), "404 characters" total, cells set in the font; click a cell for a popover with the character large, its name, code point.

## Info panel (trailing column, 300 pt wide, starts below the toolbar, toggled by ⓘ / ⌘I)

- Family name; segmented Info | Features; Style picker when more than one style.
- Info: Status, Family, Style, Full name, PostScript name, Version, Designer, Manufacturer, Weight, Variable weight, Glyphs, Format, Copyright, Languages ("213 languages, including English, German, …" + Show All popover grouped by script with search; full support marked), Character Sets (largest set per series the face has, e.g. "Latin S, Adobe Latin 3, GF Latin Core", plus "Latin M needs 12 more characters"), Location + Reveal in Finder, Other copies.
- Features: the face's OpenType features (toggles / menus); chosen features apply to that family everywhere it's previewed (list, grid, specimens, font page).
- With nothing (or several fonts) selected: "No Selection" / "3 Fonts Selected".

## Preview Options (popover)

Sample field (placeholder "Font name"; empty = each family's name in list/specimens, "Aa Gg 123" in grid), Presets menu (Font Name; "Sphinx of black quartz, judge my vow."; "Hamburgefonstiv"; "0123456789 €$£¥ %&@"; "ÀÉÎÕÜ ñçß øæœ"), Size (8–160 pt), Weight (100–900, continuous for variable fonts), Spacing (−10…40 % of the em, 0.5 steps). Use custom-drawn sliders: system sliders lose their glass knob in toolbar popovers on macOS 26.

## Menus

- **File**: Add Folder… ⇧⌘O, New Set… ⇧⌘N, New Smart Set… ⌥⌘N.
- **View**: Edit Sidebar / Done Editing Sidebar, Show System Fonts ⇧⌘. (checkmark).
- **Fonts**: Activate ⌘↩, Activate Temporarily ▸ (Until Point Quits ⌥⌘↩ / Until You Log Out), Deactivate ⌘⌫, Show Info ⌘I, Reveal in Finder ⇧⌘R, Move to Trash…, Compare ⌥⌘C, Character Toolbox ⌥⌘T, Rescan Library ⌘R, Rebuild Font List, Clear Font Caches…
- **Family context menu**: "3 Families" header for multiple; a status note ("Available in Adobe apps only", "Installed with macOS"); Activate / Activate Remaining Styles / Activate in All Apps (app-only fonts) (+ "…" when the install method is Ask); Activate Temporarily ▸; Activate Permanently… (temporary fonts); Deactivate; Add to Set ▸ (checkmark toggles, New Set from Selection…); Tags ▸ (toggles, New Tag…); Reveal in Finder; Copy Family Name(s); Compare; Open; Show Info; Move to Trash…
- **Style menu**: status label, Activate Style…, Activate Temporarily ▸, Deactivate Style, Reveal in Finder, Copy PostScript Name, Move Style to Trash…

## Library and fonts

- Sources: everything CoreText reports active (`CTFontManagerCopyAvailableFontURLs`), ~/Library/Fonts and /Library/Fonts (always active), watched folders, Point's Deactivated folder (~/Library/Application Support/Point/Deactivated).
- Files: otf ttf ttc otc dfont woff woff2; each face read with CoreText (PostScript name, family, style, full name, OS/2 weight class (fallback from traits), italic, monospace, OS/2 family class, manufacturer, version, wght axis). Unreadable files are kept for Problems. Parsed faces are cached by path + modification date + size; Date Added (Finder's, fallback creation date) is cached with them.
- Families group faces by family name (hidden "."-prefixed families skipped). The same PostScript name in several files is one face: the active file wins, the others are "other copies"; Date Added is the earliest.
- Face state: active (from macOS / installed for all users / inside an app / Adobe Fonts (CoreSync) / your Fonts folder / used in place by Point / temporarily until quit or logout / another app), inactive, or "active in <App> apps" for watched folders marked app-only (Adobe's /Library/Application Support/Adobe/Fonts is detected automatically).
- Family state: all active (system if all from macOS) / partly / inactive / app-only / system.
- Classification from OS/2 family class (1,2,3,7 serif; 4,5 slab; 8 sans; 9 ornamental; 10 script; 12 symbol), monospace first, then name hints (mono/code, slab, sans/grotesk/gothic, serif/garamond/antiqua, script/brush/hand).
- Foundry: manufacturer name trimmed of Inc./LLC/GmbH/…, URLs and copyright lines dropped, casing unified; user can rename a foundry or set a family's foundry (drop onto foundry).
- Rescan: on launch, after activation changes, on CoreText's registered-fonts-changed notification (debounced), and when the app becomes active after ≥10 s. An unchanged scan must cost almost nothing (fingerprint; no UI churn).
- Show System Fonts off hides system families everywhere except the System Fonts item.

## Activation

- Install method (Settings → General → Activation): Ask each time / Copy into ~/Library/Fonts / Use the files where they are. "Ask" shows a sheet: Install a Copy, Use Files Where They Are, an Activate Temporarily pull-down, "Remember this choice (you can change it in Settings → General)".
- Copy: into ~/Library/Fonts (unique name if needed; identical size counts as already there), remembered as installed copy → origin.
- In place: CoreText persistent registration, remembered.
- Fonts from app-only folders (Adobe) are always used in place — never copied.
- Temporary: CoreText session registration in place; until Point quits (unregistered on quit; leftovers from a crash unregistered at launch) or until you log out (forgotten when the login session changes: audit session ID + boot time).
- Deactivate: installed copies go to the Trash when another copy exists (origin or other copy outside ~/Library/Fonts); otherwise the file moves to Point's Deactivated folder — ask first if Point didn't install it ("Deactivate fonts?" alert). In-place/temporary → unregister (persistent, falling back to session). macOS, all-users, app and Adobe Fonts faces can't be turned off ("These fonts are managed by macOS or another app.").
- Activating permanently a temporarily active font ends the session registration first.
- Move to Trash (family or style): unregister, trash every file including other copies; never touches /System, /Library/Application Support/Apple, /usr, /private, app bundles, Adobe CoreSync; collections that also contain other families are named in the alert; removes the family from sets/tags/foundry overrides. Alert "Move “X” to the Trash?" with destructive Move to Trash.
- Short toasts at the bottom ("Activated.", "Deactivated.", "Moved to the Trash.", failures).

## Sets, tags, smart sets, character sets

- Sets: ordered lists of family names. Tags: names in sidebar order; family → tags.
- Smart sets: name, match all/any, rules (field · comparison · value): Name (contains / doesn’t contain / begins with / is), Foundry (is / is not / contains), Classification, Tag (has / doesn’t have), Set (is in / isn’t in), Folder (is in / isn’t in), Status (Activated / Partly Activated / Not Activated / Active in Apps Only / Installed with macOS), Kind (Variable / Monospaced / Has Italics), Format, Number of Styles (is / is more than / is less than), Language (is supported / isn’t supported; Hyperglot languages, searchable picker defaulting to the user's language), Character Set (is supported / isn’t), Date Added (is in the last / isn’t in the last N days). Editor sheet with live "N families match".
- Character sets: built-in from Resources/CharacterSets.json (Latin S–XL; Adobe Latin 1–5; Google Fonts Latin Kernel/Core/Plus/African, Cyrillic Core/Plus/Pro, Greek Core/Plus/Pro); custom sets (name + characters typed or pasted, U+ codes, 0x codes, ranges U+0100–U+017F). A family "has" a set when its regular upright face covers every character.
- Settings → Character Sets: groups with checkboxes (show in sidebar), counts, summaries, credit links; "Your Character Sets" with + / − / Edit….

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
- Conflicts: the same PostScript name active from more than one file ("Fonts with the same PostScript name are active from more than one file. macOS uses only one of them, so apps may get an old version or a different font. Keep one and turn off the rest."). Per copy: version, modified date, where; Reveal; Remove Copy… / Deactivate when Point can.
- Duplicates: same font more than once in your folders (inactive); Move Extra Copies to Trash… (keep the installed copy's origin, else newest).
- Missing files: in-place registrations whose file is gone (Forget + unregister), installed copies gone (Forget), set members no longer in the library (Remove from Set).
- Damaged or unreadable files (not WOFF/WOFF2): Reveal, Move to Trash…
- Fonts on external disks used in place: Install a Copy Instead.
- Empty state "No Problems". Never trash protected paths or a font's only copy.

## Font caches

Sheet "Clear Font Caches" (Fonts menu and Settings → General): checkboxes macOS (my account) [`atsutil databases -removeUser` + restart fontd], macOS (all users) [admin prompt via osascript; "Needs an administrator password"], Adobe apps [AdobeFnt*.lst and CT Font Cache locations; disabled with "Quit InDesign first" while an Adobe app runs; shows size], Microsoft Office [its containers are protected by macOS: never look inside until the user ticks it and clicks Clear; row says "macOS asks for permission"]. App caches go to the Trash. Afterwards rebuild Point's font list; offer "Restart Now…" only when macOS caches were cleared. Settings → General also has "Point’s font list: Rebuild".

## Settings

- General: Appearance (System / Light / Dark, applied app-wide via NSApp.appearance); Activation ("Activate fonts by" + explanation incl. app-only folders); "Show system fonts in other lists" (+ explanation); Font Caches (Rebuild, Clear…).
- Folders: list (+/−), each with a menu to mark it as loaded by an app.
- Sidebar: Finder-style checkboxes.
- Character Sets: as above.

## Data and privacy

- Everything local: ~/Library/Application Support/Point (user data, Deactivated folder), ~/Library/Caches/Point (face and coverage caches). No network, no analytics.
- The rewrite reads the existing user data file (library.json, format described in the architecture doc) once and keeps working from its own file; the old file is never modified.
