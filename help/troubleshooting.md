# Troubleshooting

[Cicero Help](README.md) › Troubleshooting

## An app doesn’t see a font

Go through these in order:

1. **Is the font on?** Find it in Cicero and look at its switch. A family tagged **Partly active** has some styles off; open its font page to see which.
2. **Is it on in every app?** A font tagged **Proofing** or with an app’s name is on in that app only. Click its switch to turn it on everywhere. One tagged **Adobe Fonts** with its switch halfway is on in Adobe apps only: turn it on in Creative Cloud to use it everywhere (see [Adobe Fonts](activating.md#adobe-fonts)). See [Fonts in Adobe apps’ folders](activating.md#fonts-in-adobe-apps-folders).
3. **Was it on just for a while?** Fonts turned on temporarily go off when Cicero quits. Fonts from an [app folder](activating.md#turn-fonts-on-with-an-app) are only on while one of the folder’s apps is open and Cicero is running.
4. **Is it Microsoft Office?** Office apps, like Word and PowerPoint, only use fonts copied into your Fonts folder, not fonts used where they are, and only from the second time they open after the font went on. See [Fonts in Microsoft Office](activating.md#fonts-in-microsoft-office).
5. **Restart the app.** Most apps see a font as soon as Cicero turns it on, but some only read the font list when they open.
6. **Look in Conflicts.** A font used from a disk that’s unplugged, a file that’s gone, or an older copy of the same font on twice can all keep the right font from showing. See [Conflicts](problems.md).
7. **Clear the font caches**, as below, and restart your Mac.

## Clear the font caches

macOS and some apps keep lists of fonts that can go stale after fonts change. Fonts then don’t show up in apps, show up twice, or look wrong. Clearing the caches makes the lists get rebuilt. You may need to restart your Mac afterwards.

1. Choose **Fonts → Clear Font Caches**, or click **Clear** next to **macOS, Adobe and Office font caches** in **Settings → General**.
2. Check the caches to clear:
   - **macOS (my account):** removes your account’s font caches and restarts the font service.
   - **macOS (all users):** the same for every account on the Mac. It needs an administrator password.
   - **Adobe apps:** moves the font caches Adobe apps keep to the Trash, and says how big they are. Quit Adobe apps first; while one is open, this says “Quit” and the app’s name, and you can’t check it.
   - **Microsoft Office:** moves Office’s font caches to the Trash. macOS asks for your permission before Cicero looks inside Office’s folders. Quit Office apps first.
3. Click **Clear**.

The apps rebuild their caches the next time they open. Afterwards, Cicero rebuilds its own font list. When you cleared the macOS caches, Cicero offers **Restart Now**, because apps that are open keep using the old caches until you restart your Mac.

## Rescan or rebuild the font list

Cicero follows changes by itself: it looks again when fonts are turned on or off, by any app, when files come or go in your locations, and when you come back to Cicero after a while. If its list still looks out of date:

- **Fonts → Rescan Library** (⌘R) looks through your fonts again. It’s quick, because Cicero remembers what it read from each file.
- **Fonts → Rebuild Font List**, or **Rebuild** next to **Library** in **Settings → General**, forgets what Cicero remembered and reads every font file again. It takes longer. Use it when a font’s details look wrong.

## A font won’t turn off

- Fonts that come with macOS, fonts installed for all users, fonts that come with an app, and Adobe Fonts from Creative Cloud can’t be turned off in Cicero. See [Fonts Cicero can’t turn off](activating.md#fonts-cicero-cant-turn-off).
- Fonts in some app folders, like InDesign’s, stay on in that app, because Cicero can’t move files out of those folders. See [The three-position switch](activating.md#the-three-position-switch).
- If a message says Cicero couldn’t deactivate a font, check that you can change the folder its file is in, then try again.

## Where did my font file go?

Turning a font off leaves a file in your Fonts folder where it is. Files that were in an app’s font folder are in Cicero’s **Deactivated** folder, `~/Library/Application Support/Cicero/Deactivated`. To find a font’s file, right-click the family and choose **Reveal in Finder**.

When you choose another copy with **Use Copy From**, a copy Cicero had installed goes to the Trash if the original is still there. The original stays where it was.

See [Turn fonts off](activating.md#turn-fonts-off).

## Questions and answers

### Does Cicero change my font files?

No. Cicero never edits a font file. It copies files into your Fonts folder, or Cicero’s Library, when you install a copy, moves files out of an app’s font folder into its Deactivated folder when you turn them off, and moves files to the Trash only when you ask, or when a copy it installed is no longer needed.

### What happens to my fonts when I quit Cicero?

Fonts you turned on stay on, whether Cicero copied them or uses them where they are. Fonts you turned on temporarily go off. App folders stop following your apps until Cicero opens again; fonts already on for an open app stay on until then, or until you log out.

### A font in my Fonts folder shows as Inactive

That’s right: its file is still in a Fonts folder, but it’s turned off in macOS, by Cicero or by Font Book. Turn it on in Cicero and Cicero turns it on where it is.

### Why are some fonts tagged System?

They come with macOS, which needs them, so they’re always on. To keep them out of your lists, turn off **Show system fonts** in **Settings → General**.

### Which file formats does Cicero read?

OpenType and TrueType fonts (`.otf`, `.ttf`), font collections (`.ttc`, `.otc`) and Mac datafork fonts (`.dfont`).

Web fonts (`.woff`, `.woff2`) are made for websites, and Adobe apps can’t use them, so Cicero leaves them out. One that’s on already stays on, but Cicero doesn’t list it: to turn it off, take it out of the Fonts folder in your Library. Nor does Cicero read PostScript Type 1 fonts, which Adobe apps no longer support either. Use the OpenType or TrueType versions of these fonts instead.

### A folder in iCloud Drive looks empty in Cicero

Files that are kept only in iCloud aren’t on your Mac, and Cicero skips them so it doesn’t download them by reading them. Download them in the Finder, and Cicero lists them.

### Why does a font support a language it doesn’t display correctly?

Cicero checks that a font has the characters a language needs, not that it joins or positions them correctly. See [How Cicero decides a font supports a language](character-sets.md#how-cicero-decides-a-font-supports-a-language).

### How do I move Cicero to a new Mac?

Make a backup with **Include font files** checked, copy the `.cicerobackup` file to the new Mac, install Cicero there and restore it. See [Export, backup and restore](export-and-backup.md).

### Where does Cicero keep its data?

In `~/Library/Application Support/Cicero` and `~/Library/Caches/Cicero`, on your Mac only. See [Privacy](privacy.md).

### How do I report a bug or ask a question?

Choose **Help → Report an Issue**. It opens a new issue on GitHub. Say which version you have (**Cicero → About Cicero**) and what you did.
