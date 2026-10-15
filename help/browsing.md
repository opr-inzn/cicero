# Browsing and previewing

[Cicero Help](README.md) › Browsing and previewing

## Choose what to show

Click an item in the sidebar, like **All Fonts**, a folder or a set, and the browser shows its families. To see the fonts of several items at once, ⌘-click or ⇧-click them; see [Select several items](organizing.md#select-several-items).

## Choose a view

Use the switcher at the left of the toolbar. Every view shows each family in its own fonts and has an on/off switch for it.

### List

One row per family, under column headers:

| Column | Shows |
| --- | --- |
| Status | The family’s on/off switch |
| Name | The family name, the colors of [your tags](organizing.md#tags), and a status tag when it isn’t simply on or off (see [Status tags](#status-tags)) |
| Preview | A sample in the font |
| Styles | How many styles the family has |
| Classification | Serif, Sans Serif, Script and so on, from what the font says, the shapes of its letters, or its name (see [Classifications](organizing.md#classifications)) |
| Foundry | Who made it |
| Latin S–XL | The largest of Latin S, M, L and XL the family has every character of |
| Adobe Latin | The largest Adobe Latin set it has, like “AL 3” |
| GF Latin, GF Cyrillic, GF Greek | The largest Google Fonts set of that script it has, like “Plus” (hidden at first) |
| A single character set | Any other set: a Unicode block, GF Latin African or one of your own. A checkmark when the family has all of it, “12 missing” when it lacks a few, nothing when it has none of it (hidden at first) |
| Date Added | When the font arrived on your Mac (hidden at first) |
| Format | OpenType PostScript, OpenType TrueType, Font Collection and so on (hidden at first) |

- **Sort:** click a column header. Click it again to reverse the order. A character set column sorts by the largest set a family has, or by how many of the set’s characters it has.
- **Show or hide columns:** right-click the headers. Single sets are under **Coverage** in that menu: your own first, then GF Latin African and the Unicode blocks. Status, Name and Preview always show.
- **Resize a column:** drag the right edge of its header.

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
| Adobe (or an app’s name) | On only in that app, from a folder it loads by itself. See [Fonts for Adobe apps](activating.md#fonts-for-adobe-apps) |
| Temporary | On until Cicero quits. See [Turn a font on just for now](activating.md#turn-a-font-on-just-for-now) |
| App Set | On while an app it’s set up for is open. See [Turn fonts on with an app](activating.md#turn-fonts-on-with-an-app) |

## Search

Type in the search field in the toolbar. Cicero shows the families in the current sidebar item whose name or manufacturer contains what you type, or the PostScript name, designer or vendor ID of one of its styles.

## Select fonts

| To | Do this |
| --- | --- |
| Select a family | Click it |
| Add or remove one | ⌘-click it |
| Select a range | Click one, then ⇧-click another |
| Select all | ⌘A |
| Select none | Esc |
| Jump to a family | Type the start of its name |
| Move the selection | ↑ or ↓; in the grid, ← and → move it a tile and ↑ and ↓ a row |
| Extend the selection | Hold ⇧ with an arrow key |

Right-click a family for its menu: activate or deactivate it, add it to a set, give it tags, reveal its files, copy its name, export it, compare it, remove a font you [added](organizing.md#added-fonts) from the library, or move it to the Trash. When you right-click one of several selected families, the menu acts on all of them.

You can drag families onto a set or a foundry in the sidebar, or into the Compare window.

## Take a quick look

Press Space, or choose **Fonts → Quick Look** (⌘Y), to see the selected family in a floating preview: a large sample, its styles, and its foundry, format and status.

- Use the arrow keys to move the selection in the browser. The preview follows.
- With several families selected, use **‹** and **›** to step through them, or ← and → in the list and specimens. The preview shows where you are, like “2 of 5”.
- Press ↩ to open the family’s font page.
- Press Space or Esc to close the preview.

## Open a font page

Double-click a family, or select it and press ↩ or ⌘↓ (**Fonts → Open**). The font page opens over the browser. To go back, press Esc or click the back button in the toolbar.

From top to bottom, a font page has:

- **The header:** the family name in its own regular style, then its foundry, format, “Variable” for a variable font, and how many styles it has and how many are activated. On the right, **Activate** and **Deactivate**. When Cicero can’t turn a family off, **Deactivate** is dimmed; hold the pointer over it to see why.
- **The text:** a large sample you can type into. Choose a **Style** (Automatic follows the weight in Preview Options), set the **Size** from 12 to 240 pt, and align the text left, center or right. The space between its lines is the **Line Spacing** in Preview Options. Cicero remembers your text.
- **Styles,** when the family has more than one: each style set in itself, with its name, weight, and a switch to turn just that style on or off. Its status says how it’s on, like “Active until Cicero quits”. Right-click a style for its menu: activate or deactivate it, turn it on just for now, reveal its file, copy its PostScript name, or move it to the Trash.
- **Ligatures,** when the style has any: see [See a font’s ligatures](#see-a-fonts-ligatures).
- **Glyphs:** every character in the font, in one section per Unicode block, like Basic Latin or Latin-1 Supplement. To find characters, type into **Filter**: a character, part of its Unicode name, or a code like U+00E9. Click a character to see it large, with its name and code.

## See a font’s ligatures

A font page lists the ligatures the style makes: the single glyphs that stand for several characters, like ﬁ for “fi”. They’re grouped by the OpenType feature that makes them: **Standard Ligatures**, which apps use unless you turn them off, then **Discretionary**, **Historical**, **Contextual** and **Required Ligatures**. Each shows the ligature’s glyph with the characters it stands for under it. Click one to see it large, with its characters, their codes and its feature.

Cicero lists the ligatures of characters you can type. Ligatures of alternates, or of forms only other features make, are left out, and so are fonts that make ligatures the Apple way (AAT) rather than the OpenType way. To try discretionary ligatures in previews, turn them on in the [Features](#try-opentype-features) tab.

## See a font’s details

Click **Info** in the toolbar, or choose **Fonts → Show Info** (⌘I). The Info panel stays open while you browse and when you open a font page. Select a single family to fill it.

The panel describes the style being previewed, the one closest to the weight in Preview Options. Its **Info** tab shows:

- **Status**, and the font’s names: family, style, full name and PostScript name
- **Tags**: the family’s tags. **Add Tag** or **Edit Tags** gives it others or takes them off.
- version, designer, manufacturer, and the vendor ID: the four letters a foundry registers, like ADBE for Adobe
- weight, and the weight range of a variable font
- number of glyphs, format and copyright
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
- **Overlay:** every font drawn over the others in its own color, with small marks for each font’s x-height and cap height. The last of the names below them is drawn on top: drag a name to change the order, which Stacked uses too.

To add fonts, drag families from the main window into the Compare window. To take one out, click its remove button. Choosing **Compare** again starts over with the new selection.
