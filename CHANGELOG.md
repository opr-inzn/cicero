# Changelog

Each version’s notes here become its release notes on the [releases page](https://github.com/opr-inzn/cicero/releases).

## Unreleased

- Quick Look no longer has a button to fill the screen. Resize it by its edges instead.

## 0.10.12

- **Glyphs** lists letters, accents, Greek, Cyrillic, punctuation and symbols alphabetically by glyph name, with Greek and Cyrillic capitals first, then lowercase, then punctuation and accents.
- **Variable** is a search filter: type **var** and choose it under **Filters** to list only variable fonts.
- A font page’s **Leading** is exact for fonts with their own line gap. Before, 100 % could be as loose as 120 %.
- A font page’s text sits in the middle between the controls and **Styles**, and its **Styles** always show the family’s name.
- Font pages no longer show **Similar**. Right-click a family and choose **Show Similar Fonts** to see them.
- **Inactive** with nothing in it says **Everything Is Active**.
- **Forget All** in Conflicts forgets every missing file at once.

## 0.10.11

- **Show Missing**, under **Coverage** in the Info panel, lists the characters a font still needs for the next Latin size. **Copy Characters** puts them on the clipboard.
- **Glyphs** groups **Small Caps**, **Localized Forms**, **Circled Figures** and Roman numerals on their own, and lists accents and small caps letter by letter.
- Font samples are full black (white in Dark Mode) in the browser, on font pages, in Compare, the **Character Toolbox** and Quick Look.
- Quick Look’s type grows and shrinks with its window as you resize it.
- Scrolling through a font page’s **Glyphs** is smooth again, even in fonts with thousands of glyphs.

## 0.10.10

- **Check Again** is gone from the Conflicts toolbar. The list updates by itself, and **Fonts → Rescan Library** (⌘R) is still there.
- Hiding or showing the sidebar no longer rearranges the grid. The tiles keep their number and height, grow wider or narrower, and every font in them grows or shrinks with them, as when you open the Info panel. **Size** in Preview Options shows the size they’re drawn at.
- The Info panel slides in and out like the sidebar, and the grid narrows and widens along with it. Before, it appeared and disappeared at once.
- Cicero’s Library is no longer listed under **Locations**. Its fonts are in **All Fonts**, like those in your Fonts folder.
- The Font Library is now called **Cicero’s Library**, in Preferences and everywhere else.
- The folder of Cicero’s Library is now `~/Cicero/Library`. Cicero moves it there from `~/Cicero/Font Library` as it opens, fonts and all, unless you put it somewhere else.

## 0.10.9

- Typing on a font page, and dragging its **Size**, **Tracking** and **Leading** sliders, no longer lags.
- In **Preview Options**, **Save as Preset** adds the preview text to **Presets**. **Remove Preset** takes it out again.

## 0.10.8

- Opening Cicero no longer shows **Finding fonts** while it checks your fonts against the ones it remembered. Your fonts are in the window from the start, and the check changes nothing there unless it finds fonts to read. The same goes for the checks when you come back to Cicero and when fonts change.
- When an update has Cicero read every font again, to learn something new from them, the capsule says **Updating font details** rather than **Identifying fonts**. Your fonts stay in the window meanwhile.
- If you quit Cicero while it reads fonts, it remembers the ones it has read, and the next time it opens it reads only the rest. Before, it started over.

## 0.10.7

- The Character Toolbox’s text field keeps the focus as you type. It lost it whenever the list of fonts came or went: with the first letter typed, the last one deleted, and each letter while no font had every character.
- Filters in the search field, like **Italic** or **Bold**, are tinted with your highlight color, the one selected text has, rather than grey. Choose it in System Settings → Appearance.
- The search field stays dark when you switch Cicero to Dark in **Preferences → General**. It turned light again half a second later and stayed light until the fonts scrolled.

## 0.10.6

- Grid tiles no longer say **1 Weight**. A family of one style says **1 Style**, and one with a regular and an italic **2 Styles**, rather than **1 Weight · 2 Styles**.
- In the sheet that **File → Import from FontExplorer X** shows, the line under **Font Library** gives just where it is and, in brackets, how many font files it has. The line under **Fonts in other folders** names the folders those fonts are in.
- **Show fonts from Creative Cloud** in **Preferences → General** says that Creative Cloud activates and deactivates Adobe Fonts, and Cicero can’t manage them.

## 0.10.5

- Grid tiles keep their width and number in a row from one list to the next. Each list in the sidebar set its own width, so a list with a few more wide fonts than another, like **Active** next to **All Fonts**, could have one fewer tile in a row, each half as wide again and taller. The tiles are now as wide as the fonts in your whole library need, and searching doesn’t change them either.
- On the **Conflicts** page, **Shared Style Names** is open at first. It was closed.
- **File → Import from FontExplorer X** brings over the fonts in a `.fexbackup`. FontExplorer X writes their paths in its own way inside the backup, which Cicero didn’t read, so it said they weren’t on this Mac and put none of them in place.
- With FontExplorer X installed, its `.fexconfig` backups can be chosen in the import’s open panel. They were greyed out.
- Smart sets with a **Comment** rule come over, as smart folders with a **Note** rule, and so do ones asking whether a font is a system font. A smart set that can’t come over names each of its rules Cicero has no counterpart for, like **PostScript Name** or **Vendor**, rather than “a rule of another kind”.
- macOS’s own fonts that FontExplorer X lists as if they were yours, like PingFang UI, stay out: they were added to your library, counted among the fonts “not in your library” and, with the dates FontExplorer X gives them, put in **Last Activated** smart folders.
- Fonts Cicero can’t use, like PostScript Type 1 fonts, font suitcases and web fonts, are named in the import sheet, with how many there are, and stay behind with the sets that have only those. Before, the sheet counted them with the others, and their sets came over empty.
- A comment FontExplorer X keeps on a file and on its styles counts once in the import sheet.
- The import sheet says **Activate the fonts that were active**, as Cicero says activate elsewhere, rather than **Turn on the fonts that were on**, and when it’s done, how many styles it activated.
- Importing again says “Nothing new” when Cicero has everything already, rather than listing the folders and tags as if they had just been made. A set none of whose fonts are in your library is left out, and named, rather than made as an empty folder.
- In the sheet that **File → Import from FontExplorer X** and **Import from Font Book** show, the button that unchecks every item in a list now says **Deselect All**, as in the Finder and other Mac apps. It said **Select None**.
- When **Import from Font Book** meets a `.collection` file it can’t read, the sheet names it as a file Cicero can’t read. It called it a smart collection.

## 0.10.4

- A variable family without a weight axis shows at its font’s default, the origin its styles are drawn from, as other variable families do: in the list, grid, specimens and on its font page, where the Axes tab starts there too. Before, it showed its first style, which can be at the far end of every axis. Searching for **italic** shows its italic at the origin’s place on the other axes.
- The Axes tab lists a variable font’s axes in the order the font gives them, and so does the **Variable** tag when you hold the pointer over it. Before, Weight, Width, Italic, Slant and Optical Size came first.
- On a font page, **Styles** has a **Weight** column only when the styles aren’t all of one weight.

## 0.10.3

- Drag an item out of the sidebar to take it away, as in the Finder’s sidebar: once it’s outside, the pointer shows an ×. A location leaves your library, as with **Remove Location from Library**, a folder or tag is deleted, as with **Delete Folder** and **Delete Tag**, and any other item is hidden. **Undo** at the bottom of the window brings it back. Before, dragging an item out of the sidebar made Cicero quit unexpectedly.
- An item you drag in the sidebar looks as it does in the Finder, its symbol in the same grey as its name. On macOS 26 the symbol was white.
- Items you drag to a new place in the sidebar land at once. Before, the items below them slid up into place afterwards, cut off at their edges.
- **All Fonts**, **Active** and **Inactive** can no longer be hidden from the sidebar: their checkboxes in **Edit** and **Preferences → Sidebar** stay on, and their menus have no **Hide from Sidebar**. One you had hidden is back.
- Right-clicking one of several items selected in the sidebar now acts on all of them. **Delete Folders**, **Delete Tags**, **Delete Classifications**, **Delete Coverage Sets**, **Remove Locations from Library**, **Hide from Sidebar**, **Export Fonts**, a tag’s **Color** and a folder’s **Activate** and **Deactivate** take every selected item. Before, only the item you right-clicked was deleted or removed. Renaming and editing are for one item at a time, so they’re left out then.
- On a font page, the **Size**, **Tracking** and **Leading** sliders take all the width beside the **Style** menu, and are as long as each other. Before, they stayed short, with empty space beside them. They stay beside the menu until they're at their narrowest, with symbols in place of their names when the names don't fit, as in a layout app's character panel, and only then go on a row of their own, which they fill to the right edge of the alignment buttons above.
- **Preview Options** no longer have **Weight**. Previews show each family in its regular style, or the style you search for, like **bold** or **light**, which is how to see other weights now. A weight you had set is forgotten.
- The Preferences window is a little wider, and in **Preferences → General** the menus for **Activate fonts by** and **When an added font is already in your library** are the same width.

## 0.10.2

- **Preview Options** no longer have **Tracking** or **Alignment**. The list, grid, specimens, Quick Look and Compare show every font with its own spacing, lined up on the left. Font pages have **Tracking** now, next to **Size** and **Leading**, starting from what you had set in Preview Options.
- On a font page, the **Size**, **Tracking** and **Leading** values sit right after their sliders, as close as the labels before them.
- When a font page is too narrow for **Size**, **Tracking** and **Leading** beside the **Style** menu, they go on a row of their own at the left, under the menu. Before, they were at the right.
- In the grid, every font is at the size you chose, also monospaced and other wide fonts: the tiles are as wide as the families listed need. Only the widest few are drawn a little smaller, and they grow and shrink with the rest as you change the size. Before, fonts wider than the Mac’s own stopped growing while the rest went on, until the tiles got fewer and bigger. With the Info panel open, every sample is a little smaller, all alike, rather than wide fonts being squeezed to the width of the rest, and **Size** in Preview Options shows the size they’re drawn at.
- The fonts Adobe apps load from their own folders, where type designers put fonts to test them, are now called **Proofing**, in the sidebar and on their red tag. **Testing** read like trial fonts. The switch in **Preferences → General** is now **Show fonts installed for proofing in Adobe apps**. A name you gave the item yourself stays.

## 0.10.1

- In the grid, tiles are taller when they’re wide, two or three in a row, so they don’t look flat. Narrow tiles keep their height, and opening the Info panel doesn’t make tiles lower.

## 0.10.0

- In the sidebar, **Folders** is now called **Locations**, for the places on your Mac Cicero lists fonts from, and sets are now folders: **Sets** is called **Folders**, with a folder icon, smart sets are smart folders and application sets app folders. The menus say so too, like **File → New Folder** (⇧⌘N), **New Smart Folder**, **New App Folder** and **Add Location** (⇧⌘O), **Add to Folder** in a family’s menu, and **Preferences → Locations**. In a smart folder’s rules, **Set** is now **Folder** and **Folder** is **Location**.
- Search for a style, like **italic**, **bold** or **condensed**, and the previews show each family in that style, or the nearest one it has. Before, they showed the regular style. **bold italic** shows the bold italics, and a font page shows the style too while its **Style** is **Automatic**.
- The search field has filters. Type **ital**, **bold**, **cond** or **fig**, say, and choose **Italic**, a weight from **Thin** to **Black**, **Condensed** or **Extended**, **Tabular Figures** or **Old-Style Figures** from the suggestions. Each one becomes a token in the field, and the families shown have all of them: with **Italic** and **Bold**, a bold italic. The previews show that style, and the figures you asked for. To know which figures your fonts have, Cicero reads them again once after the update; the window shows your fonts meanwhile.
- The sidebar has **Recents**, under **Inactive**: the families with a font that arrived on your Mac in the last week, however it came, the latest first. Fonts you add together stay together, in alphabetical order, so the ones you just added are at the top. Fonts that come with macOS or an app don’t count.
- While fonts are on until Cicero quits, the sidebar has **Temporary**, under **Inactive**, with the families they’re in. Right-click it to **Activate Permanently** or **Deactivate** them all at once. It goes away when none are on any more.
- **Problems** in the sidebar is now called **Conflicts**.
- The Info panel appears and goes at once, along with the room the fonts make for it. It slid in and out, which looked as if the window's edge cut it off.
- In the grid, tiles fit the type: low tiles for small type, up to five in a row, and fewer, bigger ones as the type grows, down to one in a row, as wide as your preview text needs. The type is always the size you chose, and however many tiles are in a row, they fill the window’s width. Tiles have less room around their contents.
- **Size** in Preview Options goes up to 200 pt instead of 160.
- Turning a font off and on again keeps its **Date Added**. Before, Cicero moved the file to its Deactivated folder and back, which gave it the date of the move.
- Cicero’s icon has new letters, C, 1 and 6 from Mischief, the typeface of Cicero’s website, on a bigger, brighter cube without a shadow, whose faces meet without light lines between them and whose letters stay sharp at small sizes, as in the Dock.
- Cicero has an icon in the menu bar. Click it to open Cicero. Right-click it, or click it with two fingers, for a menu with the fonts that are on for open apps and until Cicero quits, your folders to turn on and off, **Add Fonts**, **Find Fonts in Current Document** (the one open in the app you’re in, like a PDF in Preview or Acrobat, or a file in InDesign, Illustrator or Photoshop), **Preferences** and **Quit Cicero**. Drop font files on it to add them, or a document to see the fonts it uses. Turn it off with **Show Cicero in the menu bar** in **Preferences → General**.
- Right-click Cicero’s icon in the Dock for its open windows, as other apps list theirs, and **Add Fonts**, as in the File menu. The **Window** menu lists the open windows too, and calls the main window **Library**. Add Fonts opens Cicero’s window too, so you see the fonts you add.
- With the icon in the menu bar, **Show Cicero in the Dock** can be off: Cicero is then in the Dock only while one of its windows is open, and closing the last one takes you back to the app you were in.
- App folders and the fonts Adobe documents use start working as Cicero opens, also when it opens without its window. Before, they waited for the window.
- **Settings…** in the Cicero menu is called **Preferences** (⌘,), and messages that point to it say **Preferences → General**.
- **Export Font List** is gone, from the File menu and the sidebar’s menus.
- The **Fonts in Document** sheet has **Show in Library**, which shows the document’s fonts that are in your library in the main window, each set in itself, as **Show Similar Fonts** shows its list. **Done** in the bar above them takes you back.
- The **Fonts in Document** sheet counts a document’s fonts as active and inactive, as the rest of Cicero does, rather than on and off: “12 fonts · 8 active · 2 inactive · 2 missing”.
- In a smart folder’s **Kind** rule, the kinds are in alphabetical order: **Italic**, **Monospaced**, **Variable**.
- **Keep installed fonts in Cicero’s Font Library** in **Preferences → General** is now called **Install fonts into Cicero’s Font Library**, and says more plainly what it does: Cicero keeps the fonts it installs in a folder of its own instead of putting them into ~/Library/Fonts.

## 0.9.4

- The Compare window is in the **Window** menu, and opens with nothing selected, from there or from **Fonts → Compare**. Click **+** in its toolbar to add families from anywhere in your library: type a name and click one, or press Return. Families already there have a checkmark; click one again to take it out.
- With one family selected, **Fonts → Compare** adds it to the fonts already in the Compare window, so families far apart in your library can go there one by one. A family’s menu says **Add to Compare** for it. With several, Compare starts over with them, as before.
- The Compare window has a size of its own, from 24 to 720 pt, set with **Size** in its **Preview Options**. **View → Zoom In** and **Zoom Out** (⌘+ and ⌘−, or ⌘= on a US keyboard) make the fonts bigger and smaller. Changing it there leaves the main window’s previews as they are, and the size in the main window’s Preview Options no longer changes Compare.
- The Compare window’s title is just **Compare**, without a count of its families, and there’s no line under its toolbar when it’s empty. **Overlay** no longer draws a grey line along the baseline.
- In the Compare window’s **Stacked** layout, a font’s row stays where it is when you add a font whose letters reach further above or below. Each row is now as tall as its own font needs; before, every row grew to fit the tallest.
- In Preview Options, **Size** starts at 24 pt rather than 8, and a smaller size goes up to 24.
- In specimens, a family’s style names sit on one baseline. A style whose letters reach higher or lower than the others’, like a bold or condensed one, sat a little lower or higher.
- A font page for a family from Adobe Fonts has **Manage in Adobe Fonts**, which opens the family’s own page on the Adobe Fonts website, where you turn it on and off. Its right-click menu has it too. Before, **Manage in Creative Cloud** opened the Creative Cloud app, where you had to look for the family. Cicero finds the page in the list Creative Cloud keeps of your fonts, and opens the Creative Cloud app as before when it can’t.
- In **Problems**, **Installed Twice** has **Remove in Adobe Fonts…** for a copy from Adobe Fonts, which Cicero can’t turn off. It opens the family’s page on the Adobe Fonts website, so you can remove it there and keep your own copy. Creative Cloud then takes its copy away.
- Smart sets have a **Has Note** rule, **Yes** for every family with a note or **No** for every family without one. Before, you left the text of a **Note** rule empty.
- New smart set rules no longer offer **Times Activated** and **Last Activated**. Smart sets that have them keep them.
- In a smart set’s rules, numbers go in a box without arrows, and **Number of Styles** no longer says “styles” after its number. Text goes in a box too.
- A smart set’s **Kind** rule says **Italic** in place of **Has Italics**.
- A smart set’s **Rating** rule lists five stars first, after **No Rating**, as the **Rating** menu of a family does.
- A smart set’s **Tag** rule shows each tag with its color, as the **Tags** menu of a family does.
- A smart set’s **Status** rule says **Active in Adobe Apps Only** in place of **Active in Apps Only**, and only while **Show test fonts installed for Adobe apps** is on.

## 0.9.3

- A font page’s text and name, and the Compare window, are set with the font’s kerning. With **Tracking** at 0, they were set without it, so pairs like V and a stood apart. Tracking is added to the kerning, as in the grid, the list and specimens.
- In Preview Options, **Letter Spacing** is now called **Tracking**, as in layout apps.
- A font page’s text no longer stays empty: delete it all and click somewhere else, and “Sphinx of black quartz, judge my vow.” is back, or text in the font’s own script for a font without Latin letters. A page that opens with the text left empty shows it too.
- The Info panel’s **Features** no longer lists **Text Spacing** with **Default** and **No Kerning**, as fonts are made to be kerned. Japanese, Chinese and Korean fonts still have **Text Spacing**, for their widths, like **Half Width**.

## 0.9.2

- In **Preview Options**, the preview text field spans the whole width, with “Preview Text” in it while it’s empty, in place of a label beside it. **Presets** no longer lists **Font Name**, as clearing the field shows each family’s name, nor the accented letters.
- A font page has room for a script font’s swashes, like Zapfino’s: the family’s name is set smaller where its swashes would run into the line under it, so the header is as tall as any other font’s, the text no longer leaves an empty gap below it, and swashes reaching past the ends of its lines show in the page’s margins rather than being cut off.
- A font page’s **Glyphs** lists each group’s characters in Unicode order, but **Superscript** and **Subscript**, which start with their figures from 0 to 9, then their signs and letters, and **Fractions**, which starts with the fraction slash, then goes from ⅒ to ⅞. Accented letters were sorted by the letter they’re made from, so Æ came after every A with an accent, and Greek, figures, punctuation, currency and mathematical signs each had an order of their own.
- **Glyphs** gives each script its own group, named after it, like **Cyrillic**, **Hebrew** or **Arabic**, with its letters, figures, marks and punctuation, as **Greek** had one. They were in **Graphical**, which now keeps the glyphs no script has, like a foundry’s logos. A font without Latin letters, like an Arabic or a Syriac font, starts with its scripts, the one it has the most characters of first, then its ligatures. A glyph a font keeps in private use but names after a character, like the shifted tone marks and descenderless letters of Thai fonts, goes with that character, in **Thai**. A sign or mark several scripts share, like the danda or Arabic’s comma and vowel marks, goes with the script the font is for, so a Bengali font’s dandas are with **Bengali** and a Syriac font’s vowel marks with **Syriac**. Glyphs are grouped by Unicode 17, so recent characters, like the Saudi riyal sign, have their place too, and letters outside their script’s blocks, like halfwidth katakana or 々, are with their script.
- A font with none of the letters of the preview text, like an Arabic, Syriac or Thai font for Latin text, shows text in its own script: the names of the languages written in it, in their own letters, like العربية, in the grid, the list, specimens, Quick Look and its font page, where you can type over it. macOS used to set the text in another font, so the font’s weights and axes seemed to change in steps.
- A font page has a **Leading** slider next to **Size**, for the space between the text’s lines. It’s the one in Preview Options too, where **Line Spacing** is now called **Leading**, as in layout apps. Where the window is too narrow for both, they move to a row of their own.
- A family marked **Not Similar** leaves the list without the next one taking its place, so the list is that much shorter.
- A font page’s **Similar** always opens with the six closest, also after **Show All** on another page or when you come back to the same family. **Show All** used to stay on from one page to the next.
- Invisible characters a font has no glyph for, like the variation selectors of Japanese fonts, no longer show as empty cells in **Glyphs**.
- Marks that take no room of their own, like the shifted Thai tone marks fonts keep in private use, show in **Glyphs** and their popover. Their cells were empty.
- Cicero comes with four license tags: **Licensed**, **Unlicensed**, **Open Source** and **Trial**. **Licensed + Non-Commercial**, **Partially Licensed** and **Public Domain** go from your library, once, if you never gave them to a family or used them in a smart set and they still have their colors; the ones you used stay.

## 0.9.1

- The first time Cicero opens, the sidebar’s **Coverage** starts closed, like **Foundries**, so its many character sets don’t fill a new sidebar, and **Classifications** starts open. Click a section’s title to open or close it.
- Dragging one of several selected families onto a set, a tag, a foundry or a classification in the sidebar, or into the Compare window, takes all of them there, as their right-click menu acts on all of them. It used to take only the family you dragged. The same goes for families selected in the Character Toolbox.
- What you drag is a small label, with “Aa” in the family’s letters and its name, and how many families there are when you drag several, and it’s gone the moment you drop it, as in the Finder. It used to be the whole card, which slid off to one side after you dropped it. A style row from a font page is dragged the same way.
- Search finds what you type where a word begins: **am** finds American Typewriter, but no longer every family from a foundry with “am” inside its name, or every name with “am” in the middle of a word. When no word begins with what you type, it still looks inside the words of names, so **vetica** finds Helvetica.
- The search field suggests families as you type, up to eight whose names begin with what you’ve typed, or have a word that does, each with “Aa” in its own letters. Choose one to search for its whole name, with that family selected and in view.
- A family’s right-click menu no longer has **Copy Family Name**.
- The **Rating** menu starts with **No Rating**, then lists the stars from five down to one.
- Right-click a group under **Coverage**, like **Unicode Blocks**, and choose **Hide from Sidebar** to hide the whole group. It used to offer only **Edit Sidebar**.

## 0.9

- Cicero runs on macOS 15 Sequoia as well as macOS 26. On macOS 15 it looks like the other apps there, with the system’s toolbar controls and without Liquid Glass. Recognizing classifications from fonts’ names with Apple Intelligence needs macOS 26, so on macOS 15 Cicero recognizes them from the shapes of their letters only.
- Right-click a family and choose **Show Similar Fonts** to see the 12 families in your library that look most like it, the closest first, in place of the sidebar item’s; **Done** goes back. A font page shows the six closest under **Similar**, and **Show All** lists all 12. Cicero measures the letters of each family on your Mac, the first time in a few seconds for a thousand families: how tall the lowercase is, how heavy and how contrasted the strokes are and at what angle, how wide, spaced, slanted and open the letters are, the serifs, the o’s roundness, and the a’s and g’s stories, and looks at them with a model that has learned what letters of a kind look like. A text cut lists other text cuts before display ones, its own display cut among them, and a display cut the other way round. Copies of one design, like a trial, a variable font or a family for each weight, are listed once, the closest of them.
- A family that doesn’t look like the one it’s listed for can be marked **Not Similar**: hold the pointer over it under a font page’s **Similar**, or right-click it there or in **Show Similar Fonts**. It leaves the list, the next family takes its place, and **Undo** at the bottom of the window brings it back. Cicero reports it to its website, to improve similar fonts: the names of the families in that list and the numbers it measured from their letters, no font files. With **Share usage statistics** off, in **Settings → General**, it sends nothing, and the mark only changes your own lists.
- Cicero recognizes the classification of fonts whose files don’t say from the shapes of their letters, on your Mac, so scripts, display and decorative fonts, italics and variable fonts that stayed Unclassified go where they belong. Apple Intelligence’s classification from the name still comes first, when it has one, and the Info panel says which it is. The first time Cicero opens, it asks whether to classify your fonts automatically; **Classify fonts automatically** in **Settings → General** turns it on and off.
- Importing from FontExplorer X brings its classifications too, your own among them: a family goes in the classification most of its styles have, unless you’ve chosen one for it.
- Fonts with “Stencil”, “Inline”, “Outline”, “Fraktur” or “Blackletter” in their names are Ornamental.
- A family whose regular weight comes in two widths, like Futura’s Medium and Condensed Medium, is previewed in the normal width.
- Fonts no longer count as having characters they draw nothing for, like the empty glyphs a trial font often keeps for the characters it leaves out. Character sets, languages, the Character Toolbox and the Info panel’s **Coverage** count only the characters a font draws, so a trial font no longer passes for a font that supports a language it can’t set. A font page’s **Glyphs** leave those glyphs out too, where they used to show as empty cells. Cicero checks every font’s characters again once, the first time this version opens.
- A family you’ve rated shows its stars in the grid, at the right of its name, and in specimens, after its number of styles. They used to show only in the Info panel and the list’s **Rating** column. A family with a note has a small note symbol there too; hold the pointer over it to read the note.
- Search finds families by what they are, not only by their names: type **variable**, **mono**, **italic**, a classification like **serif**, **sans** or **script**, **display** or **text** for families made for large or small sizes, **condensed** or **extended**, a tag, or a kind of file, like **ttf**. Several words find the families that match each of them, so **variable sans** shows the variable sans serifs, and **inter variable** shows Inter if it’s variable. **mono** no longer shows every font from Monotype, only monospaced fonts and fonts with Mono in their names.
- Search looks in the names of a family’s styles too, like Condensed Bold, and in the name you gave a foundry.
- A family with a style of ornaments, like Hoefler Text, is previewed in its Regular and classified by its letters. Hoefler Text’s Ornaments style used to stand for the family, so its previews showed ornaments, it was classified Symbol, and its coverage and similar fonts were its ornaments’.
- **Settings → General** says that Microsoft Office can’t use fonts left where they are or kept in the Font Library. Office apps, like Word and PowerPoint, only use fonts copied into your Fonts folder, and only from the second time they open after a font went on. [Fonts in Microsoft Office](help/activating.md#fonts-in-microsoft-office) has the details.
- When you type to jump to a family, a space waits longer for the next letter of the name, as in Times New Roman, before it opens Quick Look. It used to open Quick Look a fifth of a second after the space, before many a next letter came. Where no family’s name goes on with a space, the space opens Quick Look at once.

## 0.8.2

- Cicero checks for updates each time it opens, as well as once a day while it stays open. It used to check only once a day, counted from its last check, so a new version could take up to a day to show up.
- Moving **Optical Size** in the Axes tab changes the text again once **Weight** has been moved as well. The letters could stay at the font’s default optical size, whatever the slider said.
- A variable font’s styles that have an optical size of their own, like Text or Display styles, are drawn at it in previews and on the font page. They were drawn at the font’s default optical size.
- The Axes tab lists **Weight**, **Width**, **Italic**, **Slant** and **Optical Size** first, in that order, then the font’s other axes, so they no longer move around from one family to the next. The **Variable** tag lists them the same way when you hold the pointer over it.

## 0.8.1

- Turning on a font Cicero had moved to its Deactivated folder moves its file back into your Fonts folder, also when Cicero copies fonts or uses them where they are. It used to copy the file there and keep it in the Deactivated folder as well, so the font still showed up there while it was on. Fonts left like that leave the Deactivated folder the next time Cicero opens.
- The Deactivated folder is no longer in the sidebar. Its fonts are off, so they’re under **Inactive**.
- Clicking a family’s switch in the grid, the list or specimens turns it on or off without selecting it.

## 0.8

- A font page’s **Glyphs** can give you a glyph’s shape, not only its character. **Copy as Vector**, in a glyph’s popover and its right-click menu, copies its outline in the style, weight and axes the page shows, to paste into a design app as a shape you can edit, or as SVG code. Drag a glyph out of the page to put it into a design app, or into the Finder as an SVG file. That works for alternates, the glyphs features draw and ligatures too, whose shapes **Copy Character** can’t take along.
- Copying from a glyph’s popover closes it and says what was copied at the bottom of the window, as turning fonts on does: **“g” copied to clipboard**. So do the copy commands in a glyph’s right-click menu. The popover’s buttons no longer darken when clicked.
- Quitting InDesign, Illustrator or Photoshop no longer opens it again, with **Activate the fonts documents use in Adobe apps** on. Cicero could still be asking the app for its documents’ fonts as it quit, and asking an app that has quit opened it.
- Fonts Cicero turned on for a document open in InDesign, Illustrator or Photoshop stay on when Cicero quits and opens again, as it does after an update, for as long as the app stays open. They used to go off until the app was next in front, and the app could then find its document’s fonts missing.
- With **Activate the fonts documents use in Adobe apps** on in Settings → General, Cicero notices the fonts of a document you open in InDesign, Illustrator or Photoshop sooner: it asks the app twice a second rather than every two seconds. The app can still take a few seconds to take up the fonts, and InDesign and Illustrator still show their Missing Fonts dialog as the document opens; the setting now says so.
- Importing a FontExplorer X database copied from another Mac without its Font Library says where Cicero looked for the folder, like “1,240 font files in ~/FontExplorer X/Font Library (not on this Mac)”, so you can put it there, or connect the disk it’s on, and import again. Those fonts used to be counted with any other font files that aren’t on this Mac.
- The **Variable** tag is green and the **App Set** tag graphite, so they no longer look like the blue **Temporary** tag, and both temporary tags have the symbol of the command that turns fonts on that way: an app for **App Set**, a clock for **Temporary**.
- A tag’s text and symbol sit in the middle of it. The text sat a little low, and some symbols a little high.
- In Settings → General, **Guess classifications from names** is off and greyed out while Apple Intelligence is off or still getting ready, and on a Mac that can’t have it. It used to show as on.
- A family’s note in the Info panel can have more than one line: Return starts a new one. It used to end the editing and select the whole note, so the next key typed over it.

## 0.7.3

- In Settings → General, **Show test fonts installed for Adobe apps** no longer has a **Glyphs** tag next to it. The fonts it shows are tagged **Testing**, and the link below it goes to Glyphs’ guide.

## 0.7.2

- In Settings → General, the **Glyphs** tag next to **Show test fonts installed for Adobe apps** is in Glyphs’ own colors, dark green on lime, rather than lime on dark green.

## 0.7.1

- A font page’s text no longer cuts off its last line at some sizes: the page makes room for the lines as they’re set, rather than as a copy of the text broke them.
- A family’s styles are listed lightest first, those of one weight along the designer’s own axes, then narrowest first, each followed by its italic: a family with Sans and Serif styles in three widths lists its Thin ones as Sans Compressed, Sans Condensed, Sans, then Serif Compressed and so on. Families with several widths used to list each width’s weights in turn.
- On a font page, **Styles** has a column after Weight for each other axis the styles sit apart on, like Width or one of the designer’s own, and room for names as long as Serif Compressed Medium Italic. Status is only as wide as its labels need, so the samples get the rest of the width.
- A variable family no longer lists a style its font doesn’t name. When none of the named ones sits at the font’s default, macOS adds the default as one more, which showed as a second Regular, next to the font’s own at a slightly different weight. It stays where no named style is at the default on every axis but weight, as the family’s previews show it there. After the update, Cicero reads your variable fonts again once.
- A font page’s **Glyphs** lists figures by kind, each on rows of its own: lining figures, then old-style ones, then their other alternates, like a slashed zero. **Tabular Figures** has its figures before the signs that go with them, like a tabular dollar, and now lists tabular old-style figures too, which a font draws with Tabular and Old-Style Figures on together.
- A font page’s **Glyphs** lists **Punctuation and Symbols** right after the figures, before **Currency**, and the signs that go with tabular figures in that order too: a tabular percent before a tabular dollar.
- **Dingbat Numerals** are called **Circled Figures**, and only figures are in them, like ① and ❶, or ⑴ and ⒈ in fonts that have them. Letters in circles, like the Ⓟ some fonts have for ℗, are with **Punctuation and Symbols** rather than in a group of their own.
- The ohm sign Ω is in **Punctuation and Symbols**, after ℮ with the kelvin and angstrom signs, rather than with other scripts’ letters; so are letter-like symbols such as ℓ, ℝ and ℵ.
- **Glyphs** has a **Greek** group, before the last one: capitals, then small letters, each followed by its accented forms, then Greek’s own accents and punctuation. Greek letters in a Latin font, like the Δ and Ω many have, were with other scripts.
- The last group of glyphs is called **Graphical** rather than **Global**: the logos, icons and other glyphs a font keeps in private use, and the letters of scripts other than Latin and Greek.
- **Diacritical Marks** and **Combining Marks** come last in **Glyphs**, after **Graphical**.
- Clicking a glyph no longer shows a keystroke for it: it was only right for the keyboard layout your Mac was set to, so the Unicode code and HTML entities are what’s left.
- In the sidebar, a section title’s **+** stays where it is when the pointer comes over the title and its chevron shows; it moved aside to make room. The chevron turns at once when the section opens or closes.

## 0.7

- The Info panel has an **Axes** tab for a variable family: a slider for each of its axes, like Weight, Width, Optical Size or the designer’s own, with its tag, to move the family’s previews along them, in the browser and on its font page, text and glyphs alike, or type a value. Axes the font hides, like parametric ones, come last, under **Hidden Axes**, which opens and closes. On a font page, **Axes**, after the alignment buttons, opens the tab, and once an axis has moved, the Style menu says **Custom**.
- Variable families stand out in the list, grid and specimens: a teal **Variable** tag next to the name (at the top of a tile), which lists the family’s axes when you hold the pointer over it. A tile’s caption names the kind of file, like TTF, as it does for other fonts.
- A variable family shows at its font’s default, the origin its other styles are drawn from, on every axis but weight, which follows the preview weight: SF Pro at its normal width, rather than Compressed, everywhere it’s previewed.
- Variable fonts are drawn at their own optical size, the font’s default or the named style’s, rather than one matched to the size of the text, so previews show the letters as they were drawn at the origin. Move Optical Size in the Axes tab to try another. After the update, Cicero reads your variable fonts again once.
- Turn on **Activate the fonts documents use in Adobe apps** in Settings → General, and when you open a document in InDesign, Illustrator or Photoshop, Cicero turns on the fonts from your library it uses that are off, and turns them off again when the app quits, like an application set. The first time, macOS asks whether Cicero may control the app.
- **File → Find Fonts in Document** reads Photoshop files (`.psd` and `.psb`) too: the fonts their text layers use.
- Settings → General sorts its switches into **Installation**, **Activation** and **Library**; **Show test fonts installed for Adobe apps** is under Library, next to the other fonts you can show or hide.
- The OpenType features you turn on in the Info panel change the text on the family’s font page, and nothing else: the list, grid and specimens, Quick Look, Compare and the page’s list of styles, now headed **Styles**, show each style as it is.
- A font page’s **Glyphs** lists the alternates the font’s features offer, like a stylistic set’s single-storey a, small capitals, old-style figures or character variants, each after the character it’s for, with a grey dot. Click one to see which feature offers it, by the name the font gives it; type a feature’s name or tag, like `ss01`, into the filter to see its alternates.
- A font page’s glyphs and ligatures are those of the style its text is set in: choose another in the **Style** menu, or move its axes, and they follow.
- On a font page, ligatures and glyphs like tabular figures are as dark as the characters beside them; they were drawn a little lighter.

## 0.6

- Coming from FontExplorer X? Choose **File → Import from FontExplorer X** to bring over its Font Library, sets (named after the folders they were in, like “Clients / Acme”), application sets with their apps, smart sets, labels as tags in their colors, ratings and how often each family was turned on, and to turn on again the fonts that were on. Cicero finds FontExplorer X’s library on your Mac by itself, or opens a backup of it (`.fexconfig` or `.fexbackup`, from **File → Local Backup**), also when you drop one on the window; a `.fexbackup`’s fonts go back where the Font Library was. A sheet shows what it found, to pick what comes over, and what stays behind, like smart sets with rules Cicero doesn’t have. FontExplorer X’s database is read from a copy, so it can stay open, and nothing of it changes.
- **File → Import from Font Book** brings Font Book’s collections over as sets, with their families and styles; or collection files from another Mac. Font Book’s own collections, like Fun and Web, start unchecked.
- Importing only adds: sets with the names of ones you have get the fonts they don’t have yet, so importing again changes nothing, and your setup is saved first, in Backups.
- Give a family one to five stars from its right-click menu (on its font page too) or the Info panel, and see them in the list’s **Rating** column (right-click the column headers to show it).
- Write a note on a family in the Info panel, like where its license is or which client it’s for. Searching finds families by their notes, a **Note** smart set rule keeps them together, and importing from FontExplorer X brings its comments over as notes.
- Smart sets have new rules: **Designer**, **Rating**, **OpenType Feature** (like Small Capitals, Old-Style Figures or Stylistic Sets), **Embedding** (Installable, Editable, Preview & Print or Restricted), **Times Activated** and **Last Activated**. From now on, Cicero counts each time a family comes on, whether you, an application set or another app turns it on.
- The Info panel shows what a font’s license lets a document do with it, as **Embedding**.
- A family whose fonts name it in your Mac’s language, as many Japanese, Chinese and Korean fonts do, shows and sorts by that name, like ヒラギノ角ゴシック for Hiragino Sans on a Mac in Japanese. Searching finds it by either name.
- After the update, Cicero reads your font files again once, for the OpenType features and embedding the new rules use, and the families’ names in other languages.
- On a font page, clicking a glyph shows its HTML entities (like `&eacute;` and `&#xE9;`) and how to type it with your keyboard layout (like ⌥E, then E), next to its Unicode code, with **Copy Character** to put it on the clipboard. Right-click a glyph for **Copy Character**, **Copy Unicode** and **Copy HTML Entity**, or a ligature for **Copy Characters** and **Copy Unicode**.
- When a font file you add has fonts your library has already, from another file, like a newer version of a font you installed, Cicero asks what to do with each family: **Skip It**, **Add as Another Copy**, or **Use the Added One**, which turns the library’s copy off the way deactivating does, so no font is lost, and the added one on. The sheet shows both versions, where your copy is and whether it’s on, and whether the added one is newer, older, the same version or the same file; each family starts at using the added one when it’s newer. To stop being asked, choose **Add it as another copy**, **Skip it**, **Use the added one** or **Keep the newer version** next to **When an added font is already in your library** in Settings → General.
- **File → Export Font List** saves the selected or listed families as a CSV file for a spreadsheet, with their styles, foundry, designer, version, year, format, classification, status, tags, rating, note and files. Sets, folders and the other items in the sidebar have it in their menus too.
- Turning on more than 100 families at once asks first, as apps list every font that’s on in their font menus. Check **Don’t ask again**, or turn it off in Settings → General.
- Tags are tags again, rather than license statuses: a family can have as many as you like. They’re under **Tags** in the sidebar, with the tag symbol, rather than **License**. Choosing a tag in a family’s **Tags** menu, or dropping the family on it, gives it that tag along with the ones it has; choosing it again takes it off, and **Remove All Tags** takes them all off. Cicero still comes with Licensed, Unlicensed and the others, given to no family, to rename, delete or keep as you like.
- When Cicero asks how to turn fonts on, each choice says all of what it does, rather than cutting its description off after a line.
- **Keep installed fonts in Cicero’s Font Library**, in Settings → General, has the fonts Cicero installs go into a folder of its own, `~/Cicero/Font Library`, in a folder for each family, and macOS uses them from there, rather than from copies in your Fonts folder. Turning one off leaves it in the library, listed and off, ready to turn on again. The library shows as **Font Library** under **Folders** in the sidebar. **Change** moves it to an empty folder of your choice, fonts and all, and **Move Them** brings in the fonts Cicero installed in your Fonts folder before.
- Turning off a font you put in your Fonts folder yourself no longer asks first. It moves to Cicero’s Deactivated folder straight away, as it did after the question, so it stays in your library and comes back when you turn it on.
- Cicero no longer reads web fonts (WOFF and WOFF2). They’re made for websites, and Adobe apps can’t use them: they don’t list one in your Fonts folder, and set blank text in one used where it is. Dropping one on the window says “WOFF2 can’t be installed”. Web fonts that are on stay on, but Cicero doesn’t list them any more.
- Messages at the bottom of the window name the fonts: “Avenir Next installed” rather than “Installed”, and “Avenir Next Bold activated”, “Avenir Next and Georgia deactivated” or, for more, “12 families activated” rather than “Activated 8 files”.
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

## 0.5.2

- Cicero has a new icon: C, 1 and 6 from AM Gaonkar Display Medium, cut into the faces of its cube.
- A font you put in a folder Cicero watches, or in the Fonts folder in your Library, shows almost at once, rather than after two or three seconds, also when your Mac is busy. One put in a Fonts folder shows as active straight away, as macOS turns it on a moment later.

## 0.5.1

- **Show fonts from Creative Cloud**, in Settings → General, keeps Adobe Fonts out of your lists, like **Show system fonts** for the fonts that come with macOS. With it off, they’re left out of every list, smart sets and the Character Toolbox, and **Adobe Fonts** leaves the sidebar. Families you also have yourself stay, as yours.
- **Type Designer Mode** comes after **Maintenance** in Settings → General.
- In Compare, the plus next to **Compare Another Style** is the color of the text, also when you hold the pointer over it. Before, it was gray.
- The About panel links to Cicero’s website.

## 0.5

- Tags are now license statuses, to keep track of what you may do with each family. Cicero comes with **Licensed**, **Licensed + Non-Commercial**, **Unlicensed**, **Partially Licensed**, **Public Domain**, **Open Source** and **Trial**, each with its color, and you can make your own. A family has one status at a time, shown as a colored dot next to its name; give it one from its right-click menu, the Info panel, or by dropping it on a status under **License** in the sidebar. Smart sets have a **License Status** rule.
- Your tags become license statuses, once, and families keep them. A family that had several tags keeps them all until you give it a status. The Red, Yellow and Green tags a library started with go if you never used them. A backup from before 0.5 gets the statuses as it’s restored.
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

## 0.4.9

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

## 0.4.8

- **Remove All Extra Copies**, at the top of Installed Twice in Problems, deals with every font there at once, after asking: it keeps the newest copy of each font and moves the others to the Trash. Of copies with the same version, it keeps one that comes with macOS or an app, then one in your own folders, then one installed for all users, before one in your Fonts folder. Duplicates has **Move All Extra Copies to Trash** too.
- Moving fonts to the Trash works when they’re in a folder only an administrator can change, like an Adobe Fonts folder an installer made: macOS asks for your password, as when you drag them to the Trash in the Finder. Before, Cicero said it couldn’t move them, for instance when moving the extra copies of a font to the Trash in Problems.

## 0.4.7

- Fonts that are on are called active, and those that are off inactive, as on font pages and in Settings → Folders: the sidebar’s **Active** and **Inactive** rather than Activated and Not Activated, “1,298 families · 716 active” under the title, **Active only** in the Character Toolbox, and **Inactive** for a style that’s off, in Quick Look, on font pages, in Problems and as a smart set’s Status.

## 0.4.6

- Font files you added that have since been deleted, or whose folder was moved or renamed, leave your library, rather than staying there unseen. Cicero no longer looks for them every time it opens, which could have macOS ask again about the folder they were in. Files on a disk that isn’t connected stay.
- When macOS asks whether Cicero may read your Documents, Desktop or Downloads folder, its message says why: to read fonts in your library that are kept there, like files you added from a download, and for **Find on This Mac**. Before, it only mentioned Find on This Mac.

## 0.4.5

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

## 0.4.4

- You can change the order of the fonts in the Compare window by dragging a row in Stacked, or a name below the fonts in Overlay, where the last one is drawn on top.
- Each font in the Compare window keeps its color when you move or remove the others.

## 0.4.3

- A folder can be **Active**: Cicero turns on every font in it, where it is, and fonts you put in it later go on by themselves. Choose it next to the folder in Settings → Folders or under **Fonts in This Folder** in its menu in the sidebar, which now offers **Inactive**, **Active**, **Active in Adobe apps** and **Active in Specific App**. Choosing Inactive again, or removing the folder, turns its fonts off.
- Settings → General is more compact: four groups instead of nine, with Appearance on its own, the settings for activation, opening at login, system fonts, Adobe fonts and classification under **Fonts**, **Library** with Rebuild, Back Up and Restore, and Clear for the font caches, under **Maintenance**, the switches for updates and usage statistics under **Updates**, and short explanations inside the rows that need them.
- Settings → Folders lists your folders in a card with **+** and **−** along its bottom, like the lists in System Settings, and you can select several to remove them together. **Show fonts installed for Adobe apps** is in Settings → General now. Folders always have the plain folder icon, whatever they’re set to.
- The window for an application set’s apps lists them in the same kind of card, with **+** and **−**, and you can select several to remove them together. **Open Cicero at login** is a checkbox next to **Done**.
- Settings → Sidebar says individual foundries rather than single ones, with a shorter note at the bottom.
- Fonts you add are described as listed without being activated, rather than without being installed.
- The **Delete** button in the coverage set editor is red, like **Clear** in Settings → General.
- Cicero asks before deleting a coverage set, from its editor, the sidebar or Settings → Coverage.
- Creating a coverage set or a smart set no longer flashes the editor’s Edit title, Delete button or Save button as the sheet closes.

## 0.4.2

- The coverage set editor explains that spaces and line breaks don’t count, so you can use them to lay out your characters.
- The characters a coverage set will check for appear under **Preview** in its editor, with their count next to the heading.

## 0.4.1

- **Use the files where they are** in Settings → General is now **Leave the files where they are**, and Cicero’s question when you turn fonts on offers **Leave Files Where They Are**.
- **Your Coverage Sets** come first in Settings → Coverage and scroll with the built-in sets. Each has an **Edit** button and a right-click menu, **+** next to the heading makes a new one, and the coverage set editor has a **Delete** button.
- Shorter explanations in Settings → General, Folders, Sidebar and Coverage.

## 0.4

- With **Copy into ~/Library/Fonts** chosen in Settings → General, font files you open in Cicero, drop on its window or choose with File → Add Fonts are copied into your Fonts folder and turned on, and show up in All Fonts, rather than being listed where they are under Added Fonts without being installed. Reveal in Finder shows the copy in your Fonts folder. Cicero then selects the first font it installed in the browser and scrolls to it.
- **Move into ~/Library/Fonts**, a new way to activate fonts in Settings → General: font files you open, drop or add are moved into your Fonts folder and turned on, and a folder they leave empty, like a font download’s folder, goes to the Trash. A folder with anything else in it stays, and fonts in your folders are still copied. With Ask each time, Cicero offers Move Into Fonts Folder for fonts you added one at a time.
- Fonts already under Added Fonts leave it once Cicero installs a copy of them, when you turn them on by copying or moving or open them again.
- Fonts you open from the Finder no longer open on their font page, whichever way you activate fonts: Cicero selects the first of them in the browser and scrolls to it, there and when you drop or add fonts.
- Turning off a copy Cicero installed sends it to the Trash only when its original is in your library too. Otherwise, as for a font installed by opening it, the copy moves to Cicero’s Deactivated folder, so the font stays in your library.
- Opening the Info panel no longer makes the grid’s tiles wider. They keep their width and place, and the panel takes a column away instead.
- Typing the start of a name in the list now shows the family it jumps to below the column headers, rather than under them.
- The messages at the bottom of the window no longer end with a full stop: “Activated 8 files” rather than “Activated 8 files.”

## 0.3.1

- Typing a letter in the font list, grid or specimens jumps straight to the first family starting with it, rather than scrolling there.
- You can type more than one letter, as in Finder: E goes to the first family starting with E, and Ed then to the first starting with Ed.

## 0.3

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

## 0.2.1

- Your fonts are there as soon as Cicero opens, as it last found them, rather than appearing a moment later. Anything that changed since follows right after.
- The app icon’s background is the same as on the icons of the apps that come with macOS: white in light mode rather than light grey, and dark grey in dark mode rather than nearly black.

## 0.2

- The sidebar’s folders, foundries and classifications are there as soon as Cicero opens, rather than appearing a moment later.

## 0.1.1

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

## 0.1

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
