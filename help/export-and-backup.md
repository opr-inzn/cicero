# Export, backup and restore

[Cicero Help](README.md) › Export, backup and restore

## Export fonts

Export copies font files into a folder or a ZIP archive, for sending them to someone or to a printer.

### Export the fonts you choose

1. Select the families in the browser.
2. Choose **File → Export Fonts…** (⇧⌘E), or right-click them and choose **Export…**
3. Pick a place and a name. Next to **Format**, choose **Folder** or **ZIP Archive**.
4. Click **Export**. Cicero shows the result in the Finder.

With no family selected, **File → Export Fonts…** exports every family in the browser: everything the sidebar item and search show.

### Export a set, folder or other sidebar item

Right-click a set, smart set, folder, foundry, classification or character set in the sidebar and choose **Export Fonts…**. The export is named after it.

For **All Fonts**, **Activated**, **Not Activated** or **System Fonts**, select the item, make sure no family is selected, and choose **File → Export Fonts…**

### What’s in an export

- A folder for each family, with its files. When you export one family, its files go straight into the folder.
- Each file once, even when it holds several styles or families. Only the file each style is using, not its other copies.
- No fonts that come with macOS or an app, and no Adobe Fonts. The message afterwards says how many were left out.

If the place you pick already has something with that name and you choose to replace it, Cicero moves the old one to the Trash once the export is complete; if the export fails or you cancel, the old one stays. It never writes over files, and it won’t replace a folder that holds fonts Cicero uses, like your Fonts folder or a watched folder: choose another name or place.

Before you send fonts to someone, check that their licenses allow it.

## Back up your library

A backup is one `.cicerobackup` file with everything you set up in Cicero, and your font files if you like. Use it to keep your setup safe, or to move it to another Mac.

1. Choose **File → Back Up Library…**, or click **Back Up…** under **Backup** in **Settings → General**.
2. **Include font files**, checked at first, puts your fonts in the backup too; uncheck it for a backup of your setup alone. Cicero shows how many files that is and how much space they take, like “3,812 files, 2.4 GB”.
3. Click **Back Up…**, pick a place, and click **Back Up**. The name is like “Cicero Backup 2026-10-13” at first.

A bar shows how it’s going, and **Cancel** stops it. When it’s done, Cicero shows the file in the Finder.

### What a backup holds

- your sets (with the apps of application sets), smart sets and character sets
- your folders, and what you chose under **Fonts in This Folder**
- foundry names you changed, and the families you moved to another foundry
- the sidebar: what’s hidden, the order, and which sections are open
- the settings for how Cicero activates fonts, **Show system fonts** and **Show fonts installed for Adobe apps**
- which fonts Cicero turned on, and how
- with **Include font files**: every font file in your library, other copies included, except the ones that come with macOS or an app, and Adobe Fonts

A backup doesn’t hold settings that belong to one Mac: the appearance, **Open at login**, the update setting, the preview options and the list’s columns.

## Restore a backup

1. Choose **File → Restore Library…**, or click **Restore…** under **Backup** in **Settings → General**.
2. Choose a `.cicerobackup` file.
3. Cicero asks “Restore the Backup from” and the date it was made. Choose what to restore:
   - **Sets, folders and settings** says what’s in the backup, like “4 sets, 2 smart sets, 3 folders and 1 character set”. It replaces what you have set up now. Cicero saves your current setup first, in `~/Library/Application Support/Cicero/Backups`.
   - **Font files**, when the backup has them, puts each font back where it was, unless a file is already there.
4. Click **Restore**.

When it’s done, a message says what came back, like “Restored 4 sets and 3,790 fonts; 22 were already there.”

### How fonts go back

- Nothing is written over. A file that’s already in its place stays as it is.
- Cicero puts only font files back, and only into font folders. Folders that are missing are made.
- Paths in your home folder move with you, so a backup works on another Mac or under another user name.
- A file that can’t go back where it was, for example because the folder belongs to an app that isn’t installed, like `/Applications/Adobe InDesign 2025/Fonts`, goes into a folder called **Fonts Restored from Cicero** in your home folder, under the same path. Cicero adds that folder to your library.
- Fonts that were used where they are get turned on again. Copies Cicero installed count again when both the copy and the original are back. Fonts that were on only temporarily stay off.
