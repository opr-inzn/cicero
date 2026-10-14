# Organizing your library

[Cicero Help](README.md) › Organizing your library

## The sidebar

At the top of the sidebar are five items that are always there:

| Item | Shows |
| --- | --- |
| All Fonts | Every family in your library |
| Activated | Families with at least one style on |
| Not Activated | Families with at least one style off |
| System Fonts | The fonts that come with macOS, while **Show system fonts** is on (see [System Fonts](#system-fonts)) |
| Problems | Things worth fixing, with a count. See [Problems](problems.md) |

Below them are sections: **Folders**, **Sets**, **Tags**, **Foundries**, **Classifications** and **Coverage**.

### Open or close a section

Click anywhere on a section’s title. The groups inside **Coverage** open and close the same way. **Foundries**, **Classifications**, and the **Unicode Blocks** and **Google Fonts** groups start closed.

### Hide items you don’t use

1. Click **Edit** next to **Fonts** at the top of the sidebar, or choose **View → Edit Sidebar**. Every item and section gets a checkbox.
2. Uncheck what you don’t want. Unchecked items are dimmed.
3. Click **Done**. The unchecked items disappear.

To hide one item quickly, right-click it and choose **Hide from Sidebar**.

The same checkboxes are in **Settings → Sidebar**, in the sidebar’s order. **Show All** brings back everything you hid. There, **Foundries** has a single checkbox for the whole section; to hide single foundries, use **Edit** in the sidebar.

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

## Folders

Add folders of fonts to see them in your library without installing them. Cicero watches these folders, so fonts you add to them or take out show up or go away by themselves.

### Add a folder

Choose **File → Add Folder** (⇧⌘O), click **+** next to **Folders**, or click **+** in **Settings → Folders**. You can pick several folders at once.

A folder called “Fonts” is shown with the name of the folder it’s in, like “Projects Fonts”.

### What a folder’s menu has

Right-click a folder in the sidebar:

- **Reveal in Finder**
- **Fonts in This Folder**: whether its fonts are **Not activated until you activate them** (the usual choice), or active in an app that loads them by itself, like **Active in Adobe apps**. See [Your own folder that an app loads](activating.md#your-own-folder-that-an-app-loads).
- **Remove Folder from Library**: Cicero stops listing it. The files stay where they are.
- **Export Fonts**: copies its fonts into a folder or a ZIP archive. See [Export fonts](export-and-backup.md#export-fonts).

### Adobe Apps

The fonts that Adobe apps load from their own folders are listed together as **Adobe Apps**, while there are any. It isn’t one of your folders: you turn it on or off with **Show fonts installed for Adobe apps** in **Settings → Folders** (on at first). If you add one of those folders with **+**, Cicero turns that switch on instead. Right-click **Adobe Apps** and choose **Reveal in Finder** to see the folders. For how these fonts turn on and off, see [Fonts for Adobe apps](activating.md#fonts-for-adobe-apps).

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

Font files you add one at a time are listed where they are, without being installed, like the fonts in a folder. They show up together as **Added Fonts** under **Folders**, while there are any.

### Add font files

- Choose **File → Add Fonts** (⌘O) and pick one or more font files.
- Drag font files from the Finder onto the browser or a font page. Drop them while the browser shows a set, and they join that set too.
- In the Finder, right-click a font file and choose **Open With → Cicero**. To have a double-click open fonts in Cicero, select a font file, choose **File → Get Info** in the Finder, pick Cicero under **Open with** and click **Change All**

Cicero reads OpenType, TrueType, font collections, datafork TrueType and web fonts (WOFF and WOFF2). When you open one family from the Finder, its font page opens. Files Cicero lists already, like those in your Fonts folder or a watched folder, are just shown. Dropping a folder adds it as a folder.

When a file you added changes, as when you build a new version of a font you’re making, Cicero reads it again.

### Remove them again

Right-click families from added files and choose **Remove from Library**. Cicero stops listing them; the files stay where they are. A font you turned on stays listed until you turn it off.

Right-click **Added Fonts** and choose **Reveal in Finder** to see the files.

## Sets

A set is a list of families you put together by hand, like the fonts for one project.

### Make a set

- Choose **File → New Set** (⇧⌘N). The families you’ve selected go into it.
- Or click **+** next to **Sets** and choose **New Set**
- Or right-click selected families and choose **Add to Set → New Set from Selection**

### Add and remove fonts

- Drag families onto the set in the sidebar.
- Or right-click families and choose **Add to Set**, then the set. A checkmark shows the sets they’re already in; choose a checked set to take them out again.

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
| Classification | is, is not | Serif, Sans Serif, Monospaced, Script, Ornamental, Symbol or Unclassified |
| Tag | has, doesn’t have | One of your tags |
| Set | is in, isn’t in | One of your sets |
| Folder | is in, isn’t in | One of your folders, Adobe Apps, or Added Fonts |
| Status | is, is not | Activated, Partly Activated, Not Activated, Active in Apps Only or Installed with macOS |
| Kind | is, is not | Variable, Monospaced or Has Italics |
| Format | is, is not | OpenType PostScript, OpenType TrueType, Font Collection, Datafork TrueType, Web Font and others |
| Number of Styles | is, is more than, is less than | A number |
| Language | is supported, isn’t supported | A language, chosen from a searchable list that starts with yours |
| Coverage | includes, doesn’t include | Any built-in set or one of your coverage sets |
| Date Added | is in the last, isn’t in the last | A number of days |

A smart set with a language or coverage rule can grow for a while after launch, as Cicero checks the characters in each font. The subtitle says so while it does.

## Tags

Tags are labels you give families, like “Licensed”, “Client approved” or “Try later”, each with a color if you like. A family can have any number of them, and its tags show as colored dots next to its name in the list, grid and specimens. A new library starts with Red, Yellow and Green tags, ready to use.

### Tag fonts

- Right-click families and choose **Tags**, then a tag. A checkmark shows the tags they have; choose a checked tag to take it off. **New Tag** makes a tag and gives it to them.
- Drag families onto a tag in the sidebar.
- In the [Info panel](browsing.md#see-a-fonts-details), click **Add Tag** or **Edit Tags** next to **Tags**.

### Make, change and delete tags

- Click **+** next to **Tags** in the sidebar to make a tag. Type a name and click a color under it, or the struck-through circle for none. The color starts on the first one no other tag has. Leave the name empty to name the tag after its color, like **Orange**.
- Right-click a tag and choose **Rename Tag**, a color under **Color** (or **None**), or **Delete Tag**. Deleting a tag takes it off every family, and smart set rules that use it are removed.

Select a tag in the sidebar to see the families that have it. To find families with several tags, or without one, make a [smart set](#smart-sets) with **Tag** rules.

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
