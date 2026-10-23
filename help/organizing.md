# Organizing your library

[Cicero Help](README.md) › Organizing your library

## The sidebar

At the top of the sidebar are these items:

| Item | Shows |
| --- | --- |
| All Fonts | Every family in your library |
| Active | Families with at least one style on |
| Inactive | Families with at least one style off |
| Temporary | Families with a style on until Cicero quits, while there are any (see [Turn a font on just for now](activating.md#turn-a-font-on-just-for-now)) |
| Recents | Families with a style that arrived on your Mac in the last week, the latest first (see [Recents](#recents)) |
| System Fonts | The fonts that come with macOS, while **Show system fonts** is on (see [System Fonts](#system-fonts)) |
| Conflicts | Things worth fixing, with a count. See [Conflicts](problems.md) |

Below them are sections: **Locations**, **Folders**, **Tags**, **Foundries**, **Classifications** and **Coverage**.

### Recents

**Recents** shows the fonts you got lately, so the ones you just added are easy to find again. A family is there for a week after a style of it arrived on your Mac, however it came: added in Cicero, copied into your Fonts folder, turned on in Adobe Fonts or put there by an installer. Fonts that come with macOS or an app don’t count, since an update gives them new dates. Turning a font off and on again doesn’t count either.

The fonts that arrived last come first, in every view. Fonts that arrived within a few minutes of each other, as when you add a folder of them, stay together in alphabetical order. In the list, click a column’s title to sort them by it instead; they’re latest first again the next time you choose **Recents**.

A font file you open where it is, without Cicero installing a copy, counts from when it arrived in its folder, so an old file doesn’t show up here.

The item you’ve selected is in the accent color. To hide the whole sidebar, choose **View → Hide Sidebar** (⌃⌘S), and **View → Show Sidebar** to bring it back.

### Open or close a section

Click anywhere on a section’s title. The groups inside **Coverage** open and close the same way. **Foundries** and **Coverage** start closed, and so do the **Unicode Blocks** and **Google Fonts** groups inside **Coverage**.

### Hide items you don’t use

1. Click **Edit** next to **Library** at the top of the sidebar, or right-click the sidebar and choose **Edit Sidebar**. Every item and section gets a checkbox. Sections stay open or closed as they were: click a section’s title to open or close it, for example to close **Foundries** and get to **Coverage** faster.
2. Uncheck what you don’t want. Unchecked items are dimmed. **All Fonts**, **Active** and **Inactive** always stay: their checkboxes can’t be unchecked.
3. Click **Done**. The unchecked items disappear.

To hide one item quickly, right-click it and choose **Hide from Sidebar**, or drag it out of the sidebar and let go, as in the Finder’s sidebar: once it’s outside, the pointer shows an ×. Dragged out, a location, folder or tag is removed rather than hidden, as below. Changed your mind? Click **Undo** in the note at the bottom of the window. Under **Coverage**, right-click a group’s title, like **Unicode Blocks**, to hide the whole group.

The same checkboxes are in **Settings → Sidebar**, in the sidebar’s order. **Show All** brings back everything you hid. There, **Foundries** has a single checkbox for the whole section; to hide individual foundries, use **Edit** in the sidebar.

When you make a new folder or coverage set, or add a location, its section shows again if you’d hidden it.

### Put items in your order

Drag items to where you want them, as in the Finder’s sidebar. An item moves within its own section: folders among your folders, locations among your locations, and so on. Character sets under **Coverage** move within their group. To reorder the groups in **Coverage**, drag a group’s title onto another: it takes that group’s place, and the groups in between move up or down one. The sections themselves stay in their place.

Items that are gone for now, like **System Fonts** while system fonts are hidden, keep their place. New items go at the end. To go back to the usual order, click **Reset Order** in **Settings → Sidebar**.

### Select several items

⌘-click or ⇧-click items in the same section to select several. The browser then shows the fonts in any of them, and the window title names them, like “Serif and Script”. Drag them to move them together.

Right-click one of the selected items for a menu that acts on all of them: delete several folders, tags or coverage sets at once, remove several locations, activate or deactivate several folders, give tags a color, export their fonts or hide them from the sidebar. Renaming and editing are for one item at a time, so they aren’t in that menu. Right-clicking an item that isn’t selected acts on that item alone.

Selected items have to be in one section, or in one group under **Coverage**. ⌘-clicking an item somewhere else starts a new selection there.

### Drop fonts onto the sidebar

Drag families from the browser onto:

- **a folder**, to add them to it
- **a tag**, to give them that tag
- **a foundry**, to say they’re from that foundry
- **a classification**, to put them in it

The item they’re over lights up in the accent color. To drop several families at once, select them and drag any one of them.

## Locations

Add folders of fonts to see their fonts in your library without activating them. They’re listed under **Locations** in the sidebar. Cicero watches these folders, so fonts you add to them or take out show up or go away by themselves.

### Add a location

Choose **File → Add Location** (⇧⌘O), click **+** next to **Locations**, or click **+** in **Settings → Locations**, and pick a folder of fonts. You can pick several folders at once.

A folder called “Fonts” is shown with the name of the folder it’s in, like “Projects Fonts”.

### What a location’s menu has

Right-click a location in the sidebar:

- **Rename Location**: gives it a name of your own in Cicero, in the sidebar, Settings and Conflicts. The folder on disk keeps its name, so apps that load fonts from it still find it. **Proofing**, **Adobe Fonts**, **Added Fonts**, **Font Library** and **Deactivated** can be renamed too. Leave the name empty to go back to the folder’s own.
- **Reveal in Finder**
- **Fonts in This Location**: **Inactive**, the usual choice, where its fonts are off until you turn them on; **Active**, where Cicero keeps them all on (see [Keep a location’s fonts on](activating.md#keep-a-locations-fonts-on)); or active in an app that loads them by itself, like **Active in Adobe apps** (see [Your own folder that an app loads](activating.md#your-own-folder-that-an-app-loads)).
- **Remove Location from Library**: Cicero stops listing it. The files stay where they are. Dragging the location out of the sidebar does the same, with **Undo** in the note at the bottom of the window. To remove several at once, select them in the sidebar and right-click one of them, or select them in **Settings → Locations** and click **−**.
- **Export Fonts**: copies its fonts into a folder or a ZIP archive. See [Export fonts](export-and-backup.md#export-fonts).

### Proofing

The fonts that Adobe apps load from their own folders, where type designers put fonts to test them, are listed together as **Proofing**, while there are any. They aren’t Adobe Fonts, which have an item of their own. **Proofing** isn’t one of your locations: you turn it on or off with **Show fonts installed for proofing in Adobe apps** under **Library** in **Settings → General** (on at first). If you add one of those folders with **+**, Cicero turns that switch on instead. Right-click **Proofing** and choose **Reveal in Finder** to see the folders. For how these fonts turn on and off, see [Fonts in Adobe apps’ folders](activating.md#fonts-in-adobe-apps-folders).

### Adobe Fonts

The fonts from Adobe Fonts, which Creative Cloud turns on, are listed as **Adobe Fonts**, while there are any, whatever **Show fonts installed for proofing in Adobe apps** says. A family of yours that Adobe Fonts also has is in it too. To hide them, turn off **Show fonts from Creative Cloud** in **Settings → General**: they’re then left out of every list, smart folders and the Character Toolbox, and **Adobe Fonts** leaves the sidebar. Families you also have yourself stay, as yours. Right-click **Adobe Fonts** and choose **Manage in Creative Cloud** to turn them on or off there. See [Adobe Fonts](activating.md#adobe-fonts).

### Font Library

Cicero’s own folder for the fonts it installs, when you keep them there. It shows while it has fonts. See [The Font Library](activating.md#the-font-library).

### Deactivated

Cicero’s own folder for fonts it moved out of your Fonts folder or an app’s folder. It shows while it has fonts. See [The Deactivated folder](activating.md#the-deactivated-folder).

### Folders in the cloud: iCloud Drive, Dropbox, Google Drive

Cloud services can keep files online only: the Finder shows them, but their contents aren’t on your Mac. Cicero leaves those fonts out, because reading them would download them. When a location has some, the browser says how many above its fonts, and **Settings → Locations** says so under it. Click **Download** to bring them down. The cloud service may take them off your Mac again later; to keep them, make the folder available offline in the Finder (right-click it and choose **Make Available Offline**, **Available offline** or **Keep Downloaded**, depending on the service).

The first time Cicero looks in a cloud service’s folder, macOS asks whether it may. If you said no, the location says “Cicero isn’t allowed to read it”: allow it in **System Settings → Privacy & Security → Files and Folders**, then click **Try Again**.

### Folders on a server or an external disk

Add a folder on a network disk or a USB drive as a location like any other. While the disk isn’t connected, its location has a question mark in the sidebar, its fonts are out of your library, and the location says “Isn’t connected”. Its fonts are back as soon as you connect the disk, and they keep their tags and their places in folders; Conflicts doesn’t list them as missing meanwhile.

Cicero sees fonts you add to a server folder from your Mac at once. Fonts someone else adds show up the next time Cicero looks, when you come back to it after a minute or more, or when you choose **Fonts → Rescan Library** (⌘R).

A location that’s gone for good, because its folder moved or was deleted, says “Can’t be found”. Remove it, and add the folder again from its new place if it moved.

### The same font from several clients

When a font is in more than one folder on your Mac, like a copy from each client, right-click the family and choose **Use Copy From**. It lists the folders the copies are in, with each one’s version, and checks the one in use. Picking one turns its copies on and turns off the copies of the same styles that Cicero turned on from the other folders, so only one is on at a time. Styles only one folder has come from there. A style’s right-click menu on its font page has **Use Copy From** for just that style. See [Use another copy of a font](activating.md#use-another-copy-of-a-font).

## Added Fonts

Font files you add one at a time are listed where they are, without being activated, like the fonts in a location. They show up together as **Added Fonts** under **Locations**, while there are any.

If you chose **Copy into ~/Library/Fonts** or **Move into ~/Library/Fonts** next to **Activate fonts by** in Settings → General, font files you add are installed instead: Cicero copies or moves them into your Fonts folder and turns them on, and they’re in **All Fonts** like any font you’ve installed, not under Added Fonts. Copied, the originals stay where they are. Moved, they’re gone from there, though the folder they were in stays; see [Copy or use in place](activating.md#copy-or-use-in-place). Fonts already under Added Fonts that you open again, or turn on by copying or moving, leave Added Fonts the same way.

### Add font files

- Choose **File → Add Fonts** (⌘O) and pick one or more font files.
- Drag font files from the Finder onto the browser or a font page. Drop them while the browser shows a folder, and they join that folder too.
- In the Finder, right-click a font file and choose **Open With → Cicero**. To have a double-click open fonts in Cicero, select a font file, choose **File → Get Info** in the Finder, pick Cicero under **Open with** and click **Change All**

Cicero reads OpenType, TrueType, font collections and datafork TrueType. It leaves out web fonts (WOFF and WOFF2), which are made for websites: Adobe apps can’t use them. Cicero then shows the fonts you added in the browser: it selects the first of them and scrolls to it. Files Cicero lists already, like those in your Fonts folder or one of your locations, are just shown. Dropping a folder adds it as a location, whichever way you activate fonts.

### Fonts already in your library

A font file you add may have fonts your library has already, from another file: a newer version of a font you installed, say, or the same file from another folder. Cicero tells them by their PostScript names, and asks what to do with each family:

- **Skip It** leaves the file out. The library’s copy stays in use, and Cicero shows it.
- **Add as Another Copy** lists or installs the file next to the library’s copy, as for any other file. You can switch between them later with [Use Copy From](activating.md#use-another-copy-of-a-font).
- **Use the Added One** adds the file and uses it in place of the library’s copy. Where that copy is on, it goes off the way deactivating turns a font off, so no font is lost: a copy Cicero installed goes to the Trash when its original is still in your library, any other file in your Fonts folder goes to Cicero’s Deactivated folder, and a font used where it is, or in Cicero’s [Font Library](activating.md#the-font-library), just turns off. Then the added one goes on, the way you activate fonts; when Cicero asks each time, it’s installed in place of a copy in your Fonts folder, else used where it is. A copy under Added Fonts that the added file replaces stops being listed. Fonts that come with macOS or an app, and Adobe Fonts, stay on; apps may then get those.

The sheet says how many styles of each family the file has, which versions you have and where, and whether the added one is **Newer**, **Older**, the **Same Version** or the **Same File**. Each family starts at **Use the Added One** when the added one is newer, else at **Skip It**; **Choose for All** sets them all at once. **Add** adds the files, those with no fonts in your library included, and **Cancel** adds none of them.

To stop being asked, choose next to **When an added font is already in your library** in Settings → General: **Add it as another copy**, **Skip it**, **Use the added one**, or **Keep the newer version**, which uses the added one when its version is newer and skips it otherwise. Locations you add, and files **Find on This Mac** turns up for a document, are added as they are.

When a file you added changes, as when you build a new version of a font you’re making, Cicero reads it again.

### Remove them again

Right-click families from added files and choose **Remove from Library**. Cicero stops listing them; the files stay where they are. A font you turned on stays listed until you turn it off.

A file you added that’s deleted later, or whose folder you move or rename, leaves the library by itself. If it’s back within 30 days, as when you rename the folder back or sign in to a cloud service again, so is its font. One on a disk that isn’t connected stays, and is back when you connect the disk.

Right-click **Added Fonts** and choose **Reveal in Finder** to see the files.

## Folders

A folder is a list of families you put together by hand, like the fonts for one project. It’s Cicero’s own: the font files stay where they are. It can have some styles of a family rather than all of them, like just the Regular and Bold you use.

### Make a folder

- Choose **File → New Folder** (⇧⌘N). The families you’ve selected go into it.
- Or click **+** next to **Folders** and choose **New Folder**
- Or right-click selected families and choose **Add to Folder → New Folder from Selection**

### Add and remove fonts

- Drag families onto the folder in the sidebar.
- Or right-click families and choose **Add to Folder**, then the folder. A checkmark shows the folders they’re already in; choose a checked folder to take them out again.
- To add a single style, open the family’s font page and drag the style’s row from **Styles** onto the folder, or right-click the style and choose **Add Style to Folder**, then the folder, or **New Folder with Style**. A checkmark shows the folders that have the style; choose a checked folder to take it out. Activating, deactivating and exporting the folder then take only the styles it has, and so does an [app folder](activating.md#turn-fonts-on-with-an-app).

### Rename or delete a folder

Right-click the folder and choose **Rename Folder** or **Delete Folder**, or drag the folder out of the sidebar to delete it, with **Undo** in the note at the bottom of the window. Deleting a folder keeps its fonts in your library. Smart folder rules that use the folder are removed.

### Turn a folder’s fonts on or off

Right-click the folder and choose **Activate Folder**, **Activate Temporarily** or **Deactivate Folder**. Smart folders have the same items. See [Turn on a whole folder](activating.md#turn-on-a-whole-folder).

A folder can also turn its fonts on while an app is open, as an app folder. See [Turn fonts on with an app](activating.md#turn-fonts-on-with-an-app).

## Smart folders

A smart folder picks its families by rules, and stays up to date as your library changes.

### Make a smart folder

1. Choose **File → New Smart Folder** (⌥⌘N), or click **+** next to **Folders** and choose **New Smart Folder**
2. Give it a name.
3. Next to **Match**, choose **All of the rules** or **Any of the rules**.
4. Set up each rule: a field, a comparison and a value. Click the **+** at the end of a rule to add one after it, or **−** to remove it.
5. Watch the count at the bottom, like “24 families match”, and click **Create**.

To change it later, right-click it and choose **Edit Smart Folder**. To remove it, choose **Delete Smart Folder**.

### Rules you can use

| Field | Comparisons | Value |
| --- | --- | --- |
| Name | contains, doesn’t contain, begins with, is | Text, matched against the family’s name and the one it shows in your Mac’s language |
| Foundry | is, is not, contains | A foundry, or text for “contains” |
| Designer | contains, doesn’t contain, is | Text, matched against the designer any of the family’s styles credits |
| Classification | is, is not | Serif, Sans Serif, Monospaced, Script, Ornamental, Symbol or Unclassified |
| Tag | is, is not | One of your tags |
| Rating | is, is not, is more than, is less than | No Rating, or one to five stars (see [Ratings](#ratings)) |
| Note | contains, doesn’t contain | Text in the family’s [note](#notes) |
| Has Note | Yes, No | Whether the family has a [note](#notes) |
| Folder | is in, isn’t in | One of your folders |
| Location | is in, isn’t in | One of your locations, Proofing, Adobe Fonts, or Added Fonts |
| Status | is, is not | Active, Partly Active, Inactive, Active in Adobe Apps Only or Installed with macOS. **Active in Adobe Apps Only** is there while **Show fonts installed for proofing in Adobe apps** is on, for the fonts only Adobe apps load (see [Fonts in Adobe apps’ folders](activating.md#fonts-in-adobe-apps-folders)) |
| Kind | is, is not | Italic, for a family with italic styles, Monospaced or Variable |
| Format | is, is not | OpenType PostScript, OpenType TrueType, Font Collection, Datafork TrueType and others |
| Number of Styles | is, is more than, is less than | A number |
| OpenType Feature | is supported, isn’t supported | Small Capitals, Old-Style Figures, Tabular Figures, Fractions, Stylistic Sets, Swashes and others, in any of the family’s styles |
| Embedding | is, is not | Installable, Editable, Preview & Print or Restricted: what the font’s license lets a document do with it, as its files say. A family’s is its most restrictive style’s |
| Language | is supported, isn’t supported | A language, chosen from a searchable list that starts with yours |
| Coverage | includes, doesn’t include | Any built-in set or one of your coverage sets |
| Date Added | is in the last, isn’t in the last | A number of days |

A smart folder with a language or coverage rule can grow for a while after launch, as Cicero checks the characters in each font. The subtitle says so while it does.

Smart folders with a **Times Activated** or **Last Activated** rule, made with an earlier version of Cicero or [imported from FontExplorer X](getting-started.md#fontexplorer-x), keep it, though new rules no longer offer them.

## Tags

Mark families with tags, which show as colored dots next to their names in the list, grid and specimens. A family can have as many tags as you like. Cicero comes with tags for keeping track of what you may do with each family, given to no family to begin with:

| Tag | Color |
| --- | --- |
| Licensed | Green |
| Unlicensed | Red |
| Open Source | Blue |
| Trial | Orange |

They’re tags like any other: rename them, delete them, or make your own. Libraries from before Cicero 0.5 get these too, once, and keep their own tags; the Red, Yellow and Green tags a library started with go if you never used them. Libraries from Cicero 0.9.1 and before also lose the Licensed + Non-Commercial, Partially Licensed and Public Domain tags they started with, once, if you never used them. From 0.5 to 0.6 a family had one tag at a time; the tags families had then, they keep.

### Tag fonts

- Right-click families and choose **Tags**, then a tag. A checkmark shows the tags they have; choose a checked one to take it off. **Remove All Tags** takes every tag off them, and **New Tag** makes a tag and gives it to them. The families keep the tags they have.
- On a font page, right-click the text, the header or a style for the same menu.
- Drag families onto a tag under **Tags** in the sidebar.
- In the [Info panel](browsing.md#see-a-fonts-details), click **Change** next to **Tags**.

### Make, change and delete tags

- Click **+** next to **Tags** in the sidebar to make a tag. Type a name and click a color under it, or the struck-through circle for none. The color starts on the first one no other tag has.
- Right-click a tag and choose **Rename Tag**, a color under **Color** (or **None**), or **Delete Tag**, or drag the tag out of the sidebar to delete it, with **Undo** in the note at the bottom of the window. Deleting a tag takes it off every family, and smart folder rules that use it are removed.

Select a tag in the sidebar to see the families that have it. To find families with several tags, any of several, or without one, make a [smart folder](#smart-folders) with **Tag** rules: **Tag** **is** a tag picks the families that have it, among their others.

## Ratings

Give a family one to five stars, to pick out your favorites or the ones you’d rather not use again.

- Right-click families and choose **Rating**, then the stars. A checkmark shows the rating they have; **No Rating** takes it away.
- On a font page, right-click the text, the header or a style for the same menu.
- In the [Info panel](browsing.md#see-a-fonts-details), click a star under **Rating**. Click the one it has again to take the rating away.

A rated family shows its stars in the grid and specimens. To see ratings in the list, right-click the column headers and choose **Rating**; click its header to sort by it. To keep your favorites together, make a [smart folder](#smart-folders) with a **Rating** rule, like **Rating** **is more than** ★★★.

## Notes

Write a note on a family: where its license is, which client it’s for, what it pairs well with. In the [Info panel](browsing.md#see-a-fonts-details), click under **Note** and type, pressing Return for a new line; Cicero saves it as you go. Delete the text to take the note away.

A family with a note has a small note symbol next to its name in the grid and specimens; hold the pointer over it to read the note. Searching finds families by their notes too. To keep families with notes together, make a [smart folder](#smart-folders) with a **Note** rule, like **Note** **contains** Acme, or **Has Note** **Yes** for every family with a note and **Has Note** **No** for every family without one.

## Foundries

Cicero reads each family’s foundry from the manufacturer name in its files, and tidies it up: it drops endings like “Inc.” or “GmbH”, leaves out web addresses and copyright lines, and puts names that differ only in capitals together.

- **Rename a foundry:** right-click it and choose **Rename Foundry**. Every family from that foundry follows.
- **Change a family’s foundry:** drag the family onto another foundry in the sidebar.

## Classifications

Cicero sorts families into Serif, Sans Serif, Monospaced, Script, Ornamental, Symbol and Unclassified, and shows the ones your library has. Slab serifs count as Serif. To decide, it goes through these in turn and stops at the first that says something:

1. The classification the font gives itself.
2. Words in the name, like “Mono”, “Stencil”, “Slab”, “Sans”, “Grotesk”, “Script” or “Symbol”.
3. The shapes of the letters. An I and an l with feet on both sides are serif, plain ones sans serif, and letters all as wide as each other monospaced. Letters that are none of these, like a script’s, say nothing.
4. The font’s PANOSE numbers, another way fonts can say what they are.
5. With **Classify fonts automatically** on in **Settings → General**, a classification Cicero recognizes, on your Mac:
   - On macOS 26 with Apple Intelligence on, from the family’s name, when the name says. The Info panel says “Recognized from its name by Apple Intelligence” under such a classification.
   - Otherwise from the shapes of its letters, when Cicero is sure enough: it tells serif, sans serif, script and ornamental letters apart, italics, display and variable fonts too, the way it learned to from thousands of freely licensed fonts. The Info panel says “Recognized from the shapes of its letters”.

   Cicero asks whether to classify fonts automatically the first time it opens. Turn **Classify fonts automatically** off, and those classifications go: the families are Unclassified again.

A family none of them tells stays Unclassified, rather than ending up in the wrong classification.

- **Make your own classification:** click **+** next to **Classifications**, or choose **Classification → New Classification** from a family’s right-click menu to put it straight in. Yours stay in the sidebar even while they’re empty.
- **Put a family in another classification:** right-click it and choose one from **Classification**, use **Change** next to **Classification** in the Info panel, or drag it onto a classification in the sidebar. To keep a family where Cicero put it, choose that classification: a later version of Cicero, or a classification it recognizes later, won’t move it. **Automatic** puts it back where its fonts say it belongs. Your choices are saved with your library, so they’re the same each time Cicero opens, and backups include them.
- **Rename a classification:** right-click it and choose **Rename Classification**. This works for Cicero’s own too; give one its old name back to undo that. Smart folders follow.
- **Delete one of yours:** right-click it and choose **Delete Classification**. Its families go back to the classifications their fonts suggest.
- **Hide a classification:** click **Edit** at the top of the sidebar and uncheck it, or choose **Hide from Sidebar** from its right-click menu.

## System Fonts

**System Fonts** shows the fonts that come with macOS. They’re always on, and Cicero can’t turn them off.

To keep them out of your lists, open **Settings → General** and turn off **Show system fonts**. They’re then hidden everywhere: in every list, in smart folders, in the Character Toolbox, and **System Fonts** leaves the sidebar too.

## Coverage

The **Coverage** section shows which fonts have every character of a set, like Latin S or Adobe Latin 3. See [Character sets and languages](character-sets.md).
