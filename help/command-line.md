# The Cicero CLI

[Cicero Help](README.md) › The Cicero CLI

The Cicero CLI (command-line tool) finds, checks and changes the fonts in Cicero’s library from Terminal, from scripts and from AI agents like Claude Code or Codex. It answers the way Cicero’s window does: the same search, the same classifications, foundries, tags and folders.

It works while Cicero is closed too, and it never opens Cicero. It turns fonts on and off, and gives families tags and puts them in folders.

## Install the CLI

1. Choose **Cicero → Install Cicero CLI**. Cicero needs to be in your Applications folder.
2. Enter your administrator password if macOS asks for it. Cicero puts a link to the CLI in `/usr/local/bin`.
3. Cicero says when the CLI is installed, and the menu item then reads **Cicero CLI Installed**.
4. Open Terminal and type `cicero --help`.

The CLI is inside Cicero (`Cicero.app/Contents/Helpers/cicero`), so it updates with Cicero.

## What it can do

| Command | What it shows |
|---|---|
| `cicero status` | How many families and styles, how many have a style on, when Cicero last looked through your fonts, your locations, and [conflicts](problems.md) |
| `cicero status Inter` | One family and its styles: on or off, and from where |
| `cicero status Inter --style Bold` | The same, and one style’s details: version, designer, license, embedding, coverage. A style name or a PostScript name (`Inter-Bold`) |
| `cicero status Inter --all-styles` | Every style’s details |
| `cicero find garamond` | Families, found as Cicero’s search field finds them: in names, foundries, designers, classifications, tags and notes |
| `cicero coverage Inter --set adobe-latin-3` | Whether a family has every character of a [coverage set](character-sets.md), and which it lacks |
| `cicero coverage Inter --text "Grüße, Łódź"` | The same for some text |
| `cicero list families` | Every family. Also `tags`, `folders`, `locations`, `foundries`, and `coverage` (the coverage sets and their ids) |
| `cicero activate Inter Roboto` | Turns the families on (also `cicero on`) |
| `cicero deactivate Inter` | Turns them off (also `cicero off`) |
| `cicero tag add Licensed Inter` | Gives families a tag. Also `tag create` and `tag remove` |
| `cicero folder add "Client A" Inter` | Puts families in a folder. Also `folder create` and `folder remove` |

Names don’t need capitals: `cicero status inter` works. When a name isn’t quite right, the command says which names are near.

### Find

Add any of these to `cicero find`, with or without words:

| Option | Families |
|---|---|
| `--foundry "Klim"` | from this foundry |
| `--class "Sans Serif"` | in this classification |
| `--released 2019`, `--released 2015..2020`, `--released 2015..` | that came out in a year, or between years |
| `--added 2024`, `--added 2024-03..`, `--added ..2024-03-15` | that came to your Mac on a date, or between dates |
| `--text "Ærøskøbing"` | that have every character of the text |
| `--set latin-m` | that have every character of the coverage set |
| `--missing 3` | with `--text` or `--set`: that may lack up to 3 characters |
| `--tag Licensed`, `--folder "Client A"`, `--location Archive` | with the tag, in the folder, in the location (its name or its path) |
| `--active`, `--inactive` | with a style on, with a style off |
| `--filter bold` | with a bold style. Also `italic`, `condensed`, `extended`, `variable`, a weight (`thin` … `black`, or `100` … `900`), `tnum` and `onum`. Give it more than once for more |
| `--sort name`, `--sort added`, `--sort released` | from A to Z, or the latest first |
| `--limit 20`, `--offset 20` | 20 at a time (50 at first; `--limit 0` for all), from the 21st |

For example, `cicero find --class serif --filter italic --set adobe-latin-3 --tag Licensed` lists the licensed serif families that have italics and all of Adobe Latin 3.

Coverage is the coverage of each family’s regular style, as everywhere in Cicero.

### Fonts Cicero hides

The command shows the fonts Cicero’s window shows. When **Settings → General** hides fonts that come with macOS, fonts from Creative Cloud or fonts installed for proofing in Adobe apps, the command hides them too. Add these to any command to show them, or `--no-…` to hide them, only for that command:

| Option | Shows |
|---|---|
| `--system-fonts`, `--no-system-fonts` | the fonts that come with macOS |
| `--adobe-fonts`, `--no-adobe-fonts` | Adobe Fonts, from Creative Cloud |
| `--proofing-fonts`, `--no-proofing-fonts` | the fonts installed for proofing in Adobe apps |

For example, `cicero status Helvetica --system-fonts`. The options don’t change Cicero’s settings. When `--proofing-fonts` or `--no-proofing-fonts` asks for the opposite of Cicero’s setting, the command looks through your fonts first, which takes a few seconds more.

### Change

| Command | Does |
|---|---|
| `cicero activate <families…>`, `--folder "Client A"`, `--tag Licensed` | turns on every style of the families, a folder’s fonts or the families with a tag, where they are, as Cicero does |
| `cicero activate … --until-quit` | until Cicero quits. Only while Cicero is open |
| `cicero deactivate <families…>`, `--folder`, `--tag` | turns them off |
| `cicero tag create Proofs --color blue` | makes a tag; without `--color`, in the first colour no tag has. Nothing changes when there’s a tag of that name |
| `cicero tag add Proofs <families…>`, `tag remove` | gives families the tag, or takes it off them |
| `cicero folder create "Client A"` | makes a folder. Nothing changes when there’s a folder of that name |
| `cicero folder add "Client A" <families…>`, `folder remove` | puts every style of the families in the folder, or takes them out |

Names must be exact, but capitals don’t matter. When a name isn’t right, nothing changes, and the command says which names are near.

**While Cicero is open,** Cicero makes the change, so you see it in its window at once. Fonts you turn on or off from the command get a message in Cicero’s window with **Undo**. **While Cicero is closed,** the command makes the change itself, and Cicero has it when it opens.

**Questions:** Cicero asks before it turns on more than 100 families at once, and before it moves fonts out of a folder others share (see [Activating fonts](activating.md)). The command asks the same question in Terminal: type `y` to go on. Add `--yes` to answer yes. A script or agent without a terminal gets the question in the answer (exit code 4), and nothing changes until it asks again with `--yes`.

## How up to date it is

- The list of families is the one Cicero saved the last time it looked through your fonts. `cicero status` says when that was. Cicero looks again by itself while it’s open. `cicero status --rescan` looks through your fonts first: while Cicero is open, Cicero does it and saves what it finds; while Cicero is closed, the command does it and saves it, as Cicero would at its next launch.
- Whether a font is on or off is what macOS says at the moment you run the command.
- What you change in Cicero is in the command’s answers a moment later. What you change with the command is in its answers at once.

## For scripts and agents

Add `--json` to any command. Every answer is one JSON object with `"schema": 1` first. Names are in camelCase, a field without a value is left out (never `null`), and an empty list is written as `[]`. Dates are in UTC, like `"2025-04-02T09:14:00Z"`. Later versions may add fields and new values to fields that have a list of values; a script should ignore what it doesn’t know. Renaming or removing a field would come with `"schema": 2`.

### A family

`find` and `list families` answer `{ "schema": 1, "families": [...], "total": 120, "limit": 50, "offset": 0 }`, each family with:

| Field | |
|---|---|
| `id` | the family’s name as its fonts give it; every command takes it |
| `name` | the name Cicero shows, maybe in your Mac’s language |
| `foundry` | the foundry Cicero shows it in, with your changes |
| `manufacturer` | the foundry as the font files name it |
| `class` | the classification Cicero shows it in |
| `status` | `active`, `inactive`, `partial` (some styles on), `appOnly` (on in one app only, named in `app`), `system` (comes with macOS) |
| `styleCount`, `tags`, `folders` (`id` and `name`), `rating` (1–5), `added`, `released` (a year) | |
| `version`, `designer`, `vendorID`, `fsType` (`installable`, `editable`, `previewAndPrint`, `restricted`) | `"mixed"` when the styles differ |
| `coverage` | `characterCount`, and `largest`: the largest Latin S–XL (`latin`) and Adobe Latin (`adobeLatin`) set the regular style has, as a list with one id, or none |

`status <family>` adds `note`; `copyright`, `designerURL`, `manufacturerURL`, `license` and `licenseURL`, read from the font files (`"mixed"` when the styles differ); `coverage.sets`, every coverage set the regular style has completely; and `styles`. Each style has `name`, `postScriptName`, `weight` (1–1000), `italic`, `width` (1–9), `status` (`active`, `inactive`, `appOnly`), `path`, `indexInFile`, `otherCopies` (other files with the same font) and `axes` (for a variable font: `tag`, `name`, `value`, `minimum`, `maximum`, `default`). An active style has `activeFrom`:

| `activeFrom` | The style is on |
|---|---|
| `fontsFolder` | from your Fonts folder |
| `cicero` | from [Cicero’s Library](activating.md#ciceros-library) |
| `inLocation` | where it is, in a location or added file, turned on by Cicero |
| `untilQuit` | until Cicero quits |
| `whileAppOpen` | while an app is open; `apps` names those apps |
| `allUsers` | from `/Library/Fonts`, for every account |
| `macOS` | as part of macOS |
| `adobeFonts` | from Adobe Fonts, through Creative Cloud |
| `other` | turned on by another app |

With `--style` or `--all-styles`, a style also has `version`, `released`, `designer`, `designerURL`, `manufacturer`, `manufacturerURL`, `vendorID`, `copyright`, `license`, `licenseURL`, `fsType` and, for the regular style, `coverage`.

### A change

Every change answers `{ "schema": 1, "changed": ["Inter"], "unchanged": ["Roboto"], "failed": [] }`: the families (or the tag or folder it made) that changed, those that were as asked already, and each file that couldn’t be turned on or off, as `{ "family", "path", "reason" }`.

### Other answers

- `status`: `familyCount`, `styleCount`, `activeFamilyCount`, `lastScan`, `hidden` (the fonts this answer leaves out: `systemFonts`, `adobeFonts`, `proofingFonts`), `locations` (`id`, `name`, `path`), `problems` (`kind`: `installedTwice`, `missing`, `unreadable`, `external`, `duplicates` or `sharedNames`; `message`; `paths`).
- `coverage`: `family`, `style`, `set` or `text`, `covered`, `missingCount`, `missing` (`character`, `unicode` like `"U+0151"`).
- `list tags`: `name`, `color`, `familyCount`. `list folders`: `id`, `name`, `familyCount`. `list locations`: `id`, `name`, `path`. `list foundries`: `name`, `familyCount`. `list coverage`: `id`, `name`, `group` (`latin`, `adobeLatin`, `google`, `unicode`, `custom`), `characterCount`.

### Errors

An error is `{ "schema": 1, "error": { "code": "notFound", "message": "…", "suggestions": ["Inter"] } }`, and the command exits with the codes below. A question adds `"question": { "kind": "manyFamilies", "title": "Activate 120 Families?", "message": "…" }` (`kind` is `manyFamilies` or `movingOutOfSharedFolder`).

| Exit code | `code` | |
|---|---|---|
| 0 | | it worked |
| 1 | `invalidArgument`, `unreadableUserData`, `appNotOpen`, `failed` | something in the command is wrong, Cicero’s data can’t be read, `--until-quit` while Cicero is closed, or something else went wrong |
| 2 | `notFound`, `ambiguous` | no family, style, tag, folder or set of that name (`suggestions` has near names), or more than one (`suggestions` says which) |
| 4 | `needsConfirmation` | the change asks first; nothing changed. Ask the user, then run it again with `--yes` |
| 5 | `busy` | Cicero is open but didn’t take the change within 5 seconds, or another `cicero` command was making one; nothing changed |

## Questions

### Does the command change anything?

Only `activate`, `deactivate`, `tag` and `folder` change things. The other commands only read what Cicero saved. `--rescan`, while Cicero is closed, updates Cicero’s saved list of fonts, as Cicero would at its next launch. The options for hidden fonts don’t change Cicero’s settings.

### What if the command stops while it turns fonts on or off?

If the command stops in the middle, for example because you press Control-C or the Mac switches off, some fonts can be on or off without Cicero knowing it. The next `cicero` change, or Cicero when it opens, puts this right. It doesn’t turn fonts on or off again. It notes which fonts are on and off now.

### Can the command and Cicero change things at the same time?

No. Only one of them changes Cicero’s data at a time. While Cicero is open, the command asks Cicero to make the change. While Cicero is closed, the command makes it, and a Cicero that opens meanwhile waits until it’s done. If that takes more than a moment, Cicero says what it waits for, and you can quit it.

### Why doesn’t it find a font that comes with macOS?

When **Show system fonts** is off in **Settings → General**, the command leaves those fonts out too, as Cicero’s window does. It says so when you ask for one by name. Add `--system-fonts` to see them (see [Fonts Cicero hides](#fonts-cicero-hides)).

### How do I remove the command?

In Terminal, type `sudo rm /usr/local/bin/cicero`. Cicero itself stays as it is.
