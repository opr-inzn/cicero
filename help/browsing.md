# Browsing and previewing

[Cicero Help](README.md) › Browsing and previewing

## Choose what to show

Click an item in the sidebar, like **All Fonts**, a folder or a set, and the browser shows its families. To see the fonts of several items at once, ⌘-click or ⇧-click them; see [Select several items](organizing.md#select-several-items).

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

One tile per family, with a large sample (“Aa Gg 123”, or your own preview text), the name, what the family’s styles span, like “9 Weights · 3 Widths” or “8 Weights · 16 Styles”, and, at the bottom right, what kind of files it comes in, like “OTF”, “TTF” or “Variable”. Hold the pointer over the caption to read all of it. Tiles grow and shrink with the preview size.

The grid is the view Cicero starts with.

### Specimens

One wide row per family: the name, the foundry and number of styles, the sample at the preview size, and up to 14 of its style names, each set in its own style.

### Status tags

Small capsules next to a family’s name tell you more about its state:

| Tag | Means |
| --- | --- |
| System | Comes with macOS |
| Partly active | Some of its styles are on, others aren’t |
| Testing (or an app’s name) | On only in Adobe apps (or that app), from a folder they load by themselves, where type designers put fonts to test them. See [Fonts in Adobe apps’ folders](activating.md#fonts-in-adobe-apps-folders) |
| Adobe Fonts | From Adobe Fonts, managed in Creative Cloud: on in every app, or in Adobe apps only when its switch sits halfway. See [Adobe Fonts](activating.md#adobe-fonts) |
| Temporary | On until Cicero quits. See [Turn a font on just for now](activating.md#turn-a-font-on-just-for-now) |
| App Set | On while an app it’s set up for is open. See [Turn fonts on with an app](activating.md#turn-fonts-on-with-an-app) |

## Search

Type in the search field in the toolbar. Cicero shows the families in the current sidebar item whose name, manufacturer or [note](organizing.md#notes) contains what you type, or the PostScript name, designer or vendor ID of one of its styles.

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

Right-click a family for its menu: activate or deactivate it, add it to a set, give it a tag or a classification, reveal its files, copy its name, export it, compare it, remove a font you [added](organizing.md#added-fonts) from the library, or move it to the Trash. When you right-click one of several selected families, the menu acts on all of them.

You can drag families onto a set, a tag, a foundry or a classification in the sidebar, or into the Compare window.

## Take a quick look

Press Space, or choose **Fonts → Quick Look** (⌘Y), to see the selected family in a floating preview: a large sample, its styles, and its foundry, format and status.

- Use the arrow keys to move the selection in the browser. The preview follows.
- With several families selected, use **‹** and **›** to step through them, or ← and → in the list and specimens. The preview shows where you are, like “2 of 5”.
- Press ↩ to open the family’s font page.
- Press Space or Esc to close the preview.

## Open a font page

Double-click a family, or select it and press ↩ or ⌘↓ (**Fonts → Open**). The font page opens over the browser. To go back, press Esc or click the back button in the toolbar.

From top to bottom, a font page has:

- **The header:** the family name in its own regular style, then its foundry, format, “Variable” for a variable font, and how many styles it has and how many of them are active, partly active (on in Adobe apps only) and inactive. On the right, **Activate** and **Deactivate**. When Cicero can’t turn a family off, **Deactivate** is dimmed; hold the pointer over it to see why. A family from [Adobe Fonts](activating.md#adobe-fonts) has **Manage in Creative Cloud** instead.
- **The text:** a large sample you can type into. Choose a **Style** (Automatic follows the weight in Preview Options; a variable font is otherwise at its default, the origin its styles are drawn from), set the **Size** from 12 to 240 pt, and align the text left, center or right. The space between its lines is the **Line Spacing** in Preview Options. Cicero remembers your text. Right-click it, or the header, for the family’s menu, as in the browser: give it tags or a rating, add it to a set or change its classification, among others. The text’s menu starts with **Cut**, **Copy** and **Paste**. A variable style has a slider for each of its axes under the Style menu, like **Weight**, **Width** or **Optical Size**, at the place the style sits on it; move one, or type a value next to it, to set the text anywhere in between. The Style menu then says **Custom**: **Reset** next to it, or choosing a style, goes back. **Optical Size** follows the text’s size until you move it. Axes the font hides don’t get a slider.
- **Styles,** when the family has more than one: each style set in itself, with its name, weight, and a switch to turn just that style on or off. Its status says how it’s on, like “Active until Cicero quits”. Right-click a style for its menu: activate or deactivate it, turn it on just for now, reveal its file, copy its PostScript name, or move it to the Trash. Under the family’s name, it has the family’s **Add to Set**, **Tags**, **Rating** and **Classification** too.
- **Glyphs:** every character in the font, grouped by kind in the order a type designer would list them: **Uppercase** and **Lowercase** from A to Z, then **Uppercase Accents** and **Lowercase Accents** (with the other Latin letters, like Æ, Þ and ß), **Ligatures**, **Proportional Figures** and **Tabular Figures**, **Dingbat Numerals**, **Currency**, **Mathematical Operators**, **Superscript**, **Subscript**, **Fractions**, **Numerators**, **Denominators**, **Ordinals**, **Punctuation and Symbols**, **Diacritical Marks**, **Combining Marks**, **Case Sensitive Forms**, **Arrows**, and **Global** for the letters and figures of other scripts. The glyphs the style’s features draw in place of characters are in their groups too, like its tabular figures (tnum), superscripts (sups) and case-sensitive forms (case); click one to see which feature draws it. The ligatures the style makes are in the Ligatures group, in a section per feature, like **Standard Ligatures** (see [See a font’s ligatures](#see-a-fonts-ligatures)). To find characters, type into the filter field: a character, part of its Unicode name, or a code like U+00E9. Ligatures made of what you type show too: “f” finds ff, fi and ffl. Click a character to see it large, with its name, its Unicode code, its HTML entities (the named one when HTML has one, like `&eacute;`, and the numeric one, like `&#xE9;`, which works for any character) and, when your keyboard layout types it, its keystroke, like ⌥E, then E for é on a U.S. keyboard (a dead key, then the letter). **Copy Character** there puts it on the clipboard; right-click a character for **Copy Character**, **Copy Unicode** and **Copy HTML Entity**. A glyph a feature draws copies the character it stands for, which looks like the glyph where the feature is on.

## See a font’s ligatures

Under **Glyphs**, in the **Ligatures** group, a font page lists the ligatures the style makes: single glyphs that stand for several characters, like ﬁ for “fi”. Most fonts give ﬁ and ﬂ a character of their own too; they’re listed once, under their ligature feature, and clicking one shows its character’s code, like U+FB01. They’re grouped by the OpenType feature that makes them: **Standard Ligatures**, which apps use unless you turn them off, then **Discretionary**, **Historical**, **Contextual** and **Required Ligatures**. Each shows the ligature’s glyph in a cell like a character’s; hold the pointer over it to see the characters it stands for. Click one to see it large, with its characters, their codes and its feature. **Copy Characters** there, or in its right-click menu, puts the characters on the clipboard, and **Copy Unicode** in the menu their codes.

Cicero lists the ligatures of characters you can type. Ligatures of alternates, or of forms only other features make, are left out, and so are fonts that make ligatures the Apple way (AAT) rather than the OpenType way. To try discretionary ligatures in previews, turn them on in the [Features](#try-opentype-features) tab.

## See a font’s details

Click **Info** in the toolbar, or choose **Fonts → Show Info** (⌘I). The Info panel stays open while you browse and when you open a font page. Select a single family to fill it.

The panel describes the style being previewed, the one closest to the weight in Preview Options. Its **Info** tab shows:

- **Note**: your [note](organizing.md#notes) on the family, at the top. Click it to write one.
- **Status**, and the font’s names: family, style, full name and PostScript name
- **Tags**: the family’s tags, or **No Tags**. **Change** gives it more or takes them off.
- **Rating**: five stars to click to give the family a [rating](organizing.md#ratings). Click the one it has again to take the rating away.
- version, designer, manufacturer, and the vendor ID: the four letters a foundry registers, like ADBE for Adobe
- weight, and the weight range of a variable font
- number of glyphs, format, embedding and copyright. **Embedding** is what the font’s license lets a document do with it, as the font says: **Installable**, **Editable** (the document can be edited with the font in it), **Preview & Print** (viewed and printed, not edited) or **Restricted** (not embedded at all)
- **Languages** the font supports, like “213 languages, including English, German, …”. **Show All** lists them by script, with a search field; a checkmark marks full support. See [Languages](character-sets.md#how-cicero-decides-a-font-supports-a-language).
- **Coverage**: the largest set of each kind the font has, like “Latin S, Adobe Latin 3, GF Latin Core”, and how close it is to the next Latin size, like “Latin M needs 12 more characters”
- **Unicode Blocks** it covers completely, and how many more it covers in part. **Show All** lists every block with a count.
- **Location**, the file’s path, with **Reveal in Finder**
- **Other copies** of the same font elsewhere on your Mac. Click one to reveal it.

## Try OpenType features

Many fonts have optional features, like small caps, old-style figures or stylistic alternates. To try them:

1. Select a family and open the Info panel.
2. Click **Features**.
3. Turn features on or off with their switches.

Some features let you choose one option of several; turning one on turns the others off, and turning the chosen one off goes back to the font’s default.

The features you choose apply to that family wherever Cicero previews it, in the list, grid, specimens and font page, until Cicero quits. They don’t change the font file.

## Change the preview text and size

Click **Preview Options** in the toolbar:

- **Preview Text:** type your own text, or pick one from **Presets**. Leave it empty to show each family’s name (the grid then shows “Aa Gg 123”).
- **Size:** 8 to 160 pt.
- **Weight:** 100 to 900. Cicero shows the style nearest to it, and the exact weight in a variable font.
- **Letter Spacing:** from −10 to 40 % of the em.
- **Line Spacing:** the distance from one line to the next, from 80 to 250 % of the size; 120 % at first. It applies wherever a sample runs over several lines: on font pages and in Quick Look.
- **Alignment:** left, center or right, for the samples in specimens and Quick Look. Font pages have their own alignment, next to the size.

The same options apply to every view, font pages and the Compare window. Cicero remembers them.

## Compare fonts

1. Select two or more families.
2. Choose **Fonts → Compare** (⌥⌘C), or right-click them and choose **Compare**.

The Compare window shows them with the preview text, size, weight and spacing from Preview Options (or “Hamburgefonstiv”, when there’s no preview text). It has its own **Preview Options** button. Choose a layout in the toolbar:

- **Stacked:** one row per font, all on the same baseline, with the name and style under each.
- **Overlay:** every font drawn over the others in its own color, on a shared baseline, with their names below. The last one is drawn on top.

Each font is in the style nearest the weight in Preview Options at first. To compare another, click the style next to its name and choose one; **Automatic** goes back to following the weight. **Compare Another Style** in the same menu adds the family again in a style that isn’t there yet, so you can set a family’s styles against each other, like Regular over Bold.

To change the order, drag a row in Stacked or a name in Overlay. Both layouts keep the same order.

To add fonts, drag families from the main window into the Compare window. To take one out, click its remove button. Choosing **Compare** again starts over with the new selection.
