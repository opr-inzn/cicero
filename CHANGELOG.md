# Changelog

Each version’s notes here become its release notes on the [releases page](https://github.com/opr-inzn/cicero/releases).

## Unreleased

- Each tile in the grid says, at its bottom right, what kind of files the family comes in: OTF, TTF, or Variable TTF, for example.

## 1.2.2

- Cicero also counts how many people start using it: the first time it sends the usage statistics from your Mac, which for anyone already using it is the first time they open this version, it adds a note that your Mac is new, with that day’s date. Nothing else is sent, and Share usage statistics still turns it all off. [Privacy](help/privacy.md#usage-statistics) has the details.

## 1.2.1

- Your fonts are there as soon as Cicero opens, as it last found them, rather than appearing a moment later. Anything that changed since follows right after.
- The app icon’s background is the same as on the icons of the apps that come with macOS: white in light mode rather than light grey, and dark grey in dark mode rather than nearly black.

## 1.2

- The sidebar’s folders, foundries and classifications are there as soon as Cicero opens, rather than appearing a moment later.

## 1.1.1

I haven’t tested this version on macOS 27 yet, so you may find UI bugs there. Please report them with Help → Report an Issue.

- Cicero counts how many people use it: each time it opens, it sends TelemetryDeck its version, the macOS version and a hashed random number for your Mac, and nothing about you or your fonts. Turn it off in Settings → General → Usage Statistics. [Privacy](help/privacy.md#usage-statistics) has the details.
- A new app icon: a glass cube with a C, an & and a g cut into its faces.
- New Tag lets you pick the tag’s color, or none, as well as its name. Leave the name empty to name the tag after its color.
- A new library starts with Red, Yellow and Green tags.
- For fonts in an Adobe app’s folder, the right-click menu says Activate Temporarily in All Apps, like Activate in All Apps beside it.
- A font page’s Activate and Deactivate buttons say the same as the font’s right-click menu: Activate in All Apps for fonts in an Adobe app’s folder, for example.
- The Info button in the toolbar is highlighted while the Info panel is open, like the chosen view beside it.
- Nothing lights up under the pointer any more: not the toolbar’s view picker and buttons, in every window, nor the tiles in the grid.
- The Info panel starts level with the first row of fonts in the grid and in specimens, rather than just below the toolbar, and sits as far from the grid as its tiles are from each other.
- The toolbar’s buttons sit closer together, as close as the Info button is to the search field.
- Specimens are set on light grey cards, like the tiles in the grid, so each family stands apart.
- Click between fonts, or below the last, to deselect them.
- Font pages keep the search field: type in it to go back to the fonts that match. They no longer show Preview Options, since they have their own size and alignment.
- Type a number for Size, Weight, Letter Spacing and Line Spacing in Preview Options, and for a font page’s Size, or press ↑ and ↓ to step them.
- Make classifications of your own, rename Cicero’s, and put families in another classification from their right-click menu, the Info panel, or by dragging them onto one in the sidebar.
- Character sets are called coverage, like their tab in Settings: the sidebar section, the Info panel row, the list’s column menu and the smart set rule (“Coverage includes Latin S”). Sets of your own are coverage sets.
- Menus and buttons no longer end in “…”, and progress messages don’t either.
- Clear Font Caches, and its row in Settings, say you may need to restart your Mac afterwards.
- The Show fonts installed for Adobe apps switch in Settings → Folders is as small as the other switches in Settings.
- Built for macOS 27: there, the Info panel’s corners follow the window’s, sliders are the system’s, tag colors still show in menus, and the Info panel’s Info and Features tabs look like tabs.

## 1.1

- Add font files without adding their folder: open them from the Finder (Open With → Cicero), drop them on the window, or choose File → Add Fonts… (⌘O). They’re listed where they are, under Added Fonts in the sidebar, without being installed, and read again when they change. Right-click to remove them from the library; the files stay. Dropping fonts while a set is shown adds them to the set, and dropping a folder adds the folder.
- Tags: label families with tags of your own, each with a Finder color, from their right-click menu, the Info panel, or by dropping them on a tag. Tags have their own sidebar section, show as colored dots next to family names, and work in smart set rules.
- Activate Set: right-click a set or smart set to turn every font in it on, temporarily on, or off.
- Font pages list the ligatures each style makes, grouped by feature (standard, discretionary, historical, contextual and required), each drawn from its glyph with the characters it stands for.
- Font pages align their text right, too, and Preview Options have Line Spacing, for font pages and Quick Look, and Alignment, for specimens and Quick Look. Spacing is now called Letter Spacing.
- The Info panel shows each font’s vendor ID, and search finds fonts by their designer and vendor ID as well. The first launch reads every font file again to learn them, so it takes a little longer.
- Fonts in a document: choose File → Find Fonts in Document…, or drop a PDF, IDML, InDesign or Illustrator file on the window, to see which fonts it uses, which of them are on, off or missing, and turn them on, make a set of them, or find a missing font’s file on your Mac with Spotlight.
- The fonts that come with macOS that CoreText doesn’t list, like Times, Courier, Iowan Old Style and Seravek, are in your library now, and fonts like them that Cicero turns on show as on.
- The Info panel stays open on font pages.
- Preview Options call the sample text Preview Text.
- Backups hold your tags and added fonts.
- Folders on a server or an external disk: while the disk isn’t connected, the folder has a question mark in the sidebar and says so, its fonts keep their tags and places in sets, Problems no longer lists them as missing, and they aren’t read again when it’s back.
- Folders in iCloud Drive, Dropbox or Google Drive say how many of their fonts are online only, and **Download** brings them down. A cloud folder macOS hasn’t let Cicero read says so, with a way to System Settings.
- **Use Copy From**: when a font is in more than one folder, like a copy from each client, right-click it to choose which folder’s copy is on. The others Cicero turned on go off.
- Duplicates in Problems only lists copies in the same place, like twice in one client’s folder, not one copy in each client’s.
- Character set groups in the sidebar have an icon, and titles as strong as the rows around them.
- Help → Privacy Policy opens Cicero’s privacy policy on its website.

## 1.0

First release.

- Browse your library as a sortable list with on/off switches, a grid, or full-width specimens.
- Quick Look: press Space, or choose Fonts → Quick Look (⌘Y), for a floating preview of the selected family. The arrow keys move the selection in the list, grid and specimens while it’s open, and ‹ › step through several selected families.
- Font pages with a large editable text, a table of styles you can switch on individually, and a searchable glyph map.
- An info panel with font details, supported languages, character sets and Unicode blocks, and a Features tab for OpenType features.
- Preview Options for sample text, size, weight and letter spacing.
- Choose a light or dark appearance, or follow macOS, in Settings → General.
- Customize the sidebar: click **Edit** next to Fonts, or use Settings → Sidebar, to show or hide any item, and drag items into the order you like within their section. Select several items in a section with ⌘- or ⇧-click to drag them together or see their fonts together. A click anywhere on a section’s title opens or closes it.
- Sets, smart sets with rules, foundries, and automatic classifications read from each font.
- Application sets: Cicero activates a set’s fonts while one of its apps is open, and can open at login so they always work.
- Character sets: Latin S–XL, Adobe Latin 1–5, Google Fonts sets, Unicode blocks, and your own; filter by them in the sidebar, and show any of them as a column in the list to sort by.
- Character Toolbox: find fonts that have every character of a text or support one of 780 languages.
- Compare fonts on a shared baseline or overlaid.
- A Problems view for fonts installed twice, missing, damaged and duplicate fonts, fonts used from external disks, and styles that share a PostScript name with another font.
- Watch folders of fonts without installing them. The fonts Adobe apps load from their own folders, InDesign’s included, are listed together as Adobe Apps, with a switch for them in Settings → Folders. Each can be on in Adobe apps only, on in every app, or off.
- System Fonts item, with an option to keep macOS fonts out of your other lists.
- Clear the macOS font caches, and the ones Adobe apps and Microsoft Office keep, and rebuild Cicero’s font list when fonts misbehave.
- Activate fonts by copying them to your Fonts folder or using them where they are. Deactivating never deletes your only copy: a file in your Fonts folder goes to the Trash only when it’s a copy Cicero installed and the original is still there; any other file there moves to Cicero’s Deactivated folder.
- Activate fonts temporarily, until Cicero quits, with nothing copied (Fonts → Activate Temporarily, ⌥⌘↩).
- Move fonts to the Trash, and reveal any font or style in Finder.
- Export the files of the selected families or the whole list (File → Export Fonts…, ⇧⌘E), or of a set, smart set, folder, foundry, classification or character set from its sidebar menu, into a folder or a ZIP archive.
- Back up your sets, smart sets, character sets, folders and sidebar, with your font files if you like, as one `.cicerobackup` file, and restore it on this Mac or another (File → Back Up Library… and Restore Library…, or Settings → General).
- Updates from GitHub: Cicero checks for new versions and offers to install them (Cicero → Check for Updates…). Automatic checks can be turned off in Settings → General → Updates.
- Opened from the disk image or your Downloads folder, Cicero offers to move itself to the Applications folder.
- A user guide, opened from Help → Cicero Help, with Release Notes and Report an Issue in the Help menu.
- No tracking and no analytics: nothing about you or your fonts leaves your Mac.
