# Roadmap

Features that could come next, roughly in the order they'd come, with how each could work, what's still open and
about how big it is (S: a few hours, M: about a day). Nothing here is promised; the order changes as Cicero does.
What's done is in the [changelog](../CHANGELOG.md).

## Next

### Similar styles (M)

**What.** Show Similar Fonts for a single style, so that an italic finds italics and a condensed style condensed ones.
Similar fonts compare families by their regular styles now.

**How.** Measure and embed every style rather than each family's regular one (about a millisecond each), and compare a
style with the others of its slant. Families' lists stay as they are.

**Open.**
- How to show a style's list: the browser lists families, so styles would need a list of their own.
- A family's own other styles: whether they belong in the list.

## Not planned

Buying fonts inside Cicero, font subscription and rental services, and team servers with accounts: Cicero has no
accounts and keeps what it knows about your fonts on your Mac.
