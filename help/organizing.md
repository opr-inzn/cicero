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

Below them are sections: **Folders**, **Sets**, **Foundries**, **Classifications** and **Character Sets**.

### Open or close a section

Click anywhere on a section’s title. The groups inside **Character Sets** open and close the same way. **Foundries**, **Classifications**, and the **Unicode Blocks** and **Google Fonts** groups start closed.

### Hide items you don’t use

1. Click **Edit** next to **Fonts** at the top of the sidebar, or choose **View → Edit Sidebar**. Every item and section gets a checkbox.
2. Uncheck what you don’t want. Unchecked items are dimmed.
3. Click **Done**. The unchecked items disappear.

To hide one item quickly, right-click it and choose **Hide from Sidebar**.

The same checkboxes are in **Settings → Sidebar**, in the sidebar’s order. **Show All** brings back everything you hid. There, **Foundries** has a single checkbox for the whole section; to hide single foundries, use **Edit** in the sidebar.

When you make a new set or character set, or add a folder, its section shows again if you’d hidden it.

### Put items in your order

Drag items to where you want them, as in the Finder’s sidebar. An item moves within its own section: sets among your sets, folders among your folders, and so on. Character sets move within their group, and the groups move within **Character Sets**. The sections themselves stay in their place.

Items that are gone for now, like **System Fonts** while system fonts are hidden, keep their place. New items go at the end. To go back to the usual order, click **Reset Order** in **Settings → Sidebar**.

### Select several items

⌘-click or ⇧-click items in the same section to select several. The browser then shows the fonts in any of them, and the window title names them, like “Serif and Script”. Drag them to move them together.

Selected items have to be in one section, or in one group of character sets. ⌘-clicking an item somewhere else starts a new selection there.

### Drop fonts onto the sidebar

Drag families from the browser onto:

- **a set**, to add them to it
- **a foundry**, to say they’re from that foundry

## Folders

Add folders of fonts to see them in your library without installing them. Cicero watches these folders, so fonts you add to them or take out show up or go away by themselves.

### Add a folder

Choose **File → Add Folder…** (⇧⌘O), click **+** next to **Folders**, or click **+** in **Settings → Folders**. You can pick several folders at once.

A folder called “Fonts” is shown with the name of the folder it’s in, like “Projects Fonts”.

### What a folder’s menu has

Right-click a folder in the sidebar:

- **Reveal in Finder**
- **Fonts in This Folder**: whether its fonts are **Not activated until you activate them** (the usual choice), or active in an app that loads them by itself, like **Active in Adobe apps**. See [Your own folder that an app loads](activating.md#your-own-folder-that-an-app-loads).
- **Remove Folder from Library**: Cicero stops listing it. The files stay where they are.
- **Export Fonts…**: copies its fonts into a folder or a ZIP archive. See [Export fonts](export-and-backup.md#export-fonts).

### Adobe Apps

The fonts that Adobe apps load from their own folders are listed together as **Adobe Apps**, while there are any. It isn’t one of your folders: you turn it on or off with **Show fonts installed for Adobe apps** in **Settings → Folders** (on at first). If you add one of those folders with **+**, Cicero turns that switch on instead. Right-click **Adobe Apps** and choose **Reveal in Finder** to see the folders. For how these fonts turn on and off, see [Fonts for Adobe apps](activating.md#fonts-for-adobe-apps).

### Deactivated

Cicero’s own folder for fonts it moved out of your Fonts folder or an app’s folder. It shows while it has fonts. See [The Deactivated folder](activating.md#the-deactivated-folder).

### Folders in iCloud Drive

Files that iCloud Drive, or another service like it, keeps only online are skipped until they’re downloaded, because reading them would download them. Download them in the Finder and Cicero lists them.

## Sets

A set is a list of families you put together by hand, like the fonts for one project.

### Make a set

- Choose **File → New Set…** (⇧⌘N). The families you’ve selected go into it.
- Or click **+** next to **Sets** and choose **New Set…**
- Or right-click selected families and choose **Add to Set → New Set from Selection…**

### Add and remove fonts

- Drag families onto the set in the sidebar.
- Or right-click families and choose **Add to Set**, then the set. A checkmark shows the sets they’re already in; choose a checked set to take them out again.

### Rename or delete a set

Right-click the set and choose **Rename Set…** or **Delete Set**. Deleting a set keeps its fonts in your library. Smart set rules that use the set are removed.

A set can also turn its fonts on while an app is open. See [Turn fonts on with an app](activating.md#turn-fonts-on-with-an-app).

## Smart sets

A smart set picks its families by rules, and stays up to date as your library changes.

### Make a smart set

1. Choose **File → New Smart Set…** (⌥⌘N), or click **+** next to **Sets** and choose **New Smart Set…**
2. Give it a name.
3. Next to **Match**, choose **All of the rules** or **Any of the rules**.
4. Set up each rule: a field, a comparison and a value. Click the **+** at the end of a rule to add one after it, or **−** to remove it.
5. Watch the count at the bottom, like “24 families match”, and click **Create**.

To change it later, right-click it and choose **Edit Smart Set…**. To remove it, choose **Delete Smart Set**.

### Rules you can use

| Field | Comparisons | Value |
| --- | --- | --- |
| Name | contains, doesn’t contain, begins with, is | Text |
| Foundry | is, is not, contains | A foundry, or text for “contains” |
| Classification | is, is not | Serif, Slab Serif, Sans Serif, Monospaced, Script, Ornamental, Symbol or Unclassified |
| Set | is in, isn’t in | One of your sets |
| Folder | is in, isn’t in | One of your folders, or Adobe Apps |
| Status | is, is not | Activated, Partly Activated, Not Activated, Active in Apps Only or Installed with macOS |
| Kind | is, is not | Variable, Monospaced or Has Italics |
| Format | is, is not | OpenType PostScript, OpenType TrueType, Font Collection, Datafork TrueType, Web Font and others |
| Number of Styles | is, is more than, is less than | A number |
| Language | is supported, isn’t supported | A language, chosen from a searchable list that starts with yours |
| Character Set | is supported, isn’t supported | Any built-in character set or one of yours |
| Date Added | is in the last, isn’t in the last | A number of days |

A smart set with a language or character set rule can grow for a while after launch, as Cicero checks the characters in each font. The subtitle says so while it does.

## Foundries

Cicero reads each family’s foundry from the manufacturer name in its files, and tidies it up: it drops endings like “Inc.” or “GmbH”, leaves out web addresses and copyright lines, and puts names that differ only in capitals together.

- **Rename a foundry:** right-click it and choose **Rename Foundry…**. Every family from that foundry follows.
- **Change a family’s foundry:** drag the family onto another foundry in the sidebar.

## Classifications

Cicero sorts families into Serif, Slab Serif, Sans Serif, Monospaced, Script, Ornamental, Symbol and Unclassified, and shows the ones your library has. It reads the classification the font gives itself, and when there’s none, looks for hints in the name, like “Mono”, “Slab”, “Sans”, “Grotesk” or “Script”.

## System Fonts

**System Fonts** shows the fonts that come with macOS. They’re always on, and Cicero can’t turn them off.

To keep them out of your lists, open **Settings → General** and turn off **Show system fonts**. They’re then hidden everywhere: in every list, in smart sets, in the Character Toolbox, and **System Fonts** leaves the sidebar too.

## Character Sets

The **Character Sets** section shows which fonts have every character of a set, like Latin S or Adobe Latin 3. See [Character sets and languages](character-sets.md).
