# Browsing and previewing

[Cicero Help](README.md) › Browsing and previewing

## Choose what to show

Click an item in the sidebar, like **All Fonts**, a location or a folder, and the browser shows its families. To see the fonts of several items at once, ⌘-click or ⇧-click them; see [Select several items](organizing.md#select-several-items).

### Names in your language

A font can name its family in other languages too, as many Japanese, Chinese and Korean fonts do. When it has a name in your Mac’s language, the first in **System Settings → General → Language & Region**, Cicero shows the family by that name and sorts it by it: Hiragino Sans is ヒラギノ角ゴシック on a Mac in Japanese. With English first, families show by their own names. The **Family** row in the [Info panel](#see-a-fonts-details) has the family’s own name, and searching finds either.

## Choose a view

Use the switcher at the left of the toolbar. Every view shows each family in its own fonts and has an on/off switch for it.

### List

One row per family, under column headers:

| Column | Shows |
| --- | --- |
| Status | The family’s on/off switch |
| Name | The family name, the color of its [tag](organizing.md#tags), and a status tag when it isn’t simply on or off (see [Status tags](#status-tags)) |
| Preview | A sample in the font |
| Styles | How many styles the family has |
| Classification | Serif, Sans Serif, Script and so on, from what the font says, the shapes of its letters, or its name (see [Classifications](organizing.md#classifications)) |
| Foundry | Who made it |
| Year | When it came out, as near as its files say: the earliest year in its copyright notice, like 2014 for “© 2014–2021”, else the year its files were made (hidden at first) |
| Rating | The stars you gave the family (see [Ratings](organizing.md#ratings); hidden at first) |
| Latin S–XL | The largest of Latin S, M, L and XL the family has every character of |
| Adobe Latin | The largest Adobe Latin set it has, like “AL 3” |
| GF Latin, GF Cyrillic, GF Greek | The largest Google Fonts set of that script it has, like “Plus” (hidden at first) |
| A single character set | Any other set: a Unicode block, GF Latin African or one of your own. A checkmark when the family has all of it, “12 missing” when it lacks a few, nothing when it has none of it (hidden at first) |
| Date Added | When the font arrived on your Mac (hidden at first) |
| Format | OpenType PostScript, OpenType TrueType, Font Collection and so on (hidden at first) |

- **Sort:** click a column header. Click it again to reverse the order. A character set column sorts by the largest set a family has, or by how many of the set’s characters it has.
- **Show or hide columns:** right-click the headers. The character set columns are under **Coverage** in that menu: Latin S–XL, Adobe Latin, the GF sets and the Unicode blocks, then your own sets. Status, Name and Preview always show.
- **Resize a column:** drag the edge between two headers. Left of the preview, that’s the column’s right edge; right of it, its left edge. The preview gets narrower or wider to make up the difference.

Cicero remembers the columns you show and their widths. When the window gets narrow, for example with the Info panel open, the preview gives way first.

### Grid

One tile per family, with a large sample (“Aa Gg 123”, or your own preview text), the name, with the family’s stars at the right if you’ve [rated](organizing.md#ratings) it and a note symbol if it has a [note](organizing.md#notes), what the family’s styles span, like “9 Weights · 3 Widths” or “8 Weights · 16 Styles”, and, at the bottom right, what kind of files it comes in, like “OTF” or “TTF”. A variable family has a **Variable** tag at the top left (see [Status tags](#status-tags)). Hold the pointer over the caption to read all of it.

The tiles fit the type: **Size** in [Preview Options](#change-the-preview-text-and-size) makes it bigger or smaller, and the tiles grow and shrink around it. Every font is at the size you chose: the tiles are as wide as the fonts in your library need, monospaced and wide fonts included, and they keep that width in every list and search, so the rows don’t change as you click from one to the next. Only the widest few, like fonts with long swashes or very extended ones, are drawn a little smaller, and they still grow and shrink with the rest. With the Info panel open, every sample is a little smaller, all alike, so the tiles keep their places, and **Size** in Preview Options says how big they are then, like 37 pt for 48; closing the panel brings back your size. Small type gives low tiles, up to five in a row; bigger type gives fewer, bigger tiles, down to one in a row, as wide as your preview text needs. The letters sit on one line across all the tiles, centred in them. However many tiles are in a row, they fill the window’s width, and wider tiles are taller. Opening the Info panel makes them narrower, not fewer.

The grid is the view Cicero starts with.

### Specimens

One wide row per family: the name, the foundry and number of styles, the family’s stars if you’ve [rated](organizing.md#ratings) it and a note symbol if it has a [note](organizing.md#notes), the sample at the preview size, and up to 14 of its style names, each set in its own style.

### Status tags

Small capsules next to a family’s name tell you more about its state:

| Tag | Means |
| --- | --- |
| System | Comes with macOS |
| Partly active | Some of its styles are on, others aren’t |
| Proofing (or an app’s name) | On only in Adobe apps (or that app), from a folder they load by themselves, where type designers put fonts to test them. See [Fonts in Adobe apps’ folders](activating.md#fonts-in-adobe-apps-folders) |
| Adobe Fonts | From Adobe Fonts, managed in Creative Cloud: on in every app, or in Adobe apps only when its switch sits halfway. See [Adobe Fonts](activating.md#adobe-fonts) |
| Temporary (with a clock) | On until Cicero quits. See [Turn a font on just for now](activating.md#turn-a-font-on-just-for-now) |
| App Folder (with an app) | On while an app it’s set up for is open. See [Turn fonts on with an app](activating.md#turn-fonts-on-with-an-app) |

A green **Variable** tag, with the symbol of sliders, marks a variable family, in the list, grid and specimens alike. Hold the pointer over it to see its axes, like “Variable: Weight, Width, Optical Size”, and move them in the Info panel’s [Axes](#try-variable-axes) tab.

## Search

Type in the search field in the toolbar. Cicero shows the families in the current sidebar item whose name, foundry or [note](organizing.md#notes) has a word that begins with what you type, or the name, PostScript name, designer or vendor ID of one of its styles. So **am** finds American Typewriter, but not every family from a foundry with “am” inside its name. When no word begins with what you type, Cicero looks inside the words of names too, so **vetica** still finds Helvetica.

As you type, the search field suggests up to eight families whose names begin with it, or have a word that does, each with “Aa” in its own letters. Choose one to search for its whole name: that family is selected and brought into view.

You can also search for what kind of family it is, whatever it’s called:

| Type | To find |
| --- | --- |
| **variable** | Variable fonts |
| **mono** or **monospaced** | Monospaced fonts |
| **italic** | Families with italics |
| **serif**, **sans**, **script**, **ornamental**, **symbol** or a classification of your own | Families in that classification. **handwriting** finds scripts too, and **dingbats** symbols |
| **slab** | Slab serifs, as their fonts say |
| **display** or **text** | Families made for large or small sizes: their names say so, like Display, Headline or Poster and Text, Caption or Micro, or they’re variable fonts with an optical size axis. **display** finds ornamental families too |
| **condensed**, **compressed** or **narrow**, and **extended**, **expanded** or **wide** | Families with styles narrower or wider than normal |
| A tag | Families with that tag |
| **otf**, **ttf**, **ttc** | Families that come in that kind of file |

Words find the families that match each of them, so **variable sans** shows the variable sans serifs, and **inter variable** shows Inter if it’s variable. A word like these finds a family by what it is, by its name and its styles’ names, and by your note, but not by its foundry, designer or PostScript names: **mono** shows monospaced fonts and fonts with Mono in their names, not every font from Monotype.

Search for a style, like **italic**, **bold**, **light** or **condensed bold**, and the previews show it: each family in its italic, bold, light or condensed bold style, or the nearest one it has. A font page whose **Style** is **Automatic** shows it too. A word that’s part of a family’s name stays its name: **avenir next condensed** shows Avenir Next Condensed as usual. Spell the word out: **it** or **bd** don’t change the previews.

### Filter by style and figures

To narrow the search to a style, to figures or to variable fonts, choose a filter from the suggestions as you type. Type **ital**, **bold**, **cond**, **fig** or **var**, say, and choose **Italic**, **Bold**, **Condensed**, **Tabular Figures**, **Old-Style Figures** or **Variable** under **Filters**. Type **weight** for all the weights, from **Thin** to **Black**, and **width** for **Condensed** and **Extended**. A filter goes into the search field as a token, next to what you type, and you can add more: **Italic** and **Bold** show the families that have a bold italic, in their bold italic, and **Variable** and **Italic** those with a variable italic. A second weight takes the place of the first. Delete a token to take its filter away.

Tabular figures are all as wide, for columns of numbers; old-style figures sit like lowercase letters, for numbers in text. A family has them when its figures are made like that, or when one of its features turns them on. With the filter, the previews show them.

## Find similar fonts

Right-click a family and choose **Show Similar Fonts**, or select it and choose **Fonts → Show Similar Fonts**. The browser shows the family and the 12 families in your library that look most like it, the closest first, in the view you’re using. A bar above them says whose they are. To go back to what you were looking at, a font page too, click **Done** in the bar, or choose an item in the sidebar. Search works within them, and in the list they stay closest first until you click a column’s title to sort by it.

If a family doesn’t look like the one it’s listed for, right-click it among the similar fonts and choose **Not Similar to** that family. It leaves the list, which is that much shorter, as no other family takes its place, and the other way round too: the one it was listed for leaves its list. Changed your mind? Click **Undo** in the note at the bottom of the window. While **Share usage statistics** is on, Cicero also reports it, to make similar fonts better for everyone; with it off, the mark stays on your Mac. See [Not-similar reports](privacy.md#not-similar-reports).

Cicero compares the letters of each family’s regular style: how tall its lowercase is against its capitals, how far its ascenders and descenders reach, how heavy its stems are, how much its strokes change from thick to thin and at what angle, how wide its letters are and how much room it leaves around them, how far it leans, whether it has serifs and how long and thick they are, how open its c and e are, how square its o is, whether its a and g have one story or two, and whether it’s monospaced. It also looks at them with a model that has learned from thousands of freely licensed fonts what letters of a kind look like, so scripts, stencils and other unusual families find their own kind too. Families of different classifications count as further apart. Of families whose names say what size they’re for, like Text and Caption or Display and Headline, a text one lists text ones first and a display one display ones, then its own sibling for the other size. Copies of one design, as their names say, like a trial, a variable font or a family for each weight, are listed once, the closest of them, and the family’s own copies not at all. It measures the letters on your Mac, once Cicero has checked your fonts’ characters: a few seconds for a thousand families the first time, then only new and changed files.

A family without the Latin letters Cicero measures, like most fonts for other scripts and symbol fonts, has no similar fonts: **Show Similar Fonts** is dimmed, and its page has no **Similar**. Fonts you’ve hidden from your lists, like the ones that come with macOS while **Show system fonts** is off, aren’t among the similar ones.

## Select fonts

| To | Do this |
| --- | --- |
| Select a family | Click it |
| Add or remove one | ⌘-click it |
| Select a range | Click one, then ⇧-click another. Families you ⌘-clicked before stay selected |
| Select all | ⌘A |
| Select none | Esc |
| Jump to a family | Type the start of its name |
| Move the selection | ↑ or ↓; in the grid, ← and → move it a tile and ↑ and ↓ a row |
| Extend the selection | Hold ⇧ with an arrow key |

Right-click a family for its menu: activate or deactivate it, add it to a folder, give it a tag or a classification, reveal its files, export it, [show similar fonts](#find-similar-fonts), compare it, remove a font you [added](organizing.md#added-fonts) from the library, or move it to the Trash. When you right-click one of several selected families, the menu acts on all of them.

You can drag families onto a folder, a tag, a foundry or a classification in the sidebar, or into the Compare window. When you drag one of several selected families, all of them go.

## Take a quick look

Press Space, or choose **Fonts → Quick Look** (⌘Y), to see the selected family in a floating preview: a large sample, its styles, and its foundry, format and status.

- Use the arrow keys to move the selection in the browser. The preview follows.
- With several families selected, use **‹** and **›** to step through them, or ← and → in the list and specimens. The preview shows where you are, like “2 of 5”.
- Press ↩ to open the family’s font page.
- Press Space or Esc to close the preview.

## Open a font page

Double-click a family, or select it and press ↩, ⌘O or ⌘↓ (**Fonts → Open**). The font page opens over the browser. To go back, press Esc or ⌘← (**View → Back**), or click the back button in the toolbar.

From top to bottom, a font page has:

- **The header:** the family name in its own regular style, then its foundry, format, “Variable” for a variable font, and how many styles it has and how many of them are active, partly active (on in Adobe apps only) and inactive. On the right, **Activate** and **Deactivate**. When Cicero can’t turn a family off, **Deactivate** is dimmed; hold the pointer over it to see why. A family from [Adobe Fonts](activating.md#adobe-fonts) has **Manage in Adobe Fonts** instead, which opens its page on the Adobe Fonts website (or **Manage in Creative Cloud**, which opens the Creative Cloud app, when Cicero can’t find the page).
- **The text:** a large sample you can type into. Choose a **Style** (Automatic shows the regular style, or the style you search for, like **italic**; a variable font is otherwise at its default, the origin its styles are drawn from), set the **Size** from 12 to 240 pt, and align the text left, center or right. **Tracking** adds space between the letters, from −10 to 40 % of the em, on top of the font’s kerning; it’s for font pages only, as the other views show every font with its own spacing. **Leading** sets the space between its lines, in percent of the size; it’s the one in Preview Options too. Cicero remembers your text. Delete it all and click somewhere else, and “Sphinx of black quartz, judge my vow.” is back. Right-click it, or the header, for the family’s menu, as in the browser: give it tags or a rating, add it to a folder or change its classification, among others. The text’s menu starts with **Cut**, **Copy** and **Paste**. For a variable style, **Axes** opens the Info panel at its [Axes](#try-variable-axes) tab. Once you’ve moved an axis there, the Style menu says **Custom**: choosing a style, or **Reset All** in the tab, goes back.
- **Styles,** when the family has more than one: each style set in itself, with its name, its weight when the styles aren’t all of one weight, its place on the other axes they differ on, and a switch to turn just that style on or off. Its status says how it’s on, like “Active until Cicero quits”. Right-click a style for its menu: activate or deactivate it, turn it on just for now, reveal its file, copy its PostScript name, or move it to the Trash. Under the family’s name, it has the family’s **Add to Folder**, **Tags**, **Rating** and **Classification** too.
- **Glyphs:** every character in the style the text is set in, the one chosen in the **Style** menu, at its axes as you’ve moved them, grouped by kind in the order a type designer would list them: **Uppercase** and **Lowercase** from A to Z, then **Uppercase Accents** and **Lowercase Accents** (with the other Latin letters, like Æ, Þ and ß), **Small Caps**, **Ligatures**, **Localized Forms** (the letters a font draws differently for a language, like Bulgarian or Turkish, in a row for each language, named above it), **Proportional Figures** and **Tabular Figures**, **Circled Figures** (like ①, ㉑ and ❶, and the Chinese ㊀ and ㈠, a row for each kind, from ⓪ up), **Roman Numerals** (capitals like Ⅻ, then small ones like ⅻ), **Punctuation and Symbols** (with signs like Ω for ohms and µ for micro), **Currency** (with the florin ƒ), **Mathematical Operators**, **Superscript**, **Subscript**, **Fractions**, **Numerators**, **Denominators**, **Ordinals**, **Case-Sensitive Forms**, **Arrows**, then a group for each other script, named after it, like **Greek**, **Cyrillic** or **Arabic**, with its letters, figures, marks and punctuation, in the order Unicode lists them (a sign or mark several scripts share, like the danda or Arabic’s comma, goes with the script the font is for; **Greek** and **Cyrillic** go by alphabet: capitals from Α to Ω or from А to Я, then the accented and other letters, then the lowercase letters the same way, then punctuation and accents), **Graphical** for the glyphs a font keeps in private use, like its foundry’s logos and icons (those named after a character, like the shifted tone marks of a Thai font, go right after that character, and an older font’s small capitals, superiors and ligatures kept there, like a.sc, h.superior or f_i, go with the **Small Caps**, **Superscript** or **Ligatures**), and last **Diacritical Marks** and **Combining Marks**. A font without Latin letters, like an Arabic or a Syriac font, starts with its scripts, the one it has the most characters of first, and its ligatures follow them. Within a group, characters are in Unicode order, but **Superscript**, **Subscript**, **Numerators** and **Denominators** start with their figures from 0 to 9, then their signs, like ⁺, then their letters, **Fractions** starts with the fraction slash, then goes from ⅒ to ⅞, and **Uppercase Accents** and **Lowercase Accents** are in the order the font editor Glyphs lists them, alphabetically by glyph name: á, ă, â, ä, à, ā, ą, å, ã, then æ and ǽ, then the c’s, with ɛ among the e’s, ø after ō and ß after the s’s. **Punctuation and Symbols** and **Mathematical Operators** are in a type designer’s order too: . , : ; first, then dashes, brackets in pairs, quotes, and symbols like @ & ¶ §; the operators start with + − × ÷ = and end with % and ‰, which Glyphs counts as operators, like ^. The `` ` `` is with the **Diacritical Marks**. Case-sensitive forms are in the same order. Glyphs that draw nothing, like the empty ones a trial font keeps for the characters it leaves out, aren’t listed, nor are spaces. The glyphs the style’s features draw in place of characters are in their groups too, like its small capitals (smcp and c2sc), tabular figures (tnum), superscripts (sups) and case-sensitive forms (case); click one to see which feature draws it. Small capitals are in the same order, from a, á, ă and the other a’s to z, a capital’s right after its lowercase letter’s, then figures and signs, each followed by its own alternates with a grey dot, like a stylistic set’s small capital or the Turkish one with a dot on the i. An older font’s small capitals that it also keeps at private-use codes are listed there too, rather than with the letters. The alternates its features offer, like a stylistic set’s single-storey a, a swash, old-style figures or a Latin font’s forms for the start and end of a word, follow the characters they’re for, each with a grey dot; click one to see which feature offers it, by the name the font gives it. Figures are listed by kind instead, each kind starting a row: lining figures, then old-style ones, then their other alternates, like a slashed zero, and under **Tabular Figures** the signs that go with them last, like a tabular dollar. The ligatures the style makes are in the Ligatures group, in a section per feature, like **Standard Ligatures** (see [See a font’s ligatures](#see-a-fonts-ligatures)). To find characters, type into the filter field: a character, part of its Unicode name, or a code like U+00E9. Ligatures made of what you type show too: “f” finds ff, fi and ffl. Click a character to see it large, with its name, its Unicode code and its HTML entities (the named one when HTML has one, like `&eacute;`, and the numeric one, like `&#xE9;`, which works for any character). **Copy Character** there puts it on the clipboard and closes the popover, and the bottom of the window says what was copied; right-click a character for **Copy Character**, **Copy Unicode** and **Copy HTML Entity**. A glyph a feature draws copies the character it stands for, which looks like the glyph where the feature is on. Pasted into the text at the top of the page, it shows as the glyph you copied, an alternate as that alternate, in whichever of the family’s styles the text is set in; other fonts’ pages show the plain character. A glyph copied with **Copy as Vector** pastes there the same way. **Copy as Vector**, there and in the right-click menu, copies the glyph’s own outline, as the page shows it, in the style chosen and at its axes as you’ve moved them: paste it into Illustrator, InDesign or another design app as a shape you can edit, or as SVG code into an app that takes it, like Figma, or a text editor. Pasted into Messages, Mail or the Finder, it’s an SVG file named after the style and the glyph, as when you drag it out. It’s how you take out the shape of an alternate, or of a glyph a feature draws. To make a file of it, drag the glyph out of the page into the Finder: it becomes an SVG file named after the style and the glyph, like “Inter Regular a.ss01.svg”. Dragged into a design app, it’s a shape there too. The outline is black, at 100 points to the em, in a frame from the font’s descender to its ascender and across the glyph’s width, so glyphs from one font line up on a baseline; a glyph that reaches further gets a bigger frame, so nothing of it is cut off.

## See a font’s ligatures

Under **Glyphs**, in the **Ligatures** group, a font page lists the ligatures the style makes: single glyphs that stand for several characters, like ﬁ for “fi”. Most fonts give ﬁ and ﬂ a character of their own too; they’re listed once, under their ligature feature, and clicking one shows its character’s code, like U+FB01. They’re grouped by the OpenType feature that makes them: **Standard Ligatures**, which apps use unless you turn them off, then **Discretionary**, **Historical**, **Contextual** and **Required Ligatures**. Each shows the ligature’s glyph in a cell like a character’s; hold the pointer over it to see the characters it stands for. Click one to see it large, with its characters, their codes and its feature. **Copy Characters** there, or in its right-click menu, puts the characters on the clipboard, and **Copy Unicode** in the menu their codes. Pasted into the text at the top of the page, the characters show as the ligature, even one you’d otherwise have to turn on. **Copy as Vector**, in both, copies the ligature’s outline, and you can drag it out of the page, as with any glyph.

Cicero lists the ligatures of characters you can type. Ligatures of alternates, or of forms only other features make, are left out, and so are fonts that make ligatures the Apple way (AAT) rather than the OpenType way. To try discretionary ligatures in the text on the font page, turn them on in the [Features](#try-opentype-features) tab.

## See a font’s details

Click **Info** in the toolbar, or choose **Fonts → Show Info** (⌘I). The Info panel stays open while you browse and when you open a font page. Select a single family to fill it.

The panel describes the family’s regular style. Its **Info** tab shows:

- **Note**: your [note](organizing.md#notes) on the family, at the top. Click it to write one.
- **Status**, and the font’s names: family, style, full name and PostScript name
- **Tags**: the family’s tags, or **No Tags**. **Change** gives it more or takes them off.
- **Rating**: five stars to click to give the family a [rating](organizing.md#ratings). Click the one it has again to take the rating away.
- version, designer, manufacturer, and the vendor ID: the four letters a foundry registers, like ADBE for Adobe
- the weight range of a variable font
- number of glyphs, format, embedding and copyright. **Embedding** is what the font’s license lets a document do with it, as the font says: **Installable**, **Editable** (the document can be edited with the font in it), **Preview & Print** (viewed and printed, not edited) or **Restricted** (not embedded at all)
- **Languages** the font supports, like “213 languages, including English, German, …”. **Show All** lists them by script, with a search field; a checkmark marks full support. See [Languages](character-sets.md#how-cicero-decides-a-font-supports-a-language).
- **Coverage**: the largest set of each kind the font has, like “Latin S, Adobe Latin 3, GF Latin Core”, and how close it is to the next Latin size, like “Latin M needs 12 more characters”. **Show Missing** lists those characters with their names and codes, and **Copy Characters** there puts them on the clipboard, to paste into your font editor.
- **Unicode Blocks** it covers completely, and how many more it covers in part. **Show All** lists every block with a count.
- **Location**, the file’s path, with **Reveal in Finder**
- **Other copies** of the same font elsewhere on your Mac. Click one to reveal it.

## Try OpenType features

Many fonts have optional features, like small caps, old-style figures or stylistic alternates. To try them:

1. Select a family and open the Info panel.
2. Click **Features**.
3. Turn features on or off with their switches.

Some features let you choose one option of several; turning one on turns the others off, and turning the chosen one off goes back to the font’s default. Kerning has no switch: fonts are made to be kerned.

The features you choose change the text on that family’s font page, until Cicero quits; everywhere else, like the list, grid and specimens and the page’s list of styles, its styles show as they are. Every alternate a feature offers is under **Glyphs** too, whether the feature is on or not: after the character it’s for, with a grey dot, or in a group of its own, like **Small Caps**. They don’t change the font file.

## Try variable axes

A variable font is drawn from its design axes, like **Weight**, **Width**, **Optical Size** or **Slant**, or the designer’s own, like Roboto Flex’s **Grade**. Cicero shows it at its default on each, the origin its styles are drawn from, Optical Size included. To move it along them:

1. Select a variable family and open the Info panel, or click **Axes** on its font page.
2. Click **Axes**.
3. Drag a slider, or type a value next to it.

Each axis shows its name and its four-letter tag, like `wdth`, in the order the font gives them. **Reset All** puts them all back. **Optical Size** stays at the font’s own, like every other axis, rather than following the size of the text, until you move it. Axes the font asks apps not to show, like Roboto Flex’s parametric ones, are listed last, under **Hidden Axes**: click it to show or hide them. Cicero remembers whether they’re shown.

Like features, the axes apply to that family wherever Cicero previews it, in the list, grid, specimens, Quick Look and its font page, text and glyphs alike, until Cicero quits. Choosing a style on the font page puts them back.

## Change the preview text and size

Click **Preview Options** in the toolbar:

- **Preview Text:** type your own text, or pick one from **Presets**. **Save as Preset** adds the text you typed to **Presets**, and **Remove Preset** takes it out again. Leave it empty to show each family’s name (the grid then shows “Aa Gg 123”). A font with none of the text’s letters, like an Arabic or a Thai font for Latin text, shows text in its own script instead: the names of languages written in it, in their own letters, like العربية, or its first letters. Otherwise macOS would set the text in another font, and you wouldn’t see the font’s own letters, weights or axes.
- **Size:** 24 to 200 pt.
- **Leading:** the distance from one line to the next, from 80 to 200 % of the size; 120 % at first. It applies wherever a sample runs over several lines: on font pages and in Quick Look.

The same options apply to every view, font pages and the Compare window, but the size: font pages and the Compare window have their own. Samples in the list, grid, specimens, Quick Look and Compare keep each font’s own spacing and line up on the left; font pages have their own [tracking and alignment](#open-a-font-page). Cicero remembers them.

## Compare fonts

1. Select two or more families.
2. Choose **Fonts → Compare** (⌥⌘C), or right-click them and choose **Compare**.

You can also open the Compare window by itself, with **Window → Compare**, or **Fonts → Compare** with no families selected, and pick the fonts there: click **+** in its toolbar (or **Add Families**, while it’s empty), type a name, and click a family or press Return to add it. ↑ and ↓ move to the next family found. Families already there have a checkmark; click one again to take it out. The list has every family in your library, wherever it is and whatever the main window shows, so families far apart are as easy to put together as neighbors. Closing the Compare window empties it.

The Compare window shows them in a text of its own, “Hamburgefonstiv” until you type another in its own **Preview Options**. Typing it there leaves the previews in the main window as they are. Choose a layout in the toolbar:

- **Stacked:** one row per font, each starting at the same place, with the name and style under each. A row is as tall as its font needs, so the rows above stay where they are as you add or take out fonts.
- **Overlay:** every font drawn over the others in its own color, on a shared baseline, with their names below. The fonts line up on the first stem of their first letter, so you can compare their stems, serifs and spacing from the same starting point. Where they overlap, the colors mix like inks on paper (or like lights, in Dark Mode), so each font shows through the others. To change a font’s color, click the dot next to its name and choose one.

The Compare window has a size of its own, from 24 to 720 pt, 72 pt at first, so you can look at the fonts up close without changing the previews in the main window. Set it with **Size** in the Compare window’s **Preview Options**, or choose **View → Zoom Out** or **Zoom In** (⌘− and ⌘+) to go to the next smaller or bigger common size, like 96, 120 or 144 pt.

Each font is in its regular style at first. To compare another, click the style next to its name and choose one; **Automatic** goes back to the regular style. **Compare Another Style** in the same menu adds the family again in a style that isn’t there yet, so you can set a family’s styles against each other, like Regular over Bold.

To change the order, drag a row in Stacked or a name in Overlay. Both layouts keep the same order.

Compare holds up to 12 fonts, one for each color. Once it’s full, take one out to add another.

To add fonts, drag families from the main window into the Compare window, or select one family and choose **Fonts → Compare**, or right-click it and choose **Add to Compare**: it joins the fonts already there. To take one out, click its remove button. Choosing **Compare** with several families selected starts over with them.
