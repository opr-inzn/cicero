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
"$T/venv/bin/python" -I scripts/embedding/train.py export "$T/work" Resources/LetterEmbedding.mlpackage
```

Training takes about a quarter of an hour on an M1 Pro. Every tenth epoch it prints how it does on the tenth of the
families it doesn't learn from: how often a style's nearest other style is its own family's, and how much the ten
nearest families share its Google tags and category. A new model changes every family's embedding: raise
`MeasurementIndex.version` with it.
