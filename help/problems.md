# Problems

[Cicero Help](README.md) › Problems

Click **Problems** in the sidebar to see what Cicero found wrong with your fonts. The number next to it counts the problems, not counting [Shared Style Names](#shared-style-names). When there’s nothing to fix, it says “No Problems”.

Problems are in groups. Each group starts with a short explanation, then shows a card per font, with its files and buttons to fix it. To look again after you’ve changed something outside Cicero, click **Check Again** in the toolbar.

## How files are shown

- When several files of a problem are in the same folder, they share one row: the folder, their versions and dates, and “18 files” to show them one by one. Each file has its own buttons too.
- **Reveal** shows the files in the Finder.
- Buttons that move files to the Trash ask first, and you can put the files back from the Trash.

Cicero never moves files that come with macOS or an app to the Trash, and never offers to remove a file that holds the only copy of a style.

## Installed Twice

The same font is on from more than one file. macOS uses only one of them, so apps may get an older version.

Each card is one family, like “Active from 2 files” or “3 styles active from 6 files”, with every file and where it is. To fix it, keep one copy and take the others away:

- **Deactivate** turns off a copy Cicero can turn off. See [Turn fonts off](activating.md#turn-fonts-off) for what happens to its file.
- **Remove Copy** moves a copy Cicero can’t turn off to the Trash, when every style in it has another copy.
- A folder’s row has **Deactivate** or **Remove Copies** for all its files at once, when every style keeps a copy outside that folder.
- A green **Newest** tag marks the folder or file with the highest version, when all the others are older. It’s usually the one to keep.

## Missing Files

Cicero remembers these files, but they’re gone.

- **A font used where it was:** its file moved, so the font no longer works. If you moved it on purpose, add its new folder and turn it on again. **Forget** tells macOS to stop looking for it, and clears Cicero’s note of it. A file on a disk that isn’t connected, or in one of your folders that can’t be found, is under [Fonts on External Disks](#fonts-on-external-disks) instead.
- **A copy Cicero installed:** the copy is gone from your Fonts folder. **Forget** clears Cicero’s note of it.
- **A family in a set that’s no longer in your library:** **Remove from Set** takes it out of the set. Families that are only away for now, on a disk that isn’t connected or online only in a cloud folder, aren’t listed.

## Damaged or Unreadable Files

Cicero couldn’t read these files. They may be damaged, or not font files at all. Use **Reveal** to look at them, or **Move to Trash** to remove one.

## Fonts on External Disks

These fonts are used from a disk that can be unplugged, like a USB drive or a network disk, so they turn off when it’s gone. **Install a Copy Instead** copies the font into your Fonts folder, so it keeps working without the disk.

While the disk isn’t connected, its fonts are listed here as “Used where it is, on “Server”, which isn’t connected”. Connect it and they work again. If the disk is gone for good, **Forget** tells macOS to stop looking for the font and clears Cicero’s note of it.

## Duplicates

The same font is in one place in your folders more than once, as files that aren’t on, like twice in one client’s folder.

Copies in different places, like one in each client’s folder, aren’t duplicates: they’re the places [Use Copy From](activating.md#use-another-copy-of-a-font) lets you choose between. Each folder you added is a place, unless it holds copies of a style in different folders inside it, like `Clients/Acme` and `Clients/Globex`: then those are places of their own.

**Move Extra Copies to Trash** keeps one copy of each style and moves the others to the Trash. It keeps the file Cicero installed a copy from, if there is one, and otherwise the one with the highest version, then the newest. With only one extra copy, the button says **Move to Trash**

## Shared Style Names

A minor note, shown closed at the bottom. Open it to see the cards.

Every font has its own main PostScript name, but variable fonts also give each named style a PostScript name, and some use just “Bold” or “Light”. When fonts that are on share one of these names, macOS gives it to only one of them, and a document set in the other may open in the wrong font.

Each card lists the families that share names, which names they share, and one row per file. A blue **Preferred** tag marks a file that macOS gives all of its shared names to; hold the pointer over it to see them. A file that gets only some of them says which, like “Preferred for Light Oblique and Bold Oblique”.

Usually there’s nothing to do. If a document opens in the wrong font, **Deactivate** the font you don’t need, or get an updated version of it.
