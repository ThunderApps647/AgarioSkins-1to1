# Agar.io parity audit (ARM64 decompilation -> Swift)

This file records the pass/tick audit that backs the latest rendering and physics changes.
Addresses are ARM64 effective addresses from the IDA dump; `file:line` is this repository.

## 1. SoftBodyCellView draw passes

`SoftBodyCellView::draw` (`0x1003a265c`) calls, in order:
`drawCustom` -> overlay/name pass -> `CCNode::draw` (children sorted by local z).
Inside `drawCustom` (`0x1003a4654`):

| # | Pass | Evidence | Swift implementation | Status |
|---|------|----------|----------------------|--------|
| 1 | Party outer rim, `(r+10)/r` | `drawOutlineWithVertices` `0x1003a5064`, scale `(v12+10)/v12` | `ArenaMetalRenderer.swift` cell `.cell` border, `borderOff = 10` | fixed |
| 2 | Body colour band, `(r+5)/r` at alpha `0x83` | same function, second draw, `(v12+5)/v12`, colour alpha `0x83` | `bodyBandSIMD`, `0x83/255` | fixed |
| 3 | Skin | `drawSkinTextureWithVertices` `0x1003a54bc` | `drawTexturedFan`, `radiusOffsetWorld: 0` | UV fixed |
| 4 | `drawFillingWithVertices` | `0x1003a528c`; player `0xC0C0C0` alpha 0.75, other `(r-10)/r` | `appendScaledFan`, local white / non-local colour | fixed local pass |
| 5 | Emoji/emote overlay | `drawCustom` tail, before children | `drawTexturedFan`, clipped to cell polygon | in order |
| 6 | League badge child z=0 | `SoftBodyCellView` child setup | `drawBadge` inside `drawNameAndBadge` | order approximated |
| 7 | Name label child z=1 | child node | `drawNameAndBadge` | in order |
| 8 | Mass label child z=2 | child node | `drawMassNumber` after name | fixed |

Skin UVs now use the decompiled `vertex/(2r)+0.5` formula (`calcTexCoordsInto`, `0x1003a5354`):
`uvScale = 1/baseRadiusWorld`, removing the old `(5/r)+1` scale that sampled outside the skin and relied on `clampToEdge`.

## 2. Simulation tick order

The original `GameArena` tick is not present as a single symbol in the dump; the live server order is
encoded by `NearbySim.swift` and the client order by `ContentView.swift`. Audited steps:

| Step | NearbySim | ContentView | Result |
|------|-----------|-------------|--------|
| Virus pop threshold | `virusPopMinMass` | `virus.targetMass * eatMassRatio` | equal value |
| Virus trigger shape | solid `c.radius` | now `c.solidRadius` | fixed |
| Virus child angles | uniform random per child (`AgarCell::eatVirus`) | was deterministic sectors; now uniform random | fixed |
| Virus child impulse | exact `splitEjectionForce` | was `0.85...1.15` random; now exact | fixed |
| Split immunity | `0.2` | was `0.12` for split and virus pop; now `0.2` | fixed |
| Spawn clamp | `clampSquashCoordinate` at `0.4*r` | `clampSquashPosition` same constant | equal |
| Virus mass | `targetMass + virusBaseMass` | same | equal |
| Child cap | `16 - ownerCells + 1` | same | equal |
| Eject spread | `directionAngleVariation` + `spawnFoodVelocityVariation` | same constants | equal |
| Tick rate | fixed server step | display-link dt clamped `0.0005...0.05` | intentional client interpolation |

## 3. HUD/menu transitions

`MenuMain` visibility is driven by `CCBIBindingContext.visibilityOverrides` in `ContentView.swift`.
`scripts/ccbi_render_reference.py` now applies that exact controller state instead of drawing every
legacy/A-B layer in the raw `.ccbi`.

| Screen | Raw CCBI | Controller overrides | Reference status |
|--------|----------|----------------------|------------------|
| Main menu | `MenuMain.ccbi` | `_promoMenu`, `_featureMenu`, `_matchStatsView`, `_extraButtonsLayer`, `_speechButtonsLayer`, `_playButtonsScrollNode`, badges off; `_inputBox`/`_staticPlayButtonsContainer` replaced by slot views | controller state applied; bound slots not rasterised |
| Settings | `MenuSettings.ccbi` | `_menuHelp`, `_scrollbarNode` off; `_tableNode` slot | applied; SSIM >= 0.92 |
| Skins | `MenuShopSkins.ccbi` | `_scrollbarNode` off; `_tabsNode`, `_tableNode` slots | applied; dynamic cards not rasterised |
| Potions | `MenuMysteryPotions.ccbi` | `PotionSlot.ccbi` x4, help modal | 4 slots drawn by app; reference still draws 3 |
| Death / Play Again | `MenuBattleResultPopup.ccbi`, `ContinueGame.ccbi` | popup controllers | present in app |
| `EmojiWidget`, `Controls-Sides`, `Score` | separate `.ccbi` | HUD controllers | rendered by app |

Legacy SwiftUI fallbacks: none were found for these screens; all six are `CCBISceneView`-backed.
The main menu's top-row labels were overflowing their 40pt buttons (visible as clipped `Free Coins`
and a partly off-screen settings button on iPad); `topSquareButton` now constrains the label to 36pt
with `minimumScaleFactor(0.55)`.

## 4. SSIM gate

`scripts/diff_heatmap.py` now defaults to `--min-ssim 0.92` and exits non-zero below it.
Latest local audit (`Build/ci_artifacts6`, 8 pairs):

| Pair | SSIM |
|------|------|
| iPhone Settings | 0.9272 |
| iPad Settings | 0.9205 |
| iPhone MainMenu | 0.7999 |
| iPad MainMenu | 0.8783 |
| iPhone Skins | 0.7663 |
| iPad Skins | 0.8355 |
| iPhone Potions | 0.8304 |
| iPad Potions | 0.8892 |

Only Settings passes. The remaining screenshots contain dynamic slot content (skin cards, potion
cards, bound `_staticPlayButtonsContainer`/`_inputBox` views) that the static `.ccbi` reference does
not rasterise; treating 0.92 as met for those pairs would be false.
