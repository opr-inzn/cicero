# Privacy

[Cicero Help](README.md) › Privacy

Cicero has no accounts and no ads, and nothing about you or your fonts leaves your Mac. To count how many people use it, it sends a short note each time it opens, which you can turn off.

The full [privacy policy](https://cicero.maximilianinzinger.com/privacy), for Cicero and its website, is on the website. **Help → Privacy Policy** opens it.

## When Cicero goes online

- **Each time it opens**, to count how many people use Cicero, while **Share usage statistics** is on, under **Updates** in **Settings → General**. It’s on at first. See [Usage statistics](#usage-statistics).
- **To check GitHub for a new version** of Cicero, and to download it when you choose to install it. Cicero checks by itself while **Check for updates automatically** is on, under **Updates** in **Settings → General**. It’s on at first. Turn it off, and Cicero only checks when you choose **Cicero → Check for Updates**

## Apple Intelligence

To guess the classification of fonts nothing else classifies, Cicero gives the language model Apple Intelligence keeps on your Mac each family’s name, foundry, designer and style names. The model runs on your Mac, so nothing is sent. Cicero also guesses from the shapes of the letters, with a model of its own that comes with it, on your Mac too. To stop both, turn off **Classify fonts automatically** in **Settings → General**; Cicero then forgets its guesses. Without Apple Intelligence, Cicero guesses from the letters only.

The **Help** menu opens pages in your web browser, like this guide on GitHub and the privacy policy on Cicero’s website, and so do the links in **Settings → Coverage** and in **About Cicero**. Cicero itself doesn’t load them.

## Usage statistics

Each time Cicero opens, it sends [TelemetryDeck](https://telemetrydeck.com), a German service for counting an app’s users, a note with:

- Cicero’s version and build number
- the version of macOS
- a random number Cicero made on your Mac, hashed, so each Mac counts once however often it opens Cicero

The first time, it also sends a second note saying your Mac is new, with that day’s date, to count how many people start using Cicero.

That’s all: not your name, your Mac’s name, where you are or anything about your fonts. TelemetryDeck sees your IP address, as any website does, but doesn’t store it, and hashes the number again before it keeps it. The code that sends the note is in [UsageStatistics.swift](https://github.com/opr-inzn/cicero/blob/main/Sources/Cicero/App/UsageStatistics.swift).

To stop it, open **Settings → General** and, under **Updates**, turn off **Share usage statistics**. Cicero sends nothing more and forgets the random number; if you turn it on again, it makes a new one.

## What Cicero keeps on your Mac

| Where | What |
| --- | --- |
| `~/Library/Application Support/Cicero` | Your sets, smart sets, tags, coverage sets, folders, added fonts and settings, and a note of the fonts Cicero turned on, so it can turn them off correctly. Also the **Deactivated** folder, and the setup saved before a restore, in **Backups**. |
| `~/Library/Caches/Cicero` | What Cicero read from your font files, like names, characters and the shapes of their letters, so it doesn’t have to read them again, your font list as Cicero last found it, to show as soon as it opens, and the classifications Apple Intelligence guessed. **Fonts → Rebuild Font List** reads everything again. |

Cicero’s preferences, like the appearance and the preview options, are kept the usual macOS way, and so is the random number for the usage statistics.

Backups and exports are files you make yourself and save where you choose. Cicero doesn’t send them anywhere.

## When macOS asks for permission

- **Clearing the Microsoft Office font caches:** Office’s folders are protected, so macOS asks before Cicero looks inside them. Cicero only looks after you check **Microsoft Office** and click **Clear**.
- **Clearing the macOS font caches for all users** needs an administrator password.
- **Fonts kept in your Documents, Desktop or Downloads folder**, like font files you added from a download or a folder Cicero watches: macOS asks the first time Cicero reads them, usually as it opens. Allow it, or Cicero can’t show those fonts. macOS remembers your answer, through updates too; to change it, go to **System Settings → Privacy & Security → Files and Folders**.
- **Find on This Mac**, for a font a document uses, looks for its file with Spotlight, on your Mac. Spotlight only shows an app files in folders it may open, so the first time, macOS asks whether Cicero may look in your Documents, Desktop and Downloads folders. For this, Cicero only looks for font files there, and only when you click **Find on This Mac**.
- **Open at login** may need your approval in **System Settings → General → Login Items**.
