# Working rules — Agar.io recovery port

This repo is a 1:1 Swift reconstruction of the retail `agar.io` iOS build. **Parity is the
goal, but it is not the only requirement**: the app must stay usable and must not regress
visually. Rules below exist because a "restore authentic X" commit already deleted the
user's settings, and a nested-scene change silently blanked the entire menu (`522b29a`).

## 1. Never delete a user-facing feature for parity

Retail has no start-mass controls, no FPS overlay, no debug menu. That is a reason to hide
them, never to delete them. Any divergence from retail that the user relies on must be kept
behind a toggle that defaults to retail behaviour, and listed in *Deliberate deviations*
below. If you are about to remove a control, stop and ask in the thread first.

## 2. The visual guard decides whether a render change ships

`Tests/Baselines/*.png` are the committed reference renders. CI compares the fresh parity
snapshots with `tools/visual_guard.py` and fails on:

- mean frame delta > 4/255
- more than 2% of pixels changed
- any 1/96 tile more than 35% changed (this is what catches a deleted widget)

Run it locally with `python3 -m pip install pillow` then:

```
python3 tools/visual_guard.py build/snapshots Tests/Baselines
```

A red guard means a screen changed. Fix it, or — if the change is intended — update the
baseline with `--update`, include the before/after PNGs in the commit message, and say so in
the thread. **Never `--update` just to get a green build.** That silently disables the guard,
which is exactly how the menu regression reached `main`.

## 3. Do not nest `CCBISceneView` inside another scene's `slotViews`

`522b29a` placed `MoreGameModesButton.ccbi` inside `_staticPlayButtonsContainer`. The parent
`MenuMain` scene then rendered only its background, logo and stats drawer — every icon,
currency bar, name field, play button and the avatar bar disappeared — and the accessibility
tree lost `menu.playOnline`, breaking the UI test. Keep scene content flat: render the CCBI
at the parent level and position it, or compose the button from MCFS art (as `cfe2c44` did).

## 4. Render/physics commits carry evidence

Any commit touching `ArenaMetalRenderer.swift`, `ContentView.swift` layout or a CCBI binding
includes either the guard diff table or a before/after screenshot pair in the body. Reviewers
compare all screens, not just the one being changed.

## Deliberate deviations from retail

| Feature | Why | State |
| --- | --- | --- |
| Player / Bot start mass + randomise toggle | user-tuned sandbox controls; retail omits them | **restore behind a "Custom start mass" switch (off = retail) — removed in `d08fc86`, required back** |

## Open user-reported defects

| # | Defect | Where | Status |
| --- | --- | --- | --- |
| 1 | Start mass controls gone from Settings | `ContentView.swift` (removed by `d08fc86`) | open |
| 2 | Spawn animation plays for every cell, including bots streaming into view | `ArenaMetalRenderer.swift:891` (any first-seen id gets a spawn time) | open |
| 3 | Extra pale inner ring on skinned cells | `ArenaMetalRenderer.swift:1074/1084` paints the `0x83` body band at `r+5` even when a skin covers the cell | open |
| 4 | Wrong names on older skins | `skin_names.json` built from bundled `productId`s in `Build/gen_skin_names.py`; needs an audit, not a rewrite | open |
| 5 | Menu chrome blank at HEAD | introduced by `522b29a` (see rule 3) | open |

Fix these without regressing rule 1–4; when one is fixed, move it out of this table and let
the guard confirm it.
