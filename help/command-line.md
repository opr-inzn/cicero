# The Cicero CLI

[Cicero Help](README.md) › The Cicero CLI

The Cicero CLI (command-line tool) finds, checks and changes the fonts in Cicero’s library from Terminal, from scripts and from AI agents like Claude Code or Codex. It answers the way Cicero’s window does: the same search, the same classifications, foundries, tags and folders.

It works while Cicero is closed too, and it never opens Cicero. It turns fonts on and off, gives families tags, ratings and notes, and puts them in folders.

## Install the CLI

1. Choose **Cicero → Install Cicero CLI**. Cicero needs to be in your Applications folder.
2. Enter your administrator password if macOS asks for it. Cicero puts a link to the CLI in `/usr/local/bin`, and links to its Tab completion for zsh, bash and fish in `/usr/local/share`.
3. Cicero says when the CLI is installed, and the menu item then reads **Cicero CLI installed**.
4. Open Terminal and type `cicero --help`.

The CLI is inside Cicero (`Cicero.app/Contents/Helpers/cicero`), so it updates with Cicero.

If you installed the CLI with an earlier beta, the menu item reads **Install Cicero CLI** again: choose it once more to add Tab completion, or its bash and fish parts.

### Tab completion

In Terminal, press Tab to complete what you type: commands (`cicero fi` becomes `cicero find`), options, and names from your library: families, styles, tags, folders, locations, foundries, classifications and coverage sets. Press Tab twice to see every choice. `cicero status Hel` and Tab shows the families whose names start with “Hel”.

Tab completion works in zsh, the shell Terminal uses unless you changed it. macOS has zsh’s completion off. When it’s off on your Mac, Cicero says so after it installs the CLI: click **Turn On Tab Completion**, and Cicero adds this line at the end of the file `.zshrc` in your home folder. Then open a new Terminal window.

```
autoload -Uz compinit && compinit -i
```

To turn it on later, choose **Cicero → Cicero CLI installed**, or add the line yourself. To turn it off, take the line out of `.zshrc`.

In fish, Tab completion works when the CLI is installed. Open a new window.

In bash, Tab completion needs bash-completion, which the bash that comes with macOS doesn’t have. Install bash and bash-completion with Homebrew (`brew install bash bash-completion@2`) and turn it on as Homebrew says. Then Tab completes `cicero` too.

## Use it in Claude and Codex

AI agents can use Cicero through the CLI’s MCP server (Model Context Protocol), `cicero mcp`. The agent then has each command as a tool: `find`, `status`, `coverage`, `compare`, `list`, `activate`, `deactivate`, `rate`, `note`, and `tag_create`, `tag_add`, `folder_add` and the other `tag` and `folder` commands. It gets the same answers as `--json` gives, and it sees the pictures `compare` draws. Apps without a terminal, like Claude Desktop, can use Cicero this way too.

Install the CLI first (see [Install the CLI](#install-the-cli)). Then add Cicero to your agent app:

**Claude Code:** in Terminal, type

```
claude mcp add --scope user cicero -- /usr/local/bin/cicero mcp
```

**Codex:** in Terminal, type

```
codex mcp add cicero -- /usr/local/bin/cicero mcp
```

or add these lines to the file `~/.codex/config.toml`:

```toml
[mcp_servers.cicero]
command = "/usr/local/bin/cicero"
args = ["mcp"]
```

**Claude Desktop:** add `cicero` to `mcpServers` in the file `~/Library/Application Support/Claude/claude_desktop_config.json` (in Claude Desktop: **Settings → Developer → Edit config**), then quit Claude Desktop and open it again:

```json
{
  "mcpServers": {
    "cicero": { "command": "/usr/local/bin/cicero", "args": ["mcp"] }
  }
}
```

Then ask, for example: “Which of my serif fonts have all of Adobe Latin 3? Show me three of them side by side.”

- **The tools’ inputs** are the command’s options without `--`, in camelCase: `--all-styles` is `allStyles`, `--system-fonts` is `systemFonts` (and `false` for `--no-system-fonts`). The names a command takes are `family`, `families`, `names`, `words`, `tag` or `folder`, as in its help.
- **Changes.** The tools tell the agent app which ones only read, and which ones turn fonts off or take tags, folders and families away, so it can ask you first. When Cicero asks before a change (more than 100 families, or fonts moving out of a folder others share), the tool answers with the question and changes nothing. The agent then asks you, and does the change only when you say yes.
- **Only find and check:** use `cicero mcp --read-only` in place of `cicero mcp`. The agent then has no tools that change things.
- **Pictures** from `compare` go in the temporary folder (the tool has no `png` input, so an agent can’t write over your files with it), and to the agent up to 8000 pixels high and wide. For a larger picture, the agent gets only its path.
- The agent app starts `cicero mcp` itself and stops it when it quits. It never opens Cicero. Each tool reads your library again, so it always has what you changed in Cicero.

## What it can do

| Command | What it shows |
|---|---|
| `cicero status` | How many families and styles, how many have a style on, when Cicero last looked through your fonts, your locations, and [conflicts](problems.md) |
| `cicero status Inter` | One family and its styles: on or off, and from where |
| `cicero status Inter --style Bold` | The same, and one style’s details: version, designer, license, embedding, coverage. A style name or a PostScript name (`Inter-Bold`) |
| `cicero status Inter --all-styles` | Every style’s details |
| `cicero find garamond` | Families, found as Cicero’s search field finds them: in names, foundries, designers, classifications, tags and notes. Also in the fonts’ licenses, descriptions and web addresses (`cicero find rosettatype.com`), which the search field doesn’t look in yet |
| `cicero coverage Inter --set adobe-latin-3` | Whether a family has every character of a [coverage set](character-sets.md), and which it lacks. Exit code 3 when it lacks some |
| `cicero coverage Inter --text "Grüße, Łódź"` | The same for some text |
| `cicero compare Inter "Source Sans 3" --text "Ορθόδοξοι υπότιτλοι" --png out.png` | A picture of the same text in each family, under its name, for you or an AI agent to look at (see [Compare](#compare)) |
| `cicero list families` | Every family. Also `tags`, `folders`, `locations`, `foundries`, and `coverage` (the coverage sets and their ids) |
| `cicero activate Inter Roboto` | Turns the families on (also `cicero on`) |
| `cicero deactivate Inter` | Turns them off (also `cicero off`) |
| `cicero tag add Licensed Inter` | Gives families a tag. Also `tag create`, `tag remove`, `tag rename` and `tag delete` |
| `cicero folder add "Client A" Inter` | Puts families in a folder. Also `folder create`, `folder remove`, `folder rename` and `folder delete` |
| `cicero rate Inter Roboto --stars 5` | Gives families a rating from 1 to 5 stars |
| `cicero note Inter "Licensed for the website"` | Writes a family’s note |

Names don’t need capitals: `cicero status inter` works. When a name isn’t quite right, the command says which names are near.

### Find

Words are found where a word begins, in every field: each word must be found in one of them. With words, `find` also reads the license, the description, and the license, manufacturer and designer URLs (OpenType name IDs 13, 10, 14, 11 and 12) of every style from its font file, so it takes longer: about a second for 7,000 styles.

Add `--any` to find the families that have any of the words, not all of them. Each word is a search of its own; words in quotes are one search, and must all be found, as without `--any`. For example, foundries call their trial fonts “Trial”, “Unlicensed” or “Test”: `cicero find trial unlicensed test --any` finds them all.

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

### Compare

`cicero compare` draws the families you name in one PNG picture, one under the other, each under a small label with its name. An AI agent can look at the picture when it helps you choose fonts, and not only read their data.

| Option | Does |
|---|---|
| `--text "Grüße, Łódź"` | draws this text. Without it, “Sphinx of black quartz, judge my vow.” A line break in the text starts a new line |
| `--all-styles` | draws every style of the families, not only the regular style |
| `--size 72` | the letters’ size in pixels, from 6 to 400 (48 at first) |
| `--width 1600` | the picture’s width in pixels, from 200 to 8000 (1200 at first). Long text goes on to the next line. A picture can have at most 36 million pixels (8000 wide: 4500 high) |
| `--png ~/Desktop/fonts.png` | where to put the picture. Without it, the picture goes in a temporary folder, and the command says where |

Instead of a family, you can name one style: by its PostScript name (`Inter-Bold`), its full name, or the family’s name and the style’s name (`"Inter Bold"`). Up to 50 styles fit in one picture.

Cicero draws each font from its file, on or off. **When a font doesn’t have a character of the text, Cicero draws the font’s own .notdef glyph in its place:** the shape the font shows for a character it lacks, often a box. It never draws the character from another font. When a font’s .notdef is empty, the place stays empty, as wide as the font makes it. The label says in red which characters the font lacks. When Cicero can’t read a font’s file, the label says so and nothing is drawn for that font.

### Fonts Cicero hides

The command shows the fonts Cicero’s window shows. When **Preferences → General** hides fonts that come with macOS, fonts from Creative Cloud or fonts installed for proofing in Adobe apps, the command hides them too. Add these to any command to show them, or `--no-…` to hide them, only for that command:

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
| `cicero tag rename Proofs "Proofs 2026"` | renames a tag. The families that have it keep it. Stops when another tag has that name |
| `cicero tag delete Proofs <tags…>` | deletes tags: they come off every family. The fonts stay |
| `cicero folder create "Client A"` | makes a folder. Nothing changes when there’s a folder of that name |
| `cicero folder add "Client A" <families…>`, `folder remove` | puts every style of the families in the folder, or takes them out |
| `cicero folder rename "Client A" "Client B"` | renames a folder. Stops when another folder has that name |
| `cicero folder delete "Client A" <folders…>` | deletes folders. Their fonts stay in the library, on or off as they are |
| `cicero rate <families…> --stars 5` | gives the families 5 stars, as the stars in the Info panel. `--stars 0` takes the rating away |
| `cicero note Inter "Licensed for the website"` | writes the family’s note, in place of the note there was. `""` takes the note away |
| `cicero note Inter "Second proof approved" --append` | adds the text after the note, on a new line |

Names must be exact, but capitals don’t matter. When a name isn’t right, nothing changes, and the command says which names are near. When you give more names than one, nothing changes if one of them isn’t right.

`tag delete` and `folder delete` don’t ask first, as in Cicero. A smart folder that used a deleted tag or folder loses that rule.

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

`status <family>` adds `note`; `description`, `copyright`, `designerURL`, `manufacturerURL`, `license` and `licenseURL`, read from the font files (`"mixed"` when the styles differ); `coverage.sets`, every coverage set the regular style has completely; and `styles`. Each style has `name`, `postScriptName`, `weight` (1–1000), `italic`, `width` (1–9), `status` (`active`, `inactive`, `appOnly`), `path`, `indexInFile`, `otherCopies` (other files with the same font) and `axes` (for a variable font: `tag`, `name`, `value`, `minimum`, `maximum`, `default`). An active style has `activeFrom`:

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

With `--style` or `--all-styles`, a style also has `version`, `released`, `designer`, `designerURL`, `manufacturer`, `manufacturerURL`, `vendorID`, `description`, `copyright`, `license`, `licenseURL`, `fsType` and, for the regular style, `coverage`.

### A change

Every change answers `{ "schema": 1, "changed": ["Inter"], "unchanged": ["Roboto"], "failed": [] }`: the families (or the tag or folder it made) that changed, those that were as asked already, and each file that couldn’t be turned on or off, as `{ "family", "path", "reason" }`.

### Other answers

- `status`: `familyCount`, `styleCount`, `activeFamilyCount`, `lastScan`, `hidden` (the fonts this answer leaves out: `systemFonts`, `adobeFonts`, `proofingFonts`), `locations` (`id`, `name`, `path`), `problems` (`kind`: `installedTwice`, `missing`, `unreadable`, `external`, `duplicates` or `sharedNames`; `message`; `paths`).
- `coverage`: `family`, `style`, `set` or `text`, `covered`, `missingCount`, `missing` (`character`, `unicode` like `"U+0151"`).
- `compare`: `png` (the picture’s full path), `width` and `height` (in pixels), `text`, `size`, and `samples`, from the top of the picture: `family`, `style`, `postScriptName`, `path`, `missingCount`, `missing` (as for `coverage`), and `unreadable: true` when Cicero can’t read the font’s file.
- `list tags`: `name`, `color`, `familyCount`. `list folders`: `id`, `name`, `familyCount`. `list locations`: `id`, `name`, `path`. `list foundries`: `name`, `familyCount`. `list coverage`: `id`, `name`, `group` (`latin`, `adobeLatin`, `google`, `unicode`, `custom`), `characterCount`.

### Errors

An error is `{ "schema": 1, "error": { "code": "notFound", "message": "…", "suggestions": ["Inter"] } }`, and the command exits with the codes below. A question adds `"question": { "kind": "manyFamilies", "title": "Activate 120 Families?", "message": "…" }` (`kind` is `manyFamilies` or `movingOutOfSharedFolder`).

| Exit code | `code` | |
|---|---|---|
| 0 | | it worked |
| 1 | `invalidArgument`, `unreadableUserData`, `appNotOpen`, `failed` | something in the command is wrong (an unknown option or a missing name too), Cicero’s data can’t be read, `--until-quit` while Cicero is closed, or something else went wrong (like a `--png` folder that isn’t there) |
| 2 | `notFound`, `ambiguous` | no family, style, tag, folder or set of that name (`suggestions` has near names), or more than one (`suggestions` says which) |
| 4 | `needsConfirmation` | the change asks first; nothing changed. Ask the user, then run it again with `--yes` |
| 5 | `busy` | Cicero is open but didn’t take the change within 5 seconds, or another `cicero` command was making one; nothing changed |

`activate` and `deactivate` exit with 6 when a file couldn’t be turned on or off, also when others could. The answer is the same as with 0: `failed` lists those files and why, `changed` the families that did change.

`coverage` exits with 3 when the family lacks characters. It isn’t an error: the answer is the same as with 0, with `"covered": false`. A script can ask `if cicero coverage Inter --set adobe-latin-3 > /dev/null` without reading the JSON.

## Questions

### Does the command change anything?

Only `activate`, `deactivate`, `tag`, `folder`, `rate` and `note` change things. The other commands only read what Cicero saved. `compare` writes only its picture. `--rescan`, while Cicero is closed, updates Cicero’s saved list of fonts, as Cicero would at its next launch. The options for hidden fonts don’t change Cicero’s settings.

### What if the command stops while it turns fonts on or off?

If the command stops in the middle, for example because you press Control-C or the Mac switches off, some fonts can be on or off without Cicero knowing it. The next `cicero` change, or Cicero when it opens, puts this right. It doesn’t turn fonts on or off again. It notes which fonts are on and off now.

### Can the command and Cicero change things at the same time?

No. Only one of them changes Cicero’s data at a time. While Cicero is open, the command asks Cicero to make the change. While Cicero is closed, the command makes it, and a Cicero that opens meanwhile waits until it’s done. If that takes more than a moment, Cicero says what it waits for, and you can quit it.

### Why doesn’t it find a font that comes with macOS?

When **Show system fonts** is off in **Preferences → General**, the command leaves those fonts out too, as Cicero’s window does. It says so when you ask for one by name. Add `--system-fonts` to see them (see [Fonts Cicero hides](#fonts-cicero-hides)).

### How do I remove the command?

In Terminal, type `sudo rm /usr/local/bin/cicero /usr/local/share/zsh/site-functions/_cicero /usr/local/share/bash-completion/completions/cicero /usr/local/share/fish/vendor_completions.d/cicero.fish`. Cicero itself stays as it is.

To take Cicero out of your agent app, type `claude mcp remove --scope user cicero` or `codex mcp remove cicero`, or take `cicero` out of Claude Desktop’s `claude_desktop_config.json`.
