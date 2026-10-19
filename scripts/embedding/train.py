#!/usr/bin/env python3
"""Learns letter embeddings from the Google Fonts families drawn by render-letters.swift, and exports the model to
Core ML for Cicero (Sources/CiceroCore/Similarity/LetterEmbedding.swift).

    python3 -I scripts/embedding/train.py train  ~/Downloads/cicero-training/work [--measurements …/measurements.tsv]
    python3 -I scripts/embedding/train.py export ~/Downloads/cicero-training/work Resources/LetterEmbedding.mlpackage

A small network looks at each of a style's 16 letters (see LetterImages.swift) the same way, then at all of them
together, and gives 128 numbers of length 1: the embedding. Two styles of one family a weight or so apart should
come out close and other families' far (a contrastive loss), and the embedding should tell Google's tags (Didone,
geometric sans, stencil, formal script…) and category, so that families of a kind come out close too, and, given
them, each style's letter measurements (LetterMeasurements.swift, one line per manifest entry: its row, then the
values, tab-separated), so that it sees weight, widths and x-height as they do. Families whose letters are drawn
alike are one family to it. A tenth of the families, by the first word of their names, are held out to see how it
does on families it hasn't seen.
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


def load_measurements(path, rows):
    """Each row's measures as standard scores, NaN where there's none to say."""
    values = np.full((rows, MEASURES), np.nan, dtype=np.float32)
    for line in Path(path).expanduser().read_text().splitlines():
        parts = line.split("\t")
        if len(parts) == MEASURES + 1:
            values[int(parts[0])] = [float(value) for value in parts[1:]]
    mean, spread = np.nanmean(values, 0), np.nanstd(values, 0)
    return (values - mean) / np.maximum(spread, 1e-6)


def load(work):
    families = json.loads((work / "families.json").read_text())
    drawn = json.loads((work / "letters.json").read_text())
    pixels = np.fromfile(work / "letters.u8", dtype=np.uint8).reshape(-1, LETTERS, SIZE, SIZE)
    tag_names = sorted({tag for family in families for tag in family["tags"]
                        if tag.startswith(KINDS) or tag.startswith("/Expressive/")})
    usable = []
    for family in families:
        entries = [entry for entry in family["entries"] if drawn[entry["row"]]]
        upright = [entry for entry in entries if not entry["italic"]] or entries
        if not upright:
            continue
        regular = min(upright, key=lambda entry: abs(entry["weight"] - 400))
        family["regular"] = regular["row"]
        family["views"] = [entry["row"] for entry in upright if abs(entry["weight"] - regular["weight"]) <= 100]
        family["all"] = [entry["row"] for entry in entries]
        target = [family["tags"].get(tag, 0.0) for tag in tag_names]
        target += [1.0 if family["category"] == category else 0.0 for category in CATEGORIES]
        family["target"] = target
        family["tagged"] = bool(family["tags"])
        usable.append(family)
    return usable, pixels, tag_names


def merge_alike(families, pixels, device):
    """Groups of families whose regulars are drawn alike, as for a family that borrows another's Latin."""
    regulars = torch.tensor(pixels[[family["regular"] for family in families]], device=device).float().reshape(len(families), -1) / 255
    squares = (regulars * regulars).sum(1)
    distances = (squares[:, None] + squares[None, :] - 2 * regulars @ regulars.T).clamp(min=0).sqrt() / math.sqrt(regulars.shape[1])
    parent = list(range(len(families)))

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
    for index in range(len(families)):
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


@torch.no_grad()
def evaluate(model, families, pixels, tag_names, device):
    """On the held-out families: how often a style's nearest other style is its own family's, and how much the
    ten nearest families' tags (by kind: Didone, geometric…) and categories are its own."""
    model.eval()
    kinds = torch.tensor([[1.0 if name.startswith(KINDS) else 0.0 for name in tag_names] + [0.0] * len(CATEGORIES)], device=device)
    held = [family for family in families if family["held_out"]]
    rows = [row for family in held for row in family["all"]]
    owners = torch.tensor([index for index, family in enumerate(held) for _ in family["all"]], device=device)
    styles = embed(model, pixels, rows, device)
    similarities = styles @ styles.T
    similarities.fill_diagonal_(-2)
    several = torch.tensor([len(held[owner]["all"]) > 1 for owner in owners.tolist()], device=device)
    nearest = similarities.argmax(1)
    own_family = (owners[nearest] == owners)[several].float().mean().item()

    regulars = embed(model, pixels, [family["regular"] for family in families], device)
    targets = torch.tensor([family["target"] for family in families], device=device) * kinds
    targets = F.normalize(targets, dim=1)
    categories = [family["category"] for family in families]
    queries = [index for index, family in enumerate(families) if family["held_out"]]
    similarities = regulars[queries] @ regulars.T
    similarities[torch.arange(len(queries)), torch.tensor(queries)] = -2
    neighbours = similarities.topk(10, dim=1).indices
    tag_agreement, category_agreement, counted = 0.0, 0.0, 0
    for query, found in zip(queries, neighbours.tolist()):
        category_agreement += sum(categories[other] == categories[query] for other in found) / 10
        if targets[query].abs().sum() > 0:
            tag_agreement += (targets[found] @ targets[query]).mean().item()
            counted += 1
    return {"own family": own_family, "tags of the ten nearest": tag_agreement / max(counted, 1),
            "category of the ten nearest": category_agreement / len(queries)}


def train(arguments):
    work = Path(arguments.work).expanduser()
    device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
    torch.manual_seed(arguments.seed)
    random.seed(arguments.seed)
    families, pixels, tag_names = load(work)
    groups = merge_alike(families, pixels, device)
    merged = [group for group in groups if len(group) > 1]
    print(f"{len(families)} families drawn, {len(groups)} once alike ones are one; alike: " +
          "; ".join(", ".join(families[index]["name"] for index in group) for group in merged[:40]))
    for family in families:
        family["held_out"] = held_out(family["name"])
    # A group is held out when any of it is, so nothing held out was seen.
    for group in groups:
        if any(families[index]["held_out"] for index in group):
            for index in group:
                families[index]["held_out"] = True
    classes = [group for group in groups if not families[group[0]]["held_out"]]
    print(f"training on {len(classes)} families ({sum(map(len, classes))} before merging), "
          f"holding out {sum(family['held_out'] for family in families)}")

    everything = torch.tensor(pixels, device=device)
    targets = torch.tensor([family["target"] for family in families], device=device)
    tagged = torch.tensor([family["tagged"] for family in families], device=device)
    # Tags of a kind count for more than the expressive ones (calm, playful…), the category most.
    tag_weights = torch.tensor([1.0 if name.startswith(KINDS) else 0.3 for name in tag_names] + [1.0] * len(CATEGORIES), device=device)
    measures = torch.tensor(load_measurements(arguments.measurements, len(pixels)), device=device) if arguments.measurements else None

    model = Embedder(len(tag_names) + len(CATEGORIES)).to(device)
    optimizer = torch.optim.AdamW(model.parameters(), lr=arguments.rate, weight_decay=arguments.decay)
    steps_per_epoch = math.ceil(len(classes) / arguments.batch)
    total = arguments.epochs * steps_per_epoch
    schedule = torch.optim.lr_scheduler.OneCycleLR(optimizer, max_lr=arguments.rate, total_steps=total, pct_start=0.05)
    best, out = None, work / arguments.name
    for epoch in range(arguments.epochs):
        model.train()
        order = random.sample(classes, len(classes))
        losses = []
        for start in range(0, len(order), arguments.batch):
            chosen = order[start:start + arguments.batch]
            if len(chosen) < 8:
                continue
            first_rows, second_rows, owners = [], [], []
            for group in chosen:
                # Two views: of one family of the group, or of two, which are drawn alike anyway.
                a, b = families[random.choice(group)], families[random.choice(group)]
                first_rows.append(random.choice(a["views"]))
                second_rows.append(random.choice(b["views"]))
                owners.append(random.choice(group))
            rows = torch.tensor(first_rows + second_rows, device=device)
            letters = augment(everything[rows].float() / 255)
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
                guessed = model.measures(embeddings * 8)
                loss = loss + arguments.measures * F.smooth_l1_loss(guessed[known], wanted[known])
            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
            schedule.step()
            losses.append(loss.item())
        if epoch % arguments.every == arguments.every - 1 or epoch == arguments.epochs - 1:
            scores = evaluate(model, families, pixels, tag_names, device)
            score = scores["own family"] + scores["tags of the ten nearest"]
            print(f"epoch {epoch + 1}: loss {np.mean(losses):.3f}  " + "  ".join(f"{key} {value:.3f}" for key, value in scores.items()), flush=True)
            if best is None or score > best:
                best = score
                torch.save({"model": model.state_dict(), "tags": tag_names, "epoch": epoch + 1, "scores": scores}, out)
    print(f"saved the best, {best:.3f}, to {out}")


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
