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

## Not planned

Buying fonts inside Cicero, font subscription and rental services, and team servers with accounts: Cicero has no
accounts and keeps what it knows about your fonts on your Mac.
