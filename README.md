# Cicero

![Cicero’s window: All Fonts as a grid of tiles, each family previewed in itself, with the sidebar on the left](docs/screenshot.png)

**[Download the latest version](https://github.com/opr-inzn/cicero/releases/latest/download/Cicero.dmg)** · [Help](help/README.md) · [All versions and release notes](https://github.com/opr-inzn/cicero/releases) · Requires macOS 26 on Apple silicon.

A font manager for macOS. Browse every font on your Mac and in your font folders, try them out, and turn them on only when you need them.

- **Three ways to browse.** A sortable list with an on/off switch for each family, a preview in the font itself, the color of its license status, and columns you can show or hide (classification, foundry, Latin S–XL, Adobe Latin and Google Fonts coverage, any Unicode block or coverage set of your own, date added, format). A grid of tiles. Or full-width specimens with every style set in itself.
- **Quick Look.** Press Space, or choose Fonts → Quick Look (⌘Y), for a floating preview of the selected family: a large sample, its styles, and its foundry, format and status. The arrow keys move through the list and the preview follows; with several families selected, ‹ and › step through them.
- **Font pages** (double-click, ↩ or ⌘↓). A large text you can type into, aligned left, center or right, a table of styles you can switch on one by one when a family has more than one, and a searchable glyph map grouped by kind, as a type designer would list it (uppercase, accents, figures, punctuation and so on), with the glyphs features like tabular figures draw and the ligatures each style makes. Right-click the text or a style to give the family a license status, add it to a set or change its classification.
- **Info and Features.** The info panel shows a font’s details (its designer and vendor ID among them), its license status, the languages it supports, its coverage and the Unicode blocks it covers; the Features tab turns OpenType features on for that family wherever it’s previewed.
- **Search** by family name, foundry, PostScript name, designer or vendor ID.
- **Preview Options.** Preview text, size, weight, letter and line spacing, and alignment, shared by every view.
- **Light or dark.** Follow macOS, or pick Light or Dark in Settings → General.
- **Customizable sidebar.** Click **Edit** next to Library and every item and group gets a checkbox; uncheck what you don’t want and click **Done**. The same list is in **Settings → Sidebar**, and right-clicking a row offers *Hide from Sidebar*. Drag items into the order you like within their section, as in the Finder, and ⌘- or ⇧-click several items in a section to drag them together or see all their fonts at once. A click anywhere on a section’s title opens or closes it, and View → Hide Sidebar (⌃⌘S) puts it away.
- **Sets and smart sets.** Group fonts by hand, whole families or single styles, or with rules that keep a set current: name, foundry, classification, license status, set, folder, status, kind, format, number of styles, language, coverage, or date added. Turn every font in a set on or off from its sidebar menu. Browse by foundry or by classification, which Cicero reads from the fonts themselves and the shapes of their letters (with Apple Intelligence, it guesses the rest from their names, on your Mac), or make classifications of your own.
- **License status.** Mark each family Licensed, Licensed + Non-Commercial, Unlicensed, Partially Licensed, Public Domain, Open Source or Trial, or a status of your own, from its right-click menu (on its font page too), the Info panel, or by dropping it on a status in the sidebar. The status shows as a colored dot next to its name, and every status has its own sidebar item.
- **Coverage.** See which fonts have every character of Latin S–XL, Adobe Latin 1–5, Google Fonts’ Latin, Cyrillic and Greek sets, a Unicode block (Latin-1 Supplement, Latin Extended-A and -B, Greek, Cyrillic and more), or a coverage set you define yourself.
- **Character Toolbox** (⌥⌘T). Paste any text to find the fonts that have every character, or pick one of 780 languages to see which fonts support it.
- **Compare** (⌥⌘C). Fonts stacked on a shared baseline or drawn over each other, each in the style you pick, a family’s styles against each other too.
- **Problems.** Finds fonts installed twice, missing and damaged files, fonts on external disks, and duplicates, with a fix for each; none of them removes the only copy of a style. Fonts whose named styles share a PostScript name with another font are listed too, as a minor note.
- **Fonts in a document.** Choose File → Find Fonts in Document, or drop a PDF, IDML, InDesign or Illustrator file on the window, to see which fonts it uses: on, in your library but off, or missing. Turn them all on at once, make a set named after the document, or find a missing font's file on your Mac with Spotlight.
- **Add fonts.** Open font files from the Finder (Open With → Cicero), drop files or folders on the window, or choose File → Add Fonts (⌘O). Single files are listed where they are, under Added Fonts, without being activated, and read again when they change; when you activate fonts by copying or moving, they’re installed into your Fonts folder instead.
- **Watched folders.** Fonts in your folders are listed without being activated. The fonts installed for Adobe apps, where type designers put fonts to test them (Adobe’s Fonts folder, and an app’s own like InDesign’s), are listed together under Testing and tagged Testing (a switch in Settings → General hides them). Adobe Fonts from Creative Cloud are listed under Adobe Fonts and tagged Adobe Fonts, with Manage in Creative Cloud on their font page (another switch hides them). They show as active in those apps instead of not activated, and so can a folder of your own that an app loads; their switch turns them on in every app, using the file where it is, or off everywhere.
- **System Fonts.** The fonts that ship with macOS have their own item, and you can keep them out of your other lists with *Show system fonts* in Settings → General.
- **Application sets.** Give a set one or more apps, and Cicero activates its fonts while one of them is open and deactivates them when it quits. Fonts you turned on yourself stay on. Cicero has to be open for this, so it can open when you log in.
- **Temporary activation.** Turn a font on just until Cicero quits, from the Fonts menu (Activate Temporarily, ⌥⌘↩), a font’s right-click menu, or a single style. Nothing is copied, and Cicero turns the font off again on its way out.
- **Deactivating never loses a font.** A file in your Fonts folder goes to the Trash only when Cicero installed it as a copy and the original is still there, in your library. Any other file there moves to Cicero’s Deactivated folder, which stays in your library, and Cicero asks first when it didn’t install the file. Fonts used where they are just turn off.
- **Font cache tools.** Clear the macOS font caches for your account or for all users, plus the caches Adobe apps and Microsoft Office keep (they go to the Trash and are rebuilt on next launch; a restart may be needed), and rebuild Cicero’s font list, from the Fonts menu or Settings → General.
- **Move to Trash** removes a font’s files, including copies in other folders; fonts that come with macOS or an app are never touched.
- **Reveal in Finder** from a font’s right-click menu, a style, ⇧⌘R, or the info panel.
- **Export fonts.** Copy the files of the selected families, or of everything in the list when none are selected, into a folder or a ZIP archive with a subfolder per family, for sending them to someone or a printer (File → Export Fonts, ⇧⌘E). Sets, smart sets, folders, foundries, classifications and character sets also have Export Fonts in their sidebar menu. Fonts that come with macOS or an app are left out.
- **Back up and restore.** Save your sets, smart sets, license statuses, coverage sets, folders, added fonts, foundry names and sidebar, the fonts Cicero turned on, and its settings for activation, system fonts, fonts from Creative Cloud and fonts installed for Adobe apps, with your font files if you like, as one `.cicerobackup` file, and restore it on this Mac or another (File → Back Up Library and Restore Library). Appearance and preview settings stay with each Mac. Each font goes back where it was unless a file is already there; nothing is ever written over.
- **Updates.** Cicero checks GitHub for new versions and offers to install them. Check now with Cicero → Check for Updates, or turn off *Check for updates automatically* in Settings → General.
- **Moves itself to Applications.** Opened from the disk image or your Downloads folder, Cicero offers to move itself to the Applications folder, where application sets, opening at login and updates work.
- **Help.** A [user guide](help/README.md), opened from Help → Cicero Help, with Release Notes and Report an Issue next to it in the Help menu.

## Privacy

Cicero has no accounts and no ads, and nothing about you or your fonts leaves your Mac: everything it knows about your fonts stays in local files. It goes online for two things, and you can turn off either in Settings → General:

- **Usage statistics.** Each time Cicero opens, it sends [TelemetryDeck](https://telemetrydeck.com) its version, the macOS version and a hashed random number that stands for your Mac, to count how many people use Cicero; the first time, it also says your Mac is new. That’s all it sends; the code is in [UsageStatistics.swift](Sources/Cicero/App/UsageStatistics.swift). Turn it off with Share usage statistics.
- **Updates.** Once a day, Cicero checks GitHub for a new version. Turn it off with Check for updates automatically.

Classifications Apple Intelligence guesses are worked out on your Mac too. The Help menu opens web pages in your browser.

## Credits

- Language data: [Hyperglot](https://github.com/rosettatype/hyperglot) by Rosetta, Apache License 2.0.
- Character sets: [Latin S–XL](https://github.com/koeberlin/Latin-Character-Sets) by Christoph Koeberlin (MIT), [Adobe Latin](https://github.com/adobe-type-tools/adobe-latin-charsets) by Adobe (MIT), the [Google Fonts glyph sets](https://github.com/googlefonts/glyphsets) (Apache License 2.0), and Unicode block data from the [Unicode Character Database](https://www.unicode.org/ucd/) (Unicode License V3).
- Updates: [Sparkle](https://sparkle-project.org).
- Design and functionality inspired by [Typecase](https://typecase.app/) and [Pica](https://pica.joshpuckett.me/).

Cicero is released under the [MIT License](LICENSE). The bundled data keeps its own licenses, included in the app: Hyperglot’s in [Languages-LICENSE.txt](Resources/Languages-LICENSE.txt), and the character set sources’ (MIT, Apache License 2.0 and Unicode License V3) in [CharacterSets-LICENSES.txt](Resources/CharacterSets-LICENSES.txt). Sparkle comes with its own license.
