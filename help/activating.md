# Activating fonts

[Cicero Help](README.md) › Activating fonts

## How activation works

Apps only offer fonts that macOS has turned on, or *activated*. Cicero lists every font in your library, on or off, and turns them on and off for you.

A font counts as activated once macOS says it is. So when the message at the bottom says a font is activated, like “Inter activated”, it’s in every app’s font menu. Most apps show it right away; if one doesn’t, see [An app doesn’t see a font](troubleshooting.md#an-app-doesnt-see-a-font). Microsoft Office needs more; see [Fonts in Microsoft Office](#fonts-in-microsoft-office).

A switch moves the moment you click it and stays there while Cicero works. If something goes wrong, it moves back and a message says what happened. While a switch is moving, clicking it again does nothing.

## Turn a font on

Any of these work:

- Click the family’s switch in the list, grid or specimens.
- Select one or more families and choose **Fonts → Activate** (⌘↩).
- Right-click a family and choose **Activate**. If some of its styles are on already, the item says **Activate Remaining Styles**.
- On a font page, click **Activate**.

To turn on a single style, open the font page and use the style’s switch in **Styles**, or right-click the style and choose **Activate Style**.

Every app lists the fonts that are on in its font menu, so hundreds at once can make apps slower to open. When you turn on more than 100 families at once, Cicero asks first. Check **Don’t ask again** there, or turn off **Ask before activating more than 100 families at once** in **Settings → General**, to go ahead without asking. Application sets and imports never ask.

### Turn on a whole set

Right-click a set or smart set in the sidebar and choose **Activate Set** or **Activate Smart Set** to turn on every font in it. **Activate Temporarily** there turns them on until Cicero quits, and **Deactivate Set** or **Deactivate Smart Set** turns them off again. Like any activation, they follow your choice in [Copy or use in place](#copy-or-use-in-place), and ask first with **Ask each time**.

### Keep a folder’s fonts on

Choose **Active** for one of your folders, next to it in **Settings → Folders** or under **Fonts in This Folder** when you right-click it in the sidebar, and Cicero turns on every font in it. They stay where they are, whatever you chose next to **Activate fonts by**. Fonts you put in the folder later go on by themselves, and a font you turn off stays off, also when the folder is on a disk you unplug and connect again. Choose **Inactive** again, or remove the folder, and Cicero turns off the fonts it turned on.

## Copy or use in place

There are two ways to turn on a font that isn’t in a Fonts folder:

| | Install a copy | Leave the files where they are |
| --- | --- | --- |
| What happens | Cicero copies the files into your Fonts folder, `~/Library/Fonts`. The originals stay where they are. | Cicero tells macOS to use the files from where they are. Nothing is copied. |
| Good for | Fonts you always need, or fonts on a disk you unplug | Large libraries you keep in one place |
| Watch out | Takes disk space | The fonts stop working if their files move or their disk is unplugged, and Microsoft Office can’t use them |

Choose which one in **Settings → General**, next to **Activate fonts by**:

- **Ask each time** (the setting at first): when you turn fonts on, Cicero asks with **Install a Copy**, **Leave Files Where They Are**, or **Activate Temporarily**, and **Move Into Fonts Folder** for font files you [added](organizing.md#added-fonts) one at a time. Check **Remember this choice** to stop being asked; you can change it again in Settings.
- **Copy into ~/Library/Fonts**: font files you open in Cicero, drop on its window or choose with **File → Add Fonts** are copied in and turned on straight away, rather than listed under [Added Fonts](organizing.md#added-fonts).
- **Move into ~/Library/Fonts**: font files you open in Cicero, drop on its window or choose with **File → Add Fonts** are moved in and turned on, so they’re no longer where they were. The folder they were in stays, even when it’s left empty. Fonts in your [folders](organizing.md#folders) are copied, so your folders stay as they are, and so is a file **Find on This Mac** finds for a document.
- **Leave the files where they are**

A few things happen either way:

- Fonts from a folder an app loads by itself, like Adobe’s, are always used where they are, never copied. See [Fonts in Adobe apps’ folders](#fonts-in-adobe-apps-folders).
- When a copy has the same name as a file already where it goes, Cicero gives it a new name, like “Name 2.otf”. If the file there has the same contents, Cicero uses it instead.
- A font in your Fonts folder that’s turned off in macOS is turned back on where it is.

### Fonts in Microsoft Office

Microsoft Office apps, like Word and PowerPoint, only use fonts whose files are in a Fonts folder, like yours at `~/Library/Fonts`. They read font files themselves, and macOS doesn’t let them read font files anywhere else, so they set text in any other font in a font of their own instead. That’s every font Cicero turns on where it is:

- fonts turned on with **Leave the files where they are**
- fonts in Cicero’s [Font Library](#the-font-library)
- fonts in a folder you chose **Active** for
- fonts turned on temporarily, or by an [application set](#turn-fonts-on-with-an-app)
- fonts in [Adobe apps’ folders](#fonts-in-adobe-apps-folders), also when they’re on in every app

To use a font in Office, turn it on by copying it into your Fonts folder: choose **Install a Copy** when Cicero asks, or **Copy into ~/Library/Fonts** next to **Activate fonts by** in **Settings → General**, with **Install fonts into Cicero’s Font Library** off. A font that’s on where it is already has to be turned off and on again that way.

Office also takes up a font only the second time it opens after the font went on, whether it was open or not: quit the app, open it, quit it again and open it once more. That goes for fonts you install any other way too.

Other apps, like Pages and Adobe’s, use fonts from anywhere.

## The Font Library

Instead of copying fonts into your Fonts folder, Cicero can keep the fonts it installs in a folder of its own, the Font Library, and have macOS use them from there. Turn on **Install fonts into Cicero’s Font Library** in **Settings → General**, under **Activate fonts by**. The library is `~/Cicero/Font Library` at first, with a folder for each family, like `~/Cicero/Font Library/Inter`.

- **Turning a font on**, by copying or moving it, or opening a file from the Finder with either chosen, puts its file into its family’s folder in the library and turns it on there. A file with fonts of more than one family, as a font collection can be, goes into the folder of the family you turned on, or of its first font when you open it from the Finder. When the library has the same file already, Cicero uses that one rather than copying it again. A font in the [Deactivated folder](#the-deactivated-folder) moves into the library.
- **Turning a font off** only turns it off: the file stays in the library, listed and off, ready to turn on again. It never goes to the Trash or the Deactivated folder. **Move to Trash** removes it from the library, and its family’s folder goes once nothing is left in it.
- **The sidebar** lists the library as **Font Library**, under **Folders**, while it has fonts, whether or not the setting is on. You can rename it, and pick it in a smart set’s **Folder** rule.
- **A font from one of your folders** has two files once it’s in the library: the one in your folder and the library’s copy. That’s not a duplicate: Problems leaves it alone, and **Use Copy From** counts the copy as being where its original is.
- **Fonts Cicero installed before** stay in your Fonts folder until you click **Move Them**, next to the setting, which shows while there are any. Cicero moves each into its family’s folder in the library, turning it off for the moment that takes and on again there. Fonts you put in your Fonts folder yourself stay where they are.
- **Turning the setting off** moves nothing: the library stays, its fonts stay on or off as they are, and fonts you install from then on go into your Fonts folder again.
- **Microsoft Office** can’t use the library’s fonts, because they aren’t in your Fonts folder. See [Fonts in Microsoft Office](#fonts-in-microsoft-office).

To keep the library somewhere else, click **Change** next to **Font Library** and choose an empty folder, or make a new one with **New Folder**. Cicero moves the library there, fonts and all, turning the ones that are on off for a moment and on again there, and the old folder goes. A few places can’t work, and Cicero says why: your Fonts folder or the one for all users (macOS would turn on everything in it), Cicero’s own folders, a folder in one of your watched folders, a folder in iCloud Drive or another cloud service’s folder (it can take files off your Mac to make room, and fonts used from there stop working), and a folder with anything in it. On an external disk, the library’s fonts are off while the disk isn’t connected. In your Documents, Desktop or Downloads folder, macOS asks the first time whether Cicero may use the folder; see [Privacy](privacy.md#when-macos-asks-for-permission).

## Use another copy of a font

When the same font is in more than one place, like a copy from each client, **Use Copy From** in the family’s right-click menu chooses which copy is on. It lists the folders the copies are in, named where their paths part (“Acme” and “Globex” for `Clients/Acme` and `Clients/Globex`), with each one’s version and how many styles it has when it hasn’t them all. The one in use is checked.

Picking a folder:

- turns on its copies, following your choice in [Copy or use in place](#copy-or-use-in-place),
- turns off the other copies of those styles that Cicero turned on, so they don’t clash, and
- leaves styles that folder doesn’t have as they are.

Copies Cicero didn’t turn on, like macOS’s, an app’s, or one you put in your Fonts folder yourself, stay on, and so do copies an [application set](#turn-fonts-on-with-an-app) has on; the message says so, and [Problems](problems.md#installed-twice) shows them as installed twice. When a file that goes off also holds other styles, as a font collection can, Cicero names them and asks first. If a new copy can’t be turned on, the old one comes back on.

To choose for one style, open the font page and right-click the style.

## Turn a font on just for now

To try a font without installing it, turn it on until Cicero quits:

- Choose **Fonts → Activate Temporarily** (⌥⌘↩).
- Or right-click a family, or a style on its font page, and choose **Activate Temporarily**.
- Or right-click a set or smart set in the sidebar and choose **Activate Temporarily**, for every font in it.
- Or choose **Activate Temporarily** when Cicero asks how to turn fonts on.

When the fonts are already on, for good or until Cicero quits, these items are dimmed or left out.

Nothing is copied. The family gets a blue **Temporary** tag with a clock, and its styles say “Active until Cicero quits”. When you quit Cicero, it turns the fonts off again. If Cicero quits unexpectedly, it turns them off the next time it opens.

Fonts for Adobe apps can be turned on temporarily too: they’re on in every app until Cicero quits, then back to how they were.

To keep a temporary font, right-click it and choose **Activate Permanently**.

## Turn fonts off

Any of these work:

- Click the family’s switch.
- Select families and press ⌫, or choose **Fonts → Deactivate**.
- Right-click a family and choose **Deactivate**, or a style and choose **Deactivate Style**.
- Right-click a set or smart set in the sidebar and choose **Deactivate Set** or **Deactivate Smart Set**.
- On a font page, click **Deactivate**.

Turning a font off never deletes your only copy of it. What happens to the file depends on how the font was on:

| The font was | When you turn it off |
| --- | --- |
| Used where it is, or on temporarily | macOS stops using it. The file stays where it is. |
| In Cicero’s [Font Library](#the-font-library) | macOS stops using it. The file stays in the library. |
| A copy Cicero installed in your Fonts folder, and the original is still there, unchanged, in your library | The copy goes to the Trash. The original stays where it is. |
| Any other file in your Fonts folder, like a font you installed by opening it | The file moves to Cicero’s [Deactivated folder](#the-deactivated-folder), so the font stays in your library. |
| In a folder an app loads by itself, like Adobe’s | The file moves to the Deactivated folder, so the app stops loading it too. See [Fonts in Adobe apps’ folders](#fonts-in-adobe-apps-folders). |

Files in your Fonts folder are turned off before they move, so apps let go of them at once. If a file can’t be moved, Cicero turns it back on and says so.

## The Deactivated folder

Cicero keeps the files it moves out of your Fonts folder and out of app font folders in its Deactivated folder, `~/Library/Application Support/Cicero/Deactivated`.

- Its fonts stay in your library, under **Inactive**. The folder isn’t in the sidebar.
- Turning one on again moves its file back out: into your Fonts folder (or the [Font Library](#the-font-library), when Cicero installs there), or into the app’s folder it came from. So the folder only ever has fonts that are off.
- To see a font’s file, right-click the font and choose **Reveal in Finder**.

## Fonts Cicero can’t turn off

Some fonts belong to macOS or another app. Their switch is dimmed, and holding the pointer over **Deactivate** on the font page says why:

- **Installed with macOS:** macOS needs them.
- **Installed for all users,** in `/Library/Fonts`: an administrator has to remove them.
- **Comes with an app:** the app manages them.
- **Adobe Fonts:** Creative Cloud manages them. See [Adobe Fonts](#adobe-fonts).

## Adobe Fonts

The fonts you turn on in Adobe Fonts, in Creative Cloud, are on in every app. Cicero lists them, with a purple **Adobe Fonts** tag, and together as **Adobe Fonts** under **Folders**. To keep them out of your lists, turn off **Show fonts from Creative Cloud** in **Settings → General**.

Adobe apps can also turn on Adobe Fonts by themselves, for instance for a document that uses them. Those are on in Adobe apps only: their switch sits halfway, and their styles say **Active in Adobe apps**, like the fonts in Adobe’s folders.

Creative Cloud turns these fonts on and off, so their switches don’t move. To change them, click **Manage in Adobe Fonts** on the font page, or choose it from the family’s right-click menu. It opens the family’s page on the Adobe Fonts website, where you turn its styles on and off. Creative Cloud then adds them to your Mac or takes them away, and Cicero’s lists follow. Cicero finds the page in the list Creative Cloud keeps of your fonts. When it can’t, the button says **Manage in Creative Cloud** and opens the Creative Cloud app. For all of them at once, right-click **Adobe Fonts** under **Folders** and choose **Manage in Creative Cloud**.

A font you also have yourself is listed as your copy, which you turn on and off as usual. A copy from Adobe Fonts never makes yours a spare one, which [Problems](problems.md) would offer to remove: Creative Cloud takes its copy away when the font is turned off there. While both are on, [Installed Twice](problems.md#installed-twice) lists them, with **Remove in Adobe Fonts…** for the copy from Adobe Fonts.

## Fonts in Adobe apps’ folders

Adobe apps load the fonts in folders of their own, without the fonts being installed:

- `/Library/Application Support/Adobe/Fonts` and `~/Library/Application Support/Adobe/Fonts`, for all Adobe apps
- the Fonts folder next to an Adobe app, like `/Applications/Adobe InDesign 2026/Fonts`, for that app only

Type designers export fonts there to test them: an Adobe app picks up a new version straight away, with no font cache in the way. Glyphs explains how in [Testing your fonts in Adobe apps](https://glyphsapp.com/learn/testing-your-fonts-in-adobe-apps).

These folders have nothing to do with Adobe Fonts, the fonts you turn on in Creative Cloud (see [Adobe Fonts](#adobe-fonts)).

Cicero lists the fonts in all of them together as **Testing** under **Folders**, while there are any. They show as active in those apps, with a red tag, **Testing**, or the app’s name for its own folder, like **InDesign**, instead of as inactive. To hide them, turn off **Show test fonts installed for Adobe apps** under **Library** in **Settings → General**. Adobe Fonts have a switch of their own, **Show fonts from Creative Cloud**.

### The three-position switch

A family whose files are all in one app’s folder has a switch with three positions:

| Position | Means | Clicking it |
| --- | --- | --- |
| Halfway, lightly tinted | On in that app only | Turns it on in every app |
| On | On in every app | Turns it off everywhere, that app included |
| Off | Off everywhere | Turns it back on in that app only |

The family’s right-click menu has the same choices: **Activate in All Apps**, **Activate Temporarily in All Apps**, **Use in Adobe Apps Only**, **Deactivate in All Apps** and **Deactivate in Adobe Apps**. For a single app’s folder, they name the app, like **Use in InDesign Only**. The switches in a font page’s **Styles** work the same way, one style at a time.

- **On in every app** uses the file where it is. Nothing is copied.
- **Off everywhere** moves the file into Cicero’s [Deactivated folder](#the-deactivated-folder) and remembers where it was, because the app would load it otherwise. Turning it on again, or **Use in Adobe Apps Only**, puts it back first.
- Some app folders, like InDesign’s, are owned by the system, and Cicero can’t move files out of them. Their fonts can’t be turned off everywhere.

### Your own folder that an app loads

If an app loads fonts from a folder of yours, tell Cicero, so it shows those fonts as active in that app and gives them the same switch. Right-click the folder in the sidebar and choose **Active in Adobe apps**, or **Active in Specific App** to type the app’s name, under **Fonts in This Folder**. The same choices are next to the folder in **Settings → Folders**.

## Turn on the fonts a document uses

To see which fonts a document needs, and turn on the ones you have:

1. Choose **File → Find Fonts in Document** and pick the document, or drag it from the Finder onto Cicero’s window.
2. Cicero lists every font the document uses, missing ones first:
   - **Active** (a green check): apps have it. The status says how, like “Active” or “Installed with macOS”.
   - **Inactive** (a dashed circle): it’s in your library but inactive. Click **Activate**.
   - **Missing** (an orange triangle): it isn’t in your library. Click **Find on This Mac** to look for its file with Spotlight; when Cicero finds one, **Add** lists it in your library, under [Added Fonts](organizing.md#added-fonts), and you can activate it. With **Copy into ~/Library/Fonts** chosen, the button says **Install** and copies it into your Fonts folder, on. The first time, macOS asks whether Cicero may look in your Documents, Desktop and Downloads folders; see [Privacy](privacy.md#when-macos-asks-for-permission).
3. **Activate All** turns on every font of the document that’s in your library. **Make Set** makes a set named after the document with its fonts that are in your library, or adds them to a set of that name.

Cicero reads PDFs, IDML files, InDesign documents (`.indd`, `.indt`), Illustrator files (`.ai`) and Photoshop files (`.psd`, `.psb`), without opening them in the app that made them, and nothing leaves your Mac. It finds a font by its PostScript name, or by its family and style.

- **PDFs** list the fonts their pages use. An **Embedded** tag marks the ones the PDF carries itself, so it shows as it should even where the font is missing.
- **IDML files** list every style of each family they use; Cicero shows the styles the document’s text and styles apply, which can now and then include one it doesn’t use.
- **InDesign and Illustrator files** keep a list of their fonts, which Cicero reads.
- **Photoshop files** keep the fonts of each text layer with its text. Text in smart objects, which are documents of their own placed in the file, isn’t read.

### Fonts documents open in Adobe apps use

You don’t have to look up a document before you open it. Turn on **Auto-activate fonts in Adobe apps** in **Settings → General**, and when a document you open in InDesign, Illustrator or Photoshop uses fonts from your library that are off, Cicero turns them on, and turns them off again when the app quits, as an [application set](#turn-fonts-on-with-an-app) does, with the same graphite **App Set** tag.

- Cicero asks the app in front, twice a second, which fonts its open documents use. The first time, macOS asks whether Cicero may control InDesign, Illustrator or Photoshop; click **Allow**. To change your answer, go to **System Settings → Privacy & Security → Automation**.
- The app’s Missing Fonts dialog still comes up as the document opens, since Cicero can only ask about a document once it’s open. Close it (**Skip** in InDesign, **Close** in Illustrator), and the text sets in the fonts. Photoshop shows none: its text layers look as they did when saved, and use the fonts once you edit them. Either way, the app can take a few seconds to take up the fonts.
- Illustrator and Photoshop say which files their documents are, and Cicero reads their fonts from the file as last saved, so a document you haven’t saved yet isn’t covered, nor text in a Photoshop smart object.
- If you turn one of those fonts off while the app is open, Cicero leaves it off until the app quits.

## Turn fonts on with an app

An *application set* is a set with one or more apps. While one of its apps is open, Cicero turns on the set’s fonts that are off, and turns them off again when the app quits.

To make one:

1. Click **+** next to **Sets** in the sidebar and choose **New Application Set**, or choose **File → New Application Set**. Name it and click **Create**.
2. Click **+** under the list and choose one or more apps.
3. Click **Done**, then drag the fonts you need onto the set.

To give apps to a set you already have, right-click it and choose **Activate with Apps** (**Edit Apps** once it has some). In that window, “Open” marks apps that are running. To take apps out, select them and click **−**.

A few rules:

- Fonts that are on for any other reason are never touched. Fonts you turned on yourself stay on.
- Fonts an application set turned on get a graphite **App Set** tag with the symbol of an app, and say “Active while its app is open”.
- If you turn one of those fonts off, or on for good, while its app is open, Cicero leaves it that way until the app quits.
- Cicero has to be open for this to work, and in your Applications folder. So it can [open when you log in](#open-cicero-at-login).
- If you quit Cicero while an app is open, its fonts stay on until Cicero opens again or you log out.

## Open Cicero at login

Turn on **Open at login** in **Settings → General**, or check **Open Cicero at login** in an application set’s apps window.

- If macOS needs your approval, allow Cicero in **System Settings → General → Login Items**.
- Cicero has to be in your Applications folder for this. If it isn’t, it offers to move there.

## Remove fonts from your Mac

To delete fonts, not just turn them off:

1. Select families and press ⌘⌫ (**Fonts → Move to Trash**), or right-click a family and choose **Move to Trash**. For one style, right-click it on the font page and choose **Move Style to Trash**
2. Read the alert and click **Move to Trash**.

Cicero turns the fonts off in every app and moves their files to the Trash, copies in other folders included. If a file also holds other families, as a font collection can, the alert names them. The families leave your sets too.

Files that come with macOS or an app always stay where they are. You can put files back from the Trash in the Finder.

## Find a font’s files

To show a family’s files in the Finder, select it and choose **Fonts → Reveal in Finder** (⇧⌘R), or right-click it and choose **Reveal in Finder**. Cicero selects every file, other copies included. For a single style, use its right-click menu on the font page, or **Reveal in Finder** in the Info panel.
