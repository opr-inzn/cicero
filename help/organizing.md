# Organizing your library

[Cicero Help](README.md) › Organizing your library

## The sidebar

At the top of the sidebar are five items that are always there:

| Item | Shows |
| --- | --- |
| All Fonts | Every family in your library |
| Active | Families with at least one style on |
| Inactive | Families with at least one style off |
| System Fonts | The fonts that come with macOS, while **Show system fonts** is on (see [System Fonts](#system-fonts)) |
| Problems | Things worth fixing, with a count. See [Problems](problems.md) |

Below them are sections: **Folders**, **Sets**, **Tags**, **Foundries**, **Classifications** and **Coverage**.

The item you’ve selected is in the accent color. To hide the whole sidebar, choose **View → Hide Sidebar** (⌃⌘S), and **View → Show Sidebar** to bring it back.

### Open or close a section

Click anywhere on a section’s title. The groups inside **Coverage** open and close the same way. **Foundries**, **Classifications**, and the **Unicode Blocks** and **Google Fonts** groups start closed.

### Hide items you don’t use

1. Click **Edit** next to **Library** at the top of the sidebar, or right-click the sidebar and choose **Edit Sidebar**. Every item and section gets a checkbox. Sections stay open or closed as they were: click a section’s title to open or close it, for example to close **Foundries** and get to **Coverage** faster.
2. Uncheck what you don’t want. Unchecked items are dimmed.
3. Click **Done**. The unchecked items disappear.

To hide one item quickly, right-click it and choose **Hide from Sidebar**.

The same checkboxes are in **Settings → Sidebar**, in the sidebar’s order. **Show All** brings back everything you hid. There, **Foundries** has a single checkbox for the whole section; to hide individual foundries, use **Edit** in the sidebar.

When you make a new set or coverage set, or add a folder, its section shows again if you’d hidden it.

### Put items in your order

Drag items to where you want them, as in the Finder’s sidebar. An item moves within its own section: sets among your sets, folders among your folders, and so on. Sets under **Coverage** move within their group. To reorder the groups in **Coverage**, drag a group’s title onto another: it takes that group’s place, and the groups in between move up or down one. The sections themselves stay in their place.

Items that are gone for now, like **System Fonts** while system fonts are hidden, keep their place. New items go at the end. To go back to the usual order, click **Reset Order** in **Settings → Sidebar**.

### Select several items

⌘-click or ⇧-click items in the same section to select several. The browser then shows the fonts in any of them, and the window title names them, like “Serif and Script”. Drag them to move them together.

Selected items have to be in one section, or in one group under **Coverage**. ⌘-clicking an item somewhere else starts a new selection there.

### Drop fonts onto the sidebar

Drag families from the browser onto:

- **a set**, to add them to it
- **a tag**, to give them that tag
- **a foundry**, to say they’re from that foundry
- **a classification**, to put them in it

The item they’re over lights up in the accent color.

## Folders

Add folders of fonts to see them in your library without activating them. Cicero watches these folders, so fonts you add to them or take out show up or go away by themselves.

### Add a folder

Choose **File → Add Folder** (⇧⌘O), click **+** next to **Folders**, or click **+** in **Settings → Folders**. You can pick several folders at once.

A folder called “Fonts” is shown with the name of the folder it’s in, like “Projects Fonts”.

### What a folder’s menu has

Right-click a folder in the sidebar:

- **Rename Folder**: gives it a name of your own in Cicero, in the sidebar, Settings and Problems. The folder on disk keeps its name, so apps that load fonts from it still find it. **Testing**, **Adobe Fonts**, **Added Fonts** and **Deactivated** can be renamed too. Leave the name empty to go back to the folder’s own.
- **Reveal in Finder**
- **Fonts in This Folder**: **Inactive**, the usual choice, where its fonts are off until you turn them on; **Active**, where Cicero keeps them all on (see [Keep a folder’s fonts on](activating.md#keep-a-folders-fonts-on)); or active in an app that loads them by itself, like **Active in Adobe apps** (see [Your own folder that an app loads](activating.md#your-own-folder-that-an-app-loads)).
- **Remove Folder from Library**: Cicero stops listing it. The files stay where they are. To remove several at once, select them in **Settings → Folders** and click **−**.
- **Export Fonts**: copies its fonts into a folder or a ZIP archive. See [Export fonts](export-and-backup.md#export-fonts).

### Testing

The fonts that Adobe apps load from their own folders, where type designers put fonts to test them, are listed together as **Testing**, while there are any. They aren’t Adobe Fonts, which have an item of their own. **Testing** isn’t one of your folders: you turn it on or off with **Show test fonts installed for Adobe apps** under **Type Designer Mode** in **Settings → General** (on at first). If you add one of those folders with **+**, Cicero turns that switch on instead. Right-click **Testing** and choose **Reveal in Finder** to see the folders. For how these fonts turn on and off, see [Fonts in Adobe apps’ folders](activating.md#fonts-in-adobe-apps-folders).

### Adobe Fonts

The fonts from Adobe Fonts, which Creative Cloud turns on, are listed as **Adobe Fonts**, while there are any, whatever **Show test fonts installed for Adobe apps** says. A family of yours that Adobe Fonts also has is in it too. To hide them, turn off **Show fonts from Creative Cloud** in **Settings → General**: they’re then left out of every list, smart sets and the Character Toolbox, and **Adobe Fonts** leaves the sidebar. Families you also have yourself stay, as yours. Right-click **Adobe Fonts** and choose **Manage in Creative Cloud** to turn them on or off there. See [Adobe Fonts](activating.md#adobe-fonts).

### Deactivated

Cicero’s own folder for fonts it moved out of your Fonts folder or an app’s folder. It shows while it has fonts. See [The Deactivated folder](activating.md#the-deactivated-folder).

### Folders in the cloud: iCloud Drive, Dropbox, Google Drive

Cloud services can keep files online only: the Finder shows them, but their contents aren’t on your Mac. Cicero leaves those fonts out, because reading them would download them. When a folder has some, the browser says how many above its fonts, and **Settings → Folders** says so under the folder. Click **Download** to bring them down. The cloud service may take them off your Mac again later; to keep them, make the folder available offline in the Finder (right-click it and choose **Make Available Offline**, **Available offline** or **Keep Downloaded**, depending on the service).

The first time Cicero looks in a cloud service’s folder, macOS asks whether it may. If you said no, the folder says “Cicero isn’t allowed to read it”: allow it in **System Settings → Privacy & Security → Files and Folders**, then click **Try Again**.

### Folders on a server or an external disk

Add a folder on a network disk or a USB drive like any other. While the disk isn’t connected, its folder has a question mark in the sidebar, its fonts are out of your library, and the folder says “Isn’t connected”. Its fonts are back as soon as you connect the disk, and they keep their tags and their places in sets; Problems doesn’t list them as missing meanwhile.

Cicero sees fonts you add to a server folder from your Mac at once. Fonts someone else adds show up the next time Cicero looks, when you come back to it after a minute or more, or when you choose **Fonts → Rescan Library** (⌘R).

A folder that’s gone for good, because it moved or was deleted, says “Can’t be found”. Remove it, and add it again from its new place if it moved.

### The same font from several clients

When a font is in more than one of your folders, like a copy from each client, right-click the family and choose **Use Copy From**. It lists the folders the copies are in, with each one’s version, and checks the one in use. Picking one turns its copies on and turns off the copies of the same styles that Cicero turned on from the other folders, so only one is on at a time. Styles only one folder has come from there. A style’s right-click menu on its font page has **Use Copy From** for just that style. See [Use another copy of a font](activating.md#use-another-copy-of-a-font).

## Added Fonts

Font files you add one at a time are listed where they are, without being activated, like the fonts in a folder. They show up together as **Added Fonts** under **Folders**, while there are any.

If you chose **Copy into ~/Library/Fonts** or **Move into ~/Library/Fonts** next to **Activate fonts by** in Settings → General, font files you add are installed instead: Cicero copies or moves them into your Fonts folder and turns them on, and they’re in **All Fonts** like any font you’ve installed, not under Added Fonts. Copied, the originals stay where they are. Moved, they’re gone from there, though the folder they were in stays; see [Copy or use in place](activating.md#copy-or-use-in-place). Fonts already under Added Fonts that you open again, or turn on by copying or moving, leave Added Fonts the same way.

### Add font files

- Choose **File → Add Fonts** (⌘O) and pick one or more font files.
- Drag font files from the Finder onto the browser or a font page. Drop them while the browser shows a set, and they join that set too.
- In the Finder, right-click a font file and choose **Open With → Cicero**. To have a double-click open fonts in Cicero, select a font file, choose **File → Get Info** in the Finder, pick Cicero under **Open with** and click **Change All**

Cicero reads OpenType, TrueType, font collections, datafork TrueType and web fonts (WOFF and WOFF2). Cicero then shows them in the browser: it selects the first of them and scrolls to it. Files Cicero lists already, like those in your Fonts folder or a watched folder, are just shown. Dropping a folder adds it as a folder, whichever way you activate fonts.

### Fonts already in your library

A font file you add may have fonts your library has already, from another file: a newer version of a font you installed, say, or the same file from another folder. Cicero tells them by their PostScript names, and asks what to do with each family:

- **Skip It** leaves the file out. The library’s copy stays in use, and Cicero shows it.
- **Add as Another Copy** lists or installs the file next to the library’s copy, as for any other file. You can switch between them later with [Use Copy From](activating.md#use-another-copy-of-a-font).
- **Use the Added One** adds the file and uses it in place of the library’s copy. Where that copy is on, it goes off the way deactivating turns a font off, so no font is lost: a copy Cicero installed goes to the Trash when its original is still in your library, any other file in your Fonts folder goes to Cicero’s Deactivated folder, and a font used where it is just turns off. Then the added one goes on, the way you activate fonts; when Cicero asks each time, it’s installed in place of a copy in your Fonts folder, else used where it is. A copy under Added Fonts that the added file replaces stops being listed. Fonts that come with macOS or an app, and Adobe Fonts, stay on; apps may then get those.

The sheet says how many styles of each family the file has, which versions you have and where, and whether the added one is **Newer**, **Older**, the **Same Version** or the **Same File**. Each family starts at **Use the Added One** when the added one is newer, else at **Skip It**; **Choose for All** sets them all at once. **Add** adds the files, those with no fonts in your library included, and **Cancel** adds none of them.

To stop being asked, choose next to **When an added font is already in your library** in Settings → General: **Add it as another copy**, **Skip it**, **Use the added one**, or **Keep the newer version**, which uses the added one when its version is newer and skips it otherwise. Folders you add, and files **Find on This Mac** turns up for a document, are added as they are.

When a file you added changes, as when you build a new version of a font you’re making, Cicero reads it again.

### Remove them again

Right-click families from added files and choose **Remove from Library**. Cicero stops listing them; the files stay where they are. A font you turned on stays listed until you turn it off.

A file you added that’s deleted later, or whose folder you move or rename, leaves the library by itself. If it’s back within 30 days, as when you rename the folder back or sign in to a cloud service again, so is its font. One on a disk that isn’t connected stays, and is back when you connect the disk.

Right-click **Added Fonts** and choose **Reveal in Finder** to see the files.

## Sets

A set is a list of families you put together by hand, like the fonts for one project. It can have some styles of a family rather than all of them, like just the Regular and Bold you use.

### Make a set

- Choose **File → New Set** (⇧⌘N). The families you’ve selected go into it.
- Or click **+** next to **Sets** and choose **New Set**
- Or right-click selected families and choose **Add to Set → New Set from Selection**

### Add and remove fonts

- Drag families onto the set in the sidebar.
- Or right-click families and choose **Add to Set**, then the set. A checkmark shows the sets they’re already in; choose a checked set to take them out again.
- To add a single style, open the family’s font page and drag the style’s row from **Styles** onto the set, or right-click the style and choose **Add Style to Set**, then the set, or **New Set with Style**. A checkmark shows the sets that have the style; choose a checked set to take it out. Activating, deactivating and exporting the set then take only the styles it has, and so does an [application set](activating.md#turn-fonts-on-with-an-app).

### Rename or delete a set

Right-click the set and choose **Rename Set** or **Delete Set**. Deleting a set keeps its fonts in your library. Smart set rules that use the set are removed.

### Turn a set’s fonts on or off

Right-click the set and choose **Activate Set**, **Activate Temporarily** or **Deactivate Set**. Smart sets have the same items. See [Turn on a whole set](activating.md#turn-on-a-whole-set).

A set can also turn its fonts on while an app is open. See [Turn fonts on with an app](activating.md#turn-fonts-on-with-an-app).

## Smart sets

A smart set picks its families by rules, and stays up to date as your library changes.

### Make a smart set

1. Choose **File → New Smart Set** (⌥⌘N), or click **+** next to **Sets** and choose **New Smart Set**
2. Give it a name.
3. Next to **Match**, choose **All of the rules** or **Any of the rules**.
4. Set up each rule: a field, a comparison and a value. Click the **+** at the end of a rule to add one after it, or **−** to remove it.
5. Watch the count at the bottom, like “24 families match”, and click **Create**.

To change it later, right-click it and choose **Edit Smart Set**. To remove it, choose **Delete Smart Set**.

### Rules you can use

| Field | Comparisons | Value |
| --- | --- | --- |
| Name | contains, doesn’t contain, begins with, is | Text |
| Foundry | is, is not, contains | A foundry, or text for “contains” |
| Designer | contains, doesn’t contain, is | Text, matched against the designer any of the family’s styles credits |
| Classification | is, is not | Serif, Sans Serif, Monospaced, Script, Ornamental, Symbol or Unclassified |
| Tag | is, is not | One of your tags |
| Rating | is, is not, is more than, is less than | No Rating, or one to five stars (see [Ratings](#ratings)) |
| Set | is in, isn’t in | One of your sets |
| Folder | is in, isn’t in | One of your folders, Testing, Adobe Fonts, or Added Fonts |
| Status | is, is not | Active, Partly Active, Inactive, Active in Apps Only or Installed with macOS |
| Kind | is, is not | Variable, Monospaced or Has Italics |
| Format | is, is not | OpenType PostScript, OpenType TrueType, Font Collection, Datafork TrueType, Web Font and others |
| Number of Styles | is, is more than, is less than | A number |
| OpenType Feature | is supported, isn’t supported | Small Capitals, Old-Style Figures, Tabular Figures, Fractions, Stylistic Sets, Swashes and others, in any of the family’s styles |
| Embedding | is, is not | Installable, Editable, Preview & Print or Restricted: what the font’s license lets a document do with it, as its files say. A family’s is its most restrictive style’s |
| Language | is supported, isn’t supported | A language, chosen from a searchable list that starts with yours |
| Coverage | includes, doesn’t include | Any built-in set or one of your coverage sets |
| Date Added | is in the last, isn’t in the last | A number of days |
| Times Activated | is, is more than, is less than | A number of times |
| Last Activated | is in the last, isn’t in the last | A number of days |

A smart set with a language or coverage rule can grow for a while after launch, as Cicero checks the characters in each font. The subtitle says so while it does.

**Times Activated** and **Last Activated** count from the version of Cicero that added them. Each time a family comes on, Cicero counts it: whether you turned it on, an application set or a document did, or another app or the Finder did, like a font you put in your Fonts folder, while Cicero is open or by the time it next opens. Fonts that come with macOS aren’t counted. A family that hasn’t come on since then has been activated 0 times, and wasn’t activated in the last however many days. To find the fonts you haven’t used for a year, make a smart set with **Last Activated** **isn’t in the last** 365 days.

## Tags

Mark families with tags, which show as colored dots next to their names in the list, grid and specimens. A family can have as many tags as you like. Cicero comes with tags for keeping track of what you may do with each family, given to no family to begin with:

| Tag | Color |
| --- | --- |
| Licensed | Green |
| Licensed + Non-Commercial | Sand |
| Unlicensed | Red |
| Partially Licensed | Yellow |
| Public Domain | Purple |
| Open Source | Blue |
| Trial | Orange |

They’re tags like any other: rename them, delete them, or make your own. Libraries from before Cicero 1.5 get these too, once, and keep their own tags; the Red, Yellow and Green tags a library started with go if you never used them. From 1.5 to 1.6 a family had one tag at a time; the tags families had then, they keep.

### Tag fonts

- Right-click families and choose **Tags**, then a tag. A checkmark shows the tags they have; choose a checked one to take it off. **Remove All Tags** takes every tag off them, and **New Tag** makes a tag and gives it to them. The families keep the tags they have.
- On a font page, right-click the text, the header or a style for the same menu.
- Drag families onto a tag under **Tags** in the sidebar.
- In the [Info panel](browsing.md#see-a-fonts-details), click **Change** next to **Tags**.

### Make, change and delete tags

- Click **+** next to **Tags** in the sidebar to make a tag. Type a name and click a color under it, or the struck-through circle for none. The color starts on the first one no other tag has.
- Right-click a tag and choose **Rename Tag**, a color under **Color** (or **None**), or **Delete Tag**. Deleting a tag takes it off every family, and smart set rules that use it are removed.

Select a tag in the sidebar to see the families that have it. To find families with several tags, any of several, or without one, make a [smart set](#smart-sets) with **Tag** rules: **Tag** **is** a tag picks the families that have it, among their others.

## Ratings

Give a family one to five stars, to pick out your favorites or the ones you’d rather not use again.

- Right-click families and choose **Rating**, then the stars. A checkmark shows the rating they have; **No Rating** takes it away.
- On a font page, right-click the text, the header or a style for the same menu.
- In the [Info panel](browsing.md#see-a-fonts-details), click a star under **Rating**. Click the one it has again to take the rating away.

To see ratings in the list, right-click the column headers and choose **Rating**; click its header to sort by it. To keep your favorites together, make a [smart set](#smart-sets) with a **Rating** rule, like **Rating** **is more than** ★★★.

## Foundries

Cicero reads each family’s foundry from the manufacturer name in its files, and tidies it up: it drops endings like “Inc.” or “GmbH”, leaves out web addresses and copyright lines, and puts names that differ only in capitals together.

- **Rename a foundry:** right-click it and choose **Rename Foundry**. Every family from that foundry follows.
- **Change a family’s foundry:** drag the family onto another foundry in the sidebar.

## Classifications

Cicero sorts families into Serif, Sans Serif, Monospaced, Script, Ornamental, Symbol and Unclassified, and shows the ones your library has. Slab serifs count as Serif. To decide, it goes through these in turn and stops at the first that says something:

1. The classification the font gives itself.
2. Words in the name, like “Mono”, “Slab”, “Sans”, “Grotesk”, “Script” or “Symbol”.
3. The shapes of the letters. An I and an l with feet on both sides are serif, plain ones sans serif, and letters all as wide as each other monospaced. Letters that are none of these, like a script’s, say nothing.
4. The font’s PANOSE numbers, another way fonts can say what they are.
5. With Apple Intelligence on, a guess from the family’s name, made on your Mac. The Info panel says “Guessed from the name by Apple Intelligence” under such a classification. To stop the guessing, turn off **Guess classifications from names** in **Settings → General**.

A family none of them tells stays Unclassified, rather than ending up in the wrong classification.

- **Make your own classification:** click **+** next to **Classifications**, or choose **Classification → New Classification** from a family’s right-click menu to put it straight in. Yours stay in the sidebar even while they’re empty.
- **Put a family in another classification:** right-click it and choose one from **Classification**, use **Change** next to **Classification** in the Info panel, or drag it onto a classification in the sidebar. To keep a family where Cicero put it, choose that classification: a later version of Cicero, or a new guess, won’t move it. **Automatic** puts it back where its fonts say it belongs. Your choices are saved with your library, so they’re the same each time Cicero opens, and backups include them.
- **Rename a classification:** right-click it and choose **Rename Classification**. This works for Cicero’s own too; give one its old name back to undo that. Smart sets follow.
- **Delete one of yours:** right-click it and choose **Delete Classification**. Its families go back to the classifications their fonts suggest.
- **Hide a classification:** click **Edit** at the top of the sidebar and uncheck it, or choose **Hide from Sidebar** from its right-click menu.

## System Fonts

**System Fonts** shows the fonts that come with macOS. They’re always on, and Cicero can’t turn them off.

To keep them out of your lists, open **Settings → General** and turn off **Show system fonts**. They’re then hidden everywhere: in every list, in smart sets, in the Character Toolbox, and **System Fonts** leaves the sidebar too.

## Coverage

The **Coverage** section shows which fonts have every character of a set, like Latin S or Adobe Latin 3. See [Character sets and languages](character-sets.md).
