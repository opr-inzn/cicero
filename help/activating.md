# Activating fonts

[Cicero Help](README.md) › Activating fonts

## How activation works

Apps only offer fonts that macOS has turned on, or *activated*. Cicero lists every font in your library, on or off, and turns them on and off for you.

A font counts as activated once macOS says it is. So when the message at the bottom says “Activated”, the font is in every app’s font menu. Most apps show it right away; if one doesn’t, see [An app doesn’t see a font](troubleshooting.md#an-app-doesnt-see-a-font).

A switch moves the moment you click it and stays there while Cicero works. If something goes wrong, it moves back and a message says what happened. While a switch is moving, clicking it again does nothing.

## Turn a font on

Any of these work:

- Click the family’s switch in the list, grid or specimens.
- Select one or more families and choose **Fonts → Activate** (⌘↩).
- Right-click a family and choose **Activate**. If some of its styles are on already, the item says **Activate Remaining Styles**.
- On a font page, click **Activate**.

To turn on a single style, open the font page and use the style’s switch in **Styles**, or right-click the style and choose **Activate Style**.

### Turn on a whole set

Right-click a set or smart set in the sidebar and choose **Activate Set** or **Activate Smart Set** to turn on every font in it. **Activate Temporarily** there turns them on until Cicero quits, and **Deactivate Set** or **Deactivate Smart Set** turns them off again. Like any activation, they follow your choice in [Copy or use in place](#copy-or-use-in-place), and ask first with **Ask each time**.

### Keep a folder’s fonts on

Choose **Active** for one of your folders, next to it in **Settings → Folders** or under **Fonts in This Folder** when you right-click it in the sidebar, and Cicero turns on every font in it. They stay where they are, whatever you chose next to **Activate fonts by**. Fonts you put in the folder later go on by themselves, and a font you turn off stays off. Choose **Inactive** again, or remove the folder, and Cicero turns off the fonts it turned on.

## Copy or use in place

There are two ways to turn on a font that isn’t in a Fonts folder:

| | Install a copy | Leave the files where they are |
| --- | --- | --- |
| What happens | Cicero copies the files into your Fonts folder, `~/Library/Fonts`. The originals stay where they are. | Cicero tells macOS to use the files from where they are. Nothing is copied. |
| Good for | Fonts you always need, or fonts on a disk you unplug | Large libraries you keep in one place |
| Watch out | Takes disk space | The fonts stop working if their files move or their disk is unplugged |

Choose which one in **Settings → General**, next to **Activate fonts by**:

- **Ask each time** (the setting at first): when you turn fonts on, Cicero asks with **Install a Copy**, **Leave Files Where They Are**, or **Activate Temporarily**, and **Move Into Fonts Folder** for font files you [added](organizing.md#added-fonts) one at a time. Check **Remember this choice** to stop being asked; you can change it again in Settings.
- **Copy into ~/Library/Fonts**: font files you open in Cicero, drop on its window or choose with **File → Add Fonts** are copied in and turned on straight away, rather than listed under [Added Fonts](organizing.md#added-fonts).
- **Move into ~/Library/Fonts**: font files you open in Cicero, drop on its window or choose with **File → Add Fonts** are moved in and turned on, so they’re no longer where they were. When that leaves the folder they were in empty, like a font download’s folder in Downloads, the folder goes to the Trash. A folder with anything else left in it, like a license, stays. Fonts in your [folders](organizing.md#folders) are copied, so your folders stay as they are, and so is a file **Find on This Mac** finds for a document.
- **Leave the files where they are**

A few things happen either way:

- Fonts from a folder an app loads by itself, like Adobe’s, are always used where they are, never copied. See [Fonts for Adobe apps](#fonts-for-adobe-apps).
- When a copy has the same name as a file already in your Fonts folder, Cicero gives it a new name, like “Name 2.otf”. If the file there has the same contents, Cicero uses it instead.
- A font in your Fonts folder that’s turned off in macOS is turned back on where it is.

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

Nothing is copied. The family gets a blue **Temporary** tag, and its styles say “Active until Cicero quits”. When you quit Cicero, it turns the fonts off again. If Cicero quits unexpectedly, it turns them off the next time it opens.

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
| A copy Cicero installed in your Fonts folder, and the original is still there, unchanged, in your library | The copy goes to the Trash. The original stays where it is. |
| Any other file in your Fonts folder, like a font you installed by opening it | The file moves to Cicero’s [Deactivated folder](#the-deactivated-folder), so the font stays in your library. If Cicero didn’t install it, Cicero asks first. |
| In a folder an app loads by itself, like Adobe’s | The file moves to the Deactivated folder, so the app stops loading it too. See [Fonts for Adobe apps](#fonts-for-adobe-apps). |

Files in your Fonts folder are turned off before they move, so apps let go of them at once. If a file can’t be moved, Cicero turns it back on and says so.

## The Deactivated folder

Cicero keeps the files it moves out of your Fonts folder and out of app font folders in its Deactivated folder, `~/Library/Application Support/Cicero/Deactivated`.

- While it has fonts, the folder shows up as **Deactivated** under **Folders** in the sidebar.
- Its fonts stay in your library, listed as not activated. Turn one on again whenever you like.
- To see the files, right-click **Deactivated** and choose **Reveal in Finder**.

## Fonts Cicero can’t turn off

Some fonts belong to macOS or another app. Their switch is dimmed, and holding the pointer over **Deactivate** on the font page says why:

- **Installed with macOS:** macOS needs them.
- **Installed for all users,** in `/Library/Fonts`: an administrator has to remove them.
- **Comes with an app:** the app manages them.
- **Adobe Fonts:** fonts you turned on in Adobe Creative Cloud are managed there.

## Fonts for Adobe apps

Adobe apps load fonts from folders of their own, without installing them:

- `/Library/Application Support/Adobe/Fonts` and `~/Library/Application Support/Adobe/Fonts`, for all Adobe apps
- the Fonts folder next to an Adobe app, like `/Applications/Adobe InDesign 2026/Fonts`, for that app only

Cicero lists the fonts in all of them together as **Adobe Apps** under **Folders**, while there are any. They show as active in those apps, with a red tag like **Adobe** or **InDesign**, instead of as not activated. To hide them, turn off **Show fonts installed for Adobe apps** in **Settings → Folders**.

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
   - **On** (a green check): apps have it. The status says how, like “Active” or “Installed with macOS”.
   - **Off** (a dashed circle): it’s in your library but not on. Click **Activate**.
   - **Missing** (an orange triangle): it isn’t in your library. Click **Find on This Mac** to look for its file with Spotlight; when Cicero finds one, **Add** lists it in your library, under [Added Fonts](organizing.md#added-fonts), and you can activate it. With **Copy into ~/Library/Fonts** chosen, the button says **Install** and copies it into your Fonts folder, on. The first time, macOS asks whether Cicero may look in your Documents, Desktop and Downloads folders; see [Privacy](privacy.md#when-macos-asks-for-permission).
3. **Activate All** turns on every font of the document that’s in your library. **Make Set** makes a set named after the document with its fonts that are in your library, or adds them to a set of that name.

Cicero reads PDFs, IDML files, InDesign documents (`.indd`, `.indt`) and Illustrator files (`.ai`), without opening them in the app that made them, and nothing leaves your Mac. It finds a font by its PostScript name, or by its family and style.

- **PDFs** list the fonts their pages use. An **Embedded** tag marks the ones the PDF carries itself, so it shows as it should even where the font is missing.
- **IDML files** list every style of each family they use; Cicero shows the styles the document’s text and styles apply, which can now and then include one it doesn’t use.
- **InDesign and Illustrator files** keep a list of their fonts, which Cicero reads.

## Turn fonts on with an app

An *application set* is a set with one or more apps. While one of its apps is open, Cicero turns on the set’s fonts that are off, and turns them off again when the app quits.

To make one:

1. Click **+** next to **Sets** in the sidebar and choose **New Application Set**, or choose **File → New Application Set**. Name it and click **Create**.
2. Click **+** under the list and choose one or more apps.
3. Click **Done**, then drag the fonts you need onto the set.

To give apps to a set you already have, right-click it and choose **Activate with Apps** (**Edit Apps** once it has some). In that window, “Open” marks apps that are running. To take apps out, select them and click **−**.

A few rules:

- Fonts that are on for any other reason are never touched. Fonts you turned on yourself stay on.
- Fonts an application set turned on get a blue **App Set** tag, and say “Active while its app is open”.
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
