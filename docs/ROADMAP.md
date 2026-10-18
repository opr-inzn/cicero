# Roadmap

Features that could come next, roughly in the order they'd come, with how each could work, what's still open and
about how big it is (S: a few hours, M: about a day, L: several days or more). Nothing here is promised; the order
changes as Cicero does. What's done but not released yet is under "Unreleased" in the [changelog](../CHANGELOG.md).

## Next

### Similar fonts (M, plus tuning)

**What.** **Show Similar Fonts** in a family's right-click menu fills the browser with the families in the library that
look most like it, the closest first, the way a search does. The font page gets a **Similar** section with a few of them
set in themselves.

**How.** For each family's regular style, measure its shapes from the outlines of a handful of letters (H, O, n, o, e,
a, c, g), the way `LetterShapes` already measures the I and l for classifications:

- x-height and cap height as parts of the em, and the ascenders and descenders
- stroke weight: the stem's width against the em
- contrast: the thick strokes of the o and O against the thin ones
- width: the lowercase's average advance
- slant
- serifs or none, and how far they reach
- aperture: how open the c and e are
- roundness: how square the o's bowl is

Each measurement is scaled across the library, so none counts for more by being a bigger number, then weighted.
Similar families are the nearest ones. The same classification helps but isn't required.

The measurements are worked out in the background and cached on disk by file, like coverage: about a minute for a
library of 1,200 families the first time, then only for new files.

**Tuning.** The weights decide whether the results look right to a type designer, and that takes a few rounds with real
libraries. Start with a test that only prints the 10 nearest families of some reference fonts (Georgia, Helvetica,
a trial from a small foundry, a script) and compare. As a check, Apple's Vision framework can make an "image
fingerprint" of a rendered sample (`VNGenerateImageFeaturePrintRequest`) on the Mac: quick to build, but not made for
type, so a comparison, not the answer.

**Open.**
- Per family or per style: whether an italic or a condensed style should find italics and condensed styles.
- Fonts without Latin letters, and scripts and symbol fonts, which the measurements don't fit: leave them out at
  first.

### Pairing (M, on top of Similar)

**What.** A **Pairs With** section on the font page: a few families that go with this one, each shown as a heading in
one and a paragraph in the other, with why ("Same designer", "Similar x-height").

**How.** Rules of thumb on the Similar measurements:
- a serif with a sans serif, or the other way round
- similar x-height and proportions, so they sit well on a line together
- weights that overlap
- a strong preference for the same superfamily: a shared name ("Freight Text" and "Freight Sans"), the same designer or
  the same foundry

The superfamily rule is cheap and reliable; the others give reasonable suggestions, some of which will look naive.

**Open.** It's a matter of taste. Families the user keeps in the same set could count as pairs they like, so the
suggestions learn from the library itself.

### Cicero in Spotlight (M)

**What.** Cicero's own information becomes searchable in Spotlight: type a family's name, or "Licensed serif", and
families from Cicero's library show among the results; choosing one opens its font page in Cicero.

**Why not a classic Spotlight importer.** macOS already has one for font files (`/System/Library/Spotlight/Font.mdimporter`):
every font file's names, designer, foundry, version and copyright are in Spotlight, with or without Cicero. What only
Cicero knows is the user's own: tags, ratings, classifications, sets and smart sets.

**How.** Core Spotlight (`CSSearchableIndex`), one item per family:
- title: the family name
- description: "Serif · Carter & Cone · Licensed · ★★★★"
- keywords: its tags, sets, classification, foundry, designers and style names
- thumbnail: a sample set in the font, made in the background and cached

Items change when the library or the user's data does (gathered for a moment, not on every change) and go when their
family does. Choosing a result reaches Cicero as a `CSSearchableItemActionType` user activity, which selects the family
and opens its page. The index stays on the Mac. Settings → General gets a switch for it; turning it off deletes the
items.

Not this way: writing Finder tags onto the font files for Cicero's tags. That changes the user's files.

**Open.**
- What 1,200 thumbnails cost to make, and whether results look good enough without them.
- Whether to index styles too, by PostScript name.

## Later

### Specimen sheets (L)

Print the selected families, or save them as a PDF: one family per page with its styles and a paragraph, a catalog of
many families with a line each, or a page of a style's characters, with the name and date in the header. Drawn with
CoreText through `NSPrintOperation`, so print and PDF are one; glyphs set by their ink bounds, never clipped. Open:
which layouts, and whether the user can edit them.

### Web preview (L)

Load a web page in Cicero and set it in fonts from the library: the whole page, or the block of text clicked, with
size, line height and colors, and a set made of the fonts tried. A `WKWebView` with the fonts brought in through
`@font-face` from a custom URL scheme (`WKURLSchemeHandler`). Open: many sites' Content Security Policy blocks fonts from
anywhere but their own servers; find out how many before building it.

### Turning on a document's fonts as it opens (L, research first)

Plug-ins for InDesign and Illustrator that ask Cicero to turn on a document's missing fonts as it opens, and turn them
off when it closes. Find Fonts in Document and application sets do this by hand today. Open: whether Adobe's UXP
plug-ins can see a document opening and its missing fonts, or whether it takes the C++ SDKs, rebuilt for every Adobe
release. Catching any app's request for a missing font isn't possible with public macOS APIs.

## Small improvements

- **Notes** (S): a note per family in the Info panel, searched with the rest, and a **Note contains** smart set rule.
- **Waterfall** (S): a style at several sizes at once, 12 to 72 pt, on the font page.
- **Kerning pairs** (M): a table of a style's kerning pairs, from GPOS or the kern table, searchable by pair.
- **Preview colors** (S): text and background colors of the user's own, and a see-through window to lay a preview over
  a design.
- **Slideshow** (S): the selected or listed families one after another, full window, on a timer.
- **More documents** (M): Find Fonts in Document also for EPS, SVG, Pages, Keynote, RTF, Word, PowerPoint,
  OpenDocument, Sketch and Scribus files, and the list saved as text or CSV.
- **Font list as CSV** (S): the listed families' names, styles, foundry, designer, version, format, tags, rating and
  paths, for a spreadsheet.
- **Share** (S): send exported fonts with AirDrop or Mail from the share sheet.
- **Ask before turning on many fonts** (S): a question before turning on more than, say, 100 families at once.
- **A shortcut from anywhere** (S): a keyboard shortcut that brings Cicero forward from any app.
- **Localized names** (S): family names in the Mac's language, when the font has them.
- **A folder of Cicero's own** (M): an option to keep every font Cicero installs in one folder of its own, a subfolder per
  family, rather than loose in ~/Library/Fonts.

## Not planned

Buying fonts inside Cicero, font subscription and rental services, and team servers with accounts: Cicero has no
accounts and keeps what it knows about your fonts on your Mac.
