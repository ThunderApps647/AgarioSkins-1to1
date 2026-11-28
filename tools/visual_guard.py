#!/usr/bin/env python3
"""Fail the build when a rendered screen drifts from its committed baseline.

The parity suite renders every screen and writes PNGs into AGAR_SNAPSHOT_DIR.
This compares those PNGs with Tests/Baselines/<name>.png, so a change that
silently deletes menu chrome or collapses the emote strip turns CI red instead
of shipping. See AGENTS.md for the review rules.

Usage:
  python3 tools/visual_guard.py build/snapshots Tests/Baselines
  python3 tools/visual_guard.py build/snapshots Tests/Baselines --update
"""
from __future__ import annotations

import sys
from pathlib import Path

try:
    from PIL import Image, ImageChops
except ImportError:  # pragma: no cover
    sys.exit("visual_guard: Pillow is required (python3 -m pip install pillow)")

MAX_MEAN_DELTA = 4.0       # mean |delta| over the whole frame, 0-255
MAX_CHANGED_RATIO = 0.02   # 2% of pixels may move on purpose
PIXEL_FLOOR = 24           # per-pixel delta ignored as AA/renderer noise
TILE_COLS, TILE_ROWS = 12, 8
MAX_TILE_CHANGED = 0.35    # one deleted widget (emote strip) lights up its tile


def compare(current: Path, baseline: Path) -> tuple[float, float, tuple[int, int], float]:
    cur = Image.open(current).convert("RGB")
    base = Image.open(baseline).convert("RGB")
    if cur.size != base.size:
        base = base.resize(cur.size, Image.LANCZOS)
    diff = ImageChops.difference(cur, base).convert("L")
    hist = diff.histogram()
    total = float(sum(hist)) or 1.0
    mean = sum(i * n for i, n in enumerate(hist)) / total
    changed = sum(hist[PIXEL_FLOOR + 1:]) / total

    # Localised check: a small widget can vanish while the frame average stays
    # quiet, so also look for any tile that changed almost completely.
    mask = diff.point(lambda v: 255 if v > PIXEL_FLOOR else 0)
    w, h = mask.size
    tw, th = max(1, w // TILE_COLS), max(1, h // TILE_ROWS)
    worst_tile, worst_ratio = (0, 0), 0.0
    for row in range(TILE_ROWS):
        for col in range(TILE_COLS):
            box = (col * tw, row * th, min(w, (col + 1) * tw), min(h, (row + 1) * th))
            tile = mask.crop(box)
            pixels = tile.size[0] * tile.size[1]
            if not pixels:
                continue
            hit = sum(tile.histogram()[128:]) / float(pixels)
            if hit > worst_ratio:
                worst_tile, worst_ratio = (col, row), hit
    return mean, changed, worst_tile, worst_ratio


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__)
        return 2
    current_dir = Path(argv[1])
    baseline_dir = Path(argv[2])
    update = "--update" in argv[3:]

    baselines = sorted(baseline_dir.glob("*.png"))
    if not baselines:
        print(f"visual_guard: no baselines in {baseline_dir}; nothing to compare")
        return 0

    rows: list[tuple[str, float, float, str, str]] = []
    failures: list[str] = []
    for base in baselines:
        cur = current_dir / base.name
        if not cur.exists():
            rows.append((base.name, 0.0, 0.0, "MISSING"))
            failures.append(f"{base.name}: snapshot missing (did the render test crash?)")
            continue
        mean, changed, tile, tile_ratio = compare(cur, base)
        reasons = []
        if mean > MAX_MEAN_DELTA:
            reasons.append(f"mean delta {mean:.2f} > {MAX_MEAN_DELTA}")
        if changed > MAX_CHANGED_RATIO:
            reasons.append(f"{changed * 100:.1f}% pixels changed > {MAX_CHANGED_RATIO * 100:.0f}%")
        if tile_ratio > MAX_TILE_CHANGED:
            reasons.append(f"tile {tile} is {tile_ratio * 100:.0f}% changed > {MAX_TILE_CHANGED * 100:.0f}%")
        verdict = "FAIL" if reasons else "ok"
        rows.append((base.name, mean, changed * 100.0, verdict, f"tile{tile} {tile_ratio * 100:.0f}%"))
        if reasons:
            failures.append(f"{base.name}: " + "; ".join(reasons))

    width = max(len(r[0]) for r in rows) + 2
    print(f"{'screen'.ljust(width)}{'mean'.rjust(8)}{'changed'.rjust(11)}  {'worst tile'.ljust(14)}verdict")
    for name, mean, pct, verdict, tile_info in rows:
        print(f"{name.ljust(width)}{mean:8.2f}{pct:10.1f}%  {tile_info.ljust(14)}{verdict}")

    if update:
        baseline_dir.mkdir(parents=True, exist_ok=True)
        for base in baselines:
            cur = current_dir / base.name
            if cur.exists():
                Path(base).write_bytes(cur.read_bytes())
        print(f"visual_guard: wrote {len(baselines)} baselines into {baseline_dir}")
        print("visual_guard: NOTE - baseline updates must be justified in the commit message.")
        return 0

    if failures:
        print("")
        print("visual_guard: rendered screens changed:")
        for line in failures:
            print(f"  - {line}")
        print("")
        print("Fix the screen, or - if the change is intended - update the baseline")
        print("and put the before/after screenshots in the commit message. Do not")
        print("update a baseline just to get a green build (AGENTS.md).")
        return 1

    print("\nvisual_guard: all screens match their baselines")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))