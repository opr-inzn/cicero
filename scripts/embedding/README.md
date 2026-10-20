# Letter embeddings

How Resources/LetterEmbedding.mlpackage is made: the model similar fonts use next to the letter measurements (see
`LetterEmbedding` and docs/SPEC.md, Similar fonts). It learns from Google Fonts' families, OFL, Apache and UFL only,
read straight from their files: nothing is installed or activated, and no font goes into the repository or the model's
package.

Keep the fonts, the Python environment and the work folder outside the repository, the fonts in a folder of their own,
and run Python on them with `-I`:

```sh
T=~/Downloads/cicero-training
git clone --depth 1 https://github.com/google/fonts "$T/google-fonts"
python3 -m venv "$T/venv" && "$T/venv/bin/pip" install torch numpy coremltools

# The families and styles to draw, then the letters, drawn with Cicero's own LetterImages.swift.
"$T/venv/bin/python" -I scripts/embedding/prepare.py "$T/google-fonts" "$T/work"
swiftc -O -parse-as-library scripts/embedding/render-letters.swift Sources/CiceroCore/Similarity/LetterImages.swift -o /tmp/render-letters
/tmp/render-letters "$T/work/manifest.json" "$T/work/letters"

# Optionally each style's letter measurements, for the model to learn to tell them: the tests' EmbeddingEvaluation
# writes them to measurements.tsv (CICERO_EMBEDDING_WORK="$T/work" swift test --filter EmbeddingEvaluation).

"$T/venv/bin/python" -I scripts/embedding/train.py train "$T/work" --measurements "$T/work/measurements.tsv"
"$T/venv/bin/python" -I scripts/embedding/train.py classify "$T/work"
"$T/venv/bin/python" -I scripts/embedding/train.py export "$T/work" Resources/LetterEmbedding.mlpackage
```

`classify` fits a small classifier on the embedding as it is, for Cicero's guesses of classifications: serif, sans
serif, script or ornamental, from Google's category, stroke and tags (see `label` in train.py). It says how often it's
right on the held-out families, and how often when it's sure, which `AppModel.letterGuessLikelihood` goes by.

It learns designs: a family's uprights at one width and optical size (the normal one, and condensed and expanded, small
and large ones of a variable font with those axes) or its italics, each a design of its own, that the others of the
family, and its siblings named for another size, width or kind (DM Serif Display and Text, Roboto Mono and Roboto),
share a batch with, so that slant, width and optical size count. Next to the letters it gets their advances
(letters-advances.f32), which the squares, each letter centred by its ink, don't show: how wide a face sets its
letters, and that a monospaced one sets them all as wide. `--stretch` adds designs drawn narrower and wider than they are, which made width
count a little more and italics less in round two; it's off. So are the other ways to learn that train.py's
docstring lists, which round five tried: weights and widths as one design (`--invariant`), more text faces (`--mix`),
designs of a kind alike (`--soft`), a smaller model (`--together small`) and averaged weights (`--ema`).

Training takes about a quarter of an hour on an M1 Pro. Every tenth epoch it prints how it does on the designs of the
tenth of the families it doesn't learn from (`--fold`, 0 to 9; one tenth's scores vary more than a change makes them,
so compare several): how often a style's nearest other style is its own design's; how much
the ten nearest upright designs share an upright one's Google tags and category; how many of the ten nearest are
upright, for an upright design, and italic, for an italic one; and how far apart in width the ten nearest are, in
`SimilarFonts`' steps. A new model changes every family's embedding: raise `MeasurementIndex.version` with it.
