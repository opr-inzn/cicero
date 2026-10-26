# Privacy

[Cicero Help](README.md) › Privacy

Cicero has no accounts and no ads. To count how many people use it, it sends a short note each time it opens, and when you mark a family not similar to another, it reports which, to improve similar fonts. One switch turns off both, and your marks then stay on your Mac. Apart from those reports, nothing about your fonts leaves your Mac.

The full [privacy policy](https://cicero.maximilianinzinger.com/privacy), for Cicero and its website, is on the website. **Help → Privacy Policy** opens it.

## When Cicero goes online

- **Each time it opens**, to count how many people use Cicero, while **Share usage statistics** is on, under **Updates** in **Settings → General**. It’s on at first. See [Usage statistics](#usage-statistics).
- **When you mark a family not similar**, to report it, while **Share usage statistics** is on, as above. See [Not-similar reports](#not-similar-reports).
- **To check GitHub for a new version** of Cicero, and to download it when you choose to install it. Cicero checks by itself, each time it opens and once a day while it stays open, as long as **Check for updates automatically** is on, under **Updates** in **Settings → General**. It’s on at first. Turn it off, and Cicero only checks when you choose **Cicero → Check for Updates**

## Apple Intelligence

To recognize the classification of fonts nothing else classifies, Cicero on macOS 26 gives the language model Apple Intelligence keeps on your Mac each family’s name, foundry, designer and style names. The model runs on your Mac, so nothing is sent. Cicero also recognizes classifications from the shapes of the letters, with a model of its own that comes with it, on your Mac too. To stop both, turn off **Classify fonts automatically** in **Settings → General**; Cicero then forgets the classifications it recognized. Without Apple Intelligence, and on macOS 15, Cicero recognizes them from the letters only.

The **Help** menu opens pages in your web browser, like this guide on GitHub and the privacy policy on Cicero’s website, and so do the links in **Settings → Coverage** and in **About Cicero**. Cicero itself doesn’t load them.

## Usage statistics

Each time Cicero opens, it sends [TelemetryDeck](https://telemetrydeck.com), a German service for counting an app’s users, a note with:

- Cicero’s version and build number
- the version of macOS
- a random number Cicero made on your Mac, hashed, so each Mac counts once however often it opens Cicero

The first time, it also sends a second note saying your Mac is new, with that day’s date, to count how many people start using Cicero.

That’s all: not your name, your Mac’s name, where you are or anything about your fonts. TelemetryDeck sees your IP address, as any website does, but doesn’t store it, and hashes the number again before it keeps it. The code that sends the note is in [UsageStatistics.swift](https://github.com/opr-inzn/cicero/blob/main/Sources/Cicero/App/UsageStatistics.swift).

To stop it, open **Settings → General** and, under **Updates**, turn off **Share usage statistics**. Cicero sends nothing more, no [not-similar reports](#not-similar-reports) either, and forgets the random number; if you turn it on again, it makes a new one.

## Not-similar reports

When you mark a family [not similar](browsing.md#find-similar-fonts) to the one it was listed for, Cicero sends its website a report, so that a later version can tell such families apart. It waits until **Undo** is gone, so a mark you undo isn’t sent. The report holds:

- the name of the family the list was for, and the names of the families in that list as you saw it, the one you marked among them, with the name of the style Cicero measured each by and its foundry and classification as Cicero shows them
- the numbers Cicero worked out from their letters on your Mac, to compare them: the measurements, like how tall the lowercase is and how heavy the strokes are, the 128 numbers its model sees in them, and how far apart Cicero found them
- Cicero’s version and build number, the version of macOS, and which version of the measurements and the model the numbers come from
- a random number Cicero made on your Mac, hashed, so that several reports from one Mac count as one person’s

That’s all: not the font files, not pictures of the letters, not your name, your Mac’s name or the rest of your library. Cicero sends at most 20 reports a day; families you mark after that stay out of your lists all the same, on your Mac. The website keeps each report, with the time it arrived but not your IP address, to improve similar fonts. The code that sends it is in [SimilarReports.swift](https://github.com/opr-inzn/cicero/blob/main/Sources/Cicero/App/SimilarReports.swift).

To stop it, open **Settings → General** and, under **Updates**, turn off **Share usage statistics**, which stops the [usage statistics](#usage-statistics) too. Marking a family not similar then only takes it out of the list, on your Mac: Cicero sends nothing, and forgets the random number.

## What Cicero keeps on your Mac

| Where | What |
| --- | --- |
| `~/Library/Application Support/Cicero` | Your folders, smart folders, tags, coverage sets, locations, added fonts and settings, the families you marked not similar, and a note of the fonts Cicero turned on, so it can turn them off correctly. Also the **Deactivated** folder, and the setup saved before a restore, in **Backups**. |
| `~/Cicero/Library` | The fonts Cicero installs, when you keep them in its [Font Library](activating.md#the-font-library), unless you moved it. |
| `~/Library/Caches/Cicero` | What Cicero read from your font files, like names, characters and the shapes of their letters, so it doesn’t have to read them again, your font list as Cicero last found it, to show as soon as it opens, and the classifications Apple Intelligence recognized. **Fonts → Rebuild Font List** reads everything again. |

Cicero’s preferences, like the appearance and the preview options, are kept the usual macOS way, and so are the random numbers for the usage statistics and the not-similar reports.

Backups and exports are files you make yourself and save where you choose. Cicero doesn’t send them anywhere.

## When macOS asks for permission

- **Clearing the Microsoft Office font caches:** Office’s folders are protected, so macOS asks before Cicero looks inside them. Cicero only looks after you check **Microsoft Office** and click **Clear**.
- **Clearing the macOS font caches for all users** needs an administrator password.
- **Fonts kept in your Documents, Desktop or Downloads folder**, like font files you added from a download, a folder you added as a location, or the Font Library if you moved it there: macOS asks the first time Cicero reads them, usually as it opens. Allow it, or Cicero can’t show those fonts. macOS remembers your answer, through updates too; to change it, go to **System Settings → Privacy & Security → Files and Folders**.
- **Find on This Mac**, for a font a document uses, looks for its file with Spotlight, on your Mac. Spotlight only shows an app files in folders it may open, so the first time, macOS asks whether Cicero may look in your Documents, Desktop and Downloads folders. For this, Cicero only looks for font files there, and only when you click **Find on This Mac**.
- **Fonts documents use in Adobe apps:** macOS asks the first time whether Cicero may control each app. Cicero only asks the app which fonts its open documents use, or which files they are, and changes nothing in it.
- **Find Fonts in Current Document** (in the menu bar): macOS asks the first time whether Cicero may control the app you’re in, like Preview or InDesign. Cicero only asks it which document is open, or which fonts it uses, and changes nothing in it. See [Activating fonts](activating.md#fonts-documents-open-in-adobe-apps-use).
- **Open at login** may need your approval in **System Settings → General → Login Items**.
