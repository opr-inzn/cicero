# Roadmap

Features that could come next, roughly in the order they'd come, with how each could work, what's still open and
about how big it is (S: a few hours, M: about a day). Nothing here is promised; the order changes as Cicero does.
What's done is in the [changelog](../CHANGELOG.md).

## Next

### Better similar lists (M)

**What.** Show Similar Fonts lists that look more alike, text serifs and grotesques above all, among which the lists are
least sure now.

**How.** The small model that looks at the letters learned from open-source families, four fifths of them, with the
rest kept back to test it. Train it on all of them, and on more text serifs and grotesques, where more examples made the
most difference. Judge its lists against the current ones on a library of fonts it has never seen, family by family; it
replaces the current model only when its lists are picked more often. Families marked Not Similar show where lists go
wrong.

**Open.**
- Whether a second model, trained another way, makes better lists alongside the first: so far it helps the six on a
  font page a little and makes the twelve in the list worse.
- The families to add: each needs tags for what it is (serif, grotesque, humanist and so on), set by hand.

### Similar styles (M)

**What.** Show Similar Fonts for a single style, so that an italic finds italics and a condensed style condensed ones.
Similar fonts compare families by their regular styles now.

**How.** Measure and embed every style rather than each family's regular one (about a millisecond each), and compare a
style with the others of its slant. Families' lists stay as they are.

**Open.**
- How to show a style's list: the browser lists families, so styles would need a list of their own.
- A family's own other styles: whether they belong in the list.

### Subfolders in Locations and Folders (M)

**What.** Show the folders inside a location under its row, and let folders hold other folders. A location is one row
now, with the fonts of every folder inside it, and folders are one flat list: FontExplorer X's nested sets come in as
"Folder / Sub / Set".

**How.** A location's row opens to the folders inside it that have fonts, named as on disk, each listing its fonts and
those of the folders inside it, with Reveal in Finder and Export Fonts. A folder gets a parent: drag one onto another,
or New Folder in a folder's menu. A folder lists its own families and those of the folders inside it, so Activate
Folder turns them all on. Backups from before load as a flat list; FontExplorer X imports keep their nesting.

**Open.**
- Whether a location's subfolder can be on in another way than the location (Fonts in This Location), and whether the
  Font Library, with a folder per family, shows its subfolders at all.
- What can go inside a folder: smart folders and app folders too, or folders only; and whether deleting a folder
  deletes the ones inside it or moves them up.

## Not planned

Buying fonts inside Cicero, font subscription and rental services, and team servers with accounts: Cicero has no
accounts and keeps what it knows about your fonts on your Mac.
