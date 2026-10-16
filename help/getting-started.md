# Getting started

[Cicero Help](README.md) › Getting started

## What you need

A Mac with Apple silicon and macOS 26.

## Install Cicero

1. Download [Cicero.dmg](https://github.com/opr-inzn/cicero/releases/latest/download/Cicero.dmg), the latest version.
2. Open the disk image and drag **Cicero** onto the **Applications** folder next to it.
3. Open Cicero from your Applications folder.

## Move Cicero to Applications

If you open Cicero right from the disk image or from your Downloads folder, it offers to move itself to the Applications folder. Let it: [application sets](activating.md#turn-fonts-on-with-an-app), [Open at login](activating.md#open-cicero-at-login) and [updates](#keep-cicero-up-to-date) only work when Cicero is in Applications.

If you say no and later turn on **Open at login**, Cicero offers again. You can also quit Cicero and drag it into Applications yourself in the Finder.

## The first launch

Cicero looks for fonts in these places:

- every font macOS has turned on, and every font that comes with macOS
- the Adobe Fonts that Adobe apps turned on by themselves, which only they use
- your Fonts folder, `~/Library/Fonts`
- the Fonts folder for all users, `/Library/Fonts`
- the folders Adobe apps load fonts from by themselves, where type designers put fonts to test them (see [Fonts in Adobe apps’ folders](activating.md#fonts-in-adobe-apps-folders))

Looking changes nothing: no font is turned on, off, copied or moved until you ask.

When a scan takes a moment, a small capsule at the bottom right says what Cicero is doing, like “Identifying fonts 200 of 4,000”. Cicero reads each font file once and remembers what it found, so later scans are quick.

After that, Cicero checks which characters each font has, in the background. Lists that depend on it, like a [character set](character-sets.md), say “checking characters” in the window’s subtitle until it’s done.

## Find your way around

The main window has three parts:

- **The sidebar** on the left chooses what to show: **All Fonts**, **Active**, **Inactive**, **System Fonts** and **Problems**, then your **Folders**, **Sets**, **Tags**, **Foundries**, **Classifications** and **Coverage**. See [Organizing your library](organizing.md).
- **The browser** in the middle shows the families of what you chose, as a list, a grid or specimens. The title is the sidebar item’s name, and the subtitle counts the families and how many are active, like “1,298 families · 716 active”. See [Browsing and previewing](browsing.md).
- **The Info panel** on the right, shown with the **Info** button in the toolbar or **Fonts → Show Info** (⌘I), describes the selected font.

Double-click a family to open its **font page**, with a large text to type into, its styles, its ligatures and its characters.

The toolbar has, from left to right, the view switcher (List, Grid, Specimens), **Preview Options**, **Info** and the search field.

Short messages at the bottom of the window confirm what Cicero did, like “Activated” or “Moved to the Trash”.

## Add your fonts

Keep fonts you don’t always need in folders of your own, and add those folders to Cicero:

1. Choose **File → Add Folder** (⇧⌘O), or click **+** next to **Folders** in the sidebar.
2. Pick one or more folders and click **Add**.

Their fonts show up in your library without being activated: they’re listed under **Inactive** until you turn them on. See [Folders](organizing.md#folders).

You can add single font files too, without adding the folder they’re in:

- Choose **File → Add Fonts** (⌘O) and pick the files.
- Drag font files from the Finder onto Cicero’s window.
- In the Finder, right-click a font file and choose **Open With → Cicero**, or double-click it when Cicero is the app that opens fonts.

They’re listed where they are, under **Added Fonts**, without being activated. If you chose **Copy into ~/Library/Fonts** or **Move into ~/Library/Fonts** in Settings → General, they’re copied or moved into your Fonts folder instead and turned on, and they’re in **All Fonts** like any font you’ve installed. See [Added Fonts](organizing.md#added-fonts).

## Turn a font on

Click the switch next to a family. It’s on in every app as soon as the switch settles and the message says “Activated”. To learn how Cicero turns fonts on, and the choices you have, see [Activating fonts](activating.md).

## Choose light or dark

Cicero follows macOS. To choose for Cicero alone, open **Cicero → Settings** (⌘,), click **General** and pick **System**, **Light** or **Dark** next to **Appearance**.

## Keep Cicero up to date

Cicero checks for new versions by itself and asks before it installs one.

- To check now, choose **Cicero → Check for Updates**
- To stop checking by itself, open **Settings → General** and, under **Updates**, turn off **Check for updates automatically**. It’s on at first. With it off, Cicero only checks when you choose **Check for Updates**

Updates come from Cicero’s [releases page on GitHub](https://github.com/opr-inzn/cicero/releases). **Help → Release Notes** opens it, so you can see what changed in each version.

## Get help

- **Help → Cicero Help** opens this guide.
- **Help → Report an Issue** opens a new issue on GitHub.
- To see which version you have, choose **Cicero → About Cicero**.
