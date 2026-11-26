# Roadmap

Features that could come next, roughly in the order they'd come, with how each could work and what's still open.
Nothing here is promised; the order changes as Cicero does. What's done is in the [changelog](../CHANGELOG.md).

## Next

### Subfolders in Locations and Folders

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

### Search licenses and descriptions

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

### Vault

**What.** A place for your fonts' licenses and the files that come with them that Cicero can't use: license PDFs,
receipts, web fonts (WOFF and WOFF2) and the ZIP a foundry sends. One family can have several licenses, one for each
client: Söhne for one client with all 12 styles, and for another with only 2 styles of an older version. Dropping a web
font now only says Cicero can't use it, and licenses are kept only as tags and notes.

**How.**
- Vault is an item in the sidebar's Library section, listing licenses grouped by owner. A license has an owner (a name
  you type, with the ones used before suggested), a name, kinds (Desktop, Web, App, Trial, Other), a project or domain,
  a date, an end date, a note, its files and the styles it covers.
- Dropping files or a ZIP on Vault, or Save in Vault on the web font toast, opens a sheet. Cicero copies the files into
  ~/Cicero/Vault/Owner/License (it never moves the originals), unpacks a ZIP, guesses the kinds from the files (OTF
  gives Desktop, WOFF2 gives Web) and links each font file to its style in the library, style by style, not by family.
- A license's page shows its details, the styles it covers with the library's version beside each, and its files, with
  Quick Look and Show in Finder.
- The Info panel lists a family's licenses, each with its owner and how many of the styles it covers, never only
  "Licensed". A license that covers only some styles is marked.
- The Vault's fonts aren't in the library: not scanned, listed or turned on. Conflicts, Replace and Move to Trash never
  touch them. Deleting a license moves it and its files to the Trash, with Undo. Files stay exactly as they came.
- Back Up Library gets "Include the Vault", on by default, with its count and size: the license PDFs are the proof.

**Open.**
- Whether a ZIP is kept too, next to its unpacked files, so everything stays as it came, at twice the space.
- Whether one Vault item is enough, or each owner gets its own sidebar item.
- Whether the font page's styles table shows whom each style is licensed for.
- Whether Cicero can read the names in WOFF and WOFF2 files to link them, or links web fonts through the desktop fonts
  next to them.
- Later, not in the first version: turning on a license's own version of a font for an old job (through Use Copy
  From), and exporting one owner's files for a developer or a printer. Installing fonts from the Vault stays out until
  then, since an old version could replace a newer one.

## Not planned

Buying fonts inside Cicero, font subscription and rental services, and team servers with accounts: Cicero has no
accounts and keeps what it knows about your fonts on your Mac.

A version for Windows, and a universal app for Macs with Intel processors: Cicero runs on macOS 15 or later on Apple
silicon only.
