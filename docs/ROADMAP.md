# Roadmap

Features that could come next, roughly in the order they'd come, with how each could work, what's still open and
about how big it is (S: a few hours, M: about a day). Nothing here is promised; the order changes as Cicero does.
What's done is in the [changelog](../CHANGELOG.md).

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

### Cicero in Spotlight (M, in progress)

**What.** Cicero's own information becomes searchable in Spotlight: type a family's name, or "Licensed serif", and
families from Cicero's library show among the results; choosing one opens its font page in Cicero.

**Why not a classic Spotlight importer.** macOS already has one for font files (`/System/Library/Spotlight/Font.mdimporter`):
every font file's names, designer, foundry, version and copyright are in Spotlight, with or without Cicero. What only
Cicero knows is the user's own: tags, ratings, classifications, sets and smart sets.

**How.** Core Spotlight (`CSSearchableIndex`), one item per family:
- title: the family name
- description: "Serif · Carter & Cone · Licensed · ★★★★"
- keywords: its tags, sets, smart sets, classification, foundry, designers, and every style's name, full name and
  PostScript name
- thumbnail: "Ag" set in its regular style, made only when its item changes

Items change when the library or the user's data does (gathered for a moment, not on every change) and go when their
family does. Choosing a result reaches Cicero as a `CSSearchableItemActionType` user activity, which selects the family
and opens its page. The index stays on the Mac. Settings → General gets a switch for it; turning it off deletes the
items.

Not this way: writing Finder tags onto the font files for Cicero's tags. That changes the user's files.

**Settled**, measured on a library of 1,180 families and 7,637 styles (`spotlight` branch):
- **Thumbnails are cheap to make.** About 1.5 ms a family on one core (making the font from the file the prefetch has
  read, drawing, encoding a PNG): under two seconds for the library, 2.4 KB each at 128 pixels, 2.8 MB in all. HEIC
  was a third smaller but took 80 seconds. Core Spotlight takes about 5 seconds to index the families with
  thumbnails, 2 to 2.5 without them; the first index, thumbnails included, took 7 seconds in the background, and later
  launches index only what changed (nothing, when nothing did).
- **No items for styles.** A style's PostScript or full name is among its family's keywords, so "HelveticaNeue-BoldItalic"
  finds Helvetica Neue. Styles as items of their own would be 6.5 times as many (10 seconds to index), and they crowd
  the families out: Core Spotlight's own search stops at 40 results, and a family's name gave 40 of its styles and
  not the family.

**Seen in Spotlight** (macOS 26.6, Dark Mode, with a test copy):
- A family's item can come first ("Helvetica Neue"), with its description under the name. Searching a PostScript name
  ("HelveticaNeue-BoldItalic") or a tag with a classification ("licensed sans") finds it.
- The thumbnail takes the place of the icon, with Cicero's icon small in its corner. Spotlight shows `thumbnailData`
  but not `thumbnailURL` or `darkThumbnailURL`, so one picture serves both appearances: black letters on a clear
  ground all but disappeared in Dark Mode, so the letters are on a white card, as Spotlight shows font files.
- Spotlight lists the font files of every style anyway ("HelveticaNeueLTStd-Roman.otf"), one more reason not to add
  items for styles.
- Choosing an item opens its font page, also with the main window closed. An app run from a temporary folder
  (`/private/tmp`) gets its items shown but can't open them, and has a blank icon.

**Still open.**
- A report from the macOS 27 betas says Spotlight there shows App Intents entities (`IndexedEntity`) but not plain
  Core Spotlight items. If so, each item needs an App Entity, which needs Xcode's `appintentsmetadataprocessor` in
  `build-app.sh`. Not testable on macOS 26.
- Return opens Spotlight's top hit, which for a family's name is often its font file, not Cicero's item.

## Small improvements

- **Notes** (S): a note per family in the Info panel, searched with the rest, and a **Note contains** smart set rule.
- **Font list as CSV** (S): the listed families' names, styles, foundry, designer, version, format, tags, rating and
  paths, for a spreadsheet.
- **Ask before turning on many fonts** (S): a question before turning on more than, say, 100 families at once.
- **Localized names** (S): family names in the Mac's language, when the font has them.
- **A folder of Cicero's own** (M): an option to keep every font Cicero installs in one folder of its own, a subfolder per
  family, rather than loose in ~/Library/Fonts.

## Not planned

Buying fonts inside Cicero, font subscription and rental services, and team servers with accounts: Cicero has no
accounts and keeps what it knows about your fonts on your Mac.
