# Activating fonts

[Cicero Help](README.md) › Activating fonts

## How activation works

Apps only offer fonts that macOS has turned on, or *activated*. Cicero lists every font in your library, on or off, and turns them on and off for you.

A font counts as activated once macOS says it is. So when the message at the bottom says a font is activated, like “Inter activated”, it’s in every app’s font menu. Most apps show it right away; if one doesn’t, see [An app doesn’t see a font](troubleshooting.md#an-app-doesnt-see-a-font). Microsoft Office needs more; see [Fonts in Microsoft Office](#fonts-in-microsoft-office).

A switch moves the moment you click it and stays there while Cicero works. If something goes wrong, it moves back and a message says what happened. While a switch is moving, clicking it again does nothing.

## Turn a font on

Any of these work:

- Click the family’s switch in the list, grid or specimens. With several families selected, clicking the switch of one of them turns them all on.
- Select one or more families and choose **Fonts → Activate** (⌘↩).
- Right-click a family and choose **Activate**. If some of its styles are on already, the item says **Activate Remaining Styles**.
- On a font page, click **Activate**.

To turn on a single style, open the font page and use the style’s switch in **Styles**, or right-click the style and choose **Activate Style**.

Every app lists the fonts that are on in its font menu, so hundreds at once can make apps slower to open. When you turn on more than 100 families at once, Cicero asks first. Check **Don’t ask again** there, or turn off **Ask before activating more than 100 families at once** in **Preferences → General**, to go ahead without asking. App folders and imports never ask.

### Turn on a whole folder

Right-click a folder or smart folder in the sidebar and choose **Activate Folder** or **Activate Smart Folder** to turn on every font in it. **Activate Temporarily** there turns them on until Cicero quits, and **Deactivate Folder** or **Deactivate Smart Folder** turns them off again. Like any activation, they follow your choice in [Copy or use in place](#copy-or-use-in-place).

### Keep a location’s fonts on

Choose **Active** for one of your locations, next to it in **Preferences → Locations** or under **Fonts in This Location** when you right-click it in the sidebar, and Cicero turns on every font in it. They stay where they are, whatever you chose next to **Activate fonts by**. Fonts you put in the folder later go on by themselves, and a font you turn off stays off, also when the folder is on a disk you unplug and connect again. Choose **Inactive** again, or remove the location, and Cicero turns off the fonts it turned on.

## Copy or use in place

There are two ways to turn on a font that isn’t in a Fonts folder:

| | Install a copy | Leave files where they are |
| --- | --- | --- |
| What happens | Cicero copies the files into your Fonts folder, `~/Library/Fonts`. The originals stay where they are. | Cicero tells macOS to use the files from where they are. Nothing is copied. |
| Good for | Fonts you always need, or fonts on a disk you unplug | Large libraries you keep in one place |
| Watch out | Takes disk space | The fonts stop working if their files move or their disk is unplugged, and Microsoft Office can’t use them |

Choose which one in **Preferences → General**, next to **Activate fonts by**:

- **Ask each time**: when you [add font files](organizing.md#add-font-files), Cicero asks once for all of them: **Install a Copy** or **Move Into Fonts Folder**, which turn them on, or **Leave Files Where They Are**, which lists them under [Added Fonts](organizing.md#added-fonts) without turning them on. Check **Remember this choice** to stop being asked; you can change it again in Preferences. Turning fonts on never asks: fonts in your [locations](organizing.md#locations) go on where they are, so Microsoft Office can’t use them.
- **Copy into ~/Library/Fonts** (the setting at first): font files you open in Cicero, drop on its window or choose with **File → Add Fonts** are copied in and turned on straight away, rather than listed under [Added Fonts](organizing.md#added-fonts).
- **Move into ~/Library/Fonts**: font files you open in Cicero, drop on its window or choose with **File → Add Fonts** are moved in and turned on, so they’re no longer where they were. The folder they were in stays, even when it’s left empty. Fonts in your [locations](organizing.md#locations) are copied, so their folders stay as they are, and so is a file **Find on This Mac** finds for a document.
- **Leave files where they are**: font files you add are listed where they are, under [Added Fonts](organizing.md#added-fonts), without being turned on. Turn them on when you need them.

A few things happen either way:

- Fonts from a folder an app loads by itself, like Adobe’s, are always used where they are, never copied. See [Fonts in Adobe apps’ folders](#fonts-in-adobe-apps-folders).
- When a copy has the same name as a file already where it goes, Cicero gives it a new name, like “Name 2.otf”. If the file there has the same contents, Cicero uses it instead.
- A font Cicero copied before goes on as that copy again, also with **Ask each time** or **Leave files where they are**, so it stays usable in Microsoft Office. If its file has changed since, like a new version from the foundry in one of your [locations](organizing.md#locations), or another font saved under its name, the old copy goes to the Trash and the new one is copied in its place.
- A font in your Fonts folder that’s turned off in macOS is turned back on where it is.

### Fonts in Microsoft Office

Microsoft Office apps, like Word and PowerPoint, only use fonts whose files are in a Fonts folder, like yours at `~/Library/Fonts`. They read font files themselves, and macOS doesn’t let them read font files anywhere else, so they set text in any other font in a font of their own instead. That’s every font Cicero turns on where it is:

- fonts turned on with **Ask each time** or **Leave files where they are** chosen
- fonts in [Cicero’s Library](#ciceros-library)
- fonts in a location you chose **Active** for
- fonts turned on temporarily, or by an [app folder](#turn-fonts-on-with-an-app)
- fonts in [Adobe apps’ folders](#fonts-in-adobe-apps-folders), also when they’re on in every app

To use a font in Office, turn it on by copying it into your Fonts folder: choose **Install a Copy** when Cicero asks as you add it, or **Copy into ~/Library/Fonts** next to **Activate fonts by** in **Preferences → General**, with **Install fonts into Cicero’s Library** off. A font that’s on where it is already has to be turned off and on again that way.

Office also takes up a font only the second time it opens after the font went on, whether it was open or not: quit the app, open it, quit it again and open it once more. That goes for fonts you install any other way too, and for turning a font off: Office still lists it the next time it opens, and lets go of it the time after.

Other apps, like Pages and Adobe’s, use fonts from anywhere.

## Cicero’s Library

Instead of copying fonts into your Fonts folder, Cicero can keep the fonts it installs in a folder of its own, Cicero’s Library, and have macOS use them from there. Turn on **Install fonts into Cicero’s Library** in **Preferences → General**, under **Activate fonts by**. The library is `~/Cicero/Library` at first, with a folder for each family, like `~/Cicero/Library/Inter`.

- **Turning a font on**, by copying or moving it, or opening a file from the Finder with either chosen, puts its file into its family’s folder in the library and turns it on there. A file with fonts of more than one family, as a font collection can be, goes into the folder of the family you turned on, or of its first font when you open it from the Finder. When the library has the same file already, Cicero uses that one rather than copying it again. A font in the [Inactive folder](#the-inactive-folder) moves into the library.
- **Turning a font off** only turns it off: the file stays in the library, listed and off, ready to turn on again. It never goes to the Trash or the Inactive folder. **Move to Trash** removes it from the library, and its family’s folder goes once nothing is left in it.
- **Its fonts are in your library** like the ones in your Fonts folder: under **All Fonts**, and **Active** or **Inactive**. Cicero’s Library itself isn’t in the sidebar.
- **A font from one of your locations** has two files once it’s in the library: the one in its folder and the library’s copy. That’s not a duplicate: Conflicts leaves it alone, and **Use Copy From** counts the copy as being where its original is.
- **Fonts already in your Fonts folder** stay there, on, whether Cicero installed them before or you did. Only fonts you turn on from now on go into the library.
- **Turning the setting off** moves nothing, and no font goes on or off. If the library has fonts, its folder becomes one of your locations, called **Cicero’s Library**, with each font on or off as it was, and fonts you install from then on go into your Fonts folder again. Turn the setting back on, and that location is the library again.
- **Microsoft Office** can’t use the library’s fonts, because they aren’t in your Fonts folder. See [Fonts in Microsoft Office](#fonts-in-microsoft-office).

To keep the library somewhere else, click **Change** next to **Cicero’s Library** and choose an empty folder, or make a new one with **New Folder**. Cicero moves the library there, fonts and all, turning the ones that are on off for a moment and on again there, and the old folder goes. A few places can’t work, and Cicero says why: your Fonts folder or the one for all users (macOS would turn on everything in it), Cicero’s own folders, a folder in one of your locations, a folder in iCloud Drive or another cloud service’s folder (it can take files off your Mac to make room, and fonts used from there stop working), and a folder with anything in it. On an external disk, the library’s fonts are off while the disk isn’t connected. In your Documents, Desktop or Downloads folder, macOS asks the first time whether Cicero may use the folder; see [Privacy](privacy.md#when-macos-asks-for-permission).

## Use another copy of a font

When the same font is in more than one place, like a copy from each client, **Use Copy From** in the family’s right-click menu chooses which copy is on. It lists the folders the copies are in, named where their paths part (“Acme” and “Globex” for `Clients/Acme` and `Clients/Globex`), with each one’s version and how many styles it has when it hasn’t them all. The one in use is checked.

Picking a folder:

- turns on its copies, following your choice in [Copy or use in place](#copy-or-use-in-place),
- turns off the other copies of those styles that Cicero turned on, so they don’t clash: a copy Cicero installed in your Fonts folder goes to the Trash when its original is still in your library, and
- leaves styles that folder doesn’t have as they are.

Copies Cicero didn’t turn on, like macOS’s, an app’s, or one you put in your Fonts folder yourself, stay on, and so do copies an [app folder](#turn-fonts-on-with-an-app) has on; the message says so, and [Conflicts](problems.md#installed-twice) shows them as installed twice. When a file that goes off also holds other styles, as a font collection can, Cicero names them and asks first. If a new copy can’t be turned on, the old one comes back on.

To choose for one style, open the font page and right-click the style.

## Turn a font on just for now

To try a font without installing it, turn it on until Cicero quits:

- Choose **Fonts → Activate Temporarily** (⌥⌘↩).
- Or right-click a family, or a style on its font page, and choose **Activate Temporarily**.
- Or right-click a folder or smart folder in the sidebar and choose **Activate Temporarily**, for every font in it.

When the fonts are already on, for good or until Cicero quits, these items are dimmed or left out.

Nothing is copied. The family gets a blue **Temporary** tag with a clock, and its styles say “Active until Cicero quits”. When you quit Cicero, it turns the fonts off again. If Cicero quits unexpectedly, it turns them off the next time it opens.

Fonts for Adobe apps can be turned on temporarily too: they’re on in every app until Cicero quits, then back to how they were.

To keep a temporary font, right-click it and choose **Activate Permanently**.

While fonts are on until Cicero quits, the sidebar has **Temporary**, under **Inactive**, with the families they’re in. Right-click it and choose **Activate Permanently** to keep them all, or **Deactivate** to turn them all off. Only the styles that are on until Cicero quits change; the families’ other styles stay as they are. When none are on any more, **Temporary** goes away.

## Turn fonts off

Any of these work:

- Click the family’s switch. With several families selected, clicking the switch of one that’s on turns them all off.
- Select families and press ⌫, or choose **Fonts → Deactivate**.
- Right-click a family and choose **Deactivate**, or a style and choose **Deactivate Style**.
- Right-click a folder or smart folder in the sidebar and choose **Deactivate Folder** or **Deactivate Smart Folder**.
- On a font page, click **Deactivate**.

Turning a font off never deletes your only copy of it. What happens to the file depends on how the font was on:

| The font was | When you turn it off |
| --- | --- |
| Used where it is, or on temporarily | macOS stops using it. The file stays where it is. |
| In [Cicero’s Library](#ciceros-library) | macOS stops using it. The file stays in the library. |
| In your Fonts folder, also a copy Cicero installed there | macOS turns it off there, as with Font Book. The file stays in your Fonts folder, ready to turn on again. |
| In a folder an app loads by itself, like Adobe’s | The file moves to the [Inactive folder](#the-inactive-folder), so the app stops loading it too. See [Fonts in Adobe apps’ folders](#fonts-in-adobe-apps-folders). |

Apps let go of a font as soon as it’s off. Another copy of the same font, in your Fonts folder or elsewhere, stays as it is. macOS remembers which fonts in your Fonts folder are off, and Font Book shows them as off too. If you move or rename a file that’s off there, or change it, macOS turns it on again.

## The Inactive folder

Cicero keeps the files it moves out of app font folders in its Inactive folder, `~/Library/Application Support/Cicero/Inactive`. Up to version 0.10.10 it was called Deactivated; Cicero renames it as it opens.

Earlier versions of Cicero also moved fonts there when you turned them off in your Fonts folder. They now go back as Cicero opens, still off: into your Fonts folder, or into [Cicero’s Library](#ciceros-library) when Cicero installs fonts there. macOS turns on any font that arrives in your Fonts folder, so Cicero turns each one off as it lands, which leaves it on for a few hundredths of a second.

- Its fonts stay in your library, under **Inactive** in the sidebar. The folder itself isn’t in the sidebar.
- Turning one on again moves its file back out: into your Fonts folder (or [Cicero’s Library](#ciceros-library), when Cicero installs there), or into the app’s folder it came from. So the folder only ever has fonts that are off.
- To see a font’s file, right-click the font and choose **Reveal in Finder**.

## Fonts Cicero can’t turn off

Some fonts belong to macOS or another app. Their switch is dimmed, and holding the pointer over **Deactivate** on the font page says why:

- **Installed with macOS:** macOS needs them.
- **Installed for all users,** in `/Library/Fonts`: an administrator has to remove them.
- **Comes with an app:** the app manages them.
- **Adobe Fonts:** Creative Cloud manages them. See [Adobe Fonts](#adobe-fonts).

## Adobe Fonts

The fonts you turn on in Adobe Fonts, in Creative Cloud, are on in every app. Cicero lists them, with a purple **Adobe Fonts** tag, and together as **Adobe Fonts** under **Locations**. To keep them out of your lists, turn off **Show fonts from Creative Cloud** in **Preferences → General**.

Adobe apps can also turn on Adobe Fonts by themselves, for instance for a document that uses them. Those are on in Adobe apps only: their switch sits halfway, and their styles say **Active in Adobe apps**, like the fonts in Adobe’s folders.

Creative Cloud turns these fonts on and off, so their switches don’t move. To change them, click **Manage in Adobe Fonts** on the font page, or choose it from the family’s right-click menu. It opens the family’s page on the Adobe Fonts website, where you turn its styles on and off. Creative Cloud then adds them to your Mac or takes them away, and Cicero’s lists follow. Cicero finds the page in the list Creative Cloud keeps of your fonts. When it can’t, the button says **Manage in Creative Cloud** and opens the Creative Cloud app. For all of them at once, right-click **Adobe Fonts** under **Locations** and choose **Manage in Creative Cloud**.

A font you also have yourself is listed as your copy, which you turn on and off as usual. A copy from Adobe Fonts never makes yours a spare one, which [Conflicts](problems.md) would offer to remove: Creative Cloud takes its copy away when the font is turned off there. While both are on, [Installed Twice](problems.md#installed-twice) lists them, with **Remove in Adobe Fonts…** for the copy from Adobe Fonts.

## Fonts in Adobe apps’ folders

Adobe apps load the fonts in folders of their own, without the fonts being installed:

- `/Library/Application Support/Adobe/Fonts` and `~/Library/Application Support/Adobe/Fonts`, for all Adobe apps
- the Fonts folder next to an Adobe app, like `/Applications/Adobe InDesign 2026/Fonts`, for that app only

Type designers export fonts there to test them: an Adobe app picks up a new version straight away, with no font cache in the way. Glyphs explains how in [Testing your fonts in Adobe apps](https://glyphsapp.com/learn/testing-your-fonts-in-adobe-apps).

These folders have nothing to do with Adobe Fonts, the fonts you turn on in Creative Cloud (see [Adobe Fonts](#adobe-fonts)).

Cicero lists the fonts in all of them together as **Proofing** under **Locations**, while there are any. They show as active in those apps, with a red tag, **Proofing**, or the app’s name for its own folder, like **InDesign**, instead of as inactive. To hide them, turn off **Show fonts installed for proofing in Adobe apps** under **Library** in **Preferences → General**. Adobe Fonts have a switch of their own, **Show fonts from Creative Cloud**.

### The three-position switch

A family whose files are all in one app’s folder has a switch with three positions:

| Position | Means | Clicking it |
| --- | --- | --- |
| Halfway, lightly tinted | On in that app only | Turns it on in every app |
| On | On in every app | Turns it off everywhere, that app included |
| Off | Off everywhere | Turns it back on in that app only |

The family’s right-click menu has the same choices: **Activate in All Apps**, **Activate Temporarily in All Apps**, **Use in Adobe Apps Only**, **Deactivate in All Apps** and **Deactivate in Adobe Apps**. For a single app’s folder, they name the app, like **Use in InDesign Only**. The switches in a font page’s **Styles** work the same way, one style at a time.

- **On in every app** uses the file where it is. Nothing is copied.
- **Off everywhere** moves the file into Cicero’s [Inactive folder](#the-inactive-folder) and remembers where it was, because the app would load it otherwise. Turning it on again, or **Use in Adobe Apps Only**, puts it back first.
- Some app folders, like InDesign’s, are owned by the system, and Cicero can’t move files out of them. Their fonts can’t be turned off everywhere.

### Your own folder that an app loads

If an app loads fonts from a folder of yours, tell Cicero, so it shows those fonts as active in that app and gives them the same switch. Right-click the folder under **Locations** in the sidebar and choose **Active in Adobe apps**, or **Active in Specific App** to type the app’s name, under **Fonts in This Location**. The same choices are next to it in **Preferences → Locations**.

## Turn on the fonts a document uses

To see which fonts a document needs, and turn on the ones you have:

1. Choose **File → Find Fonts in Document** and pick the document, or drag it from the Finder onto Cicero’s window.
2. Cicero lists every font the document uses, missing ones first:
   - **Active** (a green check): apps have it. The status says how, like “Active” or “Installed with macOS”.
   - **Inactive** (a dashed circle): it’s in your library but inactive. Click **Activate**.
   - **Missing** (an orange triangle): it isn’t in your library. Click **Find on This Mac** to look for its file with Spotlight; when Cicero finds one, **Add** lists it in your library, under [Added Fonts](organizing.md#added-fonts), and you can activate it. With **Copy into ~/Library/Fonts** chosen, the button says **Install** and copies it into your Fonts folder, on. The first time, macOS asks whether Cicero may look in your Documents, Desktop and Downloads folders, and the font says **Waiting for access to your folders** until you’ve answered; see [Privacy](privacy.md#when-macos-asks-for-permission).
3. **Activate All** turns on every font of the document that’s in your library. **Make Folder** makes a folder named after the document with its fonts that are in your library, or adds them to a folder of that name. **Show in Library** shows those fonts in the main window, each set in itself, with everything you can do there as with any list; **Done** in the bar above them takes you back.

Cicero reads PDFs, IDML files, InDesign documents (`.indd`, `.indt`), Illustrator files (`.ai`) and Photoshop files (`.psd`, `.psb`), without opening them in the app that made them, and nothing leaves your Mac. It finds a font by its PostScript name, or by its family and style.

- **PDFs** list the fonts their pages use. An **Embedded** tag marks the ones the PDF carries itself, so it shows as it should even where the font is missing.
- **IDML files** list every style of each family they use; Cicero shows the styles the document’s text and styles apply, which can now and then include one it doesn’t use.
- **InDesign and Illustrator files** keep a list of their fonts, which Cicero reads.
- **Photoshop files** keep the fonts of each text layer with its text. Text in smart objects, which are documents of their own placed in the file, isn’t read.

### Fonts documents open in Adobe apps use

You don’t have to look up a document before you open it. Turn on **Auto-activate fonts in Adobe apps** in **Preferences → General**, and when a document you open in InDesign, Illustrator or Photoshop uses fonts from your library that are off, Cicero turns them on, and turns them off again when the app quits, as an [app folder](#turn-fonts-on-with-an-app) does, with the same graphite **App Folder** tag.

- Cicero asks the app in front, twice a second, which fonts its open documents use. The first time, macOS asks whether Cicero may control InDesign, Illustrator or Photoshop; click **Allow**. To change your answer, go to **System Settings → Privacy & Security → Automation**.
- The app’s Missing Fonts dialog still comes up as the document opens, since Cicero can only ask about a document once it’s open. Close it (**Skip** in InDesign, **Close** in Illustrator), and the text sets in the fonts. Photoshop shows none: its text layers look as they did when saved, and use the fonts once you edit them. Either way, the app can take a few seconds to take up the fonts.
- Illustrator and Photoshop say which files their documents are, and Cicero reads their fonts from the file as last saved, so a document you haven’t saved yet isn’t covered, nor text in a Photoshop smart object.
- If you turn one of those fonts off while the app is open, Cicero leaves it off until the app quits.

## Turn fonts on with an app

An *app folder* is a folder with one or more apps. While one of its apps is open, Cicero turns on the folder’s fonts that are off, and turns them off again when the app quits.

To make one:

1. Click **+** next to **Folders** in the sidebar and choose **New App Folder**, or choose **File → New App Folder**. Name it and click **Create**.
2. Click **+** under the list and choose one or more apps.
3. Click **Done**, then drag the fonts you need onto the folder.

To give apps to a folder you already have, right-click it and choose **Activate with Apps** (**Edit Apps** once it has some). In that window, “Open” marks apps that are running. To take apps out, select them and click **−**.

A few rules:

- Fonts that are on for any other reason are never touched. Fonts you turned on yourself stay on.
- Fonts an app folder turned on get a graphite **App Folder** tag with the symbol of an app, and say “Active while its app is open”.
- If you turn one of those fonts off, or on for good, while its app is open, Cicero leaves it that way until the app quits.
- Cicero has to be open for this to work, and in your Applications folder. So it can [open when you log in](#open-cicero-at-login).
- If you quit Cicero while an app is open, its fonts stay on until Cicero opens again or you log out.

## Open Cicero at login

Turn on **Open at login** in **Preferences → General**, or check **Open Cicero at login** in an app folder’s apps window.

- If macOS needs your approval, allow Cicero in **System Settings → General → Login Items**.
- Cicero has to be in your Applications folder for this. If it isn’t, it offers to move there.

## Remove fonts from your Mac

To delete fonts, not just turn them off:

1. Select families and press ⌘⌫ (**Fonts → Move to Trash**), or right-click a family and choose **Move to Trash**. For one style, right-click it on the font page and choose **Move Style to Trash**
2. Read the alert and click **Move to Trash**.

Cicero turns the fonts off in every app and moves their files to the Trash, copies in other folders included. If a file also holds other families, as a font collection can, the alert names them. The families also leave the folders you put them in.

Files that come with macOS or an app always stay where they are. You can put files back from the Trash in the Finder.

## Find a font’s files

To show a family’s files in the Finder, select it and choose **Fonts → Reveal in Finder** (⇧⌘R), or right-click it and choose **Reveal in Finder**. Cicero selects every file, other copies included. For a single style, use its right-click menu on the font page, or **Reveal in Finder** in the Info panel.
