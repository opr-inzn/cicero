# Cicero — product spec for the clean rewrite

Cicero is a macOS 26 font manager (SwiftUI, Liquid Glass, Apple silicon only; the network only for updates).
This is a ground-up rewrite: new code and architecture, same product. The user shaped every
behaviour below; keep them. Never mention or reference any other font manager app anywhere.

Writing rules for all UI text: macOS HIG — Title Case for menu items, buttons and window titles,
sentence case for descriptions; short plain words; typographic apostrophes (’) in every string. No
ellipses anywhere, against the HIG: not on items that ask for more input (Export Fonts, Back Up), nor in progress text ("Finding fonts"; counts after
a comma: "Copying fonts, 3 of 10"). The one "…" left marks a cut-off preview in the coverage set editor; the menu items macOS adds (Settings…,
Services, AutoFill, Start Dictation) keep theirs: SwiftUI puts the Settings item's title, and its visibility, back
whenever the menu updates.

No hover states: nothing changes under the pointer (tooltips and the column-resize cursor aside). AppKit's
toolbar buttons and segmented pickers light up on hover in a grey of their own, so the toolbars use Cicero's
(ToolbarPicker, the .toolbar button and toggle styles, at AppKit's sizes): one grey for a toggle that's on
and a button being pressed. A picker's chosen segment is a grey lens of interactive glass, 3 pt inside the
capsule on every side, that slides to the next one chosen.

## Windows

1. **Main window** — sidebar | browser (or a font page pushed over it) | optional Info panel.
2. **Settings** — tabs General, Folders, Sidebar, Coverage (the character sets; a short name keeps the tabs evenly spaced).
3. **Character Toolbox** (⌥⌘T) — tabs Text and Languages.
4. **Compare** (⌥⌘C).
5. **Quick Look** (Space in the browser, ⌘Y) — a floating panel with the selected family.

## Sidebar

- Header "Library" with an **Edit**/**Done** button. Edit mode shows a checkbox on every row and every
  section header; unchecked items are dimmed, and disappear when you click Done. Sections and character set
  groups stay open or closed as outside it, and open and close the same way (one state for both). Switching
  isn't animated: hundreds of rows animating in and out ran into each other.
- Fixed rows: All Fonts (books.vertical), Active (checkmark.circle), Inactive (circle.dashed),
  System Fonts (apple.logo, only while system fonts are shown), Problems (exclamationmark.triangle, count badge).
- Sections, each collapsible and hideable:
  - **Folders** (+ adds folders). The folders Adobe apps load fonts from by themselves — /Library/Application Support/Adobe/Fonts, ~/Library/Application Support/Adobe/Fonts (all Adobe apps) and the Fonts folder next to any Adobe app, like /Applications/Adobe InDesign 2026/Fonts (that app only) — are one "Testing" item (`WatchedFolder.adobeAppsID`), shown while it has fonts (row menu: Reveal in Finder). Adobe Fonts (every CoreSync file, on for every app or only in Adobe apps) are one "Adobe Fonts" item (`adobeFontsID`), shown while it has fonts, whatever the switch (row menu: Manage in Creative Cloud; no Export Fonts); a family is in it when any copy is, like a folder. Type designers export fonts there to test them; they're unrelated to Adobe Fonts from Creative Cloud (CoreSync), which are always listed and tagged "Adobe Fonts", never "Adobe". They aren't in the user's folders: Settings → General → Type Designer Mode → "Show test fonts installed for Adobe apps" (on by default; saved as `showAdobeAppFolders`, formerly `showAdobeFonts`) switches them, and only them; adding one of them with + turns the switch on. Every folder row's menu starts with Rename Folder (a prompt with the current name; the name lives in `UserData.folderNames` by folder ID, the folder on disk keeps its own; empty or the folder's own name removes it; shown wherever a folder's name is: sidebar and window title, Settings → Folders, smart set rules, Problems, Use Copy From; Cicero's own items take one too; forgotten when the folder is removed). Row menu for the user's folders: Reveal in Finder; "Fonts in This Folder" picker —
    "Inactive" / "Active" / "Active in Adobe apps" / "Active in Specific App" (asks for its name); Remove Folder from Library.
    Cicero's own Deactivated folder appears here when it has fonts, and so does "Added Fonts" (doc), the
    files added one at a time (see Opening and adding files; row menu: Reveal in Finder, which selects them).
  - **Sets** (+ menu: New Set, New Smart Set, New Application Set). Sets (square.stack), application sets (app.badge.checkmark) and smart sets (gearshape). A set's menu has Activate with Apps (Edit Apps once it has some).
    Menus start with Activate Set, Activate Temporarily and Deactivate Set
    (Activate Smart Set, Deactivate Smart Set), for every family the row shows; then Rename Set, Delete Set;
    Edit Smart Set, Delete Smart Set.
  - **License** (a family's license status; saved as tags, `SidebarSection.tags`; + new status: the New License Status sheet, a name and a
    row of colour dots, None, the Finder's seven and sand, starting on the first colour no status has; an empty name
    is the colour's; a name that's taken says so and can't be created). A new library starts with Licensed (green),
    Licensed + Non-Commercial (sand), Unlicensed (red), Partially Licensed (yellow), Public Domain (purple), Open
    Source (blue) and Trial (orange). One row per status in the order they were made, a dot in its colour (a picture,
    not a tinted symbol, which the list darkened on the accent colour; or checkmark.seal when it has none). Menu:
    Rename License Status (a name that's taken says so), Color (None, Red, Orange, Yellow, Green, Blue, Purple, Gray,
    Sand; each with its dot, as are statuses in a family's License Status menu: `.titleAndIcon`, since menus built
    with the macOS 27 SDK hide images otherwise), Delete License Status (off every family, and out of smart set rules).
  - **Foundries**. Menu: Rename Foundry
  - **Classifications** (+ new classification). Serif, Sans Serif, Monospaced, Script, Ornamental, Symbol — only the ones
    with families — then the user's own (always shown, in the order they were made), then Unclassified. A family's
    classification is the one its fonts suggest unless the user put it in another: the family menu's Classification
    submenu (Automatic (Sans Serif), every classification, New Classification; a classification is checked when the
    user put every family in it, so choosing the one Automatic suggests keeps the family there), the Info panel's Classification row
    (Change menu, the same items), or dropping families on a classification row. Menu: Rename Classification (built-in
    ones too; their own name back undoes it; a name that's taken says so; overrides, smart set rules and the sidebar
    follow), Delete Classification for the user's own (its families go back to Automatic, its smart set rules go).
  - **Coverage** (titled like the Settings tab; + new custom set). Collapsible groups — Latin S–XL, Adobe Latin, Google Fonts, Unicode Blocks, Your Coverage Sets — with every set shown unless hidden (Edit, Settings). Unicode Blocks and Google Fonts start collapsed. Menu for custom: Edit Coverage Set, Delete Coverage Set.
- The menus of sets, smart sets, license statuses, folders, foundries, classifications and character sets also have Export Fonts (that row's families, see Export and backup). Every row menu also has Hide from Sidebar and Edit Sidebar.
- Order: rows drag to a new place within their own section (character sets within their group), never
  into another one; as in Finder's sidebar, the rows around the place they'd land slide apart to open a gap
  for them. Character set groups move by dragging a group's title onto another's, which is highlighted: the
  dragged group takes its place (a click on the title opens or closes the group, so the title can't also
  drag in the list). Sections don't move: a click on a title opens or closes it, and a drag does nothing (an
  order saved when sections could be dragged is kept; Reset Order puts them back). Items that are gone for now (System Fonts while
  system fonts are off, an empty Deactivated folder) keep their place; new items go last.
- Several rows of one section (or character set group) can be selected with ⌘- and ⇧-click and dragged
  together: they land side by side in the gap, in their order. The browser then shows the fonts in any of them. Selecting in another section starts over there.
- Moving through the sidebar quickly (holding an arrow key, clicking from row to row) moves the selection at
  every step; the browser shows the last one once the selection rests for a moment.
- Dropping family names (drag from the browser) onto a set, license status, foundry or classification adds them; the
  row they're over is drawn in the accent colour with white title and symbol (a status's dot keeps its colour).
- The list draws no selection (`selectionHighlightStyle = .none`): a selected row has its title and symbol in the accent
  colour on a light grey rounded fill, whether or not the list has focus (`SidebarHighlight`).
- Creating a set, license status, classification or coverage set un-hides its section.
- Settings → Sidebar lists the same items, in the sidebar's order, as Finder-style checkboxes, with
  Reset Order and Show All.

## Browser

- Title = selected item's name (several: "Serif and Script"); subtitle "1.298 families · 716 active" (or "… · checking characters, 400 of 1.298" while coverage is computed and the list depends on it).
- Toolbar, left to right, each in a glass capsule of its own, 8 pt apart like the Info button and the search field
  (ToolbarCapsule: AppKit merges neighbouring items into one capsule, and ToolbarSpacer(.fixed) leaves 16 pt): view switcher
  [List list.bullet | Grid square.grid.2x2 | Specimens rectangle.grid.1x2] · [Preview Options textformat.size] · [Info info.circle] · native search field.
- **List** (rows under column headers in a lazy stack, like the grid: not a SwiftUI Table, which makes every
  row's cells whenever an accessibility client — a password manager's autofill, say — walks the window, and
  with a thousand families kept the app busy for minutes each time it came to the front): Status (switch) ·
  Name (+ license status dot, status tag) · Preview (sample in the font, 17 pt) · Styles · Classification · Foundry · Year
  (hidden; the earliest year among the family's faces: each face's earliest 1950-or-later year in its copyright notice, else
  its head table's created year from 1985 on; read when scanning and kept in the face cache) · Latin S–XL
  (largest of Latin S/M/L/XL the family fully has) · Adobe Latin (shown as "AL 3") · GF Latin, GF Cyrillic,
  GF Greek (hidden; largest of each script's Google sets, shown as "Plus"; GF Latin African branches off
  Core, so it isn't in the series) · any set no series covers: a Unicode block, GF Latin African, a custom
  set (hidden; ✓ when the family has all of it, "12 missing" when some) · Date Added (hidden) · Format
  (hidden). The headers are a bar under the toolbar (`safeAreaBar`, with the hard scroll edge effect), so
  the rows go under both together. Click a header to sort by it, again to reverse; right-click the headers to
  show or hide columns, the character set columns (series, then built-in single sets, then the user's own after a separator) under Coverage (Status,
  Name and Preview always show); drag the gap between two headers to resize the column on the side away from
  the preview, which makes up the difference, so the edge follows the pointer (shown columns and widths saved).
  When the room runs short (the Info panel open), the preview gives way first, then the other columns down to
  their minimums. The preview isn't clipped to its row: tall glyphs run over the row's edges rather than lose
  their descenders. Selection as in the other views.
- **Grid**: tiles — status tag + switch on top, big centered sample ("Aa Gg 123", or the sample
  text when set), name with its license status dot, and what the family's styles span, in Title Case: "9 Weights · 3
  Widths", "8 Weights · 16 Styles"; at the bottom right, the kinds of file it comes in ("OTF",
  "Variable", "OTF · Variable": extensions in capitals, variable fonts just "Variable"). No axis
  ranges: a variable font's styles are its named instances, placed by their axis values; a static
  font's by its names and classes. Weights count the words in style names (Bold, Bd, U Lt) first — many static files leave
  every class at 400 and variable fonts nudge instances off round values — then the axis value or
  OS/2 class. Widths: a variable instance's wdth value, with instances whose names write the same
  width words (Condensed, not XXX Condensed) counted once; a static font's OS/2 width class unless
  it's normal, then the name. A family with more styles than weight and width tell apart (italics,
  optical sizes, other axes, small caps cut as fonts of their own) adds "N Styles". The full caption is
  the tooltip. Tiles scale with the preview size.
- **Specimens**: cards like the grid's tiles (light grey, tinted and outlined when selected, 12 pt apart, 16 pt from the edges) — name, license status dot, status tag, "Foundry · N styles", switch; the sample at preview size, lined up as Preview Options' alignment says; up to 14 style names set in themselves (+N more).
- License status dot: an 8 pt circle in the status's colour, with no ring (side by side, 2 pt apart, for a family tagged
  several ways before there were statuses). Cards are opaque (the card's grey on the window's background), so the
  picture dragged to the sidebar looks like the card.
- Selection: click, ⌘-click, ⇧-click, ⌘A, arrow keys (↑/↓ in the list and specimens; in the grid ←/→ a tile and ↑/↓ a row; ⇧ extends), Esc clears (closing Quick Look first when it's open), and so does a click between families or below the last, typing a letter jumps, Return or double-click opens the font page, Space opens Quick Look; rows are draggable as family names. Right-click → family menu.
- Search matches a family's name or foundry, or a style's PostScript name, designer or vendor ID.
- Empty states per selection (no folders or added fonts → Add Folder, Add Fonts; nothing active; empty set; smart set with no matches → Edit Smart Set; character set still being checked; search with no results).
- A small glass capsule bottom-right while a scan takes longer than 0.4 s ("Finding fonts", "Identifying fonts 200 of 4000"); quicker scans show nothing.
- Selecting Problems shows the Problems view instead of a list.
- Status tags (small capsules): System; Partly active (orange); "Adobe Fonts" (purple) when every face is from Adobe Fonts (`Family.isAdobeFonts`), whatever its state, tooltip "From Adobe Fonts, managed in Creative Cloud" (plus "Active in Adobe apps only." for those); "Testing" (red) for app-only in Adobe apps (Adobe's folders, where type designers test fonts), else the app's name, e.g. "InDesign", tooltip saying the app loads it from a folder by itself; "Temporary" (blue) for temporarily active; "App Set" (blue) for on for an application set.
- Switches: a small switch drawn in SwiftUI (not a native NSSwitch per row — too slow), with tooltip
  ("Installed with macOS" / Activate / Deactivate) and VoiceOver toggle semantics. Families whose
  every face is in (or was moved out of) one app's own folder, like Adobe's, have three positions: on in
  that app only (knob halfway, track lightly tinted), on everywhere, off everywhere. Clicking goes
  app only → everywhere → off → app only; tooltips "On in Adobe apps only. Click to turn on in every
  app." / "On in every app. Click to turn off, Adobe apps included." / "Off. Click to turn on in Adobe
  apps only." The styles table's switches do the same per style.

## Font page (pushed over the browser; Esc or Back returns)

One scrolling page, top to bottom: header, text, styles, glyphs with the ligatures after the characters (no tabs).

- Toolbar: Info · the search field, as in the browser (typing in it goes back to the browser with the matches). No Preview
  Options: the page has its own size and alignment, and takes preview text (styles list), weight and spacing from the browser's.
- Header: family name in its own regular face (34 pt), then "Foundry · OpenType PostScript · Variable · 2 Styles · 1 active · 1 inactive" (no classification; how many styles are active, partly active — on in one app only — and inactive, leaving out the kinds with none: "2 partly active", "3 active · 2 partly active · 1 inactive"), and on the right Activate (prominent) / Deactivate, worded as in the family's right-click menu (Activate in All Apps and
  Deactivate in Adobe Apps for a family in an app's folder, Activate Permanently, Activate Remaining Styles); locked families get a disabled Deactivate with the reason as tooltip, except that a family with any face from Adobe Fonts gets "Manage in Creative Cloud" instead, which opens the Creative Cloud app (com.adobe.acc.AdobeCreativeCloud; it takes no links to its Fonts page) or, without it, https://fonts.adobe.com/.
- **Text**: Style picker (Automatic = follows preview weight; or a specific style), Size slider 12–240 pt, alignment left/center/right (its own, centered at first; a left alignment chosen when there were two stays), a big editable text (default "Sphinx of black quartz, judge my vow.") that grows with what's typed, remembered. Lines are the Preview Options line spacing apart (an exact line height, so tighter than the font's own works too). Every glyph draws whole, however far past its line it reaches: the editor keeps room above and below the lines and its lines draw outside themselves (TextEditor cut them off at the font's ascent and descent). Esc goes back, as elsewhere on the page.
- **Styles** (only when the family has more than one style): laid out like a table — Preview, Style, Weight, Status (the style's switch and its state, e.g. "Active until Cicero quits"); right-click → style menu, which ends with the family's Add to Set, License Status and Classification under the family's name.
- Right-click on the header or the text → the family menu, as in the browser. The text, an NSTextView, shows it after Cut, Copy and Paste (an NSHostingMenu made at each right-click; macOS adds AutoFill).
- **Glyphs**: heading 56 pt below the styles with "404 characters" (and "· 12 ligatures" when the style makes any) and a filter field (character, Unicode name or U+ code; ligatures whose characters hold the text, or with that code, too), then one section per Unicode block with counts (Basic Latin, Latin-1 Supplement, Latin Extended-A, …), block headers pinned while scrolling, cells set in the font (a mark that combines with the character before it, like those in Combining Diacritical Marks, drawn from its outline: set alone it has nothing to sit on and showed nothing); click a cell for a popover with the character large, its name, code point.
- **Ligatures** (only when the style has any), after the blocks, in the Glyphs section. A character whose glyph a ligature is too (ﬁ, usually also U+FB01 in Alphabetic Presentation Forms) is listed once, as the ligature, whose popover says "Also U+FB01, Latin Small Ligature Fi"; the header's character count still counts it, and the filter finds it by that character or code. A pinned header per feature like a block's —
  Standard (liga), Discretionary (dlig), Historical (hlig), Contextual (clig), Required (rlig) Ligatures, with
  counts — and rows of cells like the characters' (52 pt, as many to a row): the ligature glyph drawn from its outline by
  glyph ID at the characters' 26 pt (a ligature has no character to set; centred on the ascender and descender, or the
  glyph where it reaches past them, scaled down when wide or tall), its characters in the tooltip; click
  for a popover with it large, "f + f + i", the U+ codes and the feature. Read from the GSUB table: ligature
  lookups (type 4), through extensions (7), and the lookups contextual ones (5, 6) apply. Components map to
  characters through the cmap (the lowest code point when several share a glyph), a component that is itself a
  ligature to its characters; ligatures of other glyphs (alternates, positional forms no character maps to) are
  left out. AAT-only fonts (morx) list none. Up to 3,000 per feature.

## Quick Look (Space in the browser; Fonts → Quick Look ⌘Y)

- A floating panel with the family selected in the list, grid or specimens. Space or ⌘Y opens it and closes it again; Esc closes it before it clears the selection. It opens only with families selected and never over a font page, and closes when nothing is selected any more, when a font page opens (↩ opens the family the panel shows, double-click and ⌘↓ as usual) and when the main window closes. The menu item reads "Close Quick Look" while it's open. Space never jumps to a family by its letter.
- The panel never takes the keyboard (an NSPanel that can't become key: non-activating, floating, hidden while Cicero isn't the active app). The main window stays key, so ↑/↓ (and ←/→ in the grid) go on moving the browser's selection and the panel follows at once. It opens centred over the main window at the size it was last resized to (520 × 440 at first), with a full title bar (not a utility window's small buttons and title), and steps aside while the main window shows a sheet or alert, so the activation prompt its switch can bring up isn't hidden.
- Content: the family name as the window title (the title bar in the page's colour); a large sample in the regular style — the Preview Options preview text (56 pt, wrapping), or when that's empty "Aa Gg 123" (96 pt, shrinking to fit) over A–Z, a–z and 0–9 (24 pt) — with the family's chosen OpenType features, the preview letter and line spacing and alignment; below it, when the family has more than one style, every style's name set in itself (a variable font's named instances at their own weight), scrolling with the sample; and a glass bar at the bottom: "Foundry · OpenType PostScript · Variable · 12 styles · Active" (the styles' status when they share one, else "3 of 12 activated") and the family's switch.
- Several families selected: one at a time, in the browser's order, with ‹ › and "2 of 5" in the bar (on past the last back to the first). ←/→ in the list and specimens go through them and leave the selection as it is; in the grid, where ←/→ move the selection, the panel follows that. A family just added to the selection (a click, ⇧↓) is the one shown; several added at once (⌘A, ⇧-click) keep the one shown.
- Never holds up the selection: a font file nothing has read yet is read off the main thread while room is kept for its text, and only the styles on screen are made, so big variable families with many named instances step as fast as any.

## Info panel (a pane floating at the trailing edge like the sidebar and in its colour, 300 pt wide, with 20 pt corners on macOS 26 and corners concentric with the window's on macOS 27, starts 16 pt below the toolbar, level with the first row of the grid and of specimens, and as far from the grid's last column as tiles are from each other (12 pt), stays put when a font page opens, toggled by ⓘ (a toolbar toggle, highlighted while the panel is open) / ⌘I; an overlay on the split view, since the detail column's stack swaps the whole column for a pushed page, and each page makes room for it)

- Family name; segmented Info | Features, in the tabs picker style on macOS 27 (no style picker: it describes the style being previewed).
- Info: Status, License Status (the family's, with its dot, or No Status, and a Change menu: the License Status menu), Family, Style, Full name, PostScript name, Version, Designer, Manufacturer, Vendor ID (OS/2 achVendID, padding trimmed; left out when blank or not printable), Weight, Variable weight, Glyphs, Format, Copyright, Languages ("213 languages, including English, German, …" + Show All popover grouped by script with search; full support marked), Coverage (largest set per series the face has, e.g. "Latin S, Adobe Latin 3, GF Latin Core", plus "Latin M needs 12 more characters"), Location + Reveal in Finder, Other copies.
- Features: the face's OpenType features, a box of switches per feature like the system Typography panel (in a one-at-a-time feature, switching one on switches the others off; switching the chosen one off goes back to the default); chosen features apply to that family everywhere it's previewed (list, grid, specimens, font page).
- With nothing (or several fonts) selected: "No Selection" / "3 Fonts Selected".

## Preview Options (popover)

Preview Text field (no section title; placeholder "Font name"; empty = each family's name in list/specimens, "Aa Gg 123" in grid), Presets menu (Font Name; "Sphinx of black quartz, judge my vow."; "Hamburgefonstiv"; "0123456789 €$£¥ %&@"; "ÀÉÎÕÜ ñçß øæœ"), Size (8–160 pt), Weight (100–900, continuous for variable fonts), Letter Spacing (−10…40 % of the em, 0.5 steps), Line Spacing (80–250 % of the size, steps of 5, 120 at first, as layout apps' automatic leading; wherever a sample wraps: font pages and Quick Look), Alignment (left/center/right segments, left at first; specimens and Quick Look — font pages have their own). Each slider's value beside it takes a number typed in too (Return or leaving the field applies it, kept to the range
and rounded to the step; ↑/↓ step it, ten steps with ⇧), as does the font page's Size. Use custom-drawn sliders on macOS 26, whose system sliders lose their glass knob in toolbar popovers; the system slider on macOS 27, which draws it itself (continuous and rounded to the step, so it shows no ticks).

## Menus

- **Cicero**: About Cicero (the standard panel: version, a link to maximilianinzinger.com, "© 2026 Maximilian Inzinger"), Check for Updates (disabled while a check runs).
- **File**: Add Fonts ⌘O, Add Folder ⇧⌘O, Find Fonts in Document, New Set ⇧⌘N, New Smart Set ⌥⌘N, New Application Set | Export Fonts ⇧⌘E | Back Up Library, Restore Library.
- **View**: Show Sidebar / Hide Sidebar ⌃⌘S (SwiftUI's SidebarCommands). Edit Sidebar is in the sidebar's own menus.
- **Fonts**: Activate ⌘↩, Activate Temporarily ⌥⌘↩ (until Cicero quits), Deactivate ⌫, Open ⌘↓ (one family selected), Show Info ⌘I, Quick Look ⌘Y (families selected; Close Quick Look while it's open), Reveal in Finder ⇧⌘R, Move to Trash ⌘⌫, Compare ⌥⌘C, Character Toolbox ⌥⌘T, Rescan Library ⌘R, Rebuild Font List, Clear Font Caches
- **Help** (replaces SwiftUI's default, which says help isn't available): Cicero Help ⌘? (the user guide, help/README.md on GitHub), Release Notes (the GitHub releases page) | Report an Issue (a new GitHub issue). Each opens in the default browser.
- **Family context menu**: "3 Families" header for multiple; a status note ("Available in Adobe apps only", "Installed with macOS", "From Adobe Fonts" for a family Creative Cloud has on for every app; one only Adobe apps use gets "Available in Adobe apps only"); Manage in Creative Cloud (families with a face from Adobe Fonts); Activate / Activate Remaining Styles / Activate in All Apps (app-folder fonts: they're used where they are); Use in Adobe Apps Only (app-folder fonts not already there); Activate Temporarily (until Cicero quits; "in All Apps" for app-folder fonts; hidden when everything is already on, for good or until then); Activate Permanently (temporary fonts); Deactivate / Deactivate in All Apps (app-folder fonts on everywhere) / Deactivate in Adobe Apps (app-folder fonts on in Adobe apps only); Add to Set ▸ (checkmark toggles, New Set from Selection); License Status ▸ (one checked, each with its dot; choosing one replaces the family's; No Status; New License Status); Classification ▸; Reveal in Finder; Copy Family Name(s); Export; Compare; Remove from Library (when every style's file was added one at a time); Move to Trash
- **Style menu**: status label, Activate Style, Activate Temporarily (hidden when the style is already on, for good or until Cicero quits), Deactivate Style, Reveal in Finder, Copy PostScript Name, Move Style to Trash
- Text editing keeps its shortcuts: when an editable text has the focus (the search field, the preview text field, the font page's text, a sheet's fields), ⌫, ⌘⌫ and ⌘ or ⇧⌘ with an arrow key go to the text, as in any Mac app (⌘⌫ deletes to the start of the line, ⌘↓ moves to the end), not to Deactivate, Move to Trash or Open. Menu shortcuts come before the focused view, so a key-down monitor hands those to the text view first. ⌫ and ⌘⌫ act on the main window's selection, so in other windows (Compare, Character Toolbox, Settings, sheets) the monitor hands them to that window instead of the menus. ⌘A selects the text there (Edit → Select All); in a font list it selects every family. ⌘↩ and ⌥⌘↩ mean nothing to text and stay with the Fonts menu.

## Library and fonts

- Sources: everything CoreText reports active (`CTFontManagerCopyAvailableFontURLs`), macOS's own /System/Library/Fonts (CoreText's lists leave out some of its fonts, like Times, Courier, Iowan Old Style, Seravek and many Noto fonts, though apps can use them; its files count as active, from macOS, and its hidden "." families are left out as anywhere), ~/Library/Fonts and /Library/Fonts, watched folders, the files added one at a time (Added Fonts; skipped while missing or dataless), Cicero's Deactivated folder (~/Library/Application Support/Cicero/Deactivated). A file in the Fonts folders is active when CoreText lists it, or, for the few it leaves out (fonts with hidden names), when `CTFontManagerGetScopeForURL` says so; otherwise it's not activated (it's turned off in macOS, or macOS hasn't noticed it yet). Without a list from CoreText at all, files in the Fonts folders count as active. Files Cicero registered itself (in place, or for a while) that the list leaves out are asked about the same way: the list hides some fonts though they're on, like copies of the macOS fonts it hides. Files in watched folders that iCloud or another file provider has taken off the Mac (dataless) are skipped until they're downloaded: reading one would download it.
- Files: otf ttf ttc otc dfont woff woff2; each face read with CoreText (PostScript name, family, style, full name, OS/2 weight class (fallback from traits), OS/2 width class, italic, monospace, OS/2 family class, PANOSE (kind and serif style as a classification), letter shapes (below; only for faces with no family class and no monospace flag), manufacturer, version, designer (name ID 9), OS/2 vendor ID, wght axis range, visible variation axes (tag, name — the tag when the font gives none — and the named instance's value on each)). Unreadable files are kept for Problems. Parsed faces are cached by path + modification date + size; Date Added (Finder's, fallback creation date) is cached with them.
- Families group faces by family name (hidden "."-prefixed families skipped). The same PostScript name in several files is one face: the active file wins, the others are "other copies"; Date Added is the earliest.
- Face state: active (from macOS / installed for all users / inside an app / Adobe Fonts (CoreSync) / your Fonts folder / used in place by Cicero / temporarily until Cicero quits / for an application set / another app), inactive, or "active in <App> apps" for watched folders marked app-only and the Testing folders. Also "Active in Adobe apps", as for Adobe's folders, for the Adobe Fonts Adobe apps turned on for themselves (as for a document), which Creative Cloud keeps under hidden names in ~/Library/Application Support/Adobe/CoreSync/plugins/livetype/.w (`Locations.adobeFontsInAdobeApps`, scanned always, hidden files included, and watched): app "Adobe", no folder item, and locked like every CoreSync file (`LibraryFace.isAdobeFonts`: no activate, temporary activation or deactivate; the switch sits halfway, disabled; the engine refuses them too). Such a copy ranks after every other, so a copy of the user's stays the face to switch, and it never makes a user's file spare (`SpareCopies`).
- Family state: all active (system if all from macOS) / partly / inactive / app-only / system.
- Classification, the first that says something: monospace (any face), OS/2 family class of the lightest upright face (1,2,3,4,5,7 serif, slab serifs included; 8 sans; 9 ornamental; 10 script; 12 symbol; sub-classes don't change it), name hints (mono/code, sans/grotesk/gothic, serif/slab/garamond/antiqua, script/brush/hand, symbol/dingbat/emoji), letter shapes, then PANOSE (kind 2 with serif style 2–10 serif, 11–13 sans, flared and rounded nothing; 3 script; 4 ornamental; 5 symbol; the proportion digit is ignored, as it often says monospaced wrongly). Letter shapes and PANOSE count when the upright faces (all faces, in a family of italics) that have one agree; letter shapes make a family monospaced only when every one of those faces is, and otherwise its monospaced faces don't count. Where both say something and differ, the letters are right, so they come first.
- Letter shapes (`LetterShapes`): monospaced when a drawn i, m and W (I, M and W without lowercase) are exactly as wide; letters not drawn yet, all as wide in unfinished fonts, and fonts in three widths (i and m alike, W wider) don't count. Else the capital I and lowercase l, flattened, measured with exact scanlines (non-zero winding). Each must be one stem: one run of ink at 30, 50 and 70 % of the glyph's height, widths within 1.3×, on a straight line leaning as the font's italic angle says, at most two contours. Serif when the ink 1–5 % from the bottom (and, for the I, from the top) reaches more than 0.3 stem widths past the stem on both sides of the I and at the foot of the l; sans when the I's ends reach less than 0.12 and the l's foot doesn't reach both ways (a tail to one side is fine). A font with only one of the two (capitals or lowercase only) goes by that one; an l alone is sans only with no tail either. Anything else (Verdana's serifed I with a plain l, scripts, italic l's tails) gives nothing: a wrong classification is worse than none.
- Name guesses (`ClassificationGuesser`, app): while Settings → General → "Guess classifications from names" is on (from the start; `classification.guessesFromNames`) and `SystemLanguageModel.default` is available, the families still Unclassified are asked about one at a time in the background (not ones whose upright faces' letters say serif for some and sans for others, `Family.mixesSerifAndSans`: the model picks one of the two for them), in a new `LanguageModelSession` each, with greedy sampling and guided generation into serif / sansSerif / monospaced / script / ornamental / symbol / unknown. The prompt is the family name, foundry, designer and up to 12 style names. Answers, unknown among them, are kept in Caches/Cicero/classification-guesses.json (with the prompt's version), so each family is asked once; rate limits and missing model assets stop until the next scan, other failures until the next launch. A guess applies only while the family is Unclassified and has no classification the user chose; the Info panel then says "Guessed from the name by Apple Intelligence". Turning the setting off forgets the guesses. On-device only: never `PrivateCloudComputeLanguageModel`.
- Foundry: manufacturer name trimmed of Inc./LLC/GmbH/…, URLs and copyright lines dropped, casing unified; user can rename a foundry or set a family's foundry (drop onto foundry).
- At launch the window opens with the library the last scan built (saved in the caches after every scan that changes it; faces turned on until Cicero quit, or for an application set in an earlier login session, show as off), and the launch's scan, started before the window is made, replaces it.
- Rescan: on launch, right after activation changes, on CoreText's registered-fonts-changed notification (posted to the app's own notification center, for any app's changes; debounced; while an operation runs they wait for the scan it starts when it finishes, or one right after it when it starts none), when font files come or go in the scanned folders (FSEvents), and when the app becomes active after ≥60 s. An unchanged scan must cost almost nothing (fingerprint; no UI churn).
- Show system fonts (Settings → General) off hides system families everywhere, and the System Fonts item with them.

## Fonts in a document

- File → Find Fonts in Document (an open panel for pdf ai idml indd indt), or such a file dropped on the browser or a
  font page (one at a time), reads the fonts the document uses off the main thread (`DocumentFonts`): a PDF's from
  its pages' font resources, the form XObjects and annotation appearances they use (BaseFont, subset tags dropped,
  "Identity-H" suffixes too, and whether a font file is embedded); an IDML package's from Resources/Fonts.xml,
  narrowed to the families (`<AppliedFont>`) and styles (`FontStyle=`) its styles, stories and spreads apply (read
  with `unzip -p`, nothing written); InDesign and Illustrator files' from the xmpTPg:Fonts list in their XMP (an
  Illustrator file's PDF fonts too). Each font once. A file it can't read says "Couldn’t read the fonts in “Name”."
- Sheet "Fonts in “Brochure.indd”", "12 fonts · 8 on · 2 off · 2 missing", one row per font, missing first, then off,
  then on, each by name: a status symbol (green check, dashed circle, orange triangle), the name (family and style,
  else the PostScript name) with the PostScript name under it, an "Embedded" tag for a PDF's embedded fonts, the
  status (the face's state label, "Installed with macOS" for one CoreText has though the library doesn't, else "Not
  in your library") and an action: Activate, or for a missing font Find on This Mac, which asks
  Spotlight (`mdfind 'kMDItemFonts == "Name"'`, local) for font files with its PostScript name, newest first, none
  in the Trash: "Found “Name.otf”" with Add (lists it under Added Fonts, without changing the browser), else "Not
  found on this Mac" (Find again stays available). Spotlight hides files in the folders macOS keeps private until
  the user lets the app in, without asking; so before searching, Cicero lists ~/Documents, ~/Desktop and
  ~/Downloads, which asks once (Info.plist explains why, for each).
- Matching: the library's face with the PostScript name, else the family and style names (case, spaces, hyphens
  and underscores ignored); a font the library hasn't but `CTFontCreateWithName` gives back by that exact name is on.
  Cached until the library changes, so the rows follow activations and added files.
- Buttons: Make Set (a set named after the file without its extension, with the families in the library; one of
  that name gets them added; the sheet says what it did), Activate All (every face in the library
  that's off), Done. The sheet presents the activation prompt itself; the main window holds it back meanwhile.

## Opening and adding files

- Font files (otf ttf ttc otc dfont woff woff2) come in three ways: File → Add Fonts ⌘O (an open panel for those
  types), dropped from the Finder on the browser or a font page (outlined while files from outside Cicero are over
  it), and opened from the Finder: Info.plist declares the font types (Viewer, rank Default), and the main window
  scene handles external events. URLs arriving within 150 ms of each other are one batch; before the first scan
  they wait for it.
- A dropped or opened folder is added as a watched folder. A font file the library lists already (a face's file or
  other copy, or in the Fonts folders, the Deactivated folder or a watched folder) is just shown; any other goes
  into the user data's `fontFiles` and is listed where it is, like a watched folder's fonts, under Added Fonts
  (`WatchedFolder.addedFilesID`), which un-hides. Nothing is installed.
- Duplicates (`AddedDuplicates`, `UserData.duplicateHandling`, Settings → General → "When an added font is already in your
  library"): before font files the library doesn't list are added, their faces are read off the main thread, and a
  face whose PostScript name a library style has from another file makes its family a duplicate (grouped by the
  library's family; versions compared with `FontVersion`: Newer, Older, Same Version, or Same File when the files are
  the library's byte for byte). Ask (the default) shows a sheet with a row per family: name, a Newer/Older/Same
  Version/Same File tag, "4 styles · In your library: 1.002, on in your Fonts folder · Added: 2.000", and a picker:
  Skip It / Add as Another Copy / Use the Added One, starting at Use the Added One when the added one is newer, else
  Skip It; Choose for All; Cancel adds nothing of the batch, Add adds everything else as usual. The setting can
  instead always Add it as another copy (as before), Skip it, Use the added one, or Keep the newer version (use it
  when newer, else skip). Skipped: a file only of skipped families stays out, the browser shows the library's
  copies, and the toast says "Skipped Helvetica, already in your library" / "Skipped 3 families already in your
  library". Use the added one (`AddedDuplicates.replacement`): for each style whose library copy is on, the copies
  Cicero can turn off (from a Fonts folder, in place, until quit, by another app; not macOS's, an app's, Adobe Fonts'
  or an application set's) go off through `switchCopies`, as deactivating does (a copy Cicero installed to the Trash
  when its original is in the library, any other Fonts-folder file to the Deactivated folder), then the added face
  goes on: installed (copied, or moved with Move) when fonts are activated by copying or moving, which installs the
  whole file once it takes over any style; else in place, or copied when Ask and the old copy was in a Fonts folder.
  Old copies under Added Fonts whose every face is taken over stop being listed. Toast: "Using the added copy of
  Helvetica" / "Using the added copies of 3 families", plus ". Another copy Cicero can’t turn off is still on, so
  apps may use that one" when one stays. Not for folders, nor files Find on This Mac turns up.
- After the scan that reads them, the browser shows their families selected: added files in Added Fonts (a short
  list, so they're in view: the browser doesn't scroll to a selection), others in the sidebar item shown when it has
  them all, else in All Fonts (the search cleared). One family opened from the Finder opens on its font page.
  Dropped while the browser shows a set, they join it and stay in view there ("Added 3 families to “Set”.").
  SwiftUI hands the main window's `onOpenURL` only the first of several files opened together and the app
  delegate's `application(_:open:)` the rest; both go to `AppModel.open`. A file nothing can read says "Couldn’t read “Name.otf”."; a system font while system fonts
  are hidden says so.
- Added files are watched through their folders (FSEvents), which then report only those files, so a font being
  rebuilt is read again; files right in the home folder aren't watched.
- Remove from Library (family menu, when every style's file was added) takes their paths out of `fontFiles`; the
  files stay, and a font that's on stays listed.

## Activation

- Install method (Settings → General → Activation): Ask each time / Copy into ~/Library/Fonts / Move into ~/Library/Fonts / Leave the files where they are. "Ask" shows a sheet: Install a Copy, Move Into Fonts Folder (files added one at a time), Leave Files Where They Are, an Activate Temporarily button (until Cicero quits; hidden when the fonts are already on until then), "Remember this choice (you can change it in Settings → General)".
- Every switch moves the moment it's clicked and stays there while the operation runs; the scan after it confirms or corrects it. A switch that's moving ignores clicks.
- Copy: copied into Cicero's staging folder (~/Library/Application Support/Cicero/Staging) and moved into ~/Library/Fonts, so macOS never sees a half-written file (unique name if needed; a file of the same name with the same contents counts as already there), then registered (persistent) so apps get it at once — macOS takes seconds to notice a new file by itself. Remembered as installed copy → origin. A copy macOS won't turn on is taken out again and the font counts as failed.
- In place: CoreText persistent registration, remembered.
- A font only counts as activated once macOS reports its file active (`CTFontManagerGetScopeForURL`). Registration waits for fontd, so when the toast says "Activated." the font is in every app's font list. A font in a Fonts folder that macOS has off is turned on where it is.
- Fonts from app-only folders (Adobe) are always used in place — never copied. Turning one off
  everywhere moves its file into Cicero's Deactivated folder (the app would load it otherwise) and
  records where it was (`appFolderOrigins`); it stays listed with that folder. Activating it, or Use in
  Adobe Apps Only, moves it back first (beside a newer file of the same name; fails if the folder is
  gone). Folders the user can't write to (InDesign's, owned by root) can't be turned off this way.
- Temporary: CoreText session registration in place (app-folder fonts too: on in every app for that long, then back to where they were), always until Cicero quits (the only choice): unregistered on quit, leftovers from a crash unregistered at launch. Records saved with the former "until you log out" choice load as until Cicero quits.
- Deactivate: a copy Cicero installed goes to the Trash only when its recorded origin is still there with the same contents (size and bytes, a separate file: not the same one through a link, and not one iCloud has taken off the Mac). The whole file decides, so a collection or variable font goes only when every face in it is in the origin. Every other file in ~/Library/Fonts moves to Cicero's Deactivated folder: the user's own files, whatever other copies exist (macOS's, Adobe Fonts', an app's, another version), and installed copies whose origin is gone or changed. Ask first for every file Cicero didn't install ("Deactivate fonts?" alert), from anywhere, Problems included. A file holds every face in it, so deactivating one style of a collection moves the whole file. Files in ~/Library/Fonts are unregistered before they move, so apps drop them at once; one that can't move is registered again. In-place/temporary → unregister (persistent, falling back to session). macOS, all-users, app and Adobe Fonts faces can't be turned off ("These fonts are managed by macOS or another app.").
- Activating permanently a temporarily active font ends the session registration first.
- Application sets: a set with apps (bundle ID, name, path). While one of its apps is open, its fonts that are off are registered for the session and confirmed active, like temporary activation (record scope `whileAppsRun`, with the bundle IDs of the open apps that want each file); when no open app wants a file any more it's unregistered. Fonts on for any other reason are never touched. `AppSetWatcher` follows `NSWorkspace.runningApplications` (it changes as an app starts launching, before it reads its fonts) and syncs when apps, sets, records or the library change; a font the user turns off, or on for good, while its app is open is left alone until the app quits. Registrations outlive Cicero quitting (the app may still be open) and are synced at the next launch; they end at logout anyway, so their records keep the login session (audit session ID + boot time) and ones from an earlier session are forgotten at launch. Works only while Cicero is open: Settings → General has Open at login (SMAppService), and the apps sheet offers it too.
- Move to Trash (family or style): unregister (in-place files and files in ~/Library/Fonts; registered again if they can't be moved), trash every file including other copies; never touches /System, /Library/Application Support/Apple, /usr, /private, app bundles, Adobe CoreSync; collections that also contain other families are named in the alert; removes the family from sets, its license status and foundry overrides. Alert "Move “X” to the Trash?" with destructive Move to Trash.
- Short toasts at the bottom ("Activated.", "Deactivated.", "Moved to the Trash.", failures).

## Sets, smart sets, character sets

- Sets: ordered lists of family names, optionally with apps (application sets, see Activation). The apps sheet ("Activate “Name” with Apps"): the apps with their icons, "Open" next to running ones, − to remove, Add App (an open panel in /Applications), and a line about opening Cicero at login. License statuses (saved as tags): names in the order they were made, family → statuses (one, given in place of the one it has; families tagged several ways before keep them until given one), status → colour (Finder's seven, sand, or none; New License Status starts on the first no status has, red again once all are taken; a colour a later version adds loads as none). A new library (no user-data.json and no library.json to import) starts with the seven license statuses in their colours. A user-data.json saved before there were statuses (no `licenseStatusesAdded`) gets them once as it loads, first, in their colours, and so does one restored from such a backup; Red, Yellow and Green go when they're as a library started (in their colours, on no family, in no smart set rule). Given from the family menu's License Status ▸ (in the browser and on a font page), the Info panel, or by dropping families on a status.
- Smart sets: name, match all/any, rules (field · comparison · value): Name (contains / doesn’t contain / begins with / is), Foundry (is / is not / contains), Classification, License Status (is / is not), Set (is in / isn’t in), Folder (is in / isn’t in; Testing, Adobe Fonts and Added Fonts too), Status (Active / Partly Active / Inactive / Active in Apps Only / Installed with macOS), Kind (Variable / Monospaced / Has Italics), Format, Number of Styles (is / is more than / is less than), Language (is supported / isn’t supported; Hyperglot languages, searchable picker defaulting to the user's language), Coverage (includes / doesn’t include), Date Added (is in the last / isn’t in the last N days). Editor sheet with live "N families match".
- Character sets: built-in from Resources/CharacterSets.json (Latin S–XL; Adobe Latin 1–5; 38 Unicode blocks such as Basic Latin, Latin-1 Supplement, Latin Extended-A/B/Additional, IPA Extensions, Greek and Coptic, Cyrillic, General Punctuation, Currency Symbols — only their assigned, visible characters; Google Fonts Latin Kernel/Core/Plus/African, Cyrillic Core/Plus/Pro, Greek Core/Plus/Pro); custom sets (name + characters typed or pasted, U+ codes, 0x codes, ranges U+0100–U+017F). A family "has" a set when its regular upright face covers every character.
- Settings → Coverage: groups with checkboxes (show in sidebar, all on by default), counts, summaries, credit links; "Your Coverage Sets" first, scrolling with the rest: rows with checkbox, count and Edit, + in the header, menu Edit Coverage Set / Delete Coverage Set; the editor has Delete for an existing set.

## Coverage and languages

- For each family's regular upright face: the Unicode scalars it covers (from CoreText's character set), cached on disk by file stamp, computed in the background at low priority after scans.
- Languages from Resources/Languages.json (Hyperglot 0.8.1, Apache 2.0): a language is supported when an orthography's base characters and required marks are all present, fully supported when its auxiliary characters are too. Character-coverage only (no shaping).

## Character Toolbox

- The field and controls of each tab, and the language above its fonts, are bars the lists scroll under, fading out
  just below them (`fadingTopBar`: the window's background, then an 18 pt fade; the system's soft edge reaches less far
  than these bars). Section titles in the lists scroll with the rows.
- Text: a field; lists families with every character (sample = the text in each font), count, "Include fonts missing up to N" stepper, "Active only"; shows missing characters per row; double-click opens the family in the main window.
- Languages: search (language, autonym or script), sort by speakers or name, list with speakers; selecting shows the language's characters and two sections: Fully Supported, Base Characters Only.

## Compare

Window "Compare", subtitle "3 families" ("2 families · 3 styles" when a family is there twice). Each entry (`CompareEntry`) is a family in a style: the one nearest the preview weight, or one chosen from the style menu next to its name (Automatic, the family's styles, Compare Another Style, which adds the family again after it in its first style not there yet). Layouts Stacked (one row per font on a shared baseline, name + style menu + remove button under each) and Overlay (all samples drawn over each other in tints on a shared baseline, starting level with the legend, legend chips with remove). Each sample gets room for the furthest its glyphs reach, above, below and to the left, not just the font's ascent and descent (about one font in ten draws descenders below its descent), so nothing is cut off. Uses the preview sample (or "Hamburgefonstiv"), size, weight, spacing; Preview Options in its toolbar; drop families from the main window; choosing Compare again replaces the set. Content starts top-left.


## Problems

Sidebar item with badge; groups with a short explanation and fixes:
- Installed Twice: the same font (same family) active from more than one file. Per copy: version, modified date, where; Reveal; Deactivate when Cicero can, else Remove Copy when the file is a spare copy (below).
- In every group but Shared Style Names, a problem's files that share a folder share one row: the folder, the files' version(s), modified dates and where, and "› 18 files" to show them (each with its own fixes). The row's Reveal selects them all; in Installed Twice it also has Remove Copies / Deactivate when every file has it and every style keeps a copy outside the folder (for Remove Copies, the folder's files together are spare copies), and a green "Newest" tag marks the folder (or file) with the highest version when all the others are older.
- Shared Style Names (minor — not counted in the badge, collapsed at the bottom): different active families with faces that use the same PostScript name. Not name ID 6, which differs, but the names variable fonts give their named styles (fvar instances' postScriptNameID), usually when some are just "Bold" (not when every file comes with macOS). Families linked by a shared name, directly or through another family, are one card: title "A, B and C" (more than 4: "A, B, C and 2 more"); summary "Some of their styles have the same PostScript names: Light, Regular, Medium, Bold, Black, LightOblique and 4 more." (one name: "One style in each has the same PostScript name, Sans-Book."), then "macOS gives those names to A and B." when `CTFontCreateWithName` gives every one of them to a file in the card. Names go upright before italic, then by the weight the style name spells out. One row per file, not by folder: the family as title, the full path, the styles involved and where it is (no version or date), a Preferred tag on the files macOS gives every one of their shared names to (help lists them), and "Preferred for Light Oblique and Bold Oblique" under the styles of a file it gives only some of them, so several winners in one card don't read as several picks for the same name; per file Reveal and Deactivate (when Cicero can).
- Duplicates: same font more than once in your folders (inactive); Move Extra Copies to Trash (keep the installed copy's origin, else newest; an extra file goes only while the files going are spare copies, so a collection that also holds a style with no duplicate stays).
- Missing files: in-place registrations whose file is gone (Forget + unregister), installed copies gone (Forget), set members no longer in the library (Remove from Set). Forget is queued like an activation, so an operation already running can't bring the record back.
- Damaged or unreadable files (not WOFF/WOFF2): Reveal, Move to Trash
- Fonts on external disks used in place: Install a Copy Instead.
- Spare copies: a file is offered for removal only when every face in it, of every family, has a copy in another file that stays (not the same file by another path). Which faces a file holds comes from the library, and the file is read too: one with faces the library leaves out (hidden families) is never offered. When a fix can't be offered, it's left out. The confirmation names the other families in the files ("The file also contains B, which keeps its other copies."), and the files are checked again right before they go: if a copy went in the meantime, nothing moves ("Kept the file: it holds the only copy of a font."). Deactivate asks first like any deactivation.
- Empty state "No Problems". Never trash protected paths or a font's only copy.

## Font caches

Sheet "Clear Font Caches" (Fonts menu and Settings → General; its description, and the Settings footer, say a restart
may be needed afterwards): checkboxes macOS (my account) [`atsutil databases -removeUser` + restart fontd], macOS (all users) [admin prompt via osascript; "Needs an administrator password"], Adobe apps [AdobeFnt*.lst and CT Font Cache locations; disabled with "Quit InDesign first" while an Adobe app runs; shows size], Microsoft Office [its containers are protected by macOS: never look inside until the user ticks it and clicks Clear; row says "macOS asks for permission"]. App caches go to the Trash. Afterwards rebuild Cicero's font list; offer "Restart Now" only when macOS caches were cleared. Settings → General also has "Cicero’s font list: Rebuild".

## Settings

- General: Appearance (System / Light / Dark, applied app-wide via NSApp.appearance); Activation ("Activate fonts by" + explanation incl. app-only folders); "When an added font is already in your library" (Ask each time / Add it as another copy / Skip it / Use the added one / Keep the newer version, + explanation); "Open at login" (for application sets); "Show system fonts" (+ explanation); "Guess classifications from names" (+ explanation following Apple Intelligence's availability; disabled on Macs without it); Font Caches (Rebuild, a red Clear); Backup (Back Up, Restore, one sentence on what a backup holds); Updates ("Check for updates automatically", on by default, + what it sends); Usage Statistics ("Share usage statistics", on by default, + what it sends).
- Folders: list (+/−), each with a menu to mark it as loaded by an app.
- Sidebar: Finder-style checkboxes in the sidebar's order, Reset Order, Show All. Foundries only as a whole section; single foundries are hidden from the sidebar's Edit mode.
- Coverage: the character sets, as above.

## Export and backup

- **Export Fonts** (File, ⇧⌘E; "Export" in the family menu; "Export Fonts" in the sidebar menu of a set, smart set, folder, foundry, classification or character set) copies the font files of the selected families — with none selected, of every family in the list; from a sidebar row, that row's families — into a folder or a ZIP archive, for sending them to someone or a printer. The save panel's name defaults to the row's name, the family's name for one family, or "N Families"; a Format picker in it chooses Folder or ZIP Archive. The folder holds one subfolder per family with its files; one family's files go straight into the folder. Each file is copied once (a collection shared by several faces, or families, once), only each face's own file, not its other copies. Files that come with macOS or an app, and Adobe Fonts, are left out and the toast says so: "Exported 12 families. Left out 3 fonts that come with macOS or an app." Files are copied with FileManager (APFS clones) off the main thread; a ZIP is staged in a temporary folder and made with `ditto -c -k --keepParent`. The export is built in a private folder on the destination's disk and takes its place only once complete, so a failed or cancelled one leaves nothing behind; an item the save panel confirmed replacing goes to the Trash then, never written over. An item that is, or holds, a font file in the library (an exported one, any other, or one Cicero's records name), ~/Library/Fonts, /Library/Fonts, Cicero's folder or its Deactivated folder, or a watched folder is never replaced (by its path or where links lead): nothing moves and the toast says "“Fonts” holds fonts Cicero uses, so it wasn’t replaced. Choose another name or place." The result is revealed in Finder.
- **Back Up Library** (File; Settings → General → Backup) writes a `.cicerobackup` archive (a ZIP made with ditto), named "Cicero Backup 2026-10-13.cicerobackup" by default. A sheet first says what it holds — sets, smart sets, license statuses, character sets, folders and added fonts, foundry names, the sidebar, and the settings for activation, system fonts and fonts installed for Adobe apps — with a checkbox "Include font files" and their count and size ("3,812 files, 2.4 GB": every file in the library, other copies included, protected ones left out, sized off the main thread), then shows progress (a bar while copying, indeterminate while zipping) with Cancel, and reveals the file. Like an export, it's zipped in a private folder on the destination's disk and replaces an older file (through the Trash) only once complete, so Cancel or a failure leaves the older file and nothing else; it never replaces an item holding fonts Cicero uses. Inside: `manifest.json` (format 1, created date, app version, the home folder, `includesFonts`, and every font with its path — the home folder written as "~" — its place in the archive (`Fonts/<n>/<file>`, so names never clash), size, and how it was active: in ~/Library/Fonts, in place, an installed copy with its origin, or not active), `user-data.json` exactly as the store writes it, and the files.
- **Restore Library** (File; Settings → General) opens a `.cicerobackup`, unzips it to a temporary folder and asks "Restore the Backup from 13 October 2026?" with two checkboxes: "Sets, folders and settings" (what's inside: "4 sets, 2 smart sets, 7 license statuses, 3 folders, 12 added fonts and 1 character set"; replaces the current setup, which is saved first to ~/Library/Application Support/Cicero/Backups/Before Restore <date>.json — the sheet says so) and "Font files" (only when the backup has them: "Puts each font back where it was, unless a file is already there."). "~" means this account's home folder, so a backup moves between Macs and user names; the paths in the user data move with it (folders and added fonts). Nothing is ever written over: a file already at a path is left alone. A backup is a file anyone could have made, so nothing in it is trusted: only font files go back (the extensions the scanner reads); a file's place in the archive must stay inside the unzipped folder (no "..", no absolute path, no symbolic link), else it's left out; and a file goes back only to a plain absolute path (no "." or "..", after "~" is expanded) inside a font location: ~/Library/Fonts, /Library/Fonts, Cicero's Deactivated folder, the watched folders in the backup's own user data, Adobe's shared font folders and the Fonts folder next to an Adobe app. Missing folders are made; a file meant for anywhere else, or that can't go back (no permission, or a folder next to an app that isn't installed, like /Applications/Adobe InDesign 2025/Fonts) goes into ~/Fonts Restored from Cicero/ keeping its path under it (without "." or ".." parts), and that folder is added to the watched folders. Records describe this Mac and follow the same rule (installed copies only in ~/Library/Fonts, app-folder origins only for files in the Deactivated folder): the backup's installed copies count when both files exist and the copy is the backup's (this restore put it back, or it has the origin's contents; a different file this Mac already had there is no copy), its temporary activations are dropped, its app-folder origins count when this restore put the file back (activating would otherwise move a file this Mac already had into an app's folder), its in-place registrations are activated again (in place, through the activation engine) once a scan has found the faces, and the current records stay where their files exist. Then a rescan and a toast: "Restored 4 sets and 3,790 fonts; 22 were already there." The file work runs off the main thread with progress and Cancel in the sheet; the records change is one queued operation, like an activation.

## Applications folder

- Open at login points at the copy that's running, and Sparkle replaces that copy, so both need Cicero in /Applications or ~/Applications (or a folder inside them), not on a disk image, in Downloads or at an App Translocation path. At launch, a copy elsewhere asks "Move Cicero to the Applications folder?" ("Application sets, opening at login and updates work only when Cicero is in the Applications folder."): Move to Applications Folder / Do Not Move, with a "Don’t ask again" checkbox. A binary run from .build (`swift run`) never asks.
- Turning on Open at login (Settings → General, or the apps sheet's Open at Login) outside an Applications folder shows the same alert without the checkbox instead of adding a login item; the moved copy then turns Open at login on.
- Moving copies Cicero.app into /Applications, or ~/Applications when the user can't write there; a Cicero.app already there goes to the Trash first (a Cicero running from it is asked to quit). The copy loses the quarantine attribute. The original goes to the Trash when it's on a writable volume, found through `SecTranslocateCreateOriginalPathForURL` when the app was translocated; a disk image it ran from is detached once Cicero has quit. A small shell script waits for Cicero to quit and opens the moved copy. A failure says "Couldn’t move Cicero to the Applications folder." with the reason.

## Data and privacy

- Everything local: ~/Library/Application Support/Cicero (user data, Deactivated folder), ~/Library/Caches/Cicero (face, library and coverage caches, classification guesses). Nothing about the user or their fonts is uploaded; Apple Intelligence's guesses are made by the model on the Mac.
- Usage statistics (`UsageStatistics`): when the app has finished launching, while Settings → General → "Share usage statistics" is on (it is from the start, without asking; `usageStatistics.isOn`), Cicero POSTs one TelemetryDeck signal to `https://nom.telemetrydeck.com/v2/` over an ephemeral URLSession: type `TelemetryDeck.Session.started`, a new session UUID, `clientUser` the SHA-256 of a random UUID kept in the defaults (`usageStatistics.id`), and the payload `TelemetryDeck.AppInfo.version` and `.buildNumber`, `TelemetryDeck.Device.platform` ("macOS"), `.systemVersion` ("macOS 26.1.0") and `.systemMajorVersion` ("macOS 26"). `isTestMode` is true for a build signed without a team, like build-app.sh's ad-hoc one. Until TelemetryDeck has answered with a 2xx while `usageStatistics.countedAsNew` was unset, the same request also carries a `TelemetryDeck.Acquisition.newInstallDetected` signal (the same user and session, the same payload plus `TelemetryDeck.Acquisition.firstSessionDate`, the local day like "2026-10-14"), which TelemetryDeck's Acquisition charts count as a new user; then the flag is set, and kept when the setting is turned off, so a Mac counts as new once. A failed send isn't retried, except that signal at the next launch. Turning the setting off removes the ID, so turning it on again makes a new one. Nothing is sent from a binary run from .build, or while `UsageStatistics.appID` is empty.
- Updates (Sparkle 2): once a day, while Settings → General → "Check for updates automatically" is on (it is from the start, without asking), Cicero downloads the appcast from the latest GitHub release (`SUFeedURL`); Check for Updates does it at once. Sparkle's system profile stays off, so the request carries nothing but its user agent, "Cicero/1.0 Sparkle/2.10.0". An update the user accepts is downloaded from GitHub and installed only if its EdDSA signature matches `SUPublicEDKey`. The appcast holds the latest version only, with its CHANGELOG.md section as Markdown release notes.
- The rewrite reads the existing user data file (library.json, read by `UserDataStore`) once and keeps working from its own file; the old file is never modified.
