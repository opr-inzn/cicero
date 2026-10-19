#!/usr/bin/env python3
"""Learns letter embeddings from the Google Fonts families drawn by render-letters.swift, and exports the model to
Core ML for Cicero (Sources/CiceroCore/Similarity/LetterEmbedding.swift).

    python3 -I scripts/embedding/train.py train  ~/Downloads/cicero-training/work [--measurements …/measurements.tsv]
    python3 -I scripts/embedding/train.py export ~/Downloads/cicero-training/work Resources/LetterEmbedding.mlpackage

A small network looks at each of a style's 16 letters (see LetterImages.swift) the same way, then at all of them
together, and gives 128 numbers of length 1: the embedding. It learns designs: a family's uprights at one width, or
its italics. Two styles of a design a weight or so apart should come out close and other designs far (a contrastive
loss), a family's italics and other widths too, which share a batch with its uprights, so that slant and width
count. And the embedding should tell Google's tags (Didone, geometric sans, stencil, formal script…) and category,
so that designs of a kind come out close, and, given them, each style's letter measurements (LetterMeasurements.swift,
one line per manifest entry: its row, then the values, tab-separated), so that it sees weight, widths and x-height
as they do. Designs whose letters are drawn alike are one design to it. A tenth of the families, by the first word
of their names, are held out to see how it does on designs it hasn't seen.
"""

import argparse
import json
import math
import random
import sys
import zlib
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

LETTERS, SIZE, DIMENSIONS = 16, 64, 128
# The baseline, in pixels from the top (LetterImages.baseline is from the bottom).
BASELINE = SIZE - 18
CATEGORIES = ["SANS_SERIF", "SERIF", "DISPLAY", "HANDWRITING", "MONOSPACE"]
MEASURES = 18
KINDS = ("/Sans/", "/Serif/", "/Slab/", "/Script/", "/Theme/", "/Monospace/")
# The lowercase's width among the measures, and SimilarFonts' step of it; the capitals' and the o's width.
WIDTH, WIDTH_STEP = 6, 0.08
WIDTHS = [6, 7, 8]


def block(inputs, outputs, stride=1):
    return [nn.Conv2d(inputs, outputs, 3, stride, 1, bias=False), nn.BatchNorm2d(outputs), nn.ReLU(inplace=True)]


class Embedder(nn.Module):
    def __init__(self, tags):
        super().__init__()
        self.letter = nn.Sequential(
            *block(1, 24, 2), *block(24, 48), *block(48, 48, 2), *block(48, 96), *block(96, 96, 2), *block(96, 128),
            nn.AdaptiveAvgPool2d(4), nn.Flatten(), nn.Linear(128 * 16, 128), nn.ReLU(inplace=True),
        )
        self.together = nn.Sequential(
            nn.Linear(LETTERS * 128, 512), nn.BatchNorm1d(512), nn.ReLU(inplace=True), nn.Linear(512, DIMENSIONS),
        )
        self.tags = nn.Linear(DIMENSIONS, tags)
        self.measures = nn.Linear(DIMENSIONS, MEASURES)

    def forward(self, letters):
        """(n, 16, 64, 64), 0 to 1 → (n, 128) of length 1."""
        count = letters.shape[0]
        each = self.letter(letters.reshape(count * LETTERS, 1, SIZE, SIZE)).reshape(count, LETTERS * 128)
        return F.normalize(self.together(each), dim=1)


class Exported(nn.Module):
    """One style at a time, as Cicero asks, with no shape taken from the input."""

    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, letters):
        each = self.model.letter(letters.reshape(LETTERS, 1, SIZE, SIZE)).reshape(1, LETTERS * 128)
        return F.normalize(self.model.together(each), dim=1)


def read_measurements(path, rows):
    """Each row's measures, NaN where there's none to say."""
    values = np.full((rows, MEASURES), np.nan, dtype=np.float32)
    for line in Path(path).expanduser().read_text().splitlines():
        parts = line.split("\t")
        if len(parts) == MEASURES + 1:
            values[int(parts[0])] = [float(value) for value in parts[1:]]
    return values


def standard_scores(values):
    mean, spread = np.nanmean(values, 0), np.nanstd(values, 0)
    return (values - mean) / np.maximum(spread, 1e-6)


def load(work):
    """The designs, the letters drawn and the names of the tags."""
    families = json.loads((work / "families.json").read_text())
    drawn = json.loads((work / "letters.json").read_text())
    pixels = np.fromfile(work / "letters.u8", dtype=np.uint8).reshape(-1, LETTERS, SIZE, SIZE)
    tag_names = sorted({tag for family in families for tag in family["tags"]
                        if tag.startswith(KINDS) or tag.startswith("/Expressive/")})
    designs = []
    for family in families:
        target = [family["tags"].get(tag, 0.0) for tag in tag_names]
        target += [1.0 if family["category"] == category else 0.0 for category in CATEGORIES]
        entries = [entry for entry in family["entries"] if drawn[entry["row"]]]
        kinds = sorted({(entry["italic"], entry.get("width", 100)) for entry in entries})
        for italic, width in kinds:
            own = [entry for entry in entries if entry["italic"] == italic and entry.get("width", 100) == width]
            regular = min(own, key=lambda entry: abs(entry["weight"] - 400))
            name = family["name"] + (" Italic" if italic else "") + (f" {width:g}" if width != 100 else "")
            designs.append({
                "name": name, "family": family["name"], "italic": italic, "width": width, "category": family["category"],
                "regular": regular["row"], "all": [entry["row"] for entry in own],
                "views": [entry["row"] for entry in own if abs(entry["weight"] - regular["weight"]) <= 100],
                "target": target, "tagged": bool(family["tags"]), "held_out": held_out(family["name"]),
            })
    return designs, pixels, tag_names


def merge_alike(designs, pixels, device):
    """Groups of designs whose regulars are drawn alike, as for a family that borrows another's Latin."""
    regulars = torch.tensor(pixels[[design["regular"] for design in designs]], device=device).float().reshape(len(designs), -1) / 255
    squares = (regulars * regulars).sum(1)
    distances = (squares[:, None] + squares[None, :] - 2 * regulars @ regulars.T).clamp(min=0).sqrt() / math.sqrt(regulars.shape[1])
    parent = list(range(len(designs)))

    def root(index):
        while parent[index] != index:
            parent[index] = parent[parent[index]]
            index = parent[index]
        return index

    pairs = (distances < 0.02).nonzero().tolist()
    for a, b in pairs:
        if a < b:
            parent[root(a)] = root(b)
    groups = {}
    for index in range(len(designs)):
        groups.setdefault(root(index), []).append(index)
    return list(groups.values())


def held_out(name):
    return zlib.crc32(name.split()[0].lower().encode()) % 10 == 0


def augment(batch):
    """Each style a little bigger or smaller about its baseline and moved a pixel or two, and a letter or two
    missing now and then."""
    count = batch.shape[0]
    device = batch.device
    scale = torch.empty(count, device=device).uniform_(0.9, 1.1)
    shift_x = torch.empty(count, device=device).uniform_(-2, 2) / (SIZE / 2)
    shift_y = torch.empty(count, device=device).uniform_(-1.5, 1.5) / (SIZE / 2)
    # Scaled about the middle of the baseline, in grid_sample's coordinates, -1 to 1.
    base = (BASELINE + 0.5) / (SIZE / 2) - 1
    theta = torch.zeros(count, 2, 3, device=device)
    theta[:, 0, 0] = 1 / scale
    theta[:, 1, 1] = 1 / scale
    theta[:, 0, 2] = -shift_x / scale
    theta[:, 1, 2] = base - (base + shift_y) / scale
    grid = F.affine_grid(theta, list(batch.shape), align_corners=False)
    moved = F.grid_sample(batch, grid, align_corners=False, padding_mode="zeros")
    keep = (torch.rand(count, LETTERS, 1, 1, device=device) > 0.08).float()
    return moved * keep


def stretch(batch, factors):
    """Each style drawn wider or narrower by its factor, about the middle of each square."""
    theta = torch.zeros(batch.shape[0], 2, 3, device=batch.device)
    theta[:, 0, 0] = 1 / factors
    theta[:, 1, 1] = 1
    grid = F.affine_grid(theta, list(batch.shape), align_corners=False)
    return F.grid_sample(batch, grid, align_corners=False, padding_mode="zeros")


def contrastive(embeddings, temperature):
    """NT-Xent over pairs: rows i and i + n are two views of one family."""
    count = embeddings.shape[0] // 2
    similarities = embeddings @ embeddings.T / temperature
    similarities.fill_diagonal_(-1e4)
    targets = torch.cat([torch.arange(count, 2 * count), torch.arange(0, count)]).to(embeddings.device)
    return F.cross_entropy(similarities, targets)


@torch.no_grad()
def embed(model, pixels, rows, device, batch=256):
    model.eval()
    found = []
    for start in range(0, len(rows), batch):
        letters = torch.tensor(pixels[rows[start:start + batch]], device=device).float() / 255
        found.append(model(letters))
    return torch.cat(found)


def model_distance(model, pixels, device):
    """The distance between the embeddings of rows, each embedded once."""
    known = {}

    def distance(first, second):
        missing = sorted(set(first + second) - known.keys())
        if missing:
            known.update(zip(missing, embed(model, pixels, missing, device)))
        return torch.cdist(torch.stack([known[row] for row in first]), torch.stack([known[row] for row in second]))
    return distance


@torch.no_grad()
def evaluate(distance, designs, tag_names, measurements=None):
    """On the designs held out, by `distance(rows, rows)`:
    own design: how often a style's nearest other style is its design's;
    tags, category: how much the ten nearest upright designs of the normal width share an upright one's Google tags
    by kind (Didone, geometric…) and its category;
    uprights, italics: how many of the ten nearest designs of the normal width are upright, for an upright one, and
    italic, for an italic one;
    width: how far apart the ten nearest upright designs, of any width, are in width, in SimilarFonts' steps."""
    kinds = np.array([1.0 if name.startswith(KINDS) else 0.0 for name in tag_names] + [0.0] * len(CATEGORIES))
    targets = np.array([design["target"] for design in designs]) * kinds
    targets /= np.maximum(np.linalg.norm(targets, axis=1, keepdims=True), 1e-9)

    def nearest(queries, gallery, count=10):
        found = distance([designs[index]["regular"] for index in queries], [designs[index]["regular"] for index in gallery])
        found = torch.as_tensor(found).float().clone()
        position = {index: column for column, index in enumerate(gallery)}
        for row, query in enumerate(queries):
            found[row, position[query]] = float("inf")
        return [[gallery[column] for column in row] for row in found.topk(count, dim=1, largest=False).indices.tolist()]

    held = [index for index, design in enumerate(designs) if design["held_out"]]
    rows = [row for index in held for row in designs[index]["all"]]
    owners = np.array([index for index in held for _ in designs[index]["all"]])
    found = torch.as_tensor(distance(rows, rows)).float().clone()
    found.fill_diagonal_(float("inf"))
    several = np.array([len(designs[owner]["all"]) > 1 for owner in owners])
    scores = {"own design": float((owners[found.argmin(1).cpu().numpy()] == owners)[several].mean())}

    upright = [index for index, design in enumerate(designs) if not design["italic"] and design["width"] == 100]
    queries = [index for index in upright if designs[index]["held_out"]]
    tags, category, counted = 0.0, 0.0, 0
    for query, near in zip(queries, nearest(queries, upright)):
        category += sum(designs[other]["category"] == designs[query]["category"] for other in near) / 10
        if targets[query].any():
            tags += float((targets[near] @ targets[query]).mean())
            counted += 1
    scores["tags"], scores["category"] = tags / max(counted, 1), category / len(queries)

    normal = [index for index, design in enumerate(designs) if design["width"] == 100]
    queries = [index for index in normal if designs[index]["held_out"]]
    alike = {False: [], True: []}
    for query, near in zip(queries, nearest(queries, normal)):
        italic = designs[query]["italic"]
        alike[italic].append(sum(designs[other]["italic"] == italic for other in near) / 10)
    scores["uprights"], scores["italics"] = float(np.mean(alike[False])), float(np.mean(alike[True]))

    if measurements is not None:
        uprights = [index for index, design in enumerate(designs) if not design["italic"]]
        queries = [index for index in uprights if designs[index]["held_out"]]
        width = lambda index: measurements[designs[index]["regular"], WIDTH]
        steps = [np.nanmean([abs(width(other) - width(query)) for other in near]) / WIDTH_STEP
                 for query, near in zip(queries, nearest(queries, uprights)) if not np.isnan(width(query))]
        scores["width"] = float(np.nanmean(steps))
    return scores


def train(arguments):
    work = Path(arguments.work).expanduser()
    device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
    torch.manual_seed(arguments.seed)
    random.seed(arguments.seed)
    designs, pixels, tag_names = load(work)
    groups = merge_alike(designs, pixels, device)
    merged = [group for group in groups if len(group) > 1]
    print(f"{len(designs)} designs of {len({design['family'] for design in designs})} families drawn, {len(groups)} once alike "
          "ones are one; alike: " + "; ".join(", ".join(designs[index]["name"] for index in group) for group in merged[:40]))
    # A group is held out when any of it is, so nothing held out was seen.
    for group in groups:
        if any(designs[index]["held_out"] for index in group):
            for index in group:
                designs[index]["held_out"] = True
    classes = [group for group in groups if not designs[group[0]]["held_out"]]
    families = sorted({designs[index]["family"] for group in classes for index in group})
    print(f"training on {len(classes)} designs ({sum(map(len, classes))} before merging) of {len(families)} families, "
          f"{sum(not designs[group[0]]['italic'] and designs[group[0]]['width'] == 100 for group in classes)} of them "
          f"upright and of the normal width; holding out {sum(design['held_out'] for design in designs)} designs")
    # Each family's designs, so that they go into a batch together.
    by_family = {}
    for position, group in enumerate(classes):
        for index in group:
            by_family.setdefault(designs[index]["family"], set()).add(position)

    everything = torch.tensor(pixels, device=device)
    targets = torch.tensor([design["target"] for design in designs], device=device)
    tagged = torch.tensor([design["tagged"] for design in designs], device=device)
    # Tags of a kind count for more than the expressive ones (calm, playful…), the category most.
    tag_weights = torch.tensor([1.0 if name.startswith(KINDS) else 0.3 for name in tag_names] + [1.0] * len(CATEGORIES), device=device)
    measurements = read_measurements(arguments.measurements, len(pixels)) if arguments.measurements else None
    measures = torch.tensor(standard_scores(measurements), device=device) if measurements is not None else None
    measure_weights = torch.ones(MEASURES, device=device)
    measure_weights[WIDTHS] = arguments.widths

    model = Embedder(len(tag_names) + len(CATEGORIES)).to(device)
    optimizer = torch.optim.AdamW(model.parameters(), lr=arguments.rate, weight_decay=arguments.decay)
    # Batches of whole families come out a little bigger, so never more of them than this.
    steps_per_epoch = math.ceil(len(classes) / arguments.batch) + 1
    total = arguments.epochs * steps_per_epoch
    schedule = torch.optim.lr_scheduler.OneCycleLR(optimizer, max_lr=arguments.rate, total_steps=total, pct_start=0.05)
    out = work / arguments.name
    for epoch in range(arguments.epochs):
        model.train()
        batches, batch, taken = [], [], set()
        for family in random.sample(families, len(families)):
            for position in sorted(by_family[family] - taken):
                taken.add(position)
                batch.append(classes[position])
            if len(batch) >= arguments.batch:
                batches.append(batch)
                batch = []
        batches.append(batch)
        losses = []
        for chosen in batches:
            if len(chosen) < 8:
                continue
            first_rows, second_rows, owners = [], [], []
            for group in chosen:
                # Two views: of one design of the group, or of two, which are drawn alike anyway.
                a, b = designs[random.choice(group)], designs[random.choice(group)]
                first_rows.append(random.choice(a["views"]))
                second_rows.append(random.choice(b["views"]))
                owners.append(random.choice(group))
            # Some designs again, drawn wider or narrower, as designs of their own: two views of each, alike.
            stretched = random.sample(range(len(chosen)), round(len(chosen) * arguments.stretch))
            factors = torch.tensor([random.choice([0.75, 0.85, 1.18, 1.33]) for _ in stretched], device=device)
            count = len(chosen)
            first_rows += [first_rows[index] for index in stretched]
            second_rows += [second_rows[index] for index in stretched]
            owners += [owners[index] for index in stretched]
            rows = torch.tensor(first_rows + second_rows, device=device)
            letters = everything[rows].float() / 255
            if stretched:
                total = len(first_rows)
                for offset in (count, total + count):
                    letters[offset:offset + len(stretched)] = stretch(letters[offset:offset + len(stretched)], factors)
            letters = augment(letters)
            embeddings = model(letters)
            loss = contrastive(embeddings, arguments.temperature)
            owners = torch.tensor(owners + owners, device=device)
            known = tagged[owners]
            if known.any():
                logits = model.tags(embeddings[known] * 8)
                tag_loss = F.binary_cross_entropy_with_logits(logits, targets[owners][known], reduction="none")
                loss = loss + arguments.tags * (tag_loss * tag_weights).mean()
            if measures is not None:
                wanted = measures[rows]
                known = ~wanted.isnan()
                # A stretched style's measures aren't its design's.
                plain = torch.ones(len(rows), 1, dtype=torch.bool, device=device)
                for offset in (count, len(first_rows) + count):
                    plain[offset:offset + len(stretched)] = False
                known &= plain
                guessed = model.measures(embeddings * 8)
                each = F.smooth_l1_loss(guessed, wanted.nan_to_num(), reduction="none") * measure_weights
                loss = loss + arguments.measures * each[known].mean()
            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
            schedule.step()
            losses.append(loss.item())
        if epoch % arguments.every == arguments.every - 1 or epoch == arguments.epochs - 1:
            scores = evaluate(model_distance(model, pixels, device), designs, tag_names, measurements)
            print(f"epoch {epoch + 1}: loss {np.mean(losses):.3f}  " + "  ".join(f"{key} {value:.3f}" for key, value in scores.items()), flush=True)
    torch.save({"model": model.state_dict(), "tags": tag_names, "epoch": arguments.epochs, "scores": scores}, out)
    print(f"saved {out}")


def export(arguments):
    import coremltools as ct

    work = Path(arguments.work).expanduser()
    saved = torch.load(arguments.checkpoint or work / "model.pt", map_location="cpu")
    model = Embedder(len(saved["tags"]) + len(CATEGORIES))
    model.load_state_dict(saved["model"])
    model.eval()
    exported = Exported(model).eval()
    example = torch.rand(1, LETTERS, SIZE, SIZE)
    traced = torch.jit.trace(exported, example)
    converted = ct.convert(
        traced,
        inputs=[ct.TensorType(name="letters", shape=example.shape)],
        outputs=[ct.TensorType(name="embedding", dtype=np.float32)],
        minimum_deployment_target=ct.target.macOS15,
        compute_precision=ct.precision.FLOAT16,
    )
    converted.short_description = ("A font's letters (see LetterImages.swift), 0 to 1, as 128 numbers of length 1; alike fonts are close. "
                                   "Learned from Google Fonts families under the OFL, Apache and UFL licenses.")
    converted.version = f"epoch {saved['epoch']}"
    converted.save(arguments.output)
    pixels = np.fromfile(work / "letters.u8", dtype=np.uint8).reshape(-1, LETTERS, SIZE, SIZE)
    letters = pixels[:1].astype(np.float32) / 255
    expected = exported(torch.tensor(letters)).detach().numpy()
    found = converted.predict({"letters": letters})["embedding"]
    print(f"saved {arguments.output}; Core ML and PyTorch differ by {np.abs(found - expected).max():.4f} at most")


def main():
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    training = commands.add_parser("train")
    training.add_argument("work")
    training.add_argument("--epochs", type=int, default=80)
    training.add_argument("--batch", type=int, default=128)
    training.add_argument("--rate", type=float, default=2e-3)
    training.add_argument("--decay", type=float, default=5e-4)
    training.add_argument("--temperature", type=float, default=0.1)
    training.add_argument("--tags", type=float, default=3.0)
    training.add_argument("--measurements", help="the letter measurements of each entry in the manifest")
    training.add_argument("--measures", type=float, default=1.0, help="how much telling them counts")
    training.add_argument("--widths", type=float, default=4.0, help="how much more telling the widths counts")
    training.add_argument("--stretch", type=float, default=0.0, help="the share of designs drawn wider or narrower too")
    training.add_argument("--name", default="model.pt", help="of the model saved in the work folder")
    training.add_argument("--every", type=int, default=10)
    training.add_argument("--seed", type=int, default=1)
    exporting = commands.add_parser("export")
    exporting.add_argument("work")
    exporting.add_argument("output")
    exporting.add_argument("--checkpoint", help="instead of the work folder's model.pt")
    arguments = parser.parse_args()
    {"train": train, "export": export}[arguments.command](arguments)


if __name__ == "__main__":
    sys.exit(main())
