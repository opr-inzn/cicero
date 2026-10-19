# Roadmap

Features that could come next, roughly in the order they'd come, with how each could work, what's still open and
about how big it is (S: a few hours, M: about a day). Nothing here is promised; the order changes as Cicero does.
What's done is in the [changelog](../CHANGELOG.md).

## Next

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

## Small improvements

- **Notes** (S): a note per family in the Info panel, searched with the rest, and a **Note contains** smart set rule.
- **Similar styles** (M): Show Similar Fonts for a single style, so an italic finds italics and a condensed style condensed
  ones; similar fonts compare families by their regular styles now.
- **Font list as CSV** (S): the listed families' names, styles, foundry, designer, version, format, tags, rating and
  paths, for a spreadsheet.
- **Ask before turning on many fonts** (S): a question before turning on more than, say, 100 families at once.
- **Localized names** (S): family names in the Mac's language, when the font has them.
- **A folder of Cicero's own** (M): an option to keep every font Cicero installs in one folder of its own, a subfolder per
  family, rather than loose in ~/Library/Fonts.

## Not planned

Buying fonts inside Cicero, font subscription and rental services, and team servers with accounts: Cicero has no
accounts and keeps what it knows about your fonts on your Mac.
