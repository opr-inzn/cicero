# Conflicts

[Cicero Help](README.md) › Conflicts

Click **Conflicts** in the sidebar to see what Cicero found wrong with your fonts. When there’s nothing to fix, it says “No Conflicts”.

Conflicts are in groups. Each group starts with a short explanation, then a table of its files, with buttons to fix them. The list updates automatically, including for changes made outside Cicero.

Type in the search field to show only the conflicts whose family name, file name or folder has what you type.

## How files are shown

- The list fills the window, like the font list. Under each group’s explanation are the column names: Name, Path, Version, Modified and Details. They stay at the top while you scroll through the group. Drag the line to the left of a column name to make that column wider in every group, for example to see a whole folder path. Hold the pointer over a cut text to read all of it.
- Each file has its own row. In Extra Copies, each family has a heading over its files.
- To move files to the Trash, select them with the checkbox next to their names. The bar at the bottom says how many files will go, and **Move to Trash** asks first. You can put the files back from the Trash.
- Right-click a file and choose **Show in Finder** to see it in the Finder.

Cicero never moves files that come with macOS or an app to the Trash, and never lets you select a file that holds the only copy of a style. A copy from Adobe Fonts doesn’t count as one: Creative Cloud takes it away when the font is deactivated there, so one of your own copies always stays.

## Extra Copies

The same font is in more than one file. If more than one copy is active, macOS uses only one, so apps may get an older version.

Families with copies that are active come first. Then come families with the same file more than once in one place in your locations, while they’re inactive, like twice in one client’s folder.

- The extra copies start selected. Cicero keeps one copy of each style: the file Cicero installed a copy from, if there is one, and otherwise the one with the highest version. **Deselect All** clears the checkboxes, and **Select Extra Copies** selects them again.
- Each style always keeps one copy. When you select the copy that would stay, the other one is deselected.
- A green **Newest** tag marks the file with the highest version, when some others are older. It’s usually the one to keep.
- A copy from [Adobe Fonts](activating.md#adobe-fonts) can’t be selected: only Creative Cloud can deactivate it. Your own copy next to it can be selected, but then only the copy from Adobe Fonts is left, and Creative Cloud can remove it at any time. Cicero warns you before it moves your copy to the Trash. **Manage in Adobe Fonts** opens the family’s page on the Adobe Fonts website, or **Manage in Creative Cloud** opens the Creative Cloud app. Deactivate the font there, and Creative Cloud takes its copy away.

Copies in different places, like one in each client’s folder, aren’t extra copies: they’re the places [Use Copy From](activating.md#use-another-copy-of-a-font) lets you choose between. Each location you added is a place, unless it holds copies of a style in different folders inside it, like `Clients/Acme` and `Clients/Globex`: then those are places of their own.

## Missing Files

Cicero remembers these files or families, but they can’t be found. They may have been moved or deleted.

- **A font installed from its own folder** (“Installed from its own folder, now missing”): its file moved or was deleted, so the font no longer works. If you moved it on purpose, add its new folder as a location and activate it again. **Forget** tells macOS to stop looking for it, and clears Cicero’s record of it. A file on a disk that isn’t connected, or in one of your locations that can’t be found, is under [Unavailable Fonts](#unavailable-fonts) instead.
- **A copy Cicero installed** (“Copy missing from ~/Library/Fonts” or “Copy missing from Cicero’s Library”): the copy is gone from your Fonts folder or Cicero’s Library. **Forget** clears Cicero’s record of it.
- **A family in one of your folders whose fonts are missing** (“Listed in “Favs”, now missing”): **Forget Family** takes the whole family out of the folder. Families that are only away for now, on a disk that isn’t connected or online only in a cloud folder, aren’t listed.

With more than one missing item, **Forget All** at the top forgets them all at once, families missing from folders too.

## Damaged or Unreadable Files

Cicero couldn’t read these files. They may be damaged or not valid font files. Select any you want to move to the Trash. None are selected at first.

## Unavailable Fonts

These fonts are installed from their own folder on a disk or location that isn’t available now, so they’re inactive. A disk that isn’t connected says “Disk “Server” isn’t connected”. A location that can’t be found or read says ““Client Fonts” can’t be found” or “No access to “Client Fonts””.

Connect the disk, or make the location available again, and the fonts work again. If it’s gone for good, **Forget** tells macOS to stop looking for the font and clears Cicero’s record of it.

Fonts used from a disk that is connected aren’t listed: they work as long as the disk stays connected.

## Shared Style Names

A minor note, at the bottom. It doesn’t count toward the number of conflicts at the top of the window.

Every font has its own main PostScript name, but variable fonts also give each named style a PostScript name, and some use just “Bold” or “Light”. When active fonts share one of these names, macOS assigns it to only one of them, and a document set in the other may open in the wrong font.

Each heading lists the families that share names and which names they share, with one row per file under it. A blue **Preferred** tag marks a file that macOS gives all of its shared names to; hold the pointer over it to see them. A file that gets only some of them says which, like “Preferred for Light Oblique and Bold Oblique”.

Usually there’s nothing to do. If a document opens in the wrong font, **Deactivate** the font you don’t need, or get an updated version of it.
