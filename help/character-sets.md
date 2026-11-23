# Character sets and languages

[Cicero Help](README.md) › Character sets and languages

Cicero checks which characters each font has, so you can find fonts for a text, a language or a standard set of characters.

A font only has a character it draws. A trial font often lists characters it leaves out, with empty glyphs for them, and those don’t count; a space, which draws nothing in any font, does.

It checks each family’s regular upright style. It does this in the background after each scan and remembers the results, so it only has to look at new or changed fonts. Until it’s done, lists that depend on it say “checking characters” in the subtitle.

## Character sets

A family *has* a character set when its regular upright style has every character in it. Cicero comes with these sets:

| Group | Sets |
| --- | --- |
| Latin S–XL | Latin S, M, L and XL, by Christoph Koeberlin |
| Adobe Latin | Adobe Latin 1 to 5, by Adobe |
| Google Fonts | GF Latin Kernel, Core, Plus and African; GF Cyrillic Core, Plus and Pro; GF Greek Core, Plus and Pro |
| Unicode Blocks | 38 blocks, like Basic Latin, Latin-1 Supplement, Latin Extended-A and -B, IPA Extensions, Greek and Coptic, Cyrillic, General Punctuation and Currency Symbols |

You can also make your own (see below).

### Find fonts that have a set

Click a set under **Coverage** in the sidebar. The browser shows the families that have every one of its characters.

You can also:

- show a character set as a column in the [list view](browsing.md#list) and sort by it: **Latin S–XL**, **Adobe Latin**, **GF Latin**, **GF Cyrillic** and **GF Greek** show the largest set of that kind a family has, and any other set shows whether a family has all of it or how many characters it lacks
- see the sets a font has, and how many characters it lacks for the next Latin size, under **Coverage** in the [Info panel](browsing.md#see-a-fonts-details). **Show Missing** lists them.
- use a set in a [smart folder](organizing.md#smart-folders) rule, like “Coverage includes Adobe Latin 3”

### Choose which sets the sidebar shows

Open **Preferences → Coverage**. Each group lists its sets with a checkbox, a short description and the number of characters; uncheck the ones you don’t need. All of them are shown at first. Each group also links to where its sets come from.

You can also hide sets with **Edit** in the sidebar, like any other item. See [Hide items you don’t use](organizing.md#hide-items-you-dont-use).

## Make your own coverage set

Make a set from the characters you need, like a client’s name or a language’s alphabet:

1. Click **+** next to **Coverage** in the sidebar, or **+** next to **Your Coverage Sets** at the top of **Preferences → Coverage**.
2. Give it a name.
3. Under **Characters**, type or paste them. You can also use codes like `U+00C1` or `0x00C1`, and ranges like `U+0100–U+017F`. Spaces and line breaks don’t count, so you can use them to lay things out.
4. Check the characters and their count under **Preview**, and click **Create**.

Your sets appear under **Your Coverage Sets** in the sidebar. To change one, right-click it and choose **Edit Coverage Set**; to remove it, choose **Delete Coverage Set**. In **Preferences → Coverage** you can right-click them too, or click **Edit**; the editor has a **Delete** button as well.

## The Character Toolbox

Choose **Fonts → Character Toolbox** (⌥⌘T). The window has two tabs, **Text** and **Languages**.

### Find fonts for a text

1. Click **Text**.
2. Type or paste your text, like a headline or a name with unusual letters.

Cicero lists the families that have every character, each showing your text in its own font.

- To see fonts that come close, raise **Missing characters allowed**. The **Missing** column shows which characters each one lacks.
- Check **Active only** to see just the fonts that are on.
- Double-click a family, or select it and press ↩, to open it in the main window. Right-click it for the same menu as in the browser.

### Find fonts for a language

1. Click **Languages**.
2. Find the language in the list. Search by its name, its own name for itself, or its script, and sort by **Speakers** or **Name**.
3. Select it.

Cicero shows the characters the language uses and two lists of families:

- **Fully Supported:** the font has every character the language needs, the less common ones included.
- **Base Characters Only:** the font has the characters the language needs, but not all of the less common ones.

Double-click a family to open it in the main window.

## How Cicero decides a font supports a language

Cicero knows 780 languages, from [Hyperglot](https://github.com/rosettatype/hyperglot) by Rosetta. For each one, Hyperglot lists the characters its alphabet needs, and the less common ones it sometimes uses.

- A font **supports** a language when it has all the needed characters and marks.
- It **fully supports** it when it also has the less common ones.

Cicero only checks which characters a font has. It doesn’t check whether the font joins or positions them correctly, which matters for scripts like Arabic or Devanagari. A font listed for such a language can still lack what the script needs to look right.

The languages a font supports are also in the [Info panel](browsing.md#see-a-fonts-details), and in [smart folder](organizing.md#smart-folders) rules like “Language is supported Polish”.
