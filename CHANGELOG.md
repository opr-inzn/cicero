# Changelog

Each version’s notes here become its release notes on the [releases page](https://github.com/opr-inzn/cicero/releases).

## 1.6

- Coming from FontExplorer X? Choose **File → Import from FontExplorer X** to bring over its Font Library, sets (named after the folders they were in, like “Clients / Acme”), application sets with their apps, smart sets, labels as tags in their colors, classifications, ratings and how often each family was turned on, and to turn on again the fonts that were on. Cicero finds FontExplorer X’s library on your Mac by itself, or opens a backup of it (`.fexconfig` or `.fexbackup`, from **File → Local Backup**), also when you drop one on the window; a `.fexbackup`’s fonts go back where the Font Library was. A sheet shows what it found, to pick what comes over, and what stays behind, like smart sets with rules Cicero doesn’t have. FontExplorer X’s database is read from a copy, so it can stay open, and nothing of it changes.
- **File → Import from Font Book** brings Font Book’s collections over as sets, with their families and styles; or collection files from another Mac. Font Book’s own collections, like Fun and Web, start unchecked.
- Importing only adds: sets with the names of ones you have get the fonts they don’t have yet, so importing again changes nothing, and your setup is saved first, in Backups.
- Right-click a family and choose **Show Similar Fonts** to see the 30 families in your library that look most like it, the closest first, in place of the sidebar item’s; **Done** goes back. A font page shows the six closest under **Similar**. Cicero measures the letters of each family on your Mac, the first time in a few seconds for a thousand families: how tall the lowercase is, how heavy and how contrasted the strokes are and at what angle, how wide, spaced, slanted and open the letters are, the serifs, the o’s roundness, and the a’s and g’s stories.
- Cicero guesses the classification of fonts whose files don’t say from the shapes of their letters, on your Mac, so scripts, display and decorative fonts, italics and variable fonts that stayed Unclassified go where they belong. A guess from the name by Apple Intelligence still comes first, when it has one, and the Info panel says which it is. The first time Cicero opens, it asks whether to guess; **Guess classifications** in **Settings → General** turns it on and off.
- Fonts with “Stencil”, “Inline”, “Outline”, “Fraktur” or “Blackletter” in their names are Ornamental.
- A family whose regular weight comes in two widths, like Futura’s Medium and Condensed Medium, is previewed in the normal width.
- Give a family one to five stars from its right-click menu (on its font page too) or the Info panel, and see them in the list’s **Rating** column (right-click the column headers to show it).
- Smart sets have new rules: **Designer**, **Rating**, **OpenType Feature** (like Small Capitals, Old-Style Figures or Stylistic Sets), **Embedding** (Installable, Editable, Preview & Print or Restricted), **Times Activated** and **Last Activated**. From now on, Cicero counts each time a family comes on, whether you, an application set or another app turns it on.
- The Info panel shows what a font’s license lets a document do with it, as **Embedding**.
- After the update, Cicero reads your font files again once, for the OpenType features and embedding the new rules use.
- On a font page, clicking a glyph shows its HTML entities (like `&eacute;` and `&#xE9;`) and how to type it with your keyboard layout (like ⌥E, then E), next to its Unicode code, with **Copy Character** to put it on the clipboard. Right-click a glyph for **Copy Character**, **Copy Unicode** and **Copy HTML Entity**, or a ligature for **Copy Characters** and **Copy Unicode**.
- When a font file you add has fonts your library has already, from another file, like a newer version of a font you installed, Cicero asks what to do with each family: **Skip It**, **Add as Another Copy**, or **Use the Added One**, which turns the library’s copy off the way deactivating does, so no font is lost, and the added one on. The sheet shows both versions, where your copy is and whether it’s on, and whether the added one is newer, older, the same version or the same file; each family starts at using the added one when it’s newer. To stop being asked, choose **Add it as another copy**, **Skip it**, **Use the added one** or **Keep the newer version** next to **When an added font is already in your library** in Settings → General.
- Tags are tags again, rather than license statuses: a family can have as many as you like. They’re under **Tags** in the sidebar, with the tag symbol, rather than **License**. Choosing a tag in a family’s **Tags** menu, or dropping the family on it, gives it that tag along with the ones it has; choosing it again takes it off, and **Remove All Tags** takes them all off. Cicero still comes with Licensed, Unlicensed and the others, given to no family, to rename, delete or keep as you like.
- Turning off a font you put in your Fonts folder yourself no longer asks first. It moves to Cicero’s Deactivated folder straight away, as it did after the question, so it stays in your library and comes back when you turn it on.
- Messages at the bottom of the window name the fonts: “Inter installed” rather than “Installed”, and “Inter Bold activated”, “Inter and Roboto deactivated” or, for more, “12 families activated” rather than “Activated 8 files”.
- Fonts in a folder that a symlink leads to, like a fonts folder on another disk linked into your home folder, turn on and show as active. Before, Cicero could say it couldn’t activate them, or list them twice. A folder you add that is a symlink itself shows its fonts too.
- When the disk or server with an **Active** folder is connected again, its fonts are as you left them: those you turned off stay off. Before, they all came back on.
- A font you added whose file goes away for a while, as when you rename its folder and back or sign out of a cloud service, is back in your library when the file is, within 30 days. Before, Cicero forgot it at once.
- Moving fonts into your Fonts folder leaves the folder they were in, even when it’s left empty. Before, an empty folder went to the Trash.
- A smart set rule a later version of Cicero saved, which this one doesn’t know, is left out, rather than your sets, folders and tags all starting over. A library file Cicero can’t read is never written over, also when one was kept aside before.
- A scan of every font, as after an update that reads them all again, finishes while fonts keep changing, rather than starting over each time; fonts changed meanwhile are looked at once it’s done.
- A font you put in a watched folder no longer shows and then disappears again when two scans overlap.
- A server that’s slow, or has stopped answering, no longer holds up Cicero: fonts on it are read in the background, and finding out whether a folder’s disk is connected no longer waits for it.
- If macOS takes very long to turn fonts on, those it turned on count as activated, and the rest are kept off, rather than all of them counting as failed.
- A backup, restore or clearing of font caches no longer stalls when the tool doing it reports many problems.

## 1.5.2

- Cicero has a new icon: C, 1 and 6 from AM Gaonkar Display Medium, cut into the faces of its cube.
- A font you put in a folder Cicero watches, or in the Fonts folder in your Library, shows almost at once, rather than after two or three seconds, also when your Mac is busy. One put in a Fonts folder shows as active straight away, as macOS turns it on a moment later.

## 1.5.1

- **Show fonts from Creative Cloud**, in Settings → General, keeps Adobe Fonts out of your lists, like **Show system fonts** for the fonts that come with macOS. With it off, they’re left out of every list, smart sets and the Character Toolbox, and **Adobe Fonts** leaves the sidebar. Families you also have yourself stay, as yours.
- **Type Designer Mode** comes after **Maintenance** in Settings → General.
- In Compare, the plus next to **Compare Another Style** is the color of the text, also when you hold the pointer over it. Before, it was gray.
- The About panel links to Cicero’s website.

## 1.5

- Tags are now license statuses, to keep track of what you may do with each family. Cicero comes with **Licensed**, **Licensed + Non-Commercial**, **Unlicensed**, **Partially Licensed**, **Public Domain**, **Open Source** and **Trial**, each with its color, and you can make your own. A family has one status at a time, shown as a colored dot next to its name; give it one from its right-click menu, the Info panel, or by dropping it on a status under **License** in the sidebar. Smart sets have a **License Status** rule.
- Your tags become license statuses, once, and families keep them. A family that had several tags keeps them all until you give it a status. The Red, Yellow and Green tags a library started with go if you never used them. A backup from before 1.5 gets the statuses as it’s restored.
- A set can have single styles of a family, like just the Regular and Bold: drag a style’s row from a font page onto the set, or right-click the style and choose **Add Style to Set**. Activating, deactivating and exporting the set, and an application set, then take only those styles.
- Folders in the sidebar can be renamed, Cicero’s own Testing, Adobe Fonts, Added Fonts and Deactivated too: right-click one and choose **Rename Folder**. The name shows in the sidebar, Settings, smart set rules and Problems; the folder on disk keeps its own, so apps still find it.
- A font page’s glyphs are grouped by kind, in the order a type designer would list them, rather than by Unicode block: **Uppercase** and **Lowercase** from A to Z, their accented letters with Æ, Þ, ß and the like, **Ligatures**, figures, **Currency**, **Mathematical Operators**, **Superscript**, **Subscript**, **Fractions**, **Numerators**, **Denominators**, **Ordinals**, **Punctuation and Symbols**, marks, **Case Sensitive Forms**, **Arrows**, and **Global** for other scripts.
- The glyphs a font’s features draw are in those groups too: tabular figures, superscripts, scientific inferiors, numerators, denominators, ordinals and case-sensitive forms. Click one to see which feature draws it.
- The glyphs come straight after a font page’s styles, with its ligatures in the Ligatures group, in cells the size of the characters’; hold the pointer over one to see what it stands for. Ligatures that are characters too, like ﬁ, are listed once, and the filter finds ligatures by their characters: “f” finds ff, fi and ffl.
- Accents that combine with the letter before them, like those in Combining Diacritical Marks, show on font pages, rather than leaving their cells empty.
- A font page’s group titles scroll with the glyphs, so glyphs no longer show between a title and the toolbar.
- On a font page, right-click the text, the header or a style for the family’s menu: add it to a set, give it a license status or change its classification.
- In Compare, each family can be in a style of your choosing: click the style next to its name. **Compare Another Style** adds the family again in another style, to set a family’s styles against each other.
- The sidebar’s top section is called **Library**. The selected item is in the accent color, and so is the item you drag fonts over. **View → Hide Sidebar** (⌃⌘S) hides it, and **Edit Sidebar** has moved from the View menu to the sidebar’s right-click menu, beside the **Edit** button.
- The toolbar’s pickers have an even inset and a glass lens on the chosen item, the Character Toolbox’s lists fade out under their bars, and cards you drag stay opaque.

## 1.4.9

- Adobe Fonts from Creative Cloud are told apart from the fonts you install to test in Adobe apps. They have a purple **Adobe Fonts** tag, and an **Adobe Fonts** item under **Folders** while Creative Cloud has fonts on your Mac.
- Cicero lists the Adobe Fonts an Adobe app turned on by itself, for instance for a document that uses them. They’re on in Adobe apps only, so they show as **Active in Adobe apps**, with their switch halfway.
- Creative Cloud turns Adobe Fonts on and off, so their switches don’t move. **Manage in Creative Cloud**, on the font page and in the right-click menu, opens the Creative Cloud app.
- The fonts you put in Adobe’s Fonts folders to test them, as [Glyphs explains](https://glyphsapp.com/learn/testing-your-fonts-in-adobe-apps), are tagged and listed as **Testing**, rather than Adobe and Adobe Apps.
- The switch for those test fonts, **Show test fonts installed for Adobe apps**, is under **Type Designer Mode** in Settings → General. It hides only your test fonts; Adobe Fonts are always listed.
- A copy from Adobe Fonts no longer counts as a spare of one of your own files. **Remove All Extra Copies** and **Remove Copy** in Problems always leave one of yours, because Creative Cloud takes its copy away when the font is turned off there. Before, they could keep Creative Cloud’s copy and move yours to the Trash.
- Menus have icons, as on macOS 26: the commands in the menu bar, the sidebar’s menus and the right-click menus of fonts and styles.
- With the Info panel open, the grid keeps its columns and the tiles get narrower, so its rows reach the panel. Before, the panel took columns away and could leave a gap beside it.
- On a font page, the glyph and ligature cells reach the right edge, rather than leaving a gap at the end of each row.
- In Settings → Sidebar, each coverage set has a row of its own, as tall as the other sections’ rows, under its group’s title, which opens and closes it.
- A family’s styles are listed from narrowest and lightest, by where each sits on the width and weight axes, a variable font’s named instances included.
- When you type to jump to a family, a space within the name counts as part of it, as in Times New Roman. A space with nothing after it still opens Quick Look.
- A font page no longer locks up at full CPU once you scroll to the end of a family with dozens of styles.
- Switching to specimens is up to a second faster, a first scan reads font files about twice as fast, and scrolling through specimens no longer waits on the disk for fonts not read since the Mac started.
- VoiceOver names each segment of the toolbar’s view and layout pickers, rather than all of them after the first.

## 1.4.8

- **Remove All Extra Copies**, at the top of Installed Twice in Problems, deals with every font there at once, after asking: it keeps the newest copy of each font and moves the others to the Trash. Of copies with the same version, it keeps one that comes with macOS or an app, then one in your own folders, then one installed for all users, before one in your Fonts folder. Duplicates has **Move All Extra Copies to Trash** too.
- Moving fonts to the Trash works when they’re in a folder only an administrator can change, like an Adobe Fonts folder an installer made: macOS asks for your password, as when you drag them to the Trash in the Finder. Before, Cicero said it couldn’t move them, for instance when moving the extra copies of a font to the Trash in Problems.

## 1.4.7

- Fonts that are on are called active, and those that are off inactive, as on font pages and in Settings → Folders: the sidebar’s **Active** and **Inactive** rather than Activated and Not Activated, “1,298 families · 716 active” under the title, **Active only** in the Character Toolbox, and **Inactive** for a style that’s off, in Quick Look, on font pages, in Problems and as a smart set’s Status.

## 1.4.6

- Font files you added that have since been deleted, or whose folder was moved or renamed, leave your library, rather than staying there unseen. Cicero no longer looks for them every time it opens, which could have macOS ask again about the folder they were in. Files on a disk that isn’t connected stay.
- When macOS asks whether Cicero may read your Documents, Desktop or Downloads folder, its message says why: to read fonts in your library that are kept there, like files you added from a download, and for **Find on This Mac**. Before, it only mentioned Find on This Mac.

## 1.4.5

- ⌫ turns the selected fonts off and ⌘⌫ moves them to the Trash, asking first, as in the Finder. Before, ⌘⌫ turned them off. While you type in a text field, both edit the text, and in the Compare window, the Character Toolbox and Settings they leave the main window’s fonts alone.
- ⇧-click keeps the fonts you ⌘-clicked before and adds the range from the last one you clicked, as in the Finder, rather than selecting only that range.
- The list’s column headers sit in one bar with the toolbar, so rows no longer show between the two as you scroll.
- Resizing a column in the list works: drag the edge between two headers and it follows the pointer, with the preview getting narrower or wider to make up the difference. Before, the column jumped to its narrowest.
- Latin S–XL, Adobe Latin and the GF sets are under **Coverage** in the column headers’ menu, with the other character sets.
- A **Year** column for the list, in the column headers’ menu: when a family came out, as near as its files say, from the earliest year in its copyright notice (2014 for “© 2014–2021”), else the year its files were made. Cicero reads your font files again once after updating to find it.
- Descenders and swashes are no longer cut off. About one font in ten draws below the depth it states, and every sample stopped there: in the list, the grid, specimens, Quick Look, the Compare window, the Character Toolbox and on font pages, where the text you type also lost the descenders of its last line, and with tight line spacing the parts of each line that reached past it. Glyphs may now run over the edge of a row or into the line next to them instead.
- A status tag like **Adobe** is never shortened next to a name about as wide as itself; the name would give way instead.
- Quick Look is smaller, 520 × 440 at first, and has a title bar and buttons the size of other windows’. It keeps a size only once you resize it.
- Quick Look, specimens and font pages say “1 Style” and “12 Styles”, as the grid does.
- A font page says how many of the family’s styles are active, partly active (on in Adobe apps only) and inactive, like “3 active · 2 partly active”, rather than “0 activated” for a family that’s on in Adobe apps.
- The Info panel no longer flashes as you go from one font to the next.
- When a message comes up at the bottom of the window, like after moving fonts to the Trash, the Info panel and the browser no longer slide into place with it, and font pages always appear at once.

## 1.4.4

- You can change the order of the fonts in the Compare window by dragging a row in Stacked, or a name below the fonts in Overlay, where the last one is drawn on top.
- Each font in the Compare window keeps its color when you move or remove the others.

## 1.4.3

- A folder can be **Active**: Cicero turns on every font in it, where it is, and fonts you put in it later go on by themselves. Choose it next to the folder in Settings → Folders or under **Fonts in This Folder** in its menu in the sidebar, which now offers **Inactive**, **Active**, **Active in Adobe apps** and **Active in Specific App**. Choosing Inactive again, or removing the folder, turns its fonts off.
- Settings → General is more compact: four groups instead of nine, with Appearance on its own, the settings for activation, opening at login, system fonts, Adobe fonts and classification under **Fonts**, **Library** with Rebuild, Back Up and Restore, and Clear for the font caches, under **Maintenance**, the switches for updates and usage statistics under **Updates**, and short explanations inside the rows that need them.
- Settings → Folders lists your folders in a card with **+** and **−** along its bottom, like the lists in System Settings, and you can select several to remove them together. **Show fonts installed for Adobe apps** is in Settings → General now. Folders always have the plain folder icon, whatever they’re set to.
- The window for an application set’s apps lists them in the same kind of card, with **+** and **−**, and you can select several to remove them together. **Open Cicero at login** is a checkbox next to **Done**.
- Settings → Sidebar says individual foundries rather than single ones, with a shorter note at the bottom.
- Fonts you add are described as listed without being activated, rather than without being installed.
- The **Delete** button in the coverage set editor is red, like **Clear** in Settings → General.
- Cicero asks before deleting a coverage set, from its editor, the sidebar or Settings → Coverage.
- Creating a coverage set or a smart set no longer flashes the editor’s Edit title, Delete button or Save button as the sheet closes.

## 1.4.2

- The coverage set editor explains that spaces and line breaks don’t count, so you can use them to lay out your characters.
- The characters a coverage set will check for appear under **Preview** in its editor, with their count next to the heading.

## 1.4.1

- **Use the files where they are** in Settings → General is now **Leave the files where they are**, and Cicero’s question when you turn fonts on offers **Leave Files Where They Are**.
- **Your Coverage Sets** come first in Settings → Coverage and scroll with the built-in sets. Each has an **Edit** button and a right-click menu, **+** next to the heading makes a new one, and the coverage set editor has a **Delete** button.
- Shorter explanations in Settings → General, Folders, Sidebar and Coverage.

## 1.4

- With **Copy into ~/Library/Fonts** chosen in Settings → General, font files you open in Cicero, drop on its window or choose with File → Add Fonts are copied into your Fonts folder and turned on, and show up in All Fonts, rather than being listed where they are under Added Fonts without being installed. Reveal in Finder shows the copy in your Fonts folder. Cicero then selects the first font it installed in the browser and scrolls to it.
- **Move into ~/Library/Fonts**, a new way to activate fonts in Settings → General: font files you open, drop or add are moved into your Fonts folder and turned on, and a folder they leave empty, like a font download’s folder, goes to the Trash. A folder with anything else in it stays, and fonts in your folders are still copied. With Ask each time, Cicero offers Move Into Fonts Folder for fonts you added one at a time.
- Fonts already under Added Fonts leave it once Cicero installs a copy of them, when you turn them on by copying or moving or open them again.
- Fonts you open from the Finder no longer open on their font page, whichever way you activate fonts: Cicero selects the first of them in the browser and scrolls to it, there and when you drop or add fonts.
- Turning off a copy Cicero installed sends it to the Trash only when its original is in your library too. Otherwise, as for a font installed by opening it, the copy moves to Cicero’s Deactivated folder, so the font stays in your library.
- Opening the Info panel no longer makes the grid’s tiles wider. They keep their width and place, and the panel takes a column away instead.
- Typing the start of a name in the list now shows the family it jumps to below the column headers, rather than under them.
- The messages at the bottom of the window no longer end with a full stop: “Activated 8 files” rather than “Activated 8 files.”

## 1.3.1

- Typing a letter in the font list, grid or specimens jumps straight to the first family starting with it, rather than scrolling there.
- You can type more than one letter, as in Finder: E goes to the first family starting with E, and Ed then to the first starting with Ed.

## 1.3

- Far more fonts get a classification. When a font doesn’t say what it is, Cicero looks at its letters: an I and an l with feet are serif, plain ones sans serif, and letters all as wide as each other monospaced. Letters that are none of these, like a script’s, say nothing. After that, Cicero reads the font’s PANOSE numbers, another way fonts can say what they are. In a library of 1,415 families, mostly from small foundries, Unclassified went from 934 families to 231.
- With Apple Intelligence on, Cicero guesses the classification of the fonts still left over from their names, on your Mac. Nothing is sent. The Info panel says when a classification is a guess. Turn it off in Settings → General → Guess classifications from names.
- Fonts with “Symbol”, “Dingbat” or “Emoji” in their name count as Symbol.
- Classifications you chose yourself stay as they are. To keep a family where Cicero put it, choose that classification from its right-click menu or in the Info panel: later versions of Cicero, or a new guess, won’t move it.
- Smart sets with a Classification rule may change as fonts move out of Unclassified.
- The first time it opens, Cicero reads every font file again, which takes a little longer in a large library.
- In the sidebar’s Edit mode, sections open and close as they do outside it, and stay as they were, so you can close Foundries to get to Coverage faster.
- Clicking Edit or Done in the sidebar no longer makes its rows run into each other for a moment.
- Each tile in the grid says, at its bottom right, what kind of files the family comes in: OTF, TTF or Variable, for example.
- The caption under a tile’s name counts just the weights, widths and styles: “8 Weights · 16 Styles” rather than “8 Weights · Italics”. Italics, optical sizes and a font’s own axes count as styles rather than being named.
- A font page opens with its ligatures and glyphs already there, rather than filling in a section at a time, and nothing on it moves as they appear. Cicero starts on them when you select a font, before you open it.
- Opening a font page no longer puts the cursor in the type tester’s size.
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
