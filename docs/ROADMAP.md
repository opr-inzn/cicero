# Roadmap

Features that could come next, roughly in the order they'd come, with how each could work, what's still open and
about how big it is (S: a few hours, M: about a day). Nothing here is promised; the order changes as Cicero does.
What's done is in the [changelog](../CHANGELOG.md).

## Next

### Better similar lists (M)

**What.** Show Similar Fonts lists that look more alike, text serifs and grotesques above all, among which the lists are
least sure now.

**How.** The small model that looks at the letters learned from every open-source family Cicero trains on. Train it on
more text serifs and grotesques, where more examples made the most difference. Judge its lists against the current ones
on a library of fonts it has never seen, family by family; it replaces the current model only when its lists are picked
more often.

**Open.**
- The families to add: each needs tags for what it is (serif, grotesque, humanist and so on), set by hand.

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

### Search licenses and descriptions (M)

**What.** Let the search field find words in each font's license, license URL and description, as `cicero find` does:
"rosettatype.com" finds the families whose license points there, and "sturdy serif" can find "sturdy" in a description
and "serif" in a name. The search field looks only at names, foundries and the like now.

**How.** Read the license, its URL and the description (name IDs 13, 14 and 10) when Cicero scans a font, and keep them
with the rest of what it knows about the font, so the search field doesn't open the files on every key press. `cicero
find` reads them from the files each time, about a second for 7,000 styles; it would read the saved ones too. The words
match as they do now: each word must begin a word somewhere in the family. Show the description in the Info panel.

**Open.**
- Common words: most licenses say "font", "software" and "free", so "free" would find nearly every family. Whether
  license words count only when nothing else matches, only for words that look like a web address, or only after a
  choice such as "Search Licenses Too".
- How to show why a family was found when the word isn't in its name: a line under the card, or the Info panel opened
  to it.
- Libraries saved before: whether Cicero reads every font again once, or fills in the texts as it opens each file.

## Not planned

Buying fonts inside Cicero, font subscription and rental services, and team servers with accounts: Cicero has no
accounts and keeps what it knows about your fonts on your Mac.
