# Privacy

[Cicero Help](README.md) › Privacy

Cicero doesn’t track you. It has no analytics, no accounts and no ads, and nothing about you or your fonts leaves your Mac.

The full [privacy policy](https://cicero.maximilianinzinger.com/privacy), for Cicero and its website, is on the website. **Help → Privacy Policy** opens it.

## When Cicero goes online

Only to check GitHub for a new version of Cicero, and to download it when you choose to install it.

- Cicero checks by itself while **Check for updates automatically** is on, under **Updates** in **Settings → General**. It’s on at first.
- Turn it off, and Cicero only checks when you choose **Cicero → Check for Updates**

The **Help** menu opens pages in your web browser, like this guide on GitHub and the privacy policy on Cicero’s website, and so do the links in **Settings → Coverage** and in **About Cicero**. Cicero itself doesn’t load them.

## What Cicero keeps on your Mac

| Where | What |
| --- | --- |
| `~/Library/Application Support/Cicero` | Your sets, smart sets, tags, coverage sets, folders, added fonts and settings, and a note of the fonts Cicero turned on, so it can turn them off correctly. Also the **Deactivated** folder, and the setup saved before a restore, in **Backups**. |
| `~/Library/Caches/Cicero` | What Cicero read from your font files, like names and characters, so it doesn’t have to read them again. **Fonts → Rebuild Font List** reads everything again. |

Cicero’s preferences, like the appearance and the preview options, are kept the usual macOS way.

Backups and exports are files you make yourself and save where you choose. Cicero doesn’t send them anywhere.

## When macOS asks for permission

- **Clearing the Microsoft Office font caches:** Office’s folders are protected, so macOS asks before Cicero looks inside them. Cicero only looks after you check **Microsoft Office** and click **Clear**.
- **Clearing the macOS font caches for all users** needs an administrator password.
- **Find on This Mac**, for a font a document uses, looks for its file with Spotlight, on your Mac. Spotlight only shows an app files in folders it may open, so the first time, macOS asks whether Cicero may look in your Documents, Desktop and Downloads folders. Cicero only looks for font files there, and only when you click **Find on This Mac**.
- **Open at login** may need your approval in **System Settings → General → Login Items**.
