# Cicero

**[Download the latest version](https://github.com/opr-inzn/cicero/releases/latest/download/Cicero.dmg)** · [All versions and release notes](https://github.com/opr-inzn/cicero/releases) · Requires macOS 26 on Apple silicon.

A font manager for macOS 26. Browse every font on your Mac and in your font folders, try them out, and turn them on only when you need them.

- **Three ways to browse.** A sortable list with an on/off switch for each family, a preview in the font itself, and columns you can show or hide (classification, foundry, Latin S–XL and Adobe Latin coverage, date added, format). A grid of tiles. Or full-width specimens with every style set in itself.
- **Font pages** (double-click, ↩ or ⌘↓). A large text you can type into, a table of styles you can switch on one by one when a family has more than one, and a searchable glyph map.
- **Info and Features.** The info panel shows a font's details, the languages it supports, its character sets and the Unicode blocks it covers; the Features tab turns OpenType features on for that family wherever it's previewed.
- **Preview Options.** Sample text, size, weight and letter spacing, shared by every view.
- **Light or dark.** Follow macOS, or pick Light or Dark in Settings → General.
- **Customizable sidebar.** Click **Edit** next to Fonts and every item and group gets a checkbox; uncheck what you don't want and click **Done**. The same list is in **Settings → Sidebar**, and right-clicking a row offers *Hide from Sidebar*.
- **Sets and smart sets.** Group fonts by hand, or with rules that keep a set current: name, foundry, classification, folder, status, kind, format, number of styles, language, character set, or date added. Browse by foundry or by classification, which Cicero reads from the fonts themselves.
- **Character sets.** See which fonts have every character of Latin S–XL, Adobe Latin 1–5, Google Fonts' Latin, Cyrillic and Greek sets, a Unicode block (Latin-1 Supplement, Latin Extended-A and -B, Greek, Cyrillic and more), or a set you define yourself.
- **Character Toolbox** (⌥⌘T). Paste any text to find the fonts that have every character, or pick one of 780 languages to see which fonts support it.
- **Compare** (⌥⌘C). Fonts stacked on a shared baseline or drawn over each other.
- **Problems.** Finds fonts installed twice, missing and damaged files, fonts on external disks, and duplicates, with a fix for each. Fonts whose named styles share a PostScript name with another font are listed too, as a minor note.
- **Watched folders.** Fonts in your folders are listed without being installed. The fonts installed for Adobe apps, in Adobe's Fonts folder and in an app's own like InDesign's, are listed together under Adobe Apps (a switch in Settings → Folders hides them). They show as active in those apps instead of not activated, and so can a folder of your own that an app loads; turning one of their fonts on makes it available in every app, using the file where it is.
- **System Fonts.** The fonts that ship with macOS have their own item, and you can keep them out of your other lists in Settings → General or by right-clicking System Fonts in the sidebar.
- **Application sets.** Give a set one or more apps, and Cicero activates its fonts while one of them is open and deactivates them when it quits. Fonts you turned on yourself stay on. Cicero has to be open for this, so it can open when you log in.
- **Temporary activation.** Turn a font on just until Cicero quits, or until you log out, from the Fonts menu (⌥⌘↩), a font's right-click menu, or a single style. Nothing is copied, and Cicero turns the font off again on its way out.
- **Font cache tools.** Clear the macOS font caches for your account or for all users, plus the caches Adobe apps and Microsoft Office keep (they go to the Trash and are rebuilt on next launch), and rebuild Cicero's font list, from the Fonts menu or Settings → General.
- **Move to Trash** removes a font's files, including copies in other folders; fonts that come with macOS or an app are never touched.
- **Reveal in Finder** from a font's right-click menu, a style, ⇧⌘R, or the info panel.

## Privacy

Cicero doesn't collect any data and never connects to the internet. Everything it knows about your fonts stays in local files on your Mac.

## Credits

- Language data: [Hyperglot](https://github.com/rosettatype/hyperglot) by Rosetta, Apache License 2.0.
- Character sets: [Latin S–XL](https://github.com/koeberlin/Latin-Character-Sets) by Christoph Koeberlin (MIT), [Adobe Latin](https://github.com/adobe-type-tools/adobe-latin-charsets) by Adobe (MIT), the [Google Fonts glyph sets](https://github.com/googlefonts/glyphsets) (Apache License 2.0), and Unicode block data from the [Unicode Character Database](https://www.unicode.org/ucd/) (Unicode License V3).
