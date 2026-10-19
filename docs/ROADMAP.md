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

## Not planned

Buying fonts inside Cicero, font subscription and rental services, and team servers with accounts: Cicero has no
accounts and keeps what it knows about your fonts on your Mac.
