# Getting started

[Cicero Help](README.md) › Getting started

## What you need

A Mac with Apple silicon and macOS 15 or later. Recognizing classifications from fonts’ names with Apple Intelligence needs macOS 26.

## Install Cicero

1. Download [Cicero.dmg](https://github.com/opr-inzn/cicero/releases/latest/download/Cicero.dmg), the latest version.
2. Open the disk image and drag **Cicero** onto the **Applications** folder next to it.
3. Open Cicero from your Applications folder.

## Move Cicero to Applications

If you open Cicero right from the disk image or from your Downloads folder, it offers to move itself to the Applications folder. Let it: [app folders](activating.md#turn-fonts-on-with-an-app), [Open at login](activating.md#open-cicero-at-login) and [updates](#keep-cicero-up-to-date) only work when Cicero is in Applications.

If you say no and later turn on **Open at login**, Cicero offers again. You can also quit Cicero and drag it into Applications yourself in the Finder.

## The first launch

Cicero looks for fonts in these places:

- every font macOS has turned on, and every font that comes with macOS
- the Adobe Fonts that Adobe apps turned on by themselves, which only they use
- your Fonts folder, `~/Library/Fonts`
- the Fonts folder for all users, `/Library/Fonts`
- the folders Adobe apps load fonts from by themselves, where type designers put fonts to test them (see [Fonts in Adobe apps’ folders](activating.md#fonts-in-adobe-apps-folders))

Looking changes nothing: no font is turned on, off, copied or moved until you ask.

The first time it opens, Cicero asks whether to classify your fonts automatically: the ones whose files don’t say what they are. Choose **Classify**, and it sorts them by the shapes of their letters and, with Apple Intelligence on macOS 26, by their names, on your Mac. Choose **Not Now**, and they stay Unclassified until you put them somewhere. You can change your mind with **Classify fonts automatically** in **Preferences → General** (see [Classifications](organizing.md#classifications)).

When a scan takes a moment, a small capsule at the bottom right says what Cicero is doing, like “Identifying fonts, 200 of 4,000”. Cicero reads each font file once and remembers what it found, so later scans are quick. Now and then an update to Cicero learns something new from each font, so it reads them all again once: your fonts stay in the window meanwhile, and the capsule says “Updating font details”. If you quit before it’s done, it goes on where it stopped.

After that, Cicero checks which characters each font has, in the background. Lists that depend on it, like a [character set](character-sets.md), say “checking characters” in the window’s subtitle until it’s done.

## Find your way around

The main window has three parts:

- **The sidebar** on the left chooses what to show: **All Fonts**, **Active**, **Inactive**, **Recents**, **System Fonts** and **Conflicts**, then your **Locations**, **Folders**, **Tags**, **Foundries**, **Classifications** and **Coverage**. See [Organizing your library](organizing.md).
- **The browser** in the middle shows the families of what you chose, as a list, a grid or specimens. The title is the sidebar item’s name, and the subtitle counts the families and how many are active, like “1,298 families · 716 active”. See [Browsing and previewing](browsing.md).
- **The Info panel** on the right, shown with the **Info** button in the toolbar or **Fonts → Show Info** (⌘I), describes the selected font.

Double-click a family to open its **font page**, with a large text to type into, its styles, and its characters and ligatures.

The toolbar has, from left to right, the view switcher (List, Grid, Specimens), **Preview Options**, **Info** and the search field.

Short messages at the bottom of the window confirm what Cicero did, like “Inter activated” or “Moved to the Trash”.

## Add your fonts

Keep fonts you don’t always need in folders of your own, and add those folders to Cicero as locations:

1. Choose **File → Add Location** (⇧⌘O), or click **+** next to **Locations** in the sidebar.
2. Pick one or more folders and click **Add**.

Their fonts show up in your library without being activated: they’re listed under **Inactive** until you turn them on. See [Locations](organizing.md#locations).

You can add single font files too, without adding the folder they’re in:

- Choose **File → Add Fonts** (⌘O), or right-click Cicero’s icon in the Dock and choose **Add Fonts**, and pick the files.
- Drag font files from the Finder onto Cicero’s window, or copy them in the Finder (⌘C) and paste them into Cicero’s window (⌘V).
- In the Finder, right-click a font file and choose **Open With → Cicero**, or double-click it when Cicero is the app that opens fonts.

Cicero copies them into your Fonts folder and turns them on, and they’re in **All Fonts** like any font you’ve installed. To move them there instead, or list them where they are without turning them on, choose next to **Activate fonts by** in Preferences → General, or choose **Ask each time** to decide whenever you add fonts. See [Added Fonts](organizing.md#added-fonts).

If a file has fonts your library has already, from another file, like a newer version of one you installed, Cicero asks whether to skip it, add it as a copy or replace your copy with it. See [Fonts already in your library](organizing.md#fonts-already-in-your-library).

## Coming from FontExplorer X, FontBase or Font Book

Cicero can bring over what you set up in FontExplorer X Pro, FontBase or Font Book, so you don’t have to start again.

### FontExplorer X

1. Choose **File → Import from FontExplorer X**. Cicero finds FontExplorer X’s library on this Mac by itself; if it isn’t here, pick its database (FontExplorer X.fexdb) or a backup made with **File → Local Backup** in FontExplorer X (a `.fexconfig` or `.fexbackup`). You can also drop one on Cicero’s window. **Choose Another** picks a different one.
2. Cicero shows what it found, each with a checkbox. Uncheck what you don’t want.
3. Click **Import**.

What comes over:

- **Your fonts,** copied into your Fonts folder, or into [Cicero’s Library](activating.md#ciceros-library) when you use it: those in FontExplorer X’s Font Library and those it used from other folders. They come in inactive, apart from the ones you activate again (below), and FontExplorer X’s own files stay where they are. A font that’s there already with the same contents isn’t copied twice, so importing again copies nothing new. From a `.fexbackup` with fonts, they’re copied in from the backup. Fonts Cicero can’t use, like PostScript Type 1 fonts, font suitcases and web fonts (WOFF), stay behind, and so do sets that have only those; the import sheet says how many there are. macOS’s own fonts stay out too, even the ones FontExplorer X lists as if they were yours. A database copied from another Mac needs its Font Library where it was, in your home folder or on a disk that’s connected; if it isn’t, Cicero says where it looked, and once the folder is there, importing again brings in its fonts. If an earlier version of Cicero added the Font Library as a location, its fonts stay there and aren’t copied.
- **Sets,** as folders, with the FontExplorer X folders they were in in their names, like “Clients / Acme”. FontExplorer X puts files in sets, so a folder gets every style in its set’s files: a whole family when it has them all, otherwise just those styles.
- **Application sets,** as app folders, with their apps. An app that isn’t on this Mac is found by its name, also with another year, like Adobe InDesign 2026 for Adobe InDesign 2024. Cicero has no fonts to turn off while an app is open, so the **Autodeactivate** part stays behind.
- **Smart sets,** as smart folders, when Cicero has a rule for every one of their rules: name, family name, manufacturer (as the foundry), comment (as the note, contains or doesn’t contain), designer, whether it’s activated, whether it’s a system font, rating, the set a font is in, label, number of activations, last activated and import date (in the last 7 or 30 days). Others, like ones that look at the format or language, are listed but stay behind, as without those rules they’d pick other fonts.
- **Labels,** as tags in their colors, named after them: Red, Orange, Yellow, Green, Blue, Purple and Gray. A family gets a tag for each label its styles have.
- **Classifications.** A family goes in the classification most of its styles have in FontExplorer X, as if you’d put it there, unless you chose one already. Classifications you made in FontExplorer X come along as your own.
- **Ratings.** A family gets the stars of its best-rated style, unless you gave it a rating already.
- **Comments,** as notes. A family’s note gets the comments on its files and styles, each once, unless you wrote a note already.
- **Activations:** how often each family was turned on and when last, for the **Times Activated** and **Last Activated** rules.
- **The fonts that were active,** activated again once they’re copied in. In Cicero’s Library, Microsoft Office can’t use them. Quit FontExplorer X first, as it turns its fonts on and off itself.

License details stay in FontExplorer X. Cicero opens a copy of its database and copies the fonts, so FontExplorer X and its library stay as they are.

If you imported from FontExplorer X with Cicero 0.10.13 or earlier, Cicero added its Font Library as a location rather than copying the fonts. As it opens, Cicero offers to copy them in now: click **Copy Fonts**, and they’re copied into your Fonts folder, or Cicero’s Library when you use it. Fonts that are active now are active as their copies; the others come in inactive. Then the location goes. Your folders, tags, ratings and notes stay as they are. Click **Not Now** to keep the location; Cicero asks again the next time it opens.

### FontBase

1. Choose **File → Import from FontBase**. Cicero finds FontBase’s library on this Mac by itself; to import one from another Mac, click **Choose Another** and pick its FontBase folder, from Library/Application Support in that Mac’s home folder.
2. If FontBase is open, quit it: Cicero says so and can’t import until it has quit, because FontBase saves its library as it quits. Click **Quit FontBase** in the sheet, or quit it yourself; Cicero reads the library again then.
3. Uncheck what you don’t want, and click **Import**.

What comes over:

- **Your fonts,** copied from FontBase’s folder (~/FontBase unless you moved it) into your Fonts folder, or into Cicero’s Library when you use it, inactive apart from the ones you activate again. FontBase’s folder stays as it is.
- **Collections,** as folders, and **Favorites** as a folder of that name.
- **Tags** you gave fonts, given to their families.
- **The fonts that were active,** activated again once they’re copied in, as for FontExplorer X above. FontBase turns a font on by copying it into ~/Library/Fonts/FontBase and deletes the copies when it quits; if it left any there, Cicero offers to move them to the Trash, so those fonts aren’t on twice. When you open FontBase again, it makes those copies again, so the fonts are on twice: deactivate them in FontBase to stop that.

What stays behind, as the sheet lists it: the tags FontBase gives fonts itself (like Sans and Script), Google and FontMarket fonts you haven’t downloaded, licenses, sample texts and preview settings, and turning on new fonts in an active folder by themselves. Cicero only reads FontBase’s library and copies its fonts; FontBase and its folder stay as they are.

### Font Book

Choose **File → Import from Font Book**. Each collection you made becomes a folder with its families and styles, leaving out the fonts you took out of it in Font Book. The ones Font Book comes with, like Fun and Web, start unchecked, and smart collections stay behind. To import collections from another Mac, click **Choose Another** and pick their `.collection` files, from Library/FontCollections in that Mac’s home folder.

### Importing again

An import only adds: a folder you have with the name of one coming in gets the fonts it doesn’t have yet, and a smart folder you have with the name of one coming in stays as it is, so importing twice changes nothing, and says so: “Nothing new”. Cicero saves your current setup first, in `~/Library/Application Support/Cicero/Backups`, as it does before restoring a backup.

## Turn a font on

Click the switch next to a family. It’s on in every app as soon as the switch settles and the message says so, like “Inter activated”. To learn how Cicero turns fonts on, and the choices you have, see [Activating fonts](activating.md).

## Choose light or dark

Cicero follows macOS. To choose for Cicero alone, open **Cicero → Preferences** (⌘,), click **General** and pick **System**, **Light** or **Dark** next to **Appearance**.

## Cicero in the menu bar

Cicero has an icon in the menu bar, the cube of its app icon. Click it to open Cicero’s window. Drop font files on it to add them, or a PDF, InDesign, Illustrator or Photoshop file to see the fonts it uses. Right-click it, or click it with two fingers, for a menu with:

- The fonts that are on for open apps, because of their [app folders](activating.md#turn-fonts-on-with-an-app) or a document open in an Adobe app, and the ones on [until Cicero quits](activating.md#turn-a-font-on-just-for-now)
- Your folders, as the sidebar lists them. A checkmark means all of a folder’s fonts are on, a dash that some are. Choose a folder to turn its fonts on, or off when it has a checkmark
- **Add Fonts**, as in the File menu, and **Find Fonts in Current Document**, which shows the fonts of the document you have open in the app you’re in: a PDF in Preview or Acrobat, or a file in InDesign, Illustrator or Photoshop. The first time, macOS asks whether Cicero may control that app. With no document Cicero can read there, you pick a file instead. Cicero’s window opens too, so you see what they bring
- **Preferences** and **Quit Cicero**

Closing Cicero’s windows doesn’t quit it, so app folders keep working.

- To do without the icon, open **Preferences → General** and turn off **Show Cicero in the menu bar**
- With the icon there, you can turn off **Show Cicero in the Dock**. Cicero is then in the Dock and the app switcher only while one of its windows is open

## Keep Cicero up to date

Cicero checks for new versions each time it opens and once a day while it stays open, and asks before it installs one.

- To check now, choose **Cicero → Check for Updates**
- To stop checking by itself, open **Preferences → General** and, under **Updates**, turn off **Check for updates automatically**. It’s on at first. With it off, Cicero only checks when you choose **Check for Updates**

Updates come from Cicero’s [releases page on GitHub](https://github.com/opr-inzn/cicero/releases). **Help → Release Notes** opens it, so you can see what changed in each version.

## Get help

- **Help → Cicero Help** opens this guide.
- **Help → Report an Issue** opens a new issue on GitHub.
- To see which version you have, choose **Cicero → About Cicero**.
