//
//  Agar-style arena game - performance / text / AI / teammate overhaul (v24)
//
//  Drop-in replacement. Same assets and asset names (skins "1"..."387", "virus", "token",
//  "split", "feed", "pause", "leaderboard", "arrow", "joystick-base", "joystick-circle",
//  "title", "background-ipadpro-hd", font "UbuntuSans-Bold").
//
//  v2 note: every level-of-detail shortcut from v1 is gone. Nothing is drawn smaller,
//  thinner, later or in lower quantity than in your original build - grid spacing, grid line
//  width, pellet cut-off, ejected-mass outlines, skins, cell outlines, organic-blob vertex
//  counts and label sizes/offsets are all back to the original maths. The speedups below are
//  all "same pixels, less work".
//
//  1. LAG (all pixel-neutral)
//     - Canvas `symbols:` no longer holds 337 Images (ForEach(1...387)); SwiftUI was resolving
//       every skin in the asset catalogue on EVERY redraw. Images are resolved on demand and
//       cached for the frame, so the same image is resolved at most once per frame.
//     - Labels: one cached sprite draw instead of up to 66 glyph draws per cell per frame.
//     - @Published removed from the food / ejected-mass grids (they mutate dozens of times per
//       frame, and each mutation was pushing a SwiftUI invalidation).
//     - One shared spatial index for AI + cell collisions + mass pickup; the old O(n^2) bot
//       loops and the "scan every ejected-mass bucket in the world" pass are gone.
//     - Cull cells before sorting them (the old code sorted every cell in the world, twice).
//     - Food is batched by palette index instead of hashing a Color per pellet per frame.
//     - drawLayer + clip per cell only when it can change a pixel (skin present, or the fill is
//       briefly outgrowing the border while inflating). The fill is inside the border otherwise.
//     - Deformation: reused scratch buffers instead of 3 allocations per cell per frame, and
//       cells that can't be squished (nothing near them, no wall, off camera) just relax.
//     - Game clock is a vsync-locked CADisplayLink (was Timer.publish 1/60): no beat against
//       the display, and 120Hz on ProMotion if you add `CADisableMinimumFrameDuration = true`
//       to Info.plist. Everything that used a per-frame constant is now dt-based, so the game
//       plays identically at 60 and 120.
//     - HUD extracted into Equatable child views (same layout, same modifiers) so the 60-120Hz
//       state churn stops rebuilding every button, image and gesture in the overlay.
//
//  2. TEXT SHAKING
//     - Labels are pre-rasterised outlined sprites (TextSpriteCache): names cached by string,
//       numbers composed from fixed-pitch digit tiles. Outline weight matches the old 32-stamp
//       outline (7% of font size), geometry matches the old maths exactly:
//       font = max(4, radius * 0.4) locked to physical mass, name -0.125 em, mass +1.625 em at
//       0.8 em, mass label only above 10pt. Nothing is re-laid-out per frame, so it can't jitter.
//
//  3. BOTS
//     - Rewritten brain (see MARK: - BOT BRAIN): staggered planning, threat model that
//       understands split range, prey scoring, real pellet foraging (the old code only looked
//       for food when every other steering force was exactly zero - which never happened),
//       virus play, merge discipline, per-bot temperament, plus a Bot Skill slider and an
//       optional FPS readout in the mod menu (FPS off by default).
//     - Every regular bot now also gets a weighted personal skill tier, so a lobby contains
//       rookies, casual players, skilled players, experts and a few elites instead of clones.
//     - A deliberate 500ms circular joystick signal followed by 10 of your ejected pellets
//       eaten by one regular bot recruits that owner as your single teammate for the life.
//       The teammate split-runs, macro-supports attacks, balances mass, screens threats and
//       lines up seven-feed virus shots. Rare bot pairs coordinate too; friendly fire remains
//       enabled for both kinds of team so authentic trick-splits and split-running still work.
//
//  4. MORE HIGH-CELL-COUNT WORK REMOVED (same rendered output)
//     - Zero-deformation off-screen cells are now O(1), inactive feed-bot cleanup no longer
//       scans every cell every frame, immunity maps are only built while actually needed,
//       merging only considers merge-eligible cells, and virus grids are not built with no
//       flying mass. Eaten-cell dictionaries are likewise skipped when there is no animation.
//     - Ejected mass is clamped at creation as well as during flight using its true rendered
//       ellipse + stroke bounds, so a hold-eject at any wall cannot flash outside the arena.
//
//  5. V4 TEAM VISIBILITY / RESCUE LOGIC / SCALE
//     - A recruited teammate gets adjacent equal-width #FFC300 outer and #F7F831 inner rings.
//     - Deep near-eat overlaps trigger a target-locked virus shot or an exact mass-return burst;
//       if the bot is trapped instead, it peels away and hands the finishing mass to the player.
//     - Friendly fire still enables deliberate transfers, while a bot owner's final cell strongly
//       avoids walking into a larger ally. Loose split pieces remain transferable.
//     - Cached cell radii, lightweight render sort references, local token/virus buckets,
//       off-camera planning cadence and topology-gated index rebuilds cut high-cell-count work
//       without reducing the number, geometry or detail of rendered objects.
//
//  6. V5 LARGE-CELL SCALE / ACTIVE TEAM ORDERS
//     - CellIndex stores one centre reference per cell (instead of copying high-mass cells into
//       every overlapped bucket), then expands and exact-filters queries by live radii.
//     - Split pieces share one union food-grid pass per owner, avoiding repeated large-radius
//       bucket scans. Movement power calculations are cached until mass changes materially.
//     - The recruited teammate stays near the player, cycles mass proactively, prioritises
//       player-led cannon/split-kill support, and can donate a safe loose split piece.
//     - Three full joystick rotations followed by three player pellets caught by the teammate
//       trigger a twelve-second forced feed-back order above every normal AI priority.
//
//  7. V6 REAL SPLIT-RUNNING / SHARED EJECTION / HOT-PATH CORRECTION
//     - Split-running is an alternating leader/catcher leapfrog: catch trailing pieces, then lay
//       a two/three-press rotating forward trail. Travel splits are never blindly mirrored.
//     - Player and bot W presses share one all-eligible-cell spread/convergence implementation;
//       bot tactics select deliberate through macro-fast cadence. Wall hits preserve tangential
//       velocity, so player pellets continue spreading along an edge.
//     - A hybrid cell index isolates giant radii instead of widening every query, and singleton
//       food owners bypass v5's per-frame grouping allocations. Rendering quantity is unchanged.
//     - The mod menu can disable player teaming; doing so immediately dissolves an active pact.
//
//  8. V7 TACTICAL W / SAFER TEAMMATES / PIXEL-NEUTRAL FRAME-TIME
//     - Regular bots can now commit to offensive virus shots (including shots at the player),
//       and split owners can macro toward a central receiver to consolidate mass. Tactical
//       volleys use every eligible owner cell. (v46: the low-spread centre-landing pellet
//       mode is gone - bot pellets use the player's exact spread and travel physics.)
//     - Teammate support requires a live joystick attack signal or a recent real attack split;
//       remembered headings no longer create endless support orders. Piece-aware danger checks,
//       bounded pursuit, larger reserves and player-led split-running stop tunnel-vision deaths.
//     - Ejected mass stores one compact render-style ID rather than two SwiftUI Colors per pellet.
//       Active mass/cell/virus collision work is fused into one pass.
//     - The simulation uses one shared post-movement cell-index build per normal frame, object
//       indices are rebuilt only when their contents move/change, and bot-owner bookkeeping uses
//       one aggregate dictionary. Visible tokens/viruses are culled directly in Canvas.
//     - Redundant per-tick animation/state work is removed; Canvas stays synchronous because its
//       live food/mass managers are main-thread owned. No object, skin, label, outline, grid
//       line, vertex or rendered pixel is dropped.
//
//  9. V8 SKIN EDGE-CLAMP DURING BORDER LAG
//     - When lagMass leaves an outer ring around a skinned cell, that ring no longer exposes the
//       flat cell colour. The source skin's one-pixel top/bottom rows, left/right columns and
//       four corner pixels are stretched outward as a true nine-slice clamp-to-edge texture.
//     - The extension is clipped by the exact existing outer organic path, producing the solid
//       horizontal/vertical crosshair bars while preserving the inner skin, borders and labels.
//     - Pixel slices are extracted once per skin on demand and persistently cached; normal cells
//       and unskinned cells pay no extra slice-resolution or draw cost.
//
//  10. V9 AUTOMATIC PER-SKIN GAMEPLAY PALETTES
//     - Every skin is sampled once at 40x40. A saturation-aware histogram weights the outer
//       artwork most heavily, rejects black/white detail from dominating, and finds the skin's
//       stable base hue rather than averaging multicolour art into grey.
//     - That hue produces a readable lighter ejected-mass/cell fallback colour and a darker,
//       more saturated border. Fly-like skins become sand/tan; green creature skins become
//       green/teal without maintaining a brittle hand-written table for all 387 images.
//     - Results are cached by skin name and inherited by players, bots, feed bots, ordinary
//       splits and virus splits. Unskinned cells retain the original random colour behaviour.
//
//  11. V10 DISCRETE AGAR-STYLE EJECTED-MASS SWATCHES
//     - Skin analysis now selects the closest entry from an expanded fixed gameplay palette
//       instead of synthesising an arbitrary pellet RGB. Natural sand, brown, cream, sage,
//       olive and grey families sit alongside the familiar red-through-purple colours.
//     - Each swatch has three coordinated values: a light pellet fill, a subtly darker pellet
//       outline and a clearly darker cell border. Fly-like artwork maps to light tan; the green
//       creature example maps to muted sage, matching the supplied references.
//
//  12. V11 REFERENCE-CALIBRATED PELLET TONE / OUTLINE
//     - Palette analysis now strongly samples the visible circular perimeter instead of letting
//       bright centre artwork choose the underlying gameplay colour.
//     - Dark olive, teal, blue, indigo, red, green, purple and neutral swatches preserve the
//       broad tone range visible in real examples; brightness now matters during matching.
//     - Pellet outlines sit about one subtle shade below their fills rather than creating the
//       high-contrast pastel \"donut\" seen in v10. Geometry and pellet size are unchanged.
//
//  13. V12/V13 IN-GAME LEAVE CONFIRMATION / CENTRED RESUME AIM
//     - Pause opens a modal without unmounting or freezing the active match. HUD, controls,
//       cursor and mod UI disappear instantly, while simulation and physics continue underneath.
//     - The single flat `Leave-popup` asset uses normalized invisible No/Yes hit regions; no
//       separate visual layers are required. No resumes, while Yes exits to the main menu.
//     - Resuming resets the cursor to the player-flock centre. Until the next world touch/drag,
//       feed and macro converge inward and split pieces launch toward that same centre.
//     - V13 matches the smaller reference scale, adds press/both-button darkening, a 200 ms
//       confirmation hold, and the supplied two-stage entrance and No/Yes exit timing.
//     - V14 shortens every movement phase by 40% and deepens the button overlay to the measured
//       held-button reference while preserving the deliberate 200 ms confirmation beat.
//     - V15 fixes exact-centre macro/feed presses after No (the first burst now emits immediately)
//       and shortens the V14 movement phases by another 20%.
//     - V16 prevents random virus replacements from landing on ejected-mass piles, applies the
//       normal virus-launch threshold to settled pellets, removes the fast-eject hold-start gap,
//       uses 50 ms/200 ms No/Yes confirmation delays, and exits to menu on player death.
//     - V17 preserves the intentional 1.4-second feed hold threshold but removes the extra
//       post-No gesture latency: both eject controls now receive raw touch-down events instead
//       of rebuilding empty SwiftUI Buttons around drag gestures.
//     - V19 reverts V18's pellet layering/transfer experiment entirely (ejected mass draws in
//       its original layer with original owner immunity) and fixes the real post-No fault: the
//       committed popup and dimmer stayed hit-testable through their whole exit animation, so a
//       finger that came down on feed/macro in that window was captured by the dying overlay and
//       the hold never registered until a fresh touch. Game input is now restored the instant No
//       commits, and the exiting popup is a purely visual, non-hit-testable layer.
//     - V20 removes SwiftUI's gesture-recognizer layer from the feed and macro buttons entirely.
//       Both now sit on a raw UIKit touch surface (touchesBegan/touchesEnded), which iOS delivers
//       synchronously on skin contact. No recognizer arbitration, speculative delay, or state
//       left behind by the popup transition can postpone press or release again.
//     - V23 restyles the recruited-teammate marker: instead of the normal-width orange ring plus
//       an extra normal-width yellow ring inside it (double the band, digging into the skin),
//       the marker now fits entirely inside the normal border band - same total width as every
//       other cell's border - split into an orange outer half and a yellow inner half.
//     - V24: (1) the player's own cells now wear the team marker while a pact is active and lose
//       it when the pact dissolves, matching the teammate. (2) Camera no longer snaps when a
//       cell is lost: the discontinuous jump of the mass-weighted centre is banked into an
//       offset that decays smoothly; ordinary tracking is unchanged. (3) Feed/macro buttons grey
//       out unless at least one *individual* cell clears the 32-mass eject threshold (total mass
//       was a lie when every split piece was tiny). (4) Two instant border pops fixed: the
//       organic path now compensates the quad-curve undershoot so relaxing the last dent no
//       longer swaps in a visibly larger ellipse, and vertex-count changes resample the dent
//       buffer instead of zeroing it. (5) Bot name list rebuilt from real Agar.io lobby culture
//       (skin triggers, chat/troll names, memes, handles, clan tags); placeholder-sounding
//       names removed.
//     - V31 teammate synergy overhaul (duo play modelled on high-level Agar duos):
//       (1) Feeds now aim at the receiver's PREDICTED position (joystick travel + decaying
//       split impulse), so support pellets land on the attacking piece instead of its wake.
//       (2) Attack-split support keeps feeding through the first ~1.6s even when the split
//       target dies mid-lunge, uses 3-press bursts and a tighter cadence. (3) Cannon support
//       also stages and drip-feeds when the player already owns the eat ratio and is lunging
//       (top-up feeding), not only when mass is missing. (4) Threat response is victim-aware:
//       when a player fragment is the endangered cell the teammate body-blocks the lane
//       between chaser and fragment (or holds the escape lane when too small) and
//       emergency-dumps mass into that fragment down to a small survival reserve. (5) A
//       chaser neither partner can eat now draws a DEFENSIVE virus volley (profitability
//       gate waived - sixteen forced fragments end a chase). (6) Quiet-time rebalancing:
//       with no hostiles around, a teammate sitting on >1.5x the player's mass trickles it
//       down to ~1.25x so the player is always the loaded weapon. (7) The idle escort biases
//       toward the player's smallest fragment while split, deterring opportunists early.
//     - V32 league level badges: 15% of bots roll a level (1-150) at spawn and wear the
//       matching league image ("fly-league" 1-14, "wasp-league" 15-24, "bat-league" 25-34,
//       "fox-league" 35-44, "hunter-league" 45-54, "bear-league" 55-64, "panther-league"
//       65-74, "crocodile-league" 75-84, "mammoth-league" 85-99, "kraken-league" 100-150)
//       with the level number stamped on the star using the existing outlined digit sprites.
//       No name: badge centred on the skin (height = 1.3x radius), mass counter moves to the
//       star's lower tip. Named: badge hangs on the very left of the name text at text
//       height. The main menu gained a Level row (toggle + 1-150 number pad input with live
//       clamping + auto-adjusting league preview) so the player can wear one too. Levels are
//       per-owner (every split piece wears the badge) and die with the owner. Badge digits
//       use their own sprite set: the stroke is drawn with round line joins/caps (set on
//       the CGContext before stroking - attributed-string strokes take width from the
//       attribute but join/cap from the context) so corners are soft, and its colour is
//       sampled at runtime from that league's own star image (average of the darkest ~15%
//       of fully opaque pixels = the star's rim/engraving shade), so every league's level
//       number is stroked in that star's dark colour. Sampled once per asset and cached;
//       falls back to fly-league dark gold (#806818) if an asset can't be read. The menu
//       preview's text shadow follows the same per-league colour. Also removed the
//       fontSize > 10 gate on the named-cell mass counter - small cells kept losing their
//       mass text whenever zoom pushed the label under the threshold.
//
// v34 - Split cells freeze their mass label size. Every cell born from a split (manual
//       splits via executeSplit and virus popsplits, player and bots alike) stores
//       lockedMassFontSize: the base label font size it has at birth (settled targetMass
//       radius x zoom at that moment). drawCellLabels then draws the mass counter at that
//       frozen size instead of tracking the radius, clamped every frame so the effective
//       ratio never exceeds the current default (radius x zoom x 0.4) and never drops
//       below 40% of it - the label only changes size to respect those two limits.
//       Spawned cells (nil lock) keep normal radius-based sizing; names and badges are
//       untouched, and the named layout still positions the counter off the name's font.
//
// v35 - Level text stroke 40% thicker: badge digits rasterise with strokeWidthMultiplier
//       1.4 (centred stroke 14% -> 19.6% of font size). Only the league-badge digit
//       sprites use it - mass counters and names keep the original outline weight. The
//       thicker stroke still fits the shared digit tile (extends ~9.8% outward vs the
//       16% padding), so digit pitch and layout are unchanged.
//
// v36 - Mod menu rebuilt as a visual clone of xelahot/iOS-Mod-Menu-Base (measurements
//       taken from the tweak's Menu.mm): 200x250 black-75% panel, square corners,
//       2.5pt pure-green border outside the frame, 50pt header with white grab bar,
//       centred AppleSDGothicNeo-Light title, back/close buttons and a 1.25pt green
//       divider. Items are 200pt rows outlined 0.5pt white: 40pt tap-to-toggle rows
//       that fill grey (0.35 @ 0.75) when ON with an (i) description popup, 40pt
//       submenu rows with a chevron (Macro / Gameplay / Bots / Feed Bots pages +
//       back button), 60pt slider rows (UISlider with both tracks white, value text
//       right of the track) and 60pt underline-style textfield rows. Header drag
//       moves the panel, double-tap closes, open/close fades 0.5s, and the launcher
//       is the base's draggable double-gear icon. All previous controls preserved.
//
// v37 - Mod menu launcher now uses the bundled "mod-menu-btn" image asset (50x50,
//       scaledToFit) instead of the SF Symbol double-gear; drag + tap behavior kept.
//
// v38 - Macro bots, randomized lobbies, threshold-halved mass text, no more grey buttons.
//       (1) Feed/macro start live: a new match begins in the same centre-aim mode the
//       pause popup resumes into, so the buttons are enabled from frame one (pellets
//       converge on the flock centre until the cursor first moves) instead of starting
//       greyed out. (2) "Randomize Bot Start Mass" toggle (menu Settings + mod menu >
//       Bots): the opening bot wave spawns at 40-10000 mass (skewed low/mid, a few
//       giants - an in-progress server), and every bot that dies respawns at 40-140.
//       Off = the Bot Start Mass slider, as before. (3) Mass-label sizing reworked:
//       lockedMassFontSize (freeze at birth, 40%-clamped) is REPLACED by a half-ratio
//       lineage. Splitting at/above 4000 mass (massFontHalfThreshold) drops the splitting
//       cell and each piece born from it to half the base font ratio; the label still
//       scales with the radius, just at half ratio. Children inherit half only while the
//       parent is >= 4000 at the moment it splits: a half piece that shrank below 4000
//       births normal-ratio cells while itself staying half. All split sites covered
//       (executeSplit + player/bot virus popsplits). (4) Bots recombine with real macros:
//       centre consolidation fires skill-scaled multi-press volleys at up to ~0.05s
//       cadence, allied pairs macro their rebalance, and a new macro-then-split play
//       funnels trailing pieces into the lead cell mid-chase so the next split launches
//       one bigger piece when the lead alone could not win it. (5) The recruited teammate
//       macros faster across every feed lane (4-press volleys, cooldowns 0.032-0.05,
//       faster virus loading and rebalancing). (6) More human bot play: skilled cells
//       juke perpendicular out of an incoming split lane instead of running dead-away,
//       foraging paths bend away from sub-flee pressure, owners commit to a chase via
//       prey-focus memory (1.5x scoring bonus, cleared when the hunt ends), and
//       below-elite bots launch splits with a few degrees of human aim error.
//
// v39 - Half-font fix + party HUD. (1) The half-ratio mass label now applies ONLY to the
//       new piece coming out of an at/above-4000 cell; the splitting cell itself keeps
//       its own ratio (all three split sites). (2) Friends counter in the top-right, left
//       of the leaderboard button: Image("friends-count-icon") + "(n) friend(s)" in grey.
//       (3) The pact survives the teammate's death: the counter drops to 0, and the next
//       regular bot respawn re-enters the lobby AS the same friend (name, skin, league
//       badge preserved) and rejoins the party automatically. The PLAYER dying still
//       fully dissolves it, as does toggling teaming off or leaving the match. (4) Every teammate
//       cell draws Image("friend-pfp") directly above its name text (2.1x the name font).
//       (5) When the whole teammate is off screen, Image("party-arrow-light") circles the
//       screen edge (84pt margin) always pointing at them - asset assumed pointing up -
//       with their name right below in white with a grey stroke (new
//       TextSpriteCache.partyNameSprite).
//
// v40 - Party polish. Arrow shrunk to 58pt and its name label (now 16pt, smaller relative
//       to the arrow) is drawn in the arrow's rotated layer, pinned to the flat bottom
//       edge so it spins exactly with the arrow. Friends counter reduced (36pt icon, 26pt
//       text). Teammate cells now mirror the player's name/mass layout: the pfp occupies
//       the name text's slot above centre (shrunk to 1.8x font size) and the name drops
//       into the mass text's slot below centre at the mass-text scale, league badge
//       following the relocated name.
//
// v41 - Party fit. Teammate pfp and name are now symmetric about the cell centre: the
//       name keeps the mass-text slot below (1.625x font) and the pfp mirrors it the
//       same distance above. Party arrow + label ~15% bigger (67pt arrow, 18pt label),
//       a 4pt gap opened between the flat base and the text, and the label flips half a
//       turn around its own centre whenever the arrow points downward so the name always
//       reads upright.
//
// v46 - Authentic bot feeding + pfp/badge polish. (1) Bot ejected mass is now physically
//       IDENTICAL to the player's: the special low-spread "precise" aim (0.022 rad vs the
//       player's 0.17) and its computed landing distance are gone - every pellet, whoever
//       fires it, uses the player's spread and 200+/-50 travel. (2) Bots can no longer pick
//       which cells fire: excludingCellID / sourceAlignment filters removed, so every owner
//       cell >= 32 mass emits on every press, exactly like a W press (a cell sitting on the
//       target emits nothing - zero direction - matching player converge). Consolidation,
//       virus feeding and macro-then-split still work through aim, cadence and positioning,
//       like a human. (3) Teammate pfp slightly bigger (1.2x -> 1.35x font) and higher
//       (centre 0.85 -> 1.0x font above cell centre); the name did not move. (4) The
//       beside-name league badge is 15% smaller (height 1.35x -> 1.1475x font); the big
//       centred badge on no-name cells is unchanged.
//
// v61 - v5.9.5: ONLINE score bug fixed — the HUD score summed the wire's
//       ANIMATED cell masses, so on a split the parent (easing down toward its
//       halved targetMass) and the new half were both counted for a moment
//       (~1.5x per press; macro ejects inflated the same way) and the
//       high-water score latched the phantom peak. The score now reads the
//       player's row from the server leaderboard, which sums authoritative
//       targetMass — exactly what the offline score always did. Visuals
//       untouched.
//
// v60 - v5.9.4: leaderboard truncation now fills the whole row — keep the
//       longest prefix that still fits WITH "..." appended. (v5.9.3 replaced
//       the last 3 visible glyphs with dots, but dots are much narrower than
//       the glyphs they replaced, so cut names stopped short of the right inset.)
// v59 - v5.9.3: (1) Eject pickup needs ~30% of the pellet circle covered
//       (chord rule: reach = R_cell + 8.1) — rim grazes no longer consume;
//       offline sim and server rule match. (2) Leaderboard rows wider than the
//       panel's usable width (right inset = left inset) end in "..." — the last
//       3 visible characters are replaced, measured in the actual row font.
//       (3) The player's own leaderboard row shows their nickname instead of
//       "You" ("You" only when the name is blank), offline and online.
// v58 - v5.9.1: ejected pellets ALWAYS draw below the cells (per Hudson) —
//       the on-top ingestion layer (8.5) is gone; captured pellets now render
//       in the 4.5 under-cell magnet pass, so the eater's own rim occludes
//       them naturally like the real game. Pellet stays full-size (occlusion
//       replaces the shrink), pull speed-capped ~700 u/s so the slide under
//       the rim is visible, despawn once fully under the border (~1.35 pellet
//       radii penetration, ≤55% on tiny cells), ~300 ms cap w/ safety fades.
//
// v57 - v5.9.0: rim-melt — the v56 despawn threshold (25% of CELL radius from
//       centre) let pellets visibly ride across big cells' bodies. Now the
//       melt band sits at the border: full-size/opaque up to the rim, then
//       shrink+fade within ~2 pellet radii of penetration (≤55% on tiny
//       cells), pull speed-capped at ~700 u/s, ~300 ms cap with safety fade.
//       Matches the reference footage: a quick slurp at the edge, nothing
//       gliding over the eater.
//
// v56 - v5.8.9: captured pellets now draw ON TOP of cells while the magnet
//       pulls them in (they used to be painted over by the eater the frame
//       after touch — "disappear on touch"), full-size across the rim with a
//       tail-loaded shrink/fade, ~250 ms cap, pull k = 0.18 (reference match).
// v55 - v5.8.8: v5.8.6 over-cap snap REVERTED by request — back to the v5.8.4
//       spike (mass climbs the spike, holds, then fast ~0.1s burn-off).
// v54 - v5.8.7: eject-pickup reworked to touch capture + ingestion physics —
//       a pellet is captured the moment hitboxes overlap (dist < R_cell + R_eject),
//       mass credits instantly at the trigger, then the pellet target-locks the
//       eater and lerp-snaps to its centre (k = 0.25) while its radius scales
//       with normalized distance and its alpha fades, despawning deep inside
//       the eater or after ~120 ms. Server trigger matches.
// v53 - v5.8.6: (reverted in v5.8.8) over-cap spike has NO mass interpolation — a bite at max
//       snaps the mass straight to its peak in one tick (absorb ramp bypassed
//       over the cap), then rides the burn-off down exactly; only the border
//       lag animation smooths the visuals. Server does the same online.
// v52 - v5.8.5: font-size "fixer" removed by request — half-size mass labels no
//       longer reset back to full when the owner shrinks (no ramp, no timer, no
//       server reset). Lineage rule unchanged: pieces born from a ≥4k split are
//       half-size and simply stay that way.
//
// v51 - v5.8.4: (1) Eject-pellet pickup at ~60% coverage (reach = radius - 5.1) —
//       pellets no longer vanish while half outside the rim. (2) Over-cap deflate
//       ~2x snappier: descent starts once the spike has climbed 60% and takes ~0.1s
//       (~0.25s total). (3) Mass-label size is now a pure function of the cell's
//       animated mass (halved cells ramp 0.5 @≥4k → 1.0 @≤2k): any small cell shows
//       the full label INSTANTLY and there is no time-based transition to spot.
//
// v50 - v5.8.3: the half-font reset is now invisible — the label ratio creeps at a
//       fixed 0.2/s (full 0.5→1.0 takes ~2.5s, ~0.3% per frame) instead of a ~0.3s
//       ease, offline and online. Split-born pieces still start at 0.5 instantly.
//
// v49 - v5.8.2: (1) Pellet pickup at ~45% coverage (reach = radius + 2.5).
//       (2) Over-cap spike fix: the animated mass lerps toward the target, so the
//       old instant decay meant the visible mass never rose more than ~300 over
//       22500 no matter the bite. Now the full spike HOLDS until the animated mass
//       has climbed ~70% of it (a 30k bite really peaks ~28k), then the excess
//       burns off in ~0.1s with the mass snapped down along with it.
//
// v48 - v5.8.1 tuning pass on the v47 pack, from playtest feedback:
//       (1) Pellet pickup relaxed: a pellet is eaten once the cell covers roughly a
//       third of it (reach = radius + 6.3; v47's radius-19 needed ~80-90% coverage
//       and felt sticky). Still no rim-touch grabs. (2) Soft max-mass cap is now
//       snappy: the overshoot burns off in ~0.1s (back at cap by ~0.2s total) instead
//       of ~1s. (3) The half-size mass label reset no longer pops: cells carry an
//       eased massFontScale (0.5 <-> 1.0, ~0.3s fade) used by the label renderer;
//       split-born pieces still START at half size instantly. Online mirrors ease the
//       same way from the server's flag bit.
//
// v47 - v5.8 gameplay pack (offline sim + shared visuals; server has the same rules):
//       (1) Feed bots reworked: they run AT the player and ALL-IN — approach, then spam
//       splits into you (leftovers too small to split are ejected point-blank). The mod
//       menu's Feed Bots page now also works in ONLINE games: the toggle asks the server
//       for a personal feeder squad (name/skin respected), re-requested on every respawn.
//       (2) Max-mass soft cap: eating at 22500 overshoots for a moment, then the excess
//       burns back off (~1s) — agar-style, max-mass giants stay killable. (3) Engulfed
//       piece fix: a small cell stuck fully inside a bigger own cell no longer shoves the
//       big one around — the piece slides out, the giant holds its ground. (4) Ejected
//       pellets need real coverage before pickup (centre well inside the cell, not a rim
//       touch), and a sub-21-mass cell can never re-eat its OWN pellet (bots too).
//       (5) Half-size mass labels reset to full size once every cell of the owner is
//       independently under 2000 mass and no own ejected pellets sit near the cells
//       (mid-macro flicker guard); online the server drives the same reset via flags.
//       (6) Camera zoom weighs split pieces by their mass ratio to the largest cell:
//       one giant with crumbs keeps a tight camera; an even split reads like before.
//
// v45 - League badge + name now centred as a PAIR on every named cell (bots, player,
//       teammates) via one shared drawNameWithBadgeCentred: the name shifts right by half
//       the badge's net footprint so the combined badge+name block sits on the cell
//       centre, instead of the name being centred and the badge dragging the pair left.
//       No-name centred badges and all mass-label positions are untouched.
//
// v44 - Teammate pfp 1.2x font (was 1.8x); name pulled slightly closer to centre than the
//       pfp (0.70x vs 0.85x); name + league badge now centred as a pair under the pfp.
//
// v43 - Teammate pfp/name gap pulled another 20% tighter (offsets 1.06x -> 0.85x font).
//
// v42 - Team play overhaul + fixes. Teammate pfp/name gap 35% tighter; party-arrow label
//       gap 10% tighter. Bot landing ejects capped at a real W press's range (the old 520
//       travel cap made slow feeds sail ~2.6x too far). Feed/macro buttons now fade while
//       held like the split button. Teammate AI: classic tricksplit into the player on a
//       split aimed at the teammate; eats offered player fragments when steered into;
//       collects W-mass gifts ejected at it; farms viruses at 14+ pieces; support feeding
//       gated to genuine attacks (comfort top-ups only after a real attack split, slow
//       drip cadence) so it no longer spam-feeds; split-run lead bursts start sooner.
//
// v44 - Aim arrow rides a fixed circle (bounding circle of all cells) instead of
//       hugging the split-piece silhouette; distance no longer pulses as aim rotates.
// v43 - Aim arrow projects the player's cells onto the aim direction (multi-cell offset
//       was overshooting: it added the farthest cell's distance to the biggest radius,
//       two different cells, ignoring direction). Party arrow: exactly ONE arrow, for
//       the closest fully-off-screen teammate; re-targets when reached or dead, and a
//       teammate standing next to you never hides it. Settings: Show Mass toggle.
//

import SwiftUI
import Foundation
import CoreGraphics
import UIKit
import Combine
import QuartzCore

// MARK: - SHARED HELPERS

struct GridKey: Hashable {
    let x: Int
    let y: Int
}

/// Grid loops used to build `a...b` ranges directly from Int(pos / gridSize).
/// Integer truncation goes toward zero, so a negative min could end up ABOVE max and
/// `a...b` traps at runtime (an instant freeze/crash). Always build ranges through this.
@inline(__always)
func gridRange(_ a: Int, _ b: Int) -> ClosedRange<Int> {
    return a <= b ? a...b : b...a
}

private let teammateOuterBorderColor = Color(hex: 0xFFC300)
private let teammateInnerBorderColor = Color(hex: 0xF7F831)

/// Party codes are exactly 6 characters, A-Z / 0-9. Returns "" for anything else.
/// Shared by the party menu, the online hello and the server (same rule there).
func sanitizedPartyCode(_ raw: String) -> String {
    let cleaned = raw.uppercased().filter { ("A"..."Z").contains($0) || ("0"..."9").contains($0) }
    return cleaned.count == 6 ? cleaned : ""
}

/// Splitting at/above this mass drops the splitting cell's mass label - and every piece
/// born from it - to half the base font ratio. Below it, splits inherit nothing: a
/// half-ratio piece that has shrunk under the threshold births normal-ratio children.
let massFontHalfThreshold: CGFloat = 4000

// MARK: - TEXT SPRITE CACHE (fixes both text shaking and the per-frame glyph cost)
//
// The old renderer resolved Text and then stamped it 32 times (once per outline offset)
// for the name AND the mass, every cell, every frame. Beyond being extremely expensive,
// it re-laid-out glyphs at a scale that changes every frame, which is exactly what made
// the labels shimmer/shake.
//
// Now: every label is rasterised ONCE into an outlined sprite and cached.
//  - names are cached by string (there are only ~46 bot names + the player's)
//  - numbers are composed from fixed-width digit tiles, so a mass counting up from
//    999 -> 1000 never nudges the other glyphs around: no shaking, no re-layout, 1 draw call.
final class TextSpriteCache {
    static let shared = TextSpriteCache()
    
    /// Point size everything is rasterised at. Sprites are drawn @2x on top of that,
    /// so they stay crisp when a big cell blows the label up on screen.
    let referenceFontSize: CGFloat = 96
    private let renderScale: CGFloat = 2.0
    /// The old code stamped the black text 32x around a 7%-of-font-size circle.
    /// A centred stroke of 14% extends 7% outward, so the outline weight matches.
    private let strokePercent: CGFloat = 14.0
    
    struct Sprite {
        let image: Image
        let size: CGSize      // in points, at referenceFontSize
    }
    
    private var nameCache: [String: Sprite] = [:]
    private var partyNameCache: [String: Sprite] = [:]
    private var digitCache: [Sprite] = []
    private var badgeDigitCache: [String: [Sprite]] = [:]
    private(set) var digitTile: CGSize = .zero
    /// Distance between digit centres, in reference points (fixed pitch = stable numbers).
    private(set) var digitAdvance: CGFloat = 0
    
    /// Fallback badge stroke (fly league's dark gold, sampled from the reference art).
    /// The live colour comes from LeagueBadge.strokeColor(forAsset:) - each league's star
    /// is a different colour, so the stroke is sampled from that league's own image.
    static let badgeStrokeColor = UIColor(red: 0x80 / 255.0, green: 0x68 / 255.0, blue: 0x18 / 255.0, alpha: 1.0)
    
    private func font(_ size: CGFloat) -> UIFont {
        return UIFont(name: "UbuntuSans-Bold", size: size) ?? UIFont.systemFont(ofSize: size, weight: .heavy)
    }
    
    private func rasterize(_ string: String, tile: CGSize?,
                           strokeColor: UIColor = .black, roundedStroke: Bool = false,
                           strokeWidthMultiplier: CGFloat = 1.0) -> Sprite {
        let f = font(referenceFontSize)
        let pad = referenceFontSize * 0.16
        
        let strokeAttrs: [NSAttributedString.Key: Any] = [
            .font: f,
            .foregroundColor: UIColor.clear,
            .strokeColor: strokeColor,
            .strokeWidth: Double(strokePercent * strokeWidthMultiplier)
        ]
        let fillAttrs: [NSAttributedString.Key: Any] = [
            .font: f,
            .foregroundColor: UIColor.white
        ]
        
        let strokeString = NSAttributedString(string: string, attributes: strokeAttrs)
        let fillString = NSAttributedString(string: string, attributes: fillAttrs)
        let textSize = fillString.size()
        
        let canvasSize = tile ?? CGSize(width: ceil(textSize.width + pad * 2),
                                        height: ceil(textSize.height + pad * 2))
        let safeSize = CGSize(width: max(canvasSize.width, 1), height: max(canvasSize.height, 1))
        
        let origin = CGPoint(x: (safeSize.width - textSize.width) / 2,
                             y: (safeSize.height - textSize.height) / 2)
        
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = renderScale
        format.opaque = false
        
        let renderer = UIGraphicsImageRenderer(size: safeSize, format: format)
        let uiImage = renderer.image { ctx in
            if roundedStroke {
                // Text stroking picks its width up from the string attribute, but the
                // join/cap come from the context - round both so corners stop spiking.
                ctx.cgContext.setLineJoin(.round)
                ctx.cgContext.setLineCap(.round)
            }
            strokeString.draw(at: origin)
            fillString.draw(at: origin)
        }
        
        let image = Image(uiImage: uiImage).interpolation(.high).antialiased(true)
        return Sprite(image: image, size: safeSize)
    }
    
    func nameSprite(_ name: String) -> Sprite? {
        if name.isEmpty { return nil }
        if let cached = nameCache[name] { return cached }
        // Bots pull from a fixed name list, so this cache is naturally tiny.
        if nameCache.count > 256 { nameCache.removeAll(keepingCapacity: true) }
        let sprite = rasterize(name, tile: nil)
        nameCache[name] = sprite
        return sprite
    }
    
    /// Party-arrow label: identical rasteriser, but white fill with a grey outline
    /// instead of the standard black, per the reference HUD.
    func partyNameSprite(_ name: String) -> Sprite? {
        if name.isEmpty { return nil }
        if let cached = partyNameCache[name] { return cached }
        if partyNameCache.count > 64 { partyNameCache.removeAll(keepingCapacity: true) }
        let sprite = rasterize(name, tile: nil, strokeColor: UIColor(white: 0.45, alpha: 1.0))
        partyNameCache[name] = sprite
        return sprite
    }
    
    /// Digits share one tile size => monospaced, rock-steady numbers.
    private func ensureDigits() {
        guard digitCache.isEmpty else { return }
        let f = font(referenceFontSize)
        var maxW: CGFloat = 0
        var maxH: CGFloat = 0
        for d in 0...9 {
            let s = NSAttributedString(string: String(d), attributes: [.font: f]).size()
            maxW = max(maxW, s.width)
            maxH = max(maxH, s.height)
        }
        let pad = referenceFontSize * 0.16
        let tile = CGSize(width: ceil(maxW + pad * 2), height: ceil(maxH + pad * 2))
        digitTile = tile
        // size() returns the typographic advance, which is exactly what .monospacedDigit()
        // used for spacing before, so the pitch matches the original.
        digitAdvance = maxW
        var built: [Sprite] = []
        built.reserveCapacity(10)
        for d in 0...9 {
            built.append(rasterize(String(d), tile: tile))
        }
        digitCache = built
    }
    
    func digitSprite(_ digit: Int) -> Sprite? {
        ensureDigits()
        guard digit >= 0 && digit <= 9 else { return nil }
        return digitCache[digit]
    }
    
    /// League-badge digits: same metrics/tile as the mass digits (so drawNumberSprite can
    /// lay both out identically), but stroked with that league star's dark shade and
    /// rounded joins. One 10-digit set per league asset, built on first use.
    func badgeDigitSprite(_ digit: Int, asset: String) -> Sprite? {
        ensureDigits()
        guard digit >= 0 && digit <= 9 else { return nil }
        if let cached = badgeDigitCache[asset] { return cached[digit] }
        let stroke = LeagueBadge.strokeColor(forAsset: asset)
        var built: [Sprite] = []
        built.reserveCapacity(10)
        for d in 0...9 {
            built.append(rasterize(String(d), tile: digitTile,
                                   strokeColor: stroke,
                                   roundedStroke: true,
                                   strokeWidthMultiplier: 1.4))
        }
        badgeDigitCache[asset] = built
        return built[digit]
    }
    
    func warmUp() {
        ensureDigits()
        for name in botNames { _ = nameSprite(name) }
    }
}

// MARK: - PER-FRAME IMAGE RESOLVER
//
// Canvas `symbols:` used to hold 337 Images (ForEach(1...387)) which SwiftUI resolved on
// EVERY redraw - by far the single biggest frame-time sink in the old build. Skins, viruses,
// tokens and text sprites are now resolved on demand, at most once per frame, and only for
// things actually visible.
final class FrameImageResolver {
    private var map: [String: GraphicsContext.ResolvedImage] = [:]
    
    func reset() {
        map.removeAll(keepingCapacity: true)
    }
    
    func resolve(_ key: String, context: GraphicsContext, make: () -> Image?) -> GraphicsContext.ResolvedImage? {
        if let cached = map[key] { return cached }
        guard let image = make() else { return nil }
        let resolved = context.resolve(image)
        map[key] = resolved
        return resolved
    }
}

// MARK: - SKIN EDGE-CLAMP CACHE
//
// A lagging skin needs dynamic destination widths, so one pre-rendered padded bitmap would
// distort whenever outerRadius / innerRadius changes. Cache the source image's eight one-pixel
// edge/corner slices instead; Canvas can stretch those same tiny sprites to any live radius.
final class SkinEdgeClampCache {
    static let shared = SkinEdgeClampCache()
    
    struct Slices {
        let top: Image
        let bottom: Image
        let left: Image
        let right: Image
        let topLeft: Image
        let topRight: Image
        let bottomLeft: Image
        let bottomRight: Image
    }
    
    /// Which part of the source image the clamp slices come from. Dual-width skin
    /// sheets clamp each half against that half's own edges, so the base half never
    /// bleeds alt pixels into the lagging ring (and vice versa).
    enum Half: String {
        case full = "F"
        case left = "L"
        case right = "R"
    }
    
    private var cache: [String: Slices] = [:]
    private var failedNames = Set<String>()
    
    /// Asset-catalog images are normally already `.up`. Normalize unusual orientation-tagged
    /// images once so the cached row/column coordinates still match the displayed skin.
    private func uprightCGImage(_ image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cgImage = image.cgImage {
            return cgImage
        }
        
        let pixelSize = CGSize(
            width: max(1, ceil(image.size.width * image.scale)),
            height: max(1, ceil(image.size.height * image.scale))
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let normalized = UIGraphicsImageRenderer(size: pixelSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: pixelSize))
        }
        return normalized.cgImage
    }
    
    private func sprite(from image: CGImage, rect: CGRect) -> Image? {
        guard let crop = image.cropping(to: rect) else { return nil }
        return Image(uiImage: UIImage(cgImage: crop, scale: 1, orientation: .up))
            .resizable()
            .interpolation(.high)
            .antialiased(false)
    }
    
    func slices(for skinName: String, half: Half = .full) -> Slices? {
        let key = skinName + "|" + half.rawValue
        if let cached = cache[key] { return cached }
        if failedNames.contains(key) { return nil }
        
        guard let source = UIImage(named: skinName),
              let image = uprightCGImage(source),
              image.width > 0,
              image.height > 0 else {
            failedNames.insert(key)
            return nil
        }
        
        let fullWidth = CGFloat(image.width)
        let height = CGFloat(image.height)
        // If a half is requested but the image is not actually a dual-width sheet,
        // fall back to the full image so the clamp still renders something sensible.
        let isDual = fullWidth >= height * DualSkin.aspectThreshold
        let halfWidth = (fullWidth / 2).rounded(.down)
        let originX: CGFloat
        let width: CGFloat
        switch half {
        case .left where isDual:
            originX = 0
            width = halfWidth
        case .right where isDual:
            originX = fullWidth - halfWidth
            width = halfWidth
        default:
            originX = 0
            width = fullWidth
        }
        let lastX = max(originX, originX + width - 1)
        let lastY = max(0, height - 1)
        
        guard let top = sprite(
            from: image,
            rect: CGRect(x: originX, y: 0, width: width, height: 1)
        ),
              let bottom = sprite(
                from: image,
                rect: CGRect(x: originX, y: lastY, width: width, height: 1)
              ),
              let left = sprite(
                from: image,
                rect: CGRect(x: originX, y: 0, width: 1, height: height)
              ),
              let right = sprite(
                from: image,
                rect: CGRect(x: lastX, y: 0, width: 1, height: height)
              ),
              let topLeft = sprite(
                from: image,
                rect: CGRect(x: originX, y: 0, width: 1, height: 1)
              ),
              let topRight = sprite(
                from: image,
                rect: CGRect(x: lastX, y: 0, width: 1, height: 1)
              ),
              let bottomLeft = sprite(
                from: image,
                rect: CGRect(x: originX, y: lastY, width: 1, height: 1)
              ),
              let bottomRight = sprite(
                from: image,
                rect: CGRect(x: lastX, y: lastY, width: 1, height: 1)
              ) else {
            failedNames.insert(key)
            return nil
        }
        
        let built = Slices(
            top: top,
            bottom: bottom,
            left: left,
            right: right,
            topLeft: topLeft,
            topRight: topRight,
            bottomLeft: bottomLeft,
            bottomRight: bottomRight
        )
        cache[key] = built
        return built
    }
}

// MARK: - DUAL-WIDTH SKINS (eat-triggered swap + timed shine overlay)
//
// Fully universal - no skin names are special-cased. Any skin whose bundled image is
// roughly DOUBLE WIDTH (width >= height * aspect threshold; e.g. 1024x512 vs the usual
// square) is treated as a "dual" skin holding two pieces of artwork side by side:
//
//      +----------------+----------------+
//      |   base skin    |    alt skin    |     square skins keep behaving exactly
//      |  (left half)   |  (right half)  |     as before - full image, no effects
//      +----------------+----------------+
//
// A dual skin is layered from three parts:
//   1. Base artwork (LEFT half) drawn exactly like any other skin.
//   2. Eat-triggered swap: while the player wears a dual skin, eating a token or another
//      player's/bot's cell fades the alternate artwork (RIGHT half) in on top of the base
//      half (0.03 s in, 0.1 s out, 1.5 s total including both fades), then returns to
//      normal. A brief post-swap delay must elapse before the swap can fire again, and
//      eats that land while the alternate art is up (or during that delay) are dropped
//      outright - they never queue a second swap.
//   3. Shine overlay: every 5 seconds the Spine "SkinEffects/A" pass (three additive
//      crescent glints sweeping across the cell) plays on top of the skin. The Spine
//      timeline was baked to 30 fps samples below; the three sprites are drawn straight
//      from Image("SkinEffects") sprite-sheet style (clip + offset page draw).
//
// Requires "SkinEffects" in the asset catalogue for the shine; everything degrades
// gracefully (square image -> plain skin, missing shine page -> no shine).

enum DualSkin {
    /// An image counts as dual-width when width >= height * this. Normal skins are
    /// square (ratio 1), dual sheets are ~2, so 1.5 separates them with a safe margin.
    static let aspectThreshold: CGFloat = 1.5
    /// Total time the alternate artwork is on screen, *including* both fades.
    static let altShowDuration: TimeInterval = 1.7
    /// The alternate artwork fades in over the base skin this quickly...
    static let altFadeInDuration: TimeInterval = 0.03
    /// ...and fades back out over this long at the end of the show window.
    static let altFadeOutDuration: TimeInterval = 0.1
    /// Slight delay after switching back to normal before the swap can trigger again.
    static let retriggerDelay: TimeInterval = 0.5
    /// A new shine pass starts every 5 seconds (2 s of animation + 3 s of rest),
    /// measured start-of-pass to start-of-pass.
    static let effectInterval: TimeInterval = 5.0
    /// Cell diameter, in Spine-file units, the authored shine pass is framed around.
    /// The overlay is scaled by (cellDiameter / this) so the sweep covers any cell size.
    static let effectReferenceDiameter: CGFloat = 500
    
    /// Opacity of the alt-half overlay `elapsed` seconds after the swap fired:
    /// linear 0->1 over the fade-in, hold at 1, linear 1->0 over the trailing fade-out.
    /// Outside the show window this is 0, so callers can pass any elapsed time safely.
    static func altOverlayAlpha(elapsed: TimeInterval) -> CGFloat {
        guard elapsed >= 0, elapsed < altShowDuration else { return 0 }
        if elapsed < altFadeInDuration {
            return CGFloat(elapsed / altFadeInDuration)
        }
        let remaining = altShowDuration - elapsed
        if remaining < altFadeOutDuration {
            return CGFloat(remaining / altFadeOutDuration)
        }
        return 1
    }
}

/// Eat-triggered artwork swap state. Strictly idle -> showing -> cooldown -> idle;
/// triggers are only accepted in .idle, which is what prevents queued re-triggers.
enum DualSkinSwapPhase {
    case idle
    case showing
    case cooldown
}

/// Answers "is this skin image a dual-width sheet?" from the bundled image's pixel
/// aspect ratio. Each name is measured once and cached, so per-frame checks are a
/// dictionary hit. Missing images are simply "not dual" (and remembered as such).
final class DualSkinCatalog {
    static let shared = DualSkinCatalog()
    
    private var isDualByName: [String: Bool] = [:]
    
    func isDual(_ skinName: String?) -> Bool {
        guard let skinName else { return false }
        if let cached = isDualByName[skinName] { return cached }
        var dual = false
        if let image = UIImage(named: skinName), image.size.height > 0 {
            // UIImage.size is in points; width/height share the same scale factor,
            // so the point ratio equals the pixel ratio.
            dual = image.size.width >= image.size.height * DualSkin.aspectThreshold
        }
        isDualByName[skinName] = dual
        return dual
    }
}

// MARK: Shine-atlas regions

/// The three shine sprites live on the single "SkinEffects" atlas page, loaded as a plain
/// SwiftUI `Image("SkinEffects")` exactly like every other skin asset. Region coordinates
/// come from SkinEffects.atlas (authored against a 2048x512 page) and are stored as
/// fractions of the page, so any resolution export of the same page works. Each sprite is
/// drawn sprite-sheet style: clip to the sprite's destination rect, then draw the whole
/// page scaled and offset so the region lands exactly inside the clip.
enum SkinEffectsSheet {
    /// Page-relative regions: A_Shine1, A_Shine2, A_Shine3.
    static let regions: [CGRect] = [
        CGRect(x: 451.0 / 2048.0, y: 14.0 / 512.0, width: 436.0 / 2048.0, height: 436.0 / 512.0),
        CGRect(x: 5.0 / 2048.0, y: 5.0 / 512.0, width: 441.0 / 2048.0, height: 445.0 / 512.0),
        CGRect(x: 892.0 / 2048.0, y: 174.0 / 512.0, width: 450.0 / 2048.0, height: 276.0 / 512.0),
    ]
    
    /// Draws one sprite of the resolved page into `rect` within `context`.
    static func draw(page: GraphicsContext.ResolvedImage,
                     slot: Int,
                     in rect: CGRect,
                     context: GraphicsContext) {
        guard slot >= 0, slot < regions.count else { return }
        let region = regions[slot]
        var spriteContext = context
        spriteContext.clip(to: Path(rect))
        let pageWidth = rect.width / region.width
        let pageHeight = rect.height / region.height
        spriteContext.draw(page, in: CGRect(x: rect.minX - region.minX * pageWidth,
                                            y: rect.minY - region.minY * pageHeight,
                                            width: pageWidth,
                                            height: pageHeight))
    }
}

// MARK: Baked Spine timeline

/// One sampled pose of a shine sprite, in Spine space (y-up, origin at the cell centre).
struct SkinEffectFrame {
    let x: CGFloat
    let y: CGFloat
    /// Degrees, counter-clockwise in Spine's y-up space (negate for screen space).
    let rotation: CGFloat
    let scaleX: CGFloat
    let scaleY: CGFloat
    let alpha: CGFloat
}

/// The Spine 3.5 "A" animation from SkinEffects.json, pre-sampled at 30 fps (61 samples
/// over 2 s) with the file's bezier/stepped curves already applied. Each slot's bone
/// transform and attachment offset are composed into one world pose per sample, so
/// rendering is a plain lerp + one sprite draw per slot.
enum SkinEffectsAnimation {
    static let duration: Double = 2.0
    static let sampleRate: Double = 30.0
    static let trackCount = 3
    
    /// Attachment sizes in Spine units (the atlas "orig" sizes at authored resolution).
    static let attachmentSizes: [CGSize] = [
        CGSize(width: 436, height: 436),
        CGSize(width: 441, height: 445),
        CGSize(width: 450, height: 276),
    ]
    
    private static let strideLength = 6
    
    static func frame(slot: Int, at time: Double) -> SkinEffectFrame? {
        let track: [CGFloat]
        switch slot {
        case 0: track = shine1Track
        case 1: track = shine2Track
        case 2: track = shine3Track
        default: return nil
        }
        let sampleCount = track.count / strideLength
        guard sampleCount > 1 else { return nil }
        let clamped = max(0.0, min(time, duration))
        let position = clamped * sampleRate
        let i0 = min(Int(position), sampleCount - 1)
        let i1 = min(i0 + 1, sampleCount - 1)
        let f = CGFloat(position - Double(i0))
        func value(_ sample: Int, _ field: Int) -> CGFloat {
            track[sample * strideLength + field]
        }
        func lerp(_ field: Int) -> CGFloat {
            let a = value(i0, field)
            return a + (value(i1, field) - a) * f
        }
        return SkinEffectFrame(x: lerp(0), y: lerp(1), rotation: lerp(2),
                               scaleX: lerp(3), scaleY: lerp(4), alpha: lerp(5))
    }
    
    /// A_Shine1: 61 samples at 30 fps; per sample: x, y, rotationDeg, scaleX, scaleY, alpha (Spine y-up space).
    static let shine1Track: [CGFloat] = [
        0, 0, 0, 1, 1, 0, 69.372, 6.535, -14.447, 1.153, 1.138, 0,
        138.744, 13.069, -28.894, 1.305, 1.277, 0, 208.116, 19.604, -43.341, 1.458, 1.415, 0,
        277.489, 26.139, -57.788, 1.61, 1.553, 0, 346.861, 32.673, -72.236, 1.763, 1.692, 0,
        355.258, 29.413, -88.227, 1.451, 1.574, 0, 363.595, 26.143, -104.221, 1.139, 1.455, 0,
        371.932, 22.873, -120.214, 0.826, 1.337, 0, 333.203, 22.87, -102.714, 0.879, 1.337, 0.143,
        294.428, 22.87, -85.18, 0.933, 1.337, 0.286, 255.652, 22.87, -67.646, 0.986, 1.337, 0.428,
        216.877, 22.87, -50.112, 1.04, 1.337, 0.571, 178.101, 22.87, -32.578, 1.093, 1.337, 0.714,
        139.326, 22.87, -15.044, 1.147, 1.337, 0.857, 100.55, 22.87, 2.49, 1.2, 1.337, 1,
        95.655, 12.498, 11.577, 1.221, 1.373, 0.9, 90.759, 2.126, 20.664, 1.242, 1.408, 0.8,
        85.864, -8.246, 29.751, 1.263, 1.444, 0.7, 80.968, -18.618, 38.838, 1.284, 1.479, 0.6,
        76.073, -28.99, 47.925, 1.305, 1.515, 0.5, 71.177, -39.362, 57.011, 1.325, 1.55, 0.4,
        66.282, -49.734, 66.098, 1.346, 1.586, 0.3, 61.386, -60.106, 75.185, 1.367, 1.621, 0.2,
        56.491, -70.478, 84.272, 1.388, 1.657, 0.1, 51.6, -80.84, 93.35, 1.409, 1.692, 0,
        51.6, -80.84, 93.35, 1.409, 1.692, 0, 51.6, -80.84, 93.35, 1.409, 1.692, 0,
        51.6, -80.84, 93.35, 1.409, 1.692, 0, 51.6, -80.84, 93.35, 1.409, 1.692, 0,
        51.6, -80.84, 93.35, 1.409, 1.692, 0, 51.6, -80.84, 93.35, 1.409, 1.692, 0,
        51.6, -80.84, 93.35, 1.409, 1.692, 0, 51.6, -80.84, 93.35, 1.409, 1.692, 0,
        51.6, -80.84, 93.35, 1.409, 1.692, 0, 51.6, -80.84, 93.35, 1.409, 1.692, 0,
        51.6, -80.84, 93.35, 1.409, 1.692, 0, 51.6, -80.84, 93.35, 1.409, 1.692, 0,
        51.6, -80.84, 93.35, 1.409, 1.692, 0, 51.6, -80.84, 93.35, 1.409, 1.692, 0,
        51.6, -80.84, 93.35, 1.409, 1.692, 0, 51.6, -80.84, 93.35, 1.409, 1.692, 0,
        51.6, -80.84, 93.35, 1.409, 1.692, 0, 51.6, -80.84, 93.35, 1.409, 1.692, 0,
        51.6, -80.84, 93.35, 1.409, 1.692, 0, 51.6, -80.84, 93.35, 1.409, 1.692, 0,
        51.6, -80.84, 93.35, 1.409, 1.692, 0, 51.6, -80.84, 93.35, 1.409, 1.692, 0,
        51.6, -80.84, 93.35, 1.409, 1.692, 0, 51.6, -80.84, 93.35, 1.409, 1.692, 0,
        51.6, -80.84, 93.35, 1.409, 1.692, 0, 51.6, -80.84, 93.35, 1.409, 1.692, 0,
        51.6, -80.84, 93.35, 1.409, 1.692, 0, 51.6, -80.84, 93.35, 1.409, 1.692, 0,
        51.6, -80.84, 93.35, 1.409, 1.692, 0, 51.6, -80.84, 93.35, 1.409, 1.692, 0,
        51.6, -80.84, 93.35, 1.409, 1.692, 0, 51.6, -80.84, 93.35, 1.409, 1.692, 0,
        51.6, -80.84, 93.35, 1.409, 1.692, 0, 51.6, -80.84, 93.35, 1.409, 1.692, 0,
        51.6, -80.84, 93.35, 1.409, 1.692, 0,
    ]
    
    /// A_Shine2: 61 samples at 30 fps; per sample: x, y, rotationDeg, scaleX, scaleY, alpha (Spine y-up space).
    static let shine2Track: [CGFloat] = [
        0, 0, 24.06, 1.166, 1.363, 0, 1.45, -9.805, 16.407, 1.202, 1.446, 0,
        2.9, -19.61, 8.754, 1.237, 1.528, 0, 4.35, -29.415, 1.102, 1.273, 1.611, 0,
        5.801, -39.22, -6.551, 1.308, 1.693, 0, 7.251, -49.025, -14.204, 1.344, 1.776, 0,
        8.701, -58.83, -21.857, 1.379, 1.858, 0, 10.151, -68.635, -29.509, 1.415, 1.941, 0,
        11.601, -78.44, -37.162, 1.45, 2.023, 0, 13.051, -88.245, -44.815, 1.486, 2.106, 0,
        14.504, -98.03, -52.444, 1.521, 2.188, 0, 18.466, -88.029, -36.793, 1.487, 2.07, 0.143,
        22.427, -78.027, -21.142, 1.453, 1.952, 0.286, 26.389, -68.026, -5.491, 1.419, 1.834, 0.429,
        30.351, -58.024, 10.161, 1.385, 1.717, 0.571, 34.313, -48.023, 25.812, 1.351, 1.599, 0.714,
        38.274, -38.021, 41.463, 1.317, 1.481, 0.857, 42.236, -28.02, 57.114, 1.283, 1.363, 1,
        40.051, -26.122, 62.312, 1.293, 1.369, 0.972, 37.86, -24.232, 67.5, 1.303, 1.374, 0.944,
        35.669, -22.341, 72.688, 1.312, 1.38, 0.917, 33.478, -20.451, 77.875, 1.322, 1.386, 0.889,
        31.288, -18.561, 83.063, 1.332, 1.391, 0.861, 29.097, -16.671, 88.251, 1.342, 1.397, 0.833,
        26.906, -14.781, 93.438, 1.351, 1.403, 0.806, 24.715, -12.891, 98.626, 1.361, 1.409, 0.778,
        22.524, -11.001, 103.813, 1.371, 1.414, 0.75, 20.333, -9.11, 109.001, 1.381, 1.42, 0.722,
        18.142, -7.22, 114.189, 1.39, 1.426, 0.694, 15.951, -5.33, 119.376, 1.4, 1.431, 0.667,
        13.76, -3.44, 124.564, 1.41, 1.437, 0.639, 13.76, -3.44, 129.751, 1.406, 1.434, 0.611,
        13.76, -3.44, 134.939, 1.402, 1.431, 0.583, 13.76, -3.44, 140.127, 1.398, 1.429, 0.556,
        13.76, -3.44, 145.314, 1.395, 1.426, 0.528, 13.76, -3.44, 150.502, 1.391, 1.423, 0.5,
        13.76, -3.44, 155.69, 1.387, 1.42, 0.472, 13.76, -3.44, 160.877, 1.383, 1.417, 0.444,
        13.76, -3.44, 166.065, 1.379, 1.414, 0.417, 13.76, -3.44, 172.5, 1.375, 1.412, 0.389,
        13.76, -3.44, 178.937, 1.371, 1.409, 0.361, 13.76, -3.44, 185.374, 1.367, 1.406, 0.333,
        13.76, -3.44, 191.81, 1.364, 1.403, 0.306, 13.76, -3.44, 198.247, 1.36, 1.4, 0.278,
        13.76, -3.44, 204.684, 1.356, 1.397, 0.25, 13.76, -3.44, 211.12, 1.352, 1.395, 0.222,
        13.76, -3.44, 217.557, 1.348, 1.392, 0.194, 13.76, -3.44, 223.994, 1.344, 1.389, 0.167,
        13.76, -3.44, 230.43, 1.34, 1.386, 0.139, 13.76, -3.44, 236.867, 1.336, 1.383, 0.111,
        13.76, -3.44, 243.304, 1.333, 1.38, 0.083, 13.76, -3.44, 249.74, 1.329, 1.378, 0.056,
        13.76, -3.44, 256.177, 1.325, 1.375, 0.028, 13.76, -3.44, 262.614, 1.321, 1.372, 0,
        13.76, -3.44, 262.62, 1.321, 1.372, 0, 13.76, -3.44, 262.62, 1.321, 1.372, 0,
        13.76, -3.44, 262.62, 1.321, 1.372, 0, 13.76, -3.44, 262.62, 1.321, 1.372, 0,
        13.76, -3.44, 262.62, 1.321, 1.372, 0, 13.76, -3.44, 262.62, 1.321, 1.372, 0,
        13.76, -3.44, 262.62, 1.321, 1.372, 0,
    ]
    
    /// A_Shine3: 61 samples at 30 fps; per sample: x, y, rotationDeg, scaleX, scaleY, alpha (Spine y-up space).
    static let shine3Track: [CGFloat] = [
        364.049, 252.89, -76.63, 1.355, 1.355, 0, 264.623, 282.326, -59.402, 1.343, 1.343, 0.167,
        193.844, 287.136, -47.003, 1.331, 1.331, 0.333, 139.558, 281.391, -36.965, 1.32, 1.32, 0.5,
        96.656, 270.218, -28.394, 1.308, 1.308, 0.667, 62.267, 256.116, -20.845, 1.296, 1.296, 0.833,
        34.54, 240.479, -14.06, 1.284, 1.284, 1, -27.008, 213.845, -0.137, 1.28, 1.288, 1,
        -67.276, 191.653, 10.421, 1.275, 1.291, 1, -95.32, 173.517, 18.988, 1.271, 1.295, 1,
        -115.565, 158.897, 26.195, 1.267, 1.299, 1, -130.553, 147.288, 32.395, 1.263, 1.303, 1,
        -141.886, 138.244, 37.807, 1.258, 1.306, 1, -150.633, 131.386, 42.582, 1.254, 1.31, 1,
        -157.533, 126.393, 46.826, 1.25, 1.314, 1, -176.45, 76.43, 58.441, 1.246, 1.318, 1,
        -187.742, 37.574, 68.418, 1.241, 1.321, 1, -194.872, 7.966, 77.038, 1.237, 1.325, 1,
        -200.027, -14.212, 84.515, 1.233, 1.329, 1, -204.554, -30.548, 91.014, 1.229, 1.333, 1,
        -209.261, -42.366, 96.662, 1.224, 1.336, 1, -214.605, -50.741, 101.562, 1.22, 1.34, 1,
        -220.826, -56.53, 105.798, 1.216, 1.344, 1, -228.026, -60.406, 109.441, 1.212, 1.348, 1,
        -236.222, -62.893, 112.549, 1.207, 1.351, 1, -245.379, -64.391, 115.168, 1.203, 1.355, 1,
        -248.974, -62.447, 113.18, 1.218, 1.355, 0.9, -252.634, -60.321, 111.216, 1.233, 1.355, 0.8,
        -256.356, -58.011, 109.274, 1.249, 1.355, 0.7, -260.136, -55.516, 107.353, 1.264, 1.355, 0.6,
        -263.97, -52.835, 105.452, 1.279, 1.355, 0.5, -267.856, -49.967, 103.569, 1.294, 1.355, 0.4,
        -271.791, -46.908, 101.703, 1.309, 1.355, 0.3, -275.771, -43.657, 99.852, 1.325, 1.355, 0.2,
        -279.793, -40.21, 98.016, 1.34, 1.355, 0.1, -283.855, -36.563, 96.192, 1.355, 1.355, 0,
        -276.752, -29.699, 93.694, 1.355, 1.355, 0, -269.372, -22.404, 91.219, 1.355, 1.355, 0,
        -261.719, -14.706, 88.767, 1.355, 1.355, 0, -253.788, -6.628, 86.338, 1.355, 1.355, 0,
        -245.577, 1.806, 83.932, 1.355, 1.355, 0, -237.083, 10.574, 81.548, 1.355, 1.355, 0,
        -228.305, 19.653, 79.185, 1.355, 1.355, 0, -219.244, 29.02, 76.844, 1.355, 1.355, 0,
        -209.9, 38.655, 74.524, 1.355, 1.355, 0, -200.276, 48.534, 72.224, 1.355, 1.355, 0,
        -190.375, 58.639, 69.944, 1.355, 1.355, 0, -180.202, 68.948, 67.684, 1.355, 1.355, 0,
        -169.76, 79.441, 65.443, 1.355, 1.355, 0, -159.056, 90.1, 63.221, 1.355, 1.355, 0,
        -148.096, 100.905, 61.017, 1.355, 1.355, 0, -136.887, 111.838, 58.832, 1.355, 1.355, 0,
        -125.437, 122.882, 56.663, 1.355, 1.355, 0, -113.753, 134.021, 54.512, 1.355, 1.355, 0,
        -113.741, 134.032, 54.51, 1.355, 1.355, 0, -113.741, 134.032, 54.51, 1.355, 1.355, 0,
        -113.741, 134.032, 54.51, 1.355, 1.355, 0, -113.741, 134.032, 54.51, 1.355, 1.355, 0,
        -113.741, 134.032, 54.51, 1.355, 1.355, 0, -113.741, 134.032, 54.51, 1.355, 1.355, 0,
        -113.741, 134.032, 54.51, 1.355, 1.355, 0,
    ]
    
}

// MARK: Shine renderer

/// Shared shine-pass renderer used by both the live in-game overlay and the skin-selector
/// preview button. Draws the current moment of the 3-second cycle, clipped to the cell
/// contour and composited additively (Spine's additive slot blending): sprites add
/// together inside a transparency layer and the flattened layer is added onto the skin.
enum SkinEffectsRenderer {
    static func drawShinePass(into context: GraphicsContext,
                              clipPath: Path,
                              centerX: CGFloat,
                              centerY: CGFloat,
                              radius: CGFloat,
                              wallClock: TimeInterval,
                              resolvePage: (GraphicsContext) -> GraphicsContext.ResolvedImage?) {
        guard radius > 3 else { return }
        let cycle = wallClock.truncatingRemainder(dividingBy: DualSkin.effectInterval)
        guard cycle < SkinEffectsAnimation.duration else { return }
        let worldScale = (radius * 2) / DualSkin.effectReferenceDiameter
        var effectContext = context
        effectContext.blendMode = .plusLighter
        effectContext.drawLayer { layer in
            layer.clip(to: clipPath)
            layer.blendMode = .plusLighter
            guard let page = resolvePage(layer) else { return }
            for slot in 0..<SkinEffectsAnimation.trackCount {
                guard let frame = SkinEffectsAnimation.frame(slot: slot, at: cycle),
                      frame.alpha > 0.004 else { continue }
                let size = SkinEffectsAnimation.attachmentSizes[slot]
                let width = size.width * frame.scaleX * worldScale
                let height = size.height * frame.scaleY * worldScale
                guard width > 0.5, height > 0.5 else { continue }
                var slotLayer = layer
                slotLayer.opacity = Double(frame.alpha)
                // Spine is y-up with CCW-positive rotation; Canvas is y-down, so flip both.
                slotLayer.translateBy(x: centerX + frame.x * worldScale,
                                      y: centerY - frame.y * worldScale)
                slotLayer.rotate(by: .degrees(Double(-frame.rotation)))
                SkinEffectsSheet.draw(page: page, slot: slot,
                                      in: CGRect(x: -width / 2, y: -height / 2,
                                                 width: width, height: height),
                                      context: slotLayer)
            }
        }
    }
}

/// Skin-selector button preview, safe for every skin. Square skins render as the same
/// static image the selector always used (no live canvas, so 387 buttons stay cheap).
/// Dual-width skins render their BASE (left) half with the live shine pass sweeping
/// across every `DualSkin.effectInterval` seconds - the same renderer the in-game cell
/// uses, so the button doubles as a check that the "SkinEffects" page is bundled.
struct SkinSelectorPreview: View {
    let skinName: String
    
    var body: some View {
        if DualSkinCatalog.shared.isDual(skinName) {
            TimelineView(.animation) { timeline in
                // Reading the timeline date keeps SwiftUI invalidating the canvas every frame.
                let wallClock = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    let radius = min(size.width, size.height) / 2
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let circleRect = CGRect(x: center.x - radius, y: center.y - radius,
                                            width: radius * 2, height: radius * 2)
                    let circle = Path(ellipseIn: circleRect)
                    var skinContext = context
                    skinContext.clip(to: circle)
                    // Left half only: draw the double-width sheet at 2x the destination
                    // width so the base half fills the circle and the alt half falls
                    // outside the clip.
                    skinContext.draw(Image(skinName).resizable(),
                                     in: CGRect(x: circleRect.minX, y: circleRect.minY,
                                                width: circleRect.width * 2,
                                                height: circleRect.height))
                    SkinEffectsRenderer.drawShinePass(into: context, clipPath: circle,
                                                      centerX: center.x, centerY: center.y,
                                                      radius: radius, wallClock: wallClock) { layer in
                        layer.resolve(Image("SkinEffects").resizable())
                    }
                }
            }
        } else {
            Image(skinName).resizable().scaledToFill().clipShape(Circle())
        }
    }
}


// MARK: - AUTOMATIC SKIN PALETTE CACHE
//
// The public skin set does not include a dependable 387-entry border/ejected-colour manifest.
// Derive those gameplay colours from the actual bundled artwork instead. Sampling is deliberately
// tiny and happens only on a cache miss (normally once when an owner first spawns).
struct SkinGameplayPalette {
    let ejectedMassColor: Color
    let ejectedMassBorderColor: Color
    let borderColor: Color
}

final class SkinGameplayPaletteCache {
    static let shared = SkinGameplayPaletteCache()
    
    private struct Sample {
        let red: Double
        let green: Double
        let blue: Double
        let weight: Double
        let hueBin: Int
    }
    
    private struct GameplaySwatch {
        /// The skin-family colour used only for nearest-match selection.
        let anchorHex: UInt
        /// Light, normal-looking ejected-mass fill.
        let ejectedHex: UInt
        /// Gentle outline around ejected mass (not the much darker cell border).
        let ejectedBorderHex: UInt
        /// Main cell contour.
        let cellBorderHex: UInt
    }
    
    // 80px keeps a one/two-pixel perimeter ring from being blurred into centre artwork.
    private let sampleSide = 80
    private let hueBinCount = 24
    private let gameplaySwatches: [GameplaySwatch] = [
        // Dark/medium reference tones. The anchor describes the skin perimeter; the output is
        // the normal pellet swatch associated with that family.
        GameplaySwatch(anchorHex: 0xDED7AA, ejectedHex: 0x4A4518,
                       ejectedBorderHex: 0x423C13, cellBorderHex: 0x2F2B0C),
        GameplaySwatch(anchorHex: 0x4D7880, ejectedHex: 0x55818A,
                       ejectedBorderHex: 0x4D7880, cellBorderHex: 0x34585E),
        GameplaySwatch(anchorHex: 0x386C97, ejectedHex: 0x557D99,
                       ejectedBorderHex: 0x4D718B, cellBorderHex: 0x2D536D),
        GameplaySwatch(anchorHex: 0x3F4899, ejectedHex: 0x59658F,
                       ejectedBorderHex: 0x515B82, cellBorderHex: 0x30385F),
        GameplaySwatch(anchorHex: 0x8E4545, ejectedHex: 0x9A5A5A,
                       ejectedBorderHex: 0x8C5151, cellBorderHex: 0x613333),
        GameplaySwatch(anchorHex: 0x3D734A, ejectedHex: 0x568264,
                       ejectedBorderHex: 0x4E765B, cellBorderHex: 0x31583B),
        GameplaySwatch(anchorHex: 0x63466F, ejectedHex: 0x765D7F,
                       ejectedBorderHex: 0x6B5473, cellBorderHex: 0x47334F),
        GameplaySwatch(anchorHex: 0x4A4D50, ejectedHex: 0x62676A,
                       ejectedBorderHex: 0x595D60, cellBorderHex: 0x383B3D),
        
        GameplaySwatch(anchorHex: 0xC94A55, ejectedHex: 0xE7969D,
                       ejectedBorderHex: 0xD0878D, cellBorderHex: 0x8F3540),
        GameplaySwatch(anchorHex: 0xD9583D, ejectedHex: 0xEEA08E,
                       ejectedBorderHex: 0xD69080, cellBorderHex: 0xA03F2F),
        GameplaySwatch(anchorHex: 0xD56F4B, ejectedHex: 0xE9AA91,
                       ejectedBorderHex: 0xD29982, cellBorderHex: 0x99513B),
        GameplaySwatch(anchorHex: 0xD98738, ejectedHex: 0xE8B57C,
                       ejectedBorderHex: 0xD1A370, cellBorderHex: 0x966129),
        GameplaySwatch(anchorHex: 0xC9A838, ejectedHex: 0xE1CD82,
                       ejectedBorderHex: 0xCAB875, cellBorderHex: 0x89742C),
        // Natural families absent from the old neon-only list.
        GameplaySwatch(anchorHex: 0x8E763F, ejectedHex: 0xCDB294,
                       ejectedBorderHex: 0xB5A283, cellBorderHex: 0x7F6C4D),
        GameplaySwatch(anchorHex: 0x8A6246, ejectedHex: 0xC7A383,
                       ejectedBorderHex: 0xB39376, cellBorderHex: 0x684733),
        GameplaySwatch(anchorHex: 0xB4A987, ejectedHex: 0xD8CDAF,
                       ejectedBorderHex: 0xC2B89E, cellBorderHex: 0x82775D),
        GameplaySwatch(anchorHex: 0x7F8F42, ejectedHex: 0xBEC98B,
                       ejectedBorderHex: 0xABB57D, cellBorderHex: 0x5D6A2E),
        GameplaySwatch(anchorHex: 0x67A93F, ejectedHex: 0xAED38C,
                       ejectedBorderHex: 0x9DBE7E, cellBorderHex: 0x477B2D),
        GameplaySwatch(anchorHex: 0x3D9A51, ejectedHex: 0x8BC697,
                       ejectedBorderHex: 0x7DB288, cellBorderHex: 0x2A703B),
        GameplaySwatch(anchorHex: 0x368D70, ejectedHex: 0x85BC92,
                       ejectedBorderHex: 0x79AF85, cellBorderHex: 0x35765F),
        GameplaySwatch(anchorHex: 0x2EAA86, ejectedHex: 0x83CEAC,
                       ejectedBorderHex: 0x76B99B, cellBorderHex: 0x237A61),
        GameplaySwatch(anchorHex: 0x2B9293, ejectedHex: 0x7CC4C0,
                       ejectedBorderHex: 0x70B0AD, cellBorderHex: 0x226969),
        GameplaySwatch(anchorHex: 0x2A9DB9, ejectedHex: 0x86CADB,
                       ejectedBorderHex: 0x79B6C5, cellBorderHex: 0x227287),
        GameplaySwatch(anchorHex: 0x3F8BC7, ejectedHex: 0x8BBCE0,
                       ejectedBorderHex: 0x7DA9CA, cellBorderHex: 0x2F6592),
        GameplaySwatch(anchorHex: 0x4569C2, ejectedHex: 0x91A8DE,
                       ejectedBorderHex: 0x8297C8, cellBorderHex: 0x334D8D),
        GameplaySwatch(anchorHex: 0x5E55A7, ejectedHex: 0x9F99CF,
                       ejectedBorderHex: 0x8F8ABA, cellBorderHex: 0x443D7B),
        GameplaySwatch(anchorHex: 0x7D4BA7, ejectedHex: 0xB59ACD,
                       ejectedBorderHex: 0xA38BB8, cellBorderHex: 0x5B367B),
        GameplaySwatch(anchorHex: 0xA9469C, ejectedHex: 0xCE91C5,
                       ejectedBorderHex: 0xB982B1, cellBorderHex: 0x7B3272),
        GameplaySwatch(anchorHex: 0xC94F83, ejectedHex: 0xDF9AB6,
                       ejectedBorderHex: 0xC98BA4, cellBorderHex: 0x91385F),
        GameplaySwatch(anchorHex: 0x8B8177, ejectedHex: 0xC3B8AC,
                       ejectedBorderHex: 0xB0A69B, cellBorderHex: 0x625B54),
        GameplaySwatch(anchorHex: 0x7E858C, ejectedHex: 0xB8BEC4,
                       ejectedBorderHex: 0xA6ABB0, cellBorderHex: 0x596066),
        GameplaySwatch(anchorHex: 0x607D8B, ejectedHex: 0xA1B2BA,
                       ejectedBorderHex: 0x91A0A7, cellBorderHex: 0x445C68),
        GameplaySwatch(anchorHex: 0x4F5558, ejectedHex: 0x92999D,
                       ejectedBorderHex: 0x838A8D, cellBorderHex: 0x383D3F)
    ]
    private var cache: [String: SkinGameplayPalette] = [:]
    private var failedNames = Set<String>()
    
    private func drawableCGImage(_ image: UIImage) -> CGImage? {
        if let cgImage = image.cgImage { return cgImage }
        
        let size = CGSize(
            width: max(1, ceil(image.size.width)),
            height: max(1, ceil(image.size.height))
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.cgImage
    }
    
    /// Downsample into a known RGBA byte layout. Orientation does not affect palette selection:
    /// the radial edge weighting is symmetric under rotation and mirroring.
    private func rgbaSamples(from image: CGImage) -> [UInt8]? {
        let side = sampleSide
        let bytesPerRow = side * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * side)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue |
        CGImageAlphaInfo.premultipliedLast.rawValue
        
        let rendered = pixels.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: side,
                    height: side,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo
                  ) else { return false }
            
            context.clear(CGRect(x: 0, y: 0, width: side, height: side))
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return rendered ? pixels : nil
    }
    
    private func hsv(red: Double,
                     green: Double,
                     blue: Double) -> (hue: Double, saturation: Double, value: Double) {
        let maximum = max(red, max(green, blue))
        let minimum = min(red, min(green, blue))
        let chroma = maximum - minimum
        let saturation = maximum > 0 ? chroma / maximum : 0
        guard chroma > 0.000_001 else { return (0, saturation, maximum) }
        
        var hue: Double
        if maximum == red {
            hue = (green - blue) / chroma
            if hue < 0 { hue += 6 }
        } else if maximum == green {
            hue = 2 + (blue - red) / chroma
        } else {
            hue = 4 + (red - green) / chroma
        }
        return (hue / 6, saturation, maximum)
    }
    
    private func rgbComponents(hex: UInt) -> (red: Double, green: Double, blue: Double) {
        return (
            Double((hex >> 16) & 0xFF) / 255,
            Double((hex >> 8) & 0xFF) / 255,
            Double(hex & 0xFF) / 255
        )
    }
    
    private func closestGameplaySwatch(
        to target: (hue: Double, saturation: Double, value: Double)
    ) -> GameplaySwatch {
        // The table is intentionally non-empty and compile-time fixed.
        var best = gameplaySwatches[0]
        var bestScore = Double.greatestFiniteMagnitude
        for swatch in gameplaySwatches {
            let anchorRGB = rgbComponents(hex: swatch.anchorHex)
            let anchor = hsv(
                red: anchorRGB.red,
                green: anchorRGB.green,
                blue: anchorRGB.blue
            )
            
            let score: Double
            if target.saturation < 0.10 {
                // Hue is undefined for greys; prefer the closest neutral brightness.
                score = anchor.saturation * 1.8
                + abs(target.value - anchor.value) * 0.85
            } else {
                let directHueDistance = abs(target.hue - anchor.hue)
                let hueDistance = min(directHueDistance, 1 - directHueDistance)
                score = hueDistance * 4.0
                + abs(target.saturation - anchor.saturation) * 0.65
                + abs(target.value - anchor.value) * 0.85
            }
            if score < bestScore {
                bestScore = score
                best = swatch
            }
        }
        return best
    }
    
    private func makePalette(from pixels: [UInt8]) -> SkinGameplayPalette? {
        let side = sampleSide
        let neutralBin = hueBinCount
        var histogram = [Double](repeating: 0, count: hueBinCount + 1)
        var samples: [Sample] = []
        samples.reserveCapacity(side * side)
        
        // First analyze only the circular annulus that actually touches the cell contour.
        // If an unusual asset is transparent there, fall back to the broader artwork.
        for perimeterOnly in [true, false] {
            histogram = [Double](repeating: 0, count: hueBinCount + 1)
            samples.removeAll(keepingCapacity: true)
            
            for y in 0..<side {
                for x in 0..<side {
                    let offset = (y * side + x) * 4
                    let alpha = Double(pixels[offset + 3]) / 255
                    if alpha < 0.12 { continue }
                    
                    let nx = (Double(x) + 0.5) / Double(side) * 2 - 1
                    let ny = (Double(y) + 0.5) / Double(side) * 2 - 1
                    let radialDistance = sqrt(nx * nx + ny * ny)
                    if perimeterOnly &&
                        (radialDistance < 0.72 || radialDistance > 1.05) {
                        continue
                    }
                    
                    // The bitmap is premultiplied; restore straight RGB before analysis.
                    let red = min(1, Double(pixels[offset]) / 255 / alpha)
                    let green = min(1, Double(pixels[offset + 1]) / 255 / alpha)
                    let blue = min(1, Double(pixels[offset + 2]) / 255 / alpha)
                    let components = hsv(red: red, green: green, blue: blue)
                    let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
                    
                    // Black outlines and white highlights participate at low weight.
                    var tonalQuality = 0.025
                    if luminance >= 0.045 && luminance <= 0.965 {
                        let darkGate = min(1, max(0, (luminance - 0.045) / 0.14))
                        let lightGate = min(1, max(0, (0.965 - luminance) / 0.17))
                        tonalQuality = max(0.08, darkGate * lightGate)
                    }
                    
                    let weight = alpha *
                    (0.45 + 0.85 * components.saturation) *
                    tonalQuality
                    let bin: Int
                    if components.saturation < 0.10 {
                        bin = neutralBin
                    } else {
                        bin = min(hueBinCount - 1,
                                  Int(floor(components.hue * Double(hueBinCount))))
                    }
                    histogram[bin] += weight
                    samples.append(Sample(
                        red: red,
                        green: green,
                        blue: blue,
                        weight: weight,
                        hueBin: bin
                    ))
                }
            }
            if samples.count >= side || !perimeterOnly {
                break
            }
        }
        guard !samples.isEmpty else { return nil }
        
        // Smooth adjacent hue buckets so one base colour split across a 15-degree boundary
        // remains one candidate instead of losing to a smaller accent colour.
        var bestHueBin = 0
        var bestHueScore = -Double.greatestFiniteMagnitude
        for bin in 0..<hueBinCount {
            let score = histogram[bin]
            + 0.55 * (
                histogram[(bin - 1 + hueBinCount) % hueBinCount]
                + histogram[(bin + 1) % hueBinCount]
            )
            + 0.18 * (
                histogram[(bin - 2 + hueBinCount) % hueBinCount]
                + histogram[(bin + 2) % hueBinCount]
            )
            if score > bestHueScore {
                bestHueScore = score
                bestHueBin = bin
            }
        }
        let winningBin = histogram[neutralBin] > bestHueScore * 1.35
        ? neutralBin
        : bestHueBin
        
        var redSum = 0.0
        var greenSum = 0.0
        var blueSum = 0.0
        var weightSum = 0.0
        for sample in samples {
            let accepted: Bool
            if winningBin == neutralBin {
                accepted = sample.hueBin == neutralBin
            } else if sample.hueBin == neutralBin {
                accepted = false
            } else {
                let directDistance = abs(sample.hueBin - winningBin)
                let circularDistance = min(directDistance, hueBinCount - directDistance)
                accepted = circularDistance <= 1
            }
            if accepted {
                redSum += sample.red * sample.weight
                greenSum += sample.green * sample.weight
                blueSum += sample.blue * sample.weight
                weightSum += sample.weight
            }
        }
        
        // This should only be needed for a malformed/fully transparent asset, but retain a
        // deterministic average rather than changing that owner's colour at each spawn.
        if weightSum <= 0.000_001 {
            for sample in samples {
                redSum += sample.red * sample.weight
                greenSum += sample.green * sample.weight
                blueSum += sample.blue * sample.weight
                weightSum += sample.weight
            }
        }
        guard weightSum > 0.000_001 else { return nil }
        
        let base = hsv(
            red: redSum / weightSum,
            green: greenSum / weightSum,
            blue: blueSum / weightSum
        )
        let swatch = closestGameplaySwatch(to: base)
        return SkinGameplayPalette(
            ejectedMassColor: Color(hex: swatch.ejectedHex),
            ejectedMassBorderColor: Color(hex: swatch.ejectedBorderHex),
            borderColor: Color(hex: swatch.cellBorderHex)
        )
    }
    
    func palette(for skinName: String) -> SkinGameplayPalette? {
        if let cached = cache[skinName] { return cached }
        if failedNames.contains(skinName) { return nil }
        guard let source = UIImage(named: skinName),
              let fullImage = drawableCGImage(source) else {
            failedNames.insert(skinName)
            return nil
        }
        // Dual-width sheets: gameplay colours come from the BASE (left) half only, so
        // the alt artwork can differ wildly without shifting border/ejected colours.
        var image = fullImage
        if CGFloat(fullImage.width) >= CGFloat(fullImage.height) * DualSkin.aspectThreshold,
           let baseHalf = fullImage.cropping(to: CGRect(x: 0, y: 0,
                                                        width: fullImage.width / 2,
                                                        height: fullImage.height)) {
            image = baseHalf
        }
        guard let pixels = rgbaSamples(from: image),
              let palette = makePalette(from: pixels) else {
            failedNames.insert(skinName)
            return nil
        }
        cache[skinName] = palette
        return palette
    }
}

// MARK: - DISPLAY LINK DRIVER
//
// Timer.publish(every: 1/60) is not synced to the display, so frames land slightly early or
// late forever (visible micro-stutter even when the CPU keeps up) and it caps at 60fps.
// CADisplayLink is vsync-locked and unlocks 120Hz ProMotion.
// (For >60fps also add `CADisableMinimumFrameDuration = true` to Info.plist.)
final class DisplayLinkDriver: NSObject, ObservableObject {
    let frames = PassthroughSubject<CFTimeInterval, Never>()
    private var link: CADisplayLink?
    
    func start() {
        guard link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(step(link:)))
        if #available(iOS 15.0, *) {
            l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        }
        l.add(to: .main, forMode: .common)
        link = l
    }
    
    func stop() {
        link?.invalidate()
        link = nil
    }
    
    @objc private func step(link: CADisplayLink) {
        frames.send(link.timestamp)
    }
}

struct TrigCache {
    static var cache:[Int:[(cos: CGFloat, sin: CGFloat)]] = [:]
    static func get(count: Int) ->[(cos: CGFloat, sin: CGFloat)] {
        if let cached = cache[count] { return cached }
        var newCache:[(cos: CGFloat, sin: CGFloat)] = []
        newCache.reserveCapacity(count)
        for i in 0..<count {
            let angle = (Double(i) / Double(count)) * 2 * Double.pi
            newCache.append((CGFloat(cos(angle)), CGFloat(sin(angle))))
        }
        cache[count] = newCache
        return newCache
    }
}

// MARK: - BOT NAMES
// Modeled on real Agar.io lobbies: skin-trigger names players typed for the artwork,
// beggy/troll chat names, 2015-era memes, edgy gamer handles, clan tags, and the plain
// first names that fill every FFA server. Anything that read like a placeholder bot
// ("Guest", "Player", "Pro", "Noob"...) is gone.
let botNames = [
    // Skin-trigger and country names (typing these decorated your cell in the original)
    "Doge", "Sanik", "Wun Wun", "Sir", "Poker Face", "Moustache", "Ayy Lmao",
    "Moon", "Earth", "Mars", "NASA", "USA", "China", "Russia", "Turkey",
    "Poland", "Germany", "France", "Italy", "Spain", "Japan", "Brazil",
    "Mexico", "Canada", "Texas", "Scotland", "Ukraine", "Greece", "Sealand",
    "Steam", "Reddit", "Facebook", "Google", "Yahoo", "Wikipedia", "9gag",
    "Tumblr", "Piccolo", "Goku", "Vegeta", "Spy", "Obama",
    // Lobby chat / troll names
    "Feed Me", "Don't Eat", "Team?", "no team", "team pls", "feed pls",
    "dont eat me", "1v1 me", "free mass", "eat me", "not food", "im new",
    "solo", "revenge", "ez", "get gud", "2ez4u", "rekt", "gg", "RIP",
    "oops", "sorry", "my bad", "hax", "lag", "why me", "run", "hungry",
    "nom nom", "yum", "u mad?", "trickster", "baited", "split pls",
    // Memes and 2015-era pop culture
    "Harambe", "John Cena", "Shrek", "Illuminati", "MLG", "Kappa", "Sans",
    "Dat Boi", "Senpai", "Doritos", "Mtn Dew", "Nutella", "PewDiePie",
    "Chuck Norris", "Zeach", "Jumbo", "Wonder", "Sirius", "Hero",
    // Gamer handles
    "xX_Slayer_Xx", "DarkLord", "Shadow", "Ghost", "Venom", "Toxic",
    "Reaper", "Zeus", "Titan", "Kraken", "Nova", "Blaze", "Frost",
    "Viper", "Falcon", "Phantom", "Savage", "Beast", "Alpha", "Omega",
    // Clan tags
    "TYT Wolf", "TYT Arix", "NBK Storm", "X5 Ace", "[GG] Max", "AGA Neo",
    // Plain player names
    "Emre", "Mehmet", "Kaan", "Alex", "Max", "Leo", "Kevin", "Lucas",
    "Diego", "Pablo", "Igor", "Vlad", "Timmy", "Bob", "Steve", "Jeff",
    "Chad", "Kyle", "Karen",
    // Food
    "Pizza", "Taco", "Bacon", "Cookie", "Muffin", "Waffle", "Banana",
    "Potato", "Donut", "Sushi"
]

// MARK: - Data Models

// 4500 of these exist at all times. The old version carried a UUID (allocation + 16 bytes)
// and a full SwiftUI Color per pellet, and the renderer hashed those Colors into a dictionary
// every frame. Now a pellet is 17 bytes and the palette index maps straight to a path bucket.
struct Food {
    static let palette: [Color] = [
        Color(hex: 0xFF0820), Color(hex: 0x0851FF), Color(hex: 0xFF6D08),
        Color(hex: 0x01FFBD), Color(hex: 0xFFCC00), Color(hex: 0x07FF63),
        Color(hex: 0x7B08FF), Color(hex: 0xFF2001), Color(hex: 0xFF08E7)
    ]
    static let radius: CGFloat = 31 / 1.9 / 2.0
    
    var position: CGPoint
    let colorIndex: Int
    
    init(position: CGPoint) {
        self.position = position
        self.colorIndex = Int.random(in: 0..<Food.palette.count)
    }
    
    var color: Color { return Food.palette[colorIndex] }
    var radius: CGFloat { return Food.radius }
}

// MARK: - OPTIMIZED FOOD MANAGER
class FoodManager: ObservableObject {
    // NOT @Published on purpose. This dictionary is mutated dozens of times per frame
    // (every pellet eaten by every cell); publishing that fired objectWillChange over and
    // over and dragged the whole SwiftUI graph through a diff each time.
    var grid: [GridKey: [Food]] = [:]
    let gridSize: CGFloat = 300
    let worldSize: CGFloat = 11000
    
    func spawn(count: Int) {
        for _ in 0..<count {
            var bestPos: CGPoint = .zero
            var minNeighbors = Int.max
            
            for _ in 0..<5 {
                let pos = CGPoint(x: CGFloat.random(in: 0...worldSize), y: CGFloat.random(in: 0...worldSize))
                let key = GridKey(x: Int(pos.x / gridSize), y: Int(pos.y / gridSize))
                let neighborCount = grid[key]?.count ?? 0
                
                if neighborCount < minNeighbors {
                    minNeighbors = neighborCount
                    bestPos = pos
                }
            }
            if minNeighbors == Int.max { bestPos = CGPoint(x: CGFloat.random(in: 0...worldSize), y: CGFloat.random(in: 0...worldSize)) }
            add(Food(position: bestPos))
        }
    }
    
    func add(_ food: Food) {
        let key = GridKey(x: Int(food.position.x / gridSize), y: Int(food.position.y / gridSize))
        if grid[key] == nil { grid[key] = [] }
        grid[key]?.append(food)
    }
    
    /// `everyNth` thins the field uniformly when the camera is zoomed way out, instead of
    /// hard-truncating (which would leave one corner of the screen full and the rest bare).
    func forEachVisibleFood(in viewport: CGRect, limit: Int = Int.max, everyNth: Int = 1, perform action: (Food) -> Void) {
        let minX = Int(floor(viewport.minX / gridSize))
        let maxX = Int(ceil(viewport.maxX / gridSize))
        let minY = Int(floor(viewport.minY / gridSize))
        let maxY = Int(ceil(viewport.maxY / gridSize))
        
        let step = max(1, everyNth)
        var seen = 0
        var drawn = 0
        for x in gridRange(minX, maxX) {
            for y in gridRange(minY, maxY) {
                if let bucket = grid[GridKey(x: x, y: y)] {
                    for food in bucket {
                        seen += 1
                        if step > 1 && seen % step != 0 { continue }
                        action(food)
                        drawn += 1
                        if drawn >= limit { return }
                    }
                }
            }
        }
    }
    
    /// Bot foraging: find the densest pellet cluster near a point, cheaply.
    /// We only look at bucket occupancy (no per-pellet math) and return the bucket centre,
    /// which is exactly the "go where the food is" signal the old AI never had.
    func bestFoodCluster(near point: CGPoint, searchBuckets: Int = 3, avoid: CGPoint? = nil, avoidRadius: CGFloat = 0) -> CGPoint? {
        let cx = Int(point.x / gridSize)
        let cy = Int(point.y / gridSize)
        var bestScore: CGFloat = 0
        var best: CGPoint? = nil
        
        for gx in (cx - searchBuckets)...(cx + searchBuckets) {
            for gy in (cy - searchBuckets)...(cy + searchBuckets) {
                guard let bucket = grid[GridKey(x: gx, y: gy)], bucket.count > 2 else { continue }
                let centre = CGPoint(x: (CGFloat(gx) + 0.5) * gridSize, y: (CGFloat(gy) + 0.5) * gridSize)
                
                if let avoidPoint = avoid, avoidRadius > 0 {
                    let ax = centre.x - avoidPoint.x
                    let ay = centre.y - avoidPoint.y
                    if ax * ax + ay * ay < avoidRadius * avoidRadius { continue }
                }
                
                let dx = centre.x - point.x
                let dy = centre.y - point.y
                let dist = max(sqrt(dx * dx + dy * dy), gridSize)
                let score = CGFloat(bucket.count) / dist
                if score > bestScore {
                    bestScore = score
                    best = centre
                }
            }
        }
        return best
    }
    
    func checkCollisions(with cell: inout PlayerCell,
                         onEaten: ((Food, UUID) -> Void)? = nil) -> Int {
        let cellRadius = cell.cachedVisualRadius
        let radiusSq = cellRadius * cellRadius
        
        let minX = Int((cell.position.x - cellRadius) / gridSize)
        let maxX = Int((cell.position.x + cellRadius) / gridSize)
        let minY = Int((cell.position.y - cellRadius) / gridSize)
        let maxY = Int((cell.position.y + cellRadius) / gridSize)
        
        var eatenCount = 0
        
        for x in gridRange(minX, maxX) {
            for y in gridRange(minY, maxY) {
                let key = GridKey(x: x, y: y)
                if var bucket = grid[key] {
                    let startCount = bucket.count
                    
                    var i = bucket.count - 1
                    while i >= 0 {
                        let food = bucket[i]
                        let dx = cell.position.x - food.position.x
                        if dx < -cellRadius || dx > cellRadius { i -= 1; continue }
                        let dy = cell.position.y - food.position.y
                        if dy < -cellRadius || dy > cellRadius { i -= 1; continue }
                        
                        if (dx*dx + dy*dy) < radiusSq {
                            cell.targetMass += 1
                            eatenCount += 1
                            onEaten?(food, cell.id)
                            bucket.swapAt(i, bucket.count - 1)
                            bucket.removeLast()
                        }
                        i -= 1
                    }
                    if bucket.count != startCount {
                        if bucket.isEmpty { grid.removeValue(forKey: key) }
                        else { grid[key] = bucket }
                    }
                }
            }
        }
        return eatenCount
    }
    
    /// Split owners often have 8–16 large, overlapping cells. Scanning the same food-grid
    /// buckets once per piece made the cost grow with radius *and* split count. This union pass
    /// visits each bucket once for the owner, while preserving lowest-cell-index pickup priority.
    func checkCollisions(with cells: inout [PlayerCell], indices: [Int],
                         onEaten: ((Food, UUID) -> Void)? = nil) -> Int {
        guard !indices.isEmpty else { return 0 }
        
        var candidates: [(index: Int, x: CGFloat, y: CGFloat,
                          radius: CGFloat, radiusSq: CGFloat)] = []
        candidates.reserveCapacity(indices.count)
        for index in indices where index < cells.count {
            let cell = cells[index]
            candidates.append((index, cell.position.x, cell.position.y,
                               cell.cachedVisualRadius,
                               cell.cachedVisualRadius * cell.cachedVisualRadius))
        }
        
        var relevantKeys = Set<GridKey>()
        relevantKeys.reserveCapacity(candidates.count * 16)
        for candidate in candidates {
            let minX = Int((candidate.x - candidate.radius) / gridSize)
            let maxX = Int((candidate.x + candidate.radius) / gridSize)
            let minY = Int((candidate.y - candidate.radius) / gridSize)
            let maxY = Int((candidate.y + candidate.radius) / gridSize)
            for x in gridRange(minX, maxX) {
                for y in gridRange(minY, maxY) {
                    relevantKeys.insert(GridKey(x: x, y: y))
                }
            }
        }
        
        var eatenCount = 0
        for key in relevantKeys {
            guard var bucket = grid[key], !bucket.isEmpty else { continue }
            let startCount = bucket.count
            var foodIndex = bucket.count - 1
            while foodIndex >= 0 {
                let food = bucket[foodIndex]
                var eaterIndex: Int? = nil
                for candidate in candidates {
                    let dx = candidate.x - food.position.x
                    if dx < -candidate.radius || dx > candidate.radius { continue }
                    let dy = candidate.y - food.position.y
                    if dy < -candidate.radius || dy > candidate.radius { continue }
                    if dx * dx + dy * dy < candidate.radiusSq {
                        eaterIndex = candidate.index
                        break
                    }
                }
                
                if let eaterIndex = eaterIndex {
                    cells[eaterIndex].targetMass += 1
                    eatenCount += 1
                    onEaten?(food, cells[eaterIndex].id)
                    bucket.swapAt(foodIndex, bucket.count - 1)
                    bucket.removeLast()
                }
                foodIndex -= 1
            }
            
            if bucket.count != startCount {
                if bucket.isEmpty { grid.removeValue(forKey: key) }
                else { grid[key] = bucket }
            }
        }
        return eatenCount
    }
    
    func removeAll() { grid.removeAll() }
}

struct Token: Identifiable {
    let id = UUID()
    var position: CGPoint
    let radius: CGFloat = 26
}

/// One food pellet / ejected-mass pellet / token being magnet-sucked into the cell
/// that consumed it - the same glide-and-shrink treatment eaten player cells get.
/// Purely cosmetic: the mass credit already happened on the frame it was eaten.
struct ConsumedPickupAnimation {
    enum Kind {
        case food(colorIndex: Int)
        case ejected(styleID: Int)
        case token
    }
    let kind: Kind
    var position: CGPoint
    var scale: CGFloat = 1.0
    var alpha: CGFloat = 1.0     // v5.8.7: fades 1 → 0 as the pellet is pulled in
    var age: CGFloat = 0         // v5.8.7: ingestion timer (~120 ms hard cap)
    let eaterCellID: UUID
}

/// Shared magnet-consume update used by the offline and online views.
/// v5.8.7 ingestion physics: once captured, the pellet target-locks the eater's
/// centre (following it while the cell moves) and pulls in with a speed-capped
/// lerp. v5.9.1: the pellet is rendered UNDER the cells, so it visibly slides
/// beneath the eater's rim (full-size, no artificial shrink) and despawns once
/// fully occluded (~1.35 pellet radii of penetration) or at a ~300 ms cap.
/// Purely cosmetic: the mass credit already landed on the trigger frame.
func updateConsumedPickupAnimations(_ animations: inout [ConsumedPickupAnimation],
                                    playerCells: [PlayerCell],
                                    botCells: [PlayerCell],
                                    glideSpeedFactor: CGFloat,
                                    dt: CGFloat) {
    guard !animations.isEmpty else { return }
    var allPositions = [UUID: CGPoint]()
    var allRadii = [UUID: CGFloat]()
    allPositions.reserveCapacity(playerCells.count + botCells.count)
    for c in playerCells {
        allPositions[c.id] = c.position
        allRadii[c.id] = c.cachedVisualRadius
    }
    for c in botCells {
        allPositions[c.id] = c.position
        allRadii[c.id] = c.cachedVisualRadius
    }
    
    var i = animations.count - 1
    while i >= 0 {
        if let targetPos = allPositions[animations[i].eaterCellID] {
            animations[i].age += dt
            let dx = targetPos.x - animations[i].position.x
            let dy = targetPos.y - animations[i].position.y
            let dist = sqrt(dx * dx + dy * dy)
            
            let eatDuration: CGFloat = 0.12
            let remaining = max(0.001, eatDuration - animations[i].age)
            if animations[i].age >= eatDuration || dist < 4.0 {
                animations.swapAt(i, animations.count - 1)
                animations.removeLast()
            } else {
                let frac = min(1.0, dt / remaining)
                animations[i].position.x += dx * frac
                animations[i].position.y += dy * frac
                animations[i].scale = 1.0
                animations[i].alpha = 1.0
            }
        } else {
            animations.swapAt(i, animations.count - 1)
            animations.removeLast()
        }
        i -= 1
    }
}

struct Virus: Identifiable {
    let id = UUID()
    var position: CGPoint
    var mass: CGFloat = 220
    var targetMass: CGFloat = 220
    var fedMass: CGFloat = 0
    let splitThreshold: CGFloat = 220 + (7 * 14)
    var velocity: CGSize = .zero
    
    var radius: CGFloat {
        return sqrt(mass) * 5.3
    }
}

struct TeamVirusCommitment {
    let virusID: UUID
    let targetID: UUID
    var shotsRemaining: Int
    var expiresAt: TimeInterval
}

struct TeamOverlapHandoff {
    let enemyID: UUID
    var expiresAt: TimeInterval
}

private struct BotVirusCommitment {
    let virusID: UUID
    let targetID: UUID
    var shotsRemaining: Int
    var expiresAt: TimeInterval
}

/// Opportunistic teammate hunts get a short progress budget. This prevents a valid target from
/// turning into an endless chase after the geometry or risk has changed.
private struct TeamPursuitState {
    let targetID: UUID
    let startedAt: TimeInterval
    var bestDistance: CGFloat
    var lastProgressAt: TimeInterval
}

private enum TeamSplitRunPhase: UInt8 {
    case catchPlayerTrail
    case botLeadBurst
    case offerBotTrail
}

private struct TeamSplitRunState {
    var phase: TeamSplitRunPhase
    var heading: CGSize
    var turnSign: CGFloat
    var botSplitsRemaining: Int
    var botSplitOrdinal: Int
    var nextBotSplitAt: TimeInterval
    var phaseStartedAt: TimeInterval
    var expiresAt: TimeInterval
    var lastPlayerSplitAt: TimeInterval
    var playerPiecesAtStart: Int
    var botPiecesAtStart: Int
}

private enum MassEjectionAim {
    /// Every eligible cell uses the same heading, like a full-extension joystick/cursor.
    case parallel(CGSize)
    /// Every eligible cell aims at one world point, producing the player's converging spread.
    case converge(CGPoint)
    /// Resume-centre convergence with a deterministic fallback for a source exactly at centre.
    /// Without the fallback, a one-cell player produced a zero vector and the first macro burst
    /// silently emitted nothing.
    case centerConverge(CGPoint)
}

enum BotMode: UInt8 {
    case wander
    case forage
    case hunt
    case flee
    case regroup
    case feedPlayer
    case teamFormation
    case teamSupport
    case teamAttack
    case teamVirus
    case hold      // v8: deliberate stillness (centre feed)
    case trick     // v8: trick execution (recombines, baits, virus shots)
    case travel    // v8: cross-map journey (split run, wall run)
}

// MARK: - v8 BotMind (client port of Server/BotMind.swift)
// Plan-based utility brain for offline classic bots: perceive -> candidate
// plans -> persona scoring -> COMMIT -> execute. Anti-jitter: conflicts are
// resolved at the PLAN level (committed detours/lanes), never by adding
// opposing steering vectors. Anti-camp: hides/farms carry hard time budgets.
// Keep logic in lockstep with the server file when tuning either side.

fileprivate struct BMVec: Equatable {
    var x: Double
    var y: Double
    static let zero = BMVec(x: 0, y: 0)
    init(x: Double, y: Double) { self.x = x; self.y = y }
    init(_ p: CGPoint) { self.x = Double(p.x); self.y = Double(p.y) }
    var cg: CGPoint { CGPoint(x: x, y: y) }
    var cgSize: CGSize { CGSize(width: x, height: y) }
    func dist(_ o: BMVec) -> Double { ((x - o.x) * (x - o.x) + (y - o.y) * (y - o.y)).squareRoot() }
    func distSq(_ o: BMVec) -> Double { (x - o.x) * (x - o.x) + (y - o.y) * (y - o.y) }
    func normalized() -> BMVec {
        let m = (x * x + y * y).squareRoot()
        if m < 0.0001 { return .zero }
        return BMVec(x: x / m, y: y / m)
    }
}

final class BotMindBox {
    enum Archetype: UInt8, CaseIterable { case greedy, survivor, hunter, showman, balanced }

    struct Persona {
        var archetype: Archetype
        var wMass: Double
        var wSafety: Double
        var wSpeed: Double
        var wStyle: Double
        var patience: Double
        var trickLevel: Int
        var macroPresses: Int
        var ejectControl: Double
        var aimJitter: Double
    }

    enum Kind: UInt8 {
        case roam, forage, regroup, recombine,
             hunt, splitKill, bait, travel, virusShoot, escape
    }

    static let recCentre = 0, recWall = 1, recMoving = 2, recInsta = 3
    static let skSingle = 0, skDouble = 1, skMacroDouble = 2
    static let tvPlain = 0, tvSplitRun = 1, tvMacroSplitRun = 2, tvWallRun = 3, tvAlly = 4
    static let esRun = 0, esDetour = 1, esThrough = 2, esSplitAway = 3,
               esSurf = 4, esHide = 5

    struct Plan {
        var kind: Kind = .roam
        var variant: Int = 0
        var stage: Int = 0
        var stageT: Double = 0
        var bornAt: Double = 0
        var commitUntil: Double = 0
        fileprivate var target: BMVec = .zero
        var enemyOwner: UUID? = nil
        var enemyCell: UUID? = nil
        var virusID: UUID? = nil
        var side: Double = 1
        var invested: Double = 0
        var baseCellCount: Int = 0
        var score: Double = 0
    }

    struct BotState {
        var persona: Persona
        var plan = Plan()
        var loiter: Double = 0
        var loiterVirus: UUID? = nil
        var loiterDist: Double = 1e9
        fileprivate var lastDir = BMVec.zero
        var sampleT: Double = 0
        var oscillations: Int = 0
        var lastReversalAt: Double = -1e9
        fileprivate var escapeLane = BMVec.zero
        var banVirus: UUID? = nil
        var banUntil: Double = 0
        var postEscapeUntil: Double = 0
        var lastRecombineAt: Double = -1e9
        fileprivate var moveTarget = BMVec.zero // one player-style cursor for all pieces
        fileprivate var roamTarget = BMVec.zero
        var roamUntil: Double = 0
        var planLockUntil: Double = 0
        var huntOwner: UUID? = nil
        fileprivate var huntTarget = BMVec.zero
        fileprivate var lastTargetDir = BMVec.zero
        var reversals: Int = 0
        var thinkSeconds: Double = 0
        var lastThinkAt: Double = 0
        var trickDeckIndex = 0
        var lastVisibleTrickAt: Double = -1e9
        var forcedVirusExitUntil: Double = -1e9
        var recombineReceiver: UUID? = nil
        var recombineFeedDone = false
        var lastSplitAt: Double = -1e9
        var bornAt: Double = CACurrentMediaTime()
    }

    var states: [UUID: BotState] = [:]
    var stats: [String: Int] = [:]
    @inline(__always) func bump(_ key: String) { stats[key, default: 0] += 1 }
    func forget(_ oid: UUID) { states.removeValue(forKey: oid) }

    struct Threat {
        fileprivate var pos = BMVec.zero
        fileprivate var vel = BMVec.zero
        var mass = 0.0, dist = 1e9
        var canSplitKill = false
        var ownerID = UUID()
        var severity = 0.0
    }
    struct Prey {
        var id = UUID(), ownerID = UUID()
        fileprivate var pos = BMVec.zero
        fileprivate var vel = BMVec.zero
        var mass = 0.0, dist = 1e9
        var isBot = true, isFeedBot = false
        var ownerTotalNearby = 0.0
        var ownerCellsNearby = 0
    }
    struct Neutral {
        var ownerID = UUID()
        fileprivate var pos = BMVec.zero
        var radius = 0.0
        var dist = 1e9
    }
    struct Sense {
        var threats: [Threat] = []
        var worst: Threat? = nil
        var threatScore = 0.0
        fileprivate var fleeDir = BMVec.zero
        var prey: [Prey] = []
        fileprivate var neutrals: [Neutral] = []
        fileprivate var giants: [(ownerID: UUID, pos: BMVec, mass: Double, dist: Double)] = []
        fileprivate var viruses: [(id: UUID, pos: BMVec, targetMass: Double, dist: Double, radius: Double)] = []
        fileprivate var food: BMVec? = nil
        fileprivate var pile: BMVec? = nil
        fileprivate var token: BMVec? = nil
        var wallDist = 1e9
        var crowdMass = 0.0
    }

    static func makePersona(seed: UInt64, tier: Int, aggression: Double,
                            caution: Double, skill: Double) -> Persona {
        var h = seed &* 0x9E3779B97F4A7C15
        func roll() -> Double {
            h ^= h >> 33; h = h &* 0xFF51AFD7ED558CCD; h ^= h >> 33
            return Double(h % 10_000) / 10_000.0
        }
        let pick = roll()
        let arch: Archetype
        if tier >= 3 && pick < 0.22 { arch = .showman }
        else if pick < 0.25 { arch = .greedy }
        else if pick < 0.45 { arch = caution > 0.55 ? .survivor : .hunter }
        else if pick < 0.65 { arch = aggression > 0.55 ? .hunter : .survivor }
        else { arch = .balanced }
        var wMass = 1.0, wSafety = 1.0, wSpeed = 1.0, wStyle = 0.6
        switch arch {
        case .greedy:   wMass = 1.35; wSafety = 0.55; wSpeed = 0.95; wStyle = 0.40
        case .survivor: wMass = 0.70; wSafety = 1.55; wSpeed = 0.60; wStyle = 0.30
        case .hunter:   wMass = 1.10; wSafety = 0.60; wSpeed = 1.15; wStyle = 0.60
        case .showman:  wMass = 0.85; wSafety = 0.70; wSpeed = 0.80; wStyle = 1.45
        case .balanced: wMass = 1.0;  wSafety = 1.0;  wSpeed = 1.0;  wStyle = 0.70
        }
        wMass   *= (0.85 + roll() * 0.30) * (0.85 + aggression * 0.30)
        wSafety *= (0.85 + roll() * 0.30) * (0.70 + caution * 0.60)
        wSpeed  *= 0.85 + roll() * 0.30
        wStyle  *= 0.85 + roll() * 0.30
        let presses = max(1, min(6, Int(1.0 + skill * 1.4 + Double(tier) * 0.7)))
        return Persona(archetype: arch, wMass: wMass, wSafety: wSafety,
                       wSpeed: wSpeed, wStyle: wStyle,
                       patience: 1.6 + roll() * 3.4 + Double(tier) * 0.6,
                       trickLevel: tier,
                       macroPresses: presses,
                       ejectControl: min(1.0, 0.30 + Double(tier) * 0.16 + roll() * 0.1),
                       aimJitter: max(0, 1.25 - min(skill, 1.25)) * 0.08)
    }
}


/// Individual ability is intentionally distributed: most of a lobby is ordinary, a few bots
/// are weak, and only a small tail is elite. The mod-menu slider remains a global multiplier.
enum BotSkillTier: UInt8, CaseIterable {
    case rookie
    case casual
    case skilled
    case expert
    case elite
    
    var multiplier: CGFloat {
        switch self {
        case .rookie:  return 0.62
        case .casual:  return 0.82
        case .skilled: return 1.00
        case .expert:  return 1.22
        case .elite:   return 1.48
        }
    }
    
    static func randomWeighted() -> BotSkillTier {
        let roll = Int.random(in: 0..<100)
        if roll < 12 { return .rookie }
        if roll < 43 { return .casual }
        if roll < 80 { return .skilled }
        if roll < 96 { return .expert }
        return .elite
    }
}

struct PlayerCell: Identifiable {
    let id = UUID()
    let ownerID: UUID
    
    var position: CGPoint
    var mass: CGFloat
    var targetMass: CGFloat
    var lagMass: CGFloat
    /// Updated once after mass animation instead of recomputing the same square roots in
    /// movement, three spatial-index rebuilds, food, self-collision and AI hot paths.
    var cachedSolidRadius: CGFloat
    var cachedLagRadius: CGFloat
    var cachedVisualRadius: CGFloat
    var cachedMovementSpeed: CGFloat
    var cachedMovementMass: CGFloat
    var massToAbsorb: CGFloat = 0
    
    var velocity: CGSize = .zero
    var aiMovementDirection: CGSize = .zero
    
    var mergeTimer: TimeInterval = 30
    var canMerge: Bool = false
    var splitTimer: TimeInterval = 0
    /// Mass-label size lineage. false = the label tracks the radius at the normal base
    /// ratio. true = it tracks the radius at HALF the base ratio. The flag is decided
    /// once, at birth: a piece born from a cell that is at/above massFontHalfThreshold
    /// when it splits (or virus-pops) is half, everything else is normal. Splitting
    /// NEVER changes the splitting cell's own flag - a half piece that dropped below
    /// the threshold births normal-ratio children while itself staying half, and a
    /// base-ratio giant keeps its base label no matter how often it splits.
    var massFontHalved: Bool = false
    /// v5.8.1: rendered mass-label ratio, eased toward massFontHalved's target
    /// (0.5 or 1.0) so the reset never pops. Split pieces are BORN at 0.5.
    var massFontScale: CGFloat = 1.0
    var splitImmunityTimer: TimeInterval = 0
    var immuneToCellID: UUID? = nil
    var isMerging: Bool = false
    var mergeTargetID: UUID? = nil
    var eaterID: UUID? = nil
    var skinDeformation:[CGFloat] = Array(repeating: 0.0, count: 64)
    /// Lets the deformation pass skip untouched off-screen cells without walking 20-128 zeros.
    var hasActiveDeformation: Bool = false
    
    var color: Color
    var borderColor: Color
    var ejectedMassBorderColor: Color
    let name: String
    let skinName: String?
    
    var isBot: Bool = false
    var isFeedBot: Bool = false
    /// v5 skin sync: an ONLINE opponent who is a real human (kind 0). Remote
    /// humans render dual-width skin effects (shine + eat swap) exactly like
    /// the local player; offline bots keep base artwork (always false there).
    var isRemoteHuman: Bool = false
    var aiChangeDirectionTimer: TimeInterval = 0
    var aiTargetPosition: CGPoint? = nil
    
    // MARK: AI brain state (new)
    /// Bots re-plan on their own clock (~8-16x/sec, staggered across frames) instead of
    /// re-deriving a force field from every entity, every frame, for every bot.
    var aiThinkTimer: TimeInterval = 0
    /// World point the bot is currently steering toward (its plan).
    var aiSteerTarget: CGPoint? = nil
    var aiMode: BotMode = .wander
    var aiFleeing: Bool = false
    var aiSplitCooldown: TimeInterval = 0
    var aiFeedCooldown: TimeInterval = 0
    var aiSkillTier: BotSkillTier = .skilled
    /// 0...1, derived from ownerID so a bot's temperament is stable for its whole life.
    var aiAggression: CGFloat = 0.5
    var aiCaution: CGFloat = 0.5
    
    init(ownerID: UUID, position: CGPoint, mass: CGFloat, targetMass: CGFloat, velocity: CGSize = .zero, mergeTimer: TimeInterval = 30, canMerge: Bool = false, splitTimer: TimeInterval = 0, color: Color, name: String, skinName: String? = nil, isBot: Bool = false, isFeedBot: Bool = false, isRemoteHuman: Bool = false, aiSkillTier: BotSkillTier? = nil) {
        self.ownerID = ownerID
        self.position = position
        self.mass = mass
        self.targetMass = targetMass
        self.lagMass = mass
        self.cachedSolidRadius = sqrt(mass) * 6.3245
        self.cachedLagRadius = self.cachedSolidRadius
        self.cachedVisualRadius = self.cachedSolidRadius
        // IPA inputFactorPow = -0.45 on radius -> -0.225 on mass (agar.io 0x100047408)
        self.cachedMovementSpeed = 650 / pow(max(mass, 1), 0.225)
        self.cachedMovementMass = mass
        self.velocity = velocity
        self.aiMovementDirection = .zero
        self.mergeTimer = mergeTimer
        self.canMerge = canMerge
        self.splitTimer = splitTimer
        
        if let skinName = skinName,
           let palette = SkinGameplayPaletteCache.shared.palette(for: skinName) {
            // For a skinned owner, `color` is also the ejected-mass colour and the fallback
            // behind transparent skin pixels. Every split reconstructs the same cached pair.
            self.color = palette.ejectedMassColor
            self.borderColor = palette.borderColor
            self.ejectedMassBorderColor = palette.ejectedMassBorderColor
        } else {
            let fallbackBorder = color.darker(ratio: 0.9)
            self.color = color
            self.borderColor = fallbackBorder
            self.ejectedMassBorderColor = fallbackBorder
        }
        self.name = name
        self.skinName = skinName
        self.isBot = isBot
        self.isFeedBot = isFeedBot
        self.isRemoteHuman = isRemoteHuman
        self.aiSkillTier = isBot ? (aiSkillTier ?? BotSkillTier.randomWeighted()) : .skilled
        
        // Stable per-owner temperament: some bots are bullies that split on sight,
        // some are cowards that keep their distance. Prevents the "hive mind" feel where
        // every bot reacts identically to the same situation.
        let seed = UInt(bitPattern: ownerID.hashValue)
        self.aiAggression = 0.25 + CGFloat(seed % 1000) / 1000.0 * 0.75
        self.aiCaution = 0.30 + CGFloat((seed / 1000) % 1000) / 1000.0 * 0.70
        self.aiThinkTimer = Double.random(in: 0...0.14)
    }
    
    @inline(__always)
    mutating func refreshCachedRadii() {
        cachedSolidRadius = sqrt(max(mass, 0)) * 6.3245
        cachedLagRadius = sqrt(max(lagMass, 0)) * 6.3245
        cachedVisualRadius = max(cachedSolidRadius, cachedLagRadius)
        let speedRefreshThreshold = max(0.5, cachedMovementMass * 0.004)
        if abs(mass - cachedMovementMass) >= speedRefreshThreshold {
            // IPA inputFactorPow = -0.45 on radius -> -0.225 on mass (agar.io 0x100047408)
        cachedMovementSpeed = 650 / pow(max(mass, 1), 0.225)
            cachedMovementMass = mass
        }
    }
}

fileprivate struct EjectedMassStyle {
    let color: Color
    let borderColor: Color
}

// Macro feeding creates these by the hundred per second. Colors are owner-stable, so carrying
// two comparatively large SwiftUI Color values in every pellet multiplied memory bandwidth for
// simulation, collision and render sorting. A compact style ID resolves the exact same colors.
struct EjectedMass {
    static let pelletMass: CGFloat = 16
    
    let ownerID: UUID
    let sourceCellID: UUID?
    var position: CGPoint
    var direction: CGSize
    
    var currentSpeed: CGFloat
    var isStatic: Bool = false
    let creationTime: TimeInterval
    let styleID: Int
    let zIndex: Int 
    
    /// Purely visual: offset from the physical position to where the pellet is DRAWN.
    /// Bursts spawn physics-wise on their classic spread-rotated rim spot (so flight,
    /// collisions and landings are untouched), while this offset makes every pellet
    /// appear at the cell's single default eject spot and snap out onto its rotated
    /// trajectory within a few frames. Decays in update(); .zero for online/server pellets.
    var spawnOffset: CGSize = .zero
    
    var renderPosition: CGPoint {
        CGPoint(x: position.x + spawnOffset.width, y: position.y + spawnOffset.height)
    }
    
    var mass: CGFloat { EjectedMass.pelletMass }
}

private struct RenderCellReference {
    /// 0 = player, 1 = bot, 2 = eaten animation
    let source: UInt8
    let index: Int
    let mass: CGFloat
}

class EjectedMassManager: ObservableObject {
    // Also deliberately un-@Published: mutated many times per frame.
    var activeMasses:[EjectedMass] = []
    var staticGrid:[GridKey:[EjectedMass]] = [:]
    
    private var massIndexCounter: Int = 0
    /// One style per owner/life; pellets only carry the integer index.
    private var styleByOwner: [UUID: Int] = [:]
    private var renderStyles: [EjectedMassStyle] = []
    
    let gridSize: CGFloat = 500
    let friction: CGFloat = 0.96
    let stopThreshold: CGFloat = 10.0
    private let worldSize: CGFloat = 11000
    // Renderer geometry is intentionally asymmetric (1.8r rect beginning at centre-r).
    // Include half of the 8pt stroke so no pixel can cross the world plate.
    private let renderedRadius: CGFloat = 4.0 * 6.3245
    private let renderedStrokeHalfWidth: CGFloat = 4.0
    
    @inline(__always)
    private func borderSafePosition(_ point: CGPoint) -> CGPoint {
        let minCentre = renderedRadius + renderedStrokeHalfWidth
        let maxCentre = worldSize - (renderedRadius * 0.8 + renderedStrokeHalfWidth)
        return CGPoint(x: min(maxCentre, max(minCentre, point.x)),
                       y: min(maxCentre, max(minCentre, point.y)))
    }
    
    @inline(__always)
    fileprivate func renderStyle(for styleID: Int) -> EjectedMassStyle? {
        guard styleID >= 0 && styleID < renderStyles.count else { return nil }
        return renderStyles[styleID]
    }
    
    private func styleID(for ownerID: UUID, color: Color, borderColor: Color) -> Int {
        if let cached = styleByOwner[ownerID] { return cached }
        let newID = renderStyles.count
        renderStyles.append(EjectedMassStyle(color: color, borderColor: borderColor))
        styleByOwner[ownerID] = newID
        return newID
    }
    
    func add(position: CGPoint, direction: CGSize, travelDistance: CGFloat, color: Color, ownerID: UUID, sourceCellID: UUID? = nil, borderColor: Color? = nil, spawnOffset: CGSize = .zero, now: TimeInterval = CACurrentMediaTime()) {
        let initialSpeed = travelDistance * 5.0
        // color.darker() goes through UIColor(Color) which is genuinely slow; with macro
        // feeding that ran up to 150x per frame. Callers now pass a precomputed border colour.
        let border = borderColor ?? color.darker(ratio: 0.9)
        let compactStyleID = styleID(for: ownerID, color: color, borderColor: border)
        // Clamp before the first render. Previously a pellet added after the manager's update
        // could spend one whole frame beyond the wall when hold-ejecting into the border.
        let newMass = EjectedMass(ownerID: ownerID,
                                  sourceCellID: sourceCellID,
                                  position: borderSafePosition(position),
                                  direction: direction,
                                  currentSpeed: initialSpeed,
                                  creationTime: now,
                                  styleID: compactStyleID,
                                  zIndex: massIndexCounter,
                                  spawnOffset: spawnOffset)
        
        massIndexCounter += 1
        activeMasses.append(newMass)
    }
    
    func update(dt: CGFloat, worldSize: CGFloat) {
        let timeScale = dt * 60.0
        let decay = pow(friction, timeScale)
        
        // Spawn offsets ease out slowly: ~0.93 per frame stretches the "all pellets
        // leave one spot" fan-out over roughly a second, after which the pellet is
        // exactly on its classic trajectory. Zeroed below half a world unit so the
        // computed render position stops differing from the physical one.
        let offsetDecay = pow(CGFloat(0.93), timeScale)
        
        var i = activeMasses.count - 1
        while i >= 0 {
            if activeMasses[i].spawnOffset != .zero {
                activeMasses[i].spawnOffset.width *= offsetDecay
                activeMasses[i].spawnOffset.height *= offsetDecay
                if abs(activeMasses[i].spawnOffset.width) < 0.5,
                   abs(activeMasses[i].spawnOffset.height) < 0.5 {
                    activeMasses[i].spawnOffset = .zero
                }
            }
            let distanceStep = activeMasses[i].currentSpeed * dt
            activeMasses[i].position.x += activeMasses[i].direction.width * distanceStep
            activeMasses[i].position.y += activeMasses[i].direction.height * distanceStep
            
            let unclamped = activeMasses[i].position
            activeMasses[i].position = borderSafePosition(unclamped)
            let hitVerticalWall = activeMasses[i].position.x != unclamped.x
            let hitHorizontalWall = activeMasses[i].position.y != unclamped.y
            
            activeMasses[i].currentSpeed *= decay
            if hitVerticalWall || hitHorizontalWall {
                // A wall removes only the velocity normal to it. Preserving the tangential
                // component lets a spread of W pellets fan/slide along an edge instead of all
                // collapsing into one stationary stack. A direct corner hit still stops.
                var tangent = activeMasses[i].direction
                if hitVerticalWall { tangent.width = 0 }
                if hitHorizontalWall { tangent.height = 0 }
                let retainedFraction = hypot(tangent.width, tangent.height)
                if retainedFraction > 0.001 {
                    activeMasses[i].direction = tangent.normalized()
                    activeMasses[i].currentSpeed *= min(1, retainedFraction)
                } else {
                    activeMasses[i].currentSpeed = 0
                }
            }
            
            if activeMasses[i].currentSpeed <= stopThreshold {
                activeMasses[i].isStatic = true
                // A corner/wall hit can stop a pellet while its spawn offset is still
                // live; the grid copy is frozen, so drop the offset rather than let the
                // pellet rest drawn away from its physical (collidable) spot.
                activeMasses[i].spawnOffset = .zero
                addToGrid(activeMasses[i])
                activeMasses.swapAt(i, activeMasses.count - 1)
                activeMasses.removeLast()
            }
            i -= 1
        }
    }
    
    private func gridKey(for point: CGPoint) -> GridKey {
        return GridKey(x: Int(point.x / gridSize), y: Int(point.y / gridSize))
    }
    
    private func addToGrid(_ mass: EjectedMass) {
        let key = gridKey(for: mass.position)
        if staticGrid[key] == nil { staticGrid[key] = [] }
        staticGrid[key]?.append(mass)
    }
    
    func forEachVisibleMass(in viewport: CGRect, limit: Int = Int.max, perform action: (EjectedMass) -> Void) {
        let minX = Int(floor(viewport.minX / gridSize))
        let maxX = Int(ceil(viewport.maxX / gridSize))
        let minY = Int(floor(viewport.minY / gridSize))
        let maxY = Int(ceil(viewport.maxY / gridSize))
        
        var count = 0
        for x in gridRange(minX, maxX) {
            for y in gridRange(minY, maxY) {
                let key = GridKey(x: x, y: y)
                if let bucket = staticGrid[key] {
                    for mass in bucket {
                        action(mass)
                        count += 1
                        if count >= limit { return }
                    }
                }
            }
        }
        // Active blobs are not bucketed yet, but still cull them before the renderer's
        // z-sort. A distant macro burst should not make the local camera sort every pellet.
        for mass in activeMasses where viewport.contains(mass.position) {
            action(mass)
            count += 1
            if count >= limit { return }
        }
    }
    
    /// Buckets that hold settled mass near a point - used by the collision pass so it no
    /// longer has to walk every bucket in the world every frame.
    func forEachStaticBucketKey(near point: CGPoint, radius: CGFloat, perform action: (GridKey) -> Void) {
        let minX = Int((point.x - radius) / gridSize)
        let maxX = Int((point.x + radius) / gridSize)
        let minY = Int((point.y - radius) / gridSize)
        let maxY = Int((point.y + radius) / gridSize)
        for x in gridRange(minX, maxX) {
            for y in gridRange(minY, maxY) {
                action(GridKey(x: x, y: y))
            }
        }
    }
    
    /// Virus replacement is rare, so a direct active-mass check plus nearby settled buckets is
    /// much cheaper than maintaining another per-frame index. It prevents a newly randomized
    /// virus from materializing inside an existing macro pile and swallowing it in one tick.
    func containsMass(near point: CGPoint, radius: CGFloat) -> Bool {
        let radiusSq = radius * radius
        
        for mass in activeMasses {
            let dx = mass.position.x - point.x
            if dx < -radius || dx > radius { continue }
            let dy = mass.position.y - point.y
            if dy < -radius || dy > radius { continue }
            if dx * dx + dy * dy < radiusSq { return true }
        }
        
        let minX = Int((point.x - radius) / gridSize)
        let maxX = Int((point.x + radius) / gridSize)
        let minY = Int((point.y - radius) / gridSize)
        let maxY = Int((point.y + radius) / gridSize)
        for x in gridRange(minX, maxX) {
            for y in gridRange(minY, maxY) {
                guard let bucket = staticGrid[GridKey(x: x, y: y)] else { continue }
                for mass in bucket {
                    let dx = mass.position.x - point.x
                    if dx < -radius || dx > radius { continue }
                    let dy = mass.position.y - point.y
                    if dy < -radius || dy > radius { continue }
                    if dx * dx + dy * dy < radiusSq { return true }
                }
            }
        }
        return false
    }
    
    /// Bots use this to find a pile of ejected mass worth eating.
    func nearestStaticMassPosition(near point: CGPoint,
                                   radius: CGFloat,
                                   ownerID: UUID? = nil) -> CGPoint? {
        var best: CGPoint? = nil
        var bestDistSq: CGFloat = radius * radius
        let minX = Int((point.x - radius) / gridSize)
        let maxX = Int((point.x + radius) / gridSize)
        let minY = Int((point.y - radius) / gridSize)
        let maxY = Int((point.y + radius) / gridSize)
        
        for x in gridRange(minX, maxX) {
            for y in gridRange(minY, maxY) {
                guard let bucket = staticGrid[GridKey(x: x, y: y)], !bucket.isEmpty else { continue }
                // Generic forage samples a dense pile. A teammate return request filters for
                // the player's pellets so it can catch and send back the intended donation.
                let probeMass: EjectedMass
                if let requiredOwner = ownerID {
                    guard let owned = bucket.first(where: { $0.ownerID == requiredOwner }) else {
                        continue
                    }
                    probeMass = owned
                } else {
                    probeMass = bucket[bucket.count / 2]
                }
                let probe = probeMass.position
                let dx = probe.x - point.x
                let dy = probe.y - point.y
                let distSq = dx * dx + dy * dy
                // Weight by pile size so a fat pile beats a single closer pellet.
                let weighted = distSq / CGFloat(max(1, min(bucket.count, 40)))
                if weighted < bestDistSq {
                    bestDistSq = weighted
                    best = probe
                }
            }
        }
        return best
    }
    
    func getLimitedVisibleMassesArray(in viewport: CGRect, limit: Int = 10) -> [EjectedMass] {
        var visible:[EjectedMass] = []
        visible.reserveCapacity(limit)
        
        let minX = Int(floor(viewport.minX / gridSize))
        let maxX = Int(ceil(viewport.maxX / gridSize))
        let minY = Int(floor(viewport.minY / gridSize))
        let maxY = Int(ceil(viewport.maxY / gridSize))
        
        outerLoop: for x in gridRange(minX, maxX) {
            for y in gridRange(minY, maxY) {
                let key = GridKey(x: x, y: y)
                if let bucket = staticGrid[key] {
                    for mass in bucket {
                        visible.append(mass)
                        if visible.count >= limit { break outerLoop }
                    }
                }
            }
        }
        return visible
    }
    
    func clearAll() {
        activeMasses.removeAll()
        staticGrid.removeAll()
        styleByOwner.removeAll(keepingCapacity: true)
        renderStyles.removeAll(keepingCapacity: true)
        massIndexCounter = 0
    }
}

// MARK: - Rendering World
// MARK: - LEAGUE LEVEL BADGES
//
// Agar.io-style league badges. A level (1-150) maps to one of ten league images bundled in
// the asset catalog ("fly-league" ... "kraken-league", 320x300 each: star + creature). The
// level number is drawn on the star's centre with the same outlined digit sprites the mass
// counter uses, so badges never re-layout text. 15% of bots roll a level at spawn; the
// player opts in from the main menu.
enum LeagueBadge {
    /// Bundled league images are 320x300.
    static let imageAspect: CGFloat = 320.0 / 300.0
    
    @inline(__always)
    static func clamp(_ level: Int) -> Int { min(150, max(1, level)) }
    
    static func assetName(forLevel level: Int) -> String {
        switch clamp(level) {
        case 1...14: return "fly-league"
        case 15...24: return "wasp-league"
        case 25...34: return "bat-league"
        case 35...44: return "fox-league"
        case 45...54: return "hunter-league"
        case 55...64: return "bear-league"
        case 65...74: return "panther-league"
        case 75...84: return "crocodile-league"
        case 85...99: return "mammoth-league"
        default: return "kraken-league"
        }
    }
    
    /// Every league star is a different colour, so the level text's stroke is sampled from
    /// the league's own image: the average of the darkest ~15% of its fully opaque pixels
    /// lands on the star's rim/engraving shade (the "dark part of the star"). Sampled once
    /// per asset, then cached. Main-thread only (menu body + Canvas rendering).
    private static var strokeCache: [String: UIColor] = [:]
    
    static func strokeColor(forAsset asset: String) -> UIColor {
        if let cached = strokeCache[asset] { return cached }
        let color = sampleDarkColor(UIImage(named: asset)) ?? TextSpriteCache.badgeStrokeColor
        strokeCache[asset] = color
        return color
    }
    
    static func strokeColor(forLevel level: Int) -> UIColor {
        return strokeColor(forAsset: assetName(forLevel: level))
    }
    
    private static func sampleDarkColor(_ image: UIImage?) -> UIColor? {
        guard let cg = image?.cgImage else { return nil }
        let w = 48, h = 45
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let base = ctx.data else { return nil }
        let buf = base.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var samples: [(lum: CGFloat, r: CGFloat, g: CGFloat, b: CGFloat)] = []
        samples.reserveCapacity(w * h)
        for i in stride(from: 0, to: w * h * 4, by: 4) {
            let a = CGFloat(buf[i + 3])
            guard a > 240 else { continue }              // solid star pixels only, no fringe
            let r = CGFloat(buf[i]) / a                  // un-premultiply -> 0...1
            let g = CGFloat(buf[i + 1]) / a
            let b = CGFloat(buf[i + 2]) / a
            samples.append((0.299 * r + 0.587 * g + 0.114 * b, r, g, b))
        }
        guard samples.count >= 40 else { return nil }
        samples.sort { $0.lum < $1.lum }
        let take = max(12, samples.count / 7)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        for s in samples.prefix(take) {
            r += s.r
            g += s.g
            b += s.b
        }
        let n = CGFloat(take)
        return UIColor(red: r / n, green: g / n, blue: b / n, alpha: 1)
    }
}

struct GameWorldView: View {
    let worldSize: CGFloat = 11000
    let cellSize: CGFloat = 31
    let gridLineWidth: CGFloat = 1
    let screenSize: CGSize
    
    @Binding var smoothedPlayerPosition: CGPoint
    @Binding var zoomLevel: CGFloat
    @Binding var playerCells: [PlayerCell]
    @Binding var botCells: [PlayerCell]
    @Binding var animatingEatenCells: [PlayerCell]
    let tokens: [Token]
    
    @ObservedObject var foodManager: FoodManager
    @ObservedObject var massManager: EjectedMassManager
    
    let viruses: [Virus]
    var showGrid: Bool
    var showSkins: Bool
    var teammateOwnerID: UUID?
    /// Online parties: every remote owner in the local player's party (the offline
    /// pact keeps using the single teammateOwnerID above). Both feed the same
    /// teammate visuals: rings, pfp + name layout, and the off-screen party arrow.
    var teammateOwnerIDs: Set<UUID> = []
    /// Online: true while the local player has a party code set, even before any
    /// party member has joined the server. The player's own cells wear the party
    /// border from the moment they are in a party - 0 friends included.
    var localPlayerInParty: Bool = false
    /// Wall-clock time the dual skin's eat-triggered swap fired, nil while not showing.
    /// The renderer derives the alt-half overlay opacity from this every frame.
    var dualSkinSwapShowingSince: TimeInterval? = nil
    /// v5 skin sync: per-owner swap starts for REMOTE humans (online play).
    var dualSkinSwapShowingSinceByOwner: [UUID: TimeInterval] = [:]
    /// ownerID -> league level (1-150) for every owner that shows a badge: the ~15% of bots
    /// that rolled one at spawn, plus the player while the menu toggle is on.
    var ownerLevels: [UUID: Int] = [:]
    /// Pickups (food/ejected mass/tokens) mid magnet-suck into their eater.
    var consumeAnimations: [ConsumedPickupAnimation] = []
    /// Active player emote drawn inside every player split cell (clipped to cell boundary).
    var activeEmoteAsset: String? = nil
    var activeEmoteStartedAt: TimeInterval = 0
    var activeEmoteExpiresAt: TimeInterval = 0
    
    /// Dark mode: inverts the grid colours (background plate + grid lines are the
    /// exact RGB inverse of the light values). Stored so both the offline and the
    /// online match screen pick it up without any plumbing.
    @AppStorage("macro.darkModeGrid") private var darkModeGrid: Bool = false
    
    /// Show Mass (settings): hides the numeric mass counter on cells when off.
    /// Stored like darkModeGrid so offline and online pick it up without plumbing.
    @AppStorage("macro.showMassText") private var showMassText: Bool = true
    @AppStorage("macro.showMinimap") private var showMinimap: Bool = false
    
    /// Resolved-image cache, reset at the top of every draw. State-backed reference storage
    /// keeps SwiftUI from allocating a fresh cache every time the parent body is evaluated.
    @State private var resolver = FrameImageResolver()
    
    // NOTE: no level-of-detail / budget constants here on purpose. Every draw in this file
    // reproduces the original output exactly; the speedups come from *how* things are drawn
    // (cached resolves, cached label sprites, batched paths, culling before sorting), never
    // from drawing less.
    
    var body: some View {
        // opaque: true - we paint every pixel ourselves, so the compositor can skip blending.
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            resolver.reset()
            
            let zoom = zoomLevel
            let cameraOffsetX = -smoothedPlayerPosition.x * zoom + size.width / 2
            let cameraOffsetY = -smoothedPlayerPosition.y * zoom + size.height / 2
            
            let visibleRect = CGRect(
                origin: CGPoint(x: (0 - cameraOffsetX) / zoom, y: (0 - cameraOffsetY) / zoom),
                size: CGSize(width: size.width / zoom, height: size.height / zoom)
            ).insetBy(dx: -100, dy: -100)
            
            let screenBounds = CGRect(origin: .zero, size: size)
            
            // 1. Background. Opaque canvas, so paint every pixel: the original relied on
            // .background(0xFFFFFF) for anything outside the world plate, and both are the
            // same colour, so one fill over the whole canvas is pixel-identical.
            // Dark mode swaps in the exact RGB inverse of the light palette.
            context.fill(Path(screenBounds), with: .color(Color(hex: darkModeGrid ? 0x000000 : 0xFFFFFF)))
            
            // 2. Grid - IPA OptimizedArenaBackground::draw (0x10030e108):
            // v = clamp((50 * zoom)^2 / 5000 + 0.10, 0.10, 0.85)
            // Light mode gray = 1 - v; Dark mode gray = v; lineWidth = darkMode ? 2 : 1.
            if showGrid {
                let gridIntensity = min(0.85, max(0.10, (50.0 * 50.0 * zoom * zoom) / 5000.0 + 0.10))
                let gridGray = darkModeGrid ? gridIntensity : (1.0 - gridIntensity)
                let gridColor = Color(red: gridGray, green: gridGray, blue: gridGray)
                let lineWidth: CGFloat = darkModeGrid ? 2.0 : 1.0
                
                let startX = floor(visibleRect.minX / cellSize) * cellSize
                let endX = ceil(visibleRect.maxX / cellSize) * cellSize
                let gridPathX = Path { p in
                    for x in stride(from: startX, through: endX, by: cellSize) {
                        let screenX = x * zoom + cameraOffsetX
                        p.move(to: CGPoint(x: screenX, y: 0))
                        p.addLine(to: CGPoint(x: screenX, y: size.height))
                    }
                }
                context.stroke(gridPathX, with: .color(gridColor), lineWidth: lineWidth)
                
                let startY = floor(visibleRect.minY / cellSize) * cellSize
                let endY = ceil(visibleRect.maxY / cellSize) * cellSize
                let gridPathY = Path { p in
                    for y in stride(from: startY, through: endY, by: cellSize) {
                        let screenY = y * zoom + cameraOffsetY
                        p.move(to: CGPoint(x: 0, y: screenY))
                        p.addLine(to: CGPoint(x: size.width, y: screenY))
                    }
                }
                context.stroke(gridPathY, with: .color(gridColor), lineWidth: lineWidth)
            }

            // 2b. Arena Boundary (ArenaBoundaryShaderEffect): dim out-of-bounds space outside
            // 0...worldSize with smooth shading + subtle inner guide line.
            let boundaryRect = CGRect(x: cameraOffsetX,
                                      y: cameraOffsetY,
                                      width: worldSize * zoom,
                                      height: worldSize * zoom)
            let outOfBoundsPath = Path { p in
                p.addRect(screenBounds)
                p.addRect(boundaryRect)
            }
            context.fill(outOfBoundsPath,
                         with: .color(Color.black.opacity(darkModeGrid ? 0.38 : 0.10)),
                         style: FillStyle(eoFill: true))
            if boundaryRect.intersects(screenBounds) {
                let guideColor = Color(hex: darkModeGrid ? 0x33373D : 0xD2D8DC).opacity(0.65)
                context.stroke(Path(boundaryRect), with: .color(guideColor), lineWidth: max(1.0, 1.5 * zoom))
            }
            
            // 3. Food - same pellets, same 0.5px cutoff as before. The win is that the
            // pellets are grouped by palette index instead of hashing a Color per pellet
            // into a dictionary every frame.
            let foodScreenRadius = Food.radius * zoom
            if foodScreenRadius >= 0.5 {
                var foodPaths = [Path](repeating: Path(), count: Food.palette.count)
                var drewAny = false
                foodManager.forEachVisibleFood(in: visibleRect) { food in
                    let foodScreenX = food.position.x * zoom + cameraOffsetX
                    let foodScreenY = food.position.y * zoom + cameraOffsetY
                    let rect = CGRect(x: foodScreenX - foodScreenRadius,
                                      y: foodScreenY - foodScreenRadius,
                                      width: foodScreenRadius * 2,
                                      height: foodScreenRadius * 2)
                    foodPaths[food.colorIndex].addEllipse(in: rect)
                    drewAny = true
                }
                if drewAny {
                    for i in 0..<foodPaths.count {
                        if !foodPaths[i].isEmpty {
                            context.fill(foodPaths[i], with: .color(Food.palette[i]))
                        }
                    }
                }
            }
            
            // 3.5 Tokens
            if !tokens.isEmpty,
               let tImage = resolver.resolve("img:token", context: context, make: { Image("token").resizable() }) {
                for token in tokens {
                    let tScreenX = token.position.x * zoom + cameraOffsetX
                    let tScreenY = token.position.y * zoom + cameraOffsetY
                    let tRadius = token.radius * zoom
                    let tokenRect = CGRect(x: tScreenX - tRadius, y: tScreenY - tRadius, width: tRadius * 1.8, height: tRadius * 2)
                    if screenBounds.intersects(tokenRect) {
                        context.draw(tImage, in: tokenRect)
                    }
                }
            }
            
            // 4. Ejected mass - every visible pellet, sorted by zIndex, filled and stroked
            // exactly as before. Cheaper only because the manager hands back just the
            // buckets that intersect the viewport.
            var visibleMasses: [EjectedMass] = []
            visibleMasses.reserveCapacity(128)
            massManager.forEachVisibleMass(in: visibleRect) { mass in
                visibleMasses.append(mass)
            }
            visibleMasses.sort { $0.zIndex < $1.zIndex }
            
            let massRadius = 4.0 * 6.3245 * zoom   // sqrt(16) * 6.3245, mass is always 16
            let massStroke = 8 * zoom
            for mass in visibleMasses {
                guard let style = massManager.renderStyle(for: mass.styleID) else { continue }
                // renderPosition = physical position + decaying spawn offset, so fresh
                // burst pellets are drawn emerging from the cell's single eject spot.
                let massScreenX = mass.renderPosition.x * zoom + cameraOffsetX
                let massScreenY = mass.renderPosition.y * zoom + cameraOffsetY
                
                let drawRect = CGRect(x: massScreenX - massRadius,
                                      y: massScreenY - massRadius,
                                      width: massRadius * 1.8,
                                      height: massRadius * 1.8)
                
                if screenBounds.intersects(drawRect) {
                    let massPath = Path(ellipseIn: drawRect)
                    context.fill(massPath, with: .color(style.color))
                    context.stroke(massPath, with: .color(style.borderColor), lineWidth: massStroke)
                }
            }
            
            // 4.5 Magnet-consume animations (food, tokens AND ejected pellets):
            // ALL drawn under the cells so they slip beneath their eater —
            // v5.9.1: the eater's own rim occludes a captured pellet naturally,
            // exactly like the real game. The magnet pull is speed-capped, so
            // the slide under the rim stays visible (the old v5.8.7 "vanish on
            // touch" came from instant despawn, not from under-drawing).
            for animation in consumeAnimations {
                let animScreenX = animation.position.x * zoom + cameraOffsetX
                let animScreenY = animation.position.y * zoom + cameraOffsetY
                switch animation.kind {
                case .food(let colorIndex):
                    let r = Food.radius * animation.scale * zoom
                    if r < 0.5 { continue }
                    let rect = CGRect(x: animScreenX - r, y: animScreenY - r, width: r * 2, height: r * 2)
                    if screenBounds.intersects(rect), colorIndex >= 0, colorIndex < Food.palette.count {
                        context.fill(Path(ellipseIn: rect),
                                     with: .color(Food.palette[colorIndex].opacity(animation.alpha)))
                    }
                case .ejected(let styleID):
                    guard let style = massManager.renderStyle(for: styleID) else { continue }
                    let r = 4.0 * 6.3245 * animation.scale * zoom
                    let rect = CGRect(x: animScreenX - r, y: animScreenY - r, width: r * 1.8, height: r * 1.8)
                    if screenBounds.intersects(rect) {
                        let path = Path(ellipseIn: rect)
                        context.fill(path, with: .color(style.color.opacity(animation.alpha)))
                        context.stroke(path, with: .color(style.borderColor.opacity(animation.alpha)),
                                       lineWidth: 8 * animation.scale * zoom)
                    }
                case .token:
                    let r = 26 * animation.scale * zoom
                    let rect = CGRect(x: animScreenX - r, y: animScreenY - r, width: r * 1.8, height: r * 2)
                    if screenBounds.intersects(rect),
                       let tImage = resolver.resolve("img:token", context: context, make: { Image("token").resizable() }) {
                        let prevOpacity = context.opacity
                        context.opacity = animation.alpha
                        context.draw(tImage, in: rect)
                        context.opacity = prevOpacity
                    }
                }
            }
            
            // 5. Cells & viruses - cull first, then sort lightweight references. Sorting full
            // PlayerCell values moved UUIDs, colours, AI state and deformation-array handles
            // repeatedly; references keep the exact draw order with a tiny sort payload.
            var cellRefs: [RenderCellReference] = []
            cellRefs.reserveCapacity(64)
            
            let cullPad: CGFloat = 4
            func collect(_ cells: [PlayerCell], source: UInt8) {
                for (index, cell) in cells.enumerated() {
                    if cell.mass < 2 { continue }
                    let r = cell.cachedVisualRadius * zoom
                    let sx = cell.position.x * zoom + cameraOffsetX
                    let sy = cell.position.y * zoom + cameraOffsetY
                    if sx + r < -cullPad || sx - r > size.width + cullPad { continue }
                    if sy + r < -cullPad || sy - r > size.height + cullPad { continue }
                    cellRefs.append(RenderCellReference(source: source, index: index, mass: cell.mass))
                }
            }
            collect(playerCells, source: 0)
            collect(botCells, source: 1)
            collect(animatingEatenCells, source: 2)
            
            cellRefs.sort { $0.mass < $1.mass }
            
            func draw(_ reference: RenderCellReference) {
                let cell: PlayerCell
                switch reference.source {
                case 0:
                    guard reference.index < playerCells.count else { return }
                    cell = playerCells[reference.index]
                case 1:
                    guard reference.index < botCells.count else { return }
                    cell = botCells[reference.index]
                default:
                    guard reference.index < animatingEatenCells.count else { return }
                    cell = animatingEatenCells[reference.index]
                }
                drawPlayerCell(context: context,
                               cell: cell,
                               cameraOffsetX: cameraOffsetX,
                               cameraOffsetY: cameraOffsetY,
                               screenSize: size,
                               showSkins: showSkins)
            }
            
            // Viruses interleave with the mass-sorted cells: a cell draws ABOVE a
            // virus once it reaches that virus's "on top" threshold - 100 mass at
            // the base 220 virus mass, scaling up as the virus is fed bigger.
            // Sorting the viruses by mass lets one merged sweep place every cell
            // correctly above/below each individual virus.
            if viruses.isEmpty {
                for reference in cellRefs { draw(reference) }
            } else {
                let virusImage = resolver.resolve("img:virus", context: context, make: { Image("virus").resizable() })
                var virusOrder = Array(viruses.indices)
                virusOrder.sort { viruses[$0].mass < viruses[$1].mass }
                
                var cellCursor = 0
                for virusIdx in virusOrder {
                    let virus = viruses[virusIdx]
                    let onTopThreshold = virus.mass * (100.0 / 220.0)
                    while cellCursor < cellRefs.count, cellRefs[cellCursor].mass < onTopThreshold {
                        draw(cellRefs[cellCursor])
                        cellCursor += 1
                    }
                    
                    let screenRadius = virus.radius * zoom
                    let vScreenX = virus.position.x * zoom + cameraOffsetX
                    let vScreenY = virus.position.y * zoom + cameraOffsetY
                    let virusRect = CGRect(x: vScreenX - screenRadius, y: vScreenY - screenRadius, width: screenRadius * 2, height: screenRadius * 2)
                    if !screenBounds.intersects(virusRect) { continue }
                    
                    if let vImage = virusImage {
                        context.draw(vImage, in: virusRect)
                    } else {
                        context.fill(Path(ellipseIn: virusRect), with: .color(.green))
                    }
                }
                while cellCursor < cellRefs.count {
                    draw(cellRefs[cellCursor])
                    cellCursor += 1
                }
            }
            
            // 9. Party arrow (screen space, on top of the world): exactly ONE
            // arrow, for the CLOSEST teammate whose every cell is off screen.
            // A teammate standing right next to you never suppresses it, and it
            // re-targets the moment you reach its teammate or they die - always
            // the nearest missing friend.
            var offscreenIDs = teammateOwnerIDs
            if let teammateOwnerID { offscreenIDs.insert(teammateOwnerID) }
            var arrowTarget: UUID? = nil
            var arrowDistSq = CGFloat.greatestFiniteMagnitude
            for teammateID in offscreenIDs {
                if let d = offscreenTeammateDistSq(size: size, zoom: zoom,
                                                   cameraOffsetX: cameraOffsetX,
                                                   cameraOffsetY: cameraOffsetY,
                                                   teammateID: teammateID),
                   d < arrowDistSq {
                    arrowDistSq = d
                    arrowTarget = teammateID
                }
            }
            if let arrowTarget {
                drawPartyArrow(context: context, size: size, zoom: zoom,
                               cameraOffsetX: cameraOffsetX, cameraOffsetY: cameraOffsetY,
                               teammateID: arrowTarget)
            }
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .background(Color(hex: darkModeGrid ? 0x000000 : 0xFFFFFF))
        .clipped()
    }
    
    // MARK: - DRAW FUNCTION
    func drawPlayerCell(context: GraphicsContext, cell: PlayerCell, cameraOffsetX: CGFloat, cameraOffsetY: CGFloat, screenSize: CGSize, showSkins: Bool) {
        if cell.mass < 2 { return }
        
        let zoom = zoomLevel
        let screenX = cell.position.x * zoom + cameraOffsetX
        let screenY = cell.position.y * zoom + cameraOffsetY
        let cellRadius = cell.cachedVisualRadius * zoom
        let bounds = CGRect(x: screenX - cellRadius, y: screenY - cellRadius, width: cellRadius * 2, height: cellRadius * 2)
        if !CGRect(origin: .zero, size: screenSize).intersects(bounds) { return }
        
        let lagFillColor: Color = cell.color
        let drawSkin = showSkins
        let borderWidth = 8 * zoom
        // The same contour is built two or three times. Determine ellipse-vs-organic once
        // instead of rescanning the deformation buffer for every path.
        var hasRenderableDeformation = false
        if cell.hasActiveDeformation {
            for value in cell.skinDeformation where value > 0.1 || value < -0.1 {
                hasRenderableDeformation = true
                break
            }
        }
        
        if cell.lagMass > cell.mass + 1 {
            let outerRadius = cell.cachedLagRadius * zoom
            let innerRadius = cell.cachedSolidRadius * zoom
            let coreRadius = outerRadius * 0.85
            let outerPath = createOrganicPath(center: CGPoint(x: screenX, y: screenY), baseRadius: outerRadius, deformations: cell.skinDeformation, hasDeformation: hasRenderableDeformation, zoom: zoom, minRadius: coreRadius)
            let innerPath = createOrganicPath(center: CGPoint(x: screenX, y: screenY), baseRadius: innerRadius, deformations: cell.skinDeformation, hasDeformation: hasRenderableDeformation, zoom: zoom, minRadius: coreRadius * (innerRadius / outerRadius))
            
            // Keep the flat colour only as a transparent-asset/failure fallback. For a valid
            // skin, the nine-slice clamp below covers the entire lagging outer mask with the
            // skin's own edge pixels instead of exposing this colour.
            context.fill(outerPath, with: .color(lagFillColor))
            if drawSkin, let skinName = displaySkinName(for: cell) {
                drawSkinEdgeClamp(
                    context: context,
                    skinName: skinName,
                    outerPath: outerPath,
                    center: CGPoint(x: screenX, y: screenY),
                    innerRadius: innerRadius,
                    outerRadius: outerRadius
                )
                // Dual-skin swap overlay: repeat the clamp with the ALT half's edge
                // pixels at the overlay's current opacity so the lagging outer ring
                // fades in step with the cell fill.
                let overlayAlpha = dualSkinOverlayAlpha(for: cell)
                if overlayAlpha > 0.001 {
                    var overlayContext = context
                    overlayContext.opacity = Double(overlayAlpha)
                    drawSkinEdgeClamp(
                        context: overlayContext,
                        skinName: skinName,
                        outerPath: outerPath,
                        center: CGPoint(x: screenX, y: screenY),
                        innerRadius: innerRadius,
                        outerRadius: outerRadius,
                        useAltHalf: true
                    )
                }
            }
            drawCellFill(context: context, cell: cell, path: innerPath, screenX: screenX, screenY: screenY, radius: innerRadius, showSkins: drawSkin)
            drawCellBorder(context: context,
                           cell: cell,
                           outerPath: outerPath,
                           center: CGPoint(x: screenX, y: screenY),
                           radius: outerRadius,
                           coreRadius: coreRadius,
                           borderWidth: borderWidth,
                           hasDeformation: hasRenderableDeformation,
                           zoom: zoom)
            if drawSkin, !cell.isBot || cell.isRemoteHuman, !cell.isFeedBot, DualSkinCatalog.shared.isDual(cell.skinName) {
                drawSkinEffectsPass(context: context, clipPath: outerPath,
                                    centerX: screenX, centerY: screenY, radius: outerRadius)
            }
        } else {
            let fillRadius = cell.cachedSolidRadius * zoom
            let borderRadius = cell.cachedLagRadius * zoom
            let fillCoreRadius = fillRadius * 0.85
            let borderCoreRadius = borderRadius * 0.85
            
            let fillPath = createOrganicPath(center: CGPoint(x: screenX, y: screenY), baseRadius: fillRadius, deformations: cell.skinDeformation, hasDeformation: hasRenderableDeformation, zoom: zoom, minRadius: fillCoreRadius)
            let borderPath = createOrganicPath(center: CGPoint(x: screenX, y: screenY), baseRadius: borderRadius, deformations: cell.skinDeformation, hasDeformation: hasRenderableDeformation, zoom: zoom, minRadius: borderCoreRadius)
            
            // drawLayer + clip is only needed when there's a skin to mask, or while the cell
            // is inflating (fill briefly outgrows the border ring). Otherwise a plain fill is
            // identical on screen and much cheaper - this used to run for every cell, always.
            let needsClip = (drawSkin && cell.skinName != nil) || fillRadius > borderRadius + 0.5
            if needsClip {
                context.drawLayer { layerContext in
                    layerContext.clip(to: borderPath)
                    drawCellFill(context: layerContext, cell: cell, path: fillPath, screenX: screenX, screenY: screenY, radius: fillRadius, showSkins: drawSkin)
                }
            } else {
                context.fill(fillPath, with: .color(cell.color))
            }
            drawCellBorder(context: context,
                           cell: cell,
                           outerPath: borderPath,
                           center: CGPoint(x: screenX, y: screenY),
                           radius: borderRadius,
                           coreRadius: borderCoreRadius,
                           borderWidth: borderWidth,
                           hasDeformation: hasRenderableDeformation,
                           zoom: zoom)
            if drawSkin, !cell.isBot || cell.isRemoteHuman, !cell.isFeedBot, DualSkinCatalog.shared.isDual(cell.skinName) {
                drawSkinEffectsPass(context: context, clipPath: borderPath,
                                    centerX: screenX, centerY: screenY, radius: borderRadius)
            }
        }
        
        drawCellLabels(context: context, cell: cell, screenX: screenX, screenY: screenY)
    }
    
    /// Dual-width skins: the base half is always drawn; the eat-triggered swap fades the
    /// alternate half in *on top* of it instead of replacing it outright.
    func displaySkinName(for cell: PlayerCell) -> String? {
        return cell.skinName
    }
    
    /// Current opacity of the alt-half overlay for this frame (0 = not showing).
    private var dualSkinOverlayAlpha: CGFloat {
        guard let start = dualSkinSwapShowingSince else { return 0 }
        return DualSkin.altOverlayAlpha(elapsed: CACurrentMediaTime() - start)
    }
    
    /// Whether the alt-half overlay applies to this cell right now. The player's
    /// own cells use the local swap state; REMOTE human cells (online) use the
    /// per-owner map fed by server eat events (v5 skin sync). Bots, feed bots
    /// and square skins always keep the base artwork.
    private func dualSkinOverlayAlpha(for cell: PlayerCell) -> CGFloat {
        guard !cell.isFeedBot, DualSkinCatalog.shared.isDual(cell.skinName) else { return 0 }
        if cell.isRemoteHuman {
            guard let start = dualSkinSwapShowingSinceByOwner[cell.ownerID] else { return 0 }
            return DualSkin.altOverlayAlpha(elapsed: CACurrentMediaTime() - start)
        }
        guard !cell.isBot else { return 0 }
        return dualSkinOverlayAlpha
    }
    
    /// Additive Spine shine pass, clipped to the cell's live outer contour. A pass starts
    /// every `DualSkin.effectInterval` seconds on a shared wall clock, so split cells
    /// glint in sync exactly like one cell would.
    private func drawSkinEffectsPass(context: GraphicsContext,
                                     clipPath: Path,
                                     centerX: CGFloat,
                                     centerY: CGFloat,
                                     radius: CGFloat) {
        SkinEffectsRenderer.drawShinePass(into: context, clipPath: clipPath,
                                          centerX: centerX, centerY: centerY,
                                          radius: radius, wallClock: CACurrentMediaTime()) { layer in
            resolver.resolve("img:SkinEffects", context: layer) { Image("SkinEffects").resizable() }
        }
    }
    
    /// Draw the source skin as a dynamic clamp-to-edge texture:
    ///   corners | top row stretched vertically | corners
    ///   left column stretched horizontally | original skin | right column
    ///   corners | bottom row stretched vertically | corners
    /// The existing organic path remains the sole outer mask, so deformation and border lag
    /// geometry are unchanged.
    private func drawSkinEdgeClamp(context: GraphicsContext,
                                   skinName: String,
                                   outerPath: Path,
                                   center: CGPoint,
                                   innerRadius: CGFloat,
                                   outerRadius: CGFloat,
                                   useAltHalf: Bool = false) {
        // Dual-width sheets clamp only the half being shown; square skins use the full image.
        let half: SkinEdgeClampCache.Half = DualSkinCatalog.shared.isDual(skinName)
        ? (useAltHalf ? .right : .left)
        : .full
        let edgeKeyPrefix = "skin-edge:" + skinName + ":" + half.rawValue + ":"
        guard outerRadius > innerRadius + 0.01,
              let slices = SkinEdgeClampCache.shared.slices(for: skinName, half: half),
              let source = resolver.resolve(
                "skin:" + skinName,
                context: context,
                make: { Image(skinName).resizable() }
              ),
              let top = resolver.resolve(
                edgeKeyPrefix + "top",
                context: context,
                make: { slices.top }
              ),
              let bottom = resolver.resolve(
                edgeKeyPrefix + "bottom",
                context: context,
                make: { slices.bottom }
              ),
              let left = resolver.resolve(
                edgeKeyPrefix + "left",
                context: context,
                make: { slices.left }
              ),
              let right = resolver.resolve(
                edgeKeyPrefix + "right",
                context: context,
                make: { slices.right }
              ),
              let topLeft = resolver.resolve(
                edgeKeyPrefix + "top-left",
                context: context,
                make: { slices.topLeft }
              ),
              let topRight = resolver.resolve(
                edgeKeyPrefix + "top-right",
                context: context,
                make: { slices.topRight }
              ),
              let bottomLeft = resolver.resolve(
                edgeKeyPrefix + "bottom-left",
                context: context,
                make: { slices.bottomLeft }
              ),
              let bottomRight = resolver.resolve(
                edgeKeyPrefix + "bottom-right",
                context: context,
                make: { slices.bottomRight }
              ) else { return }
        
        let outerRect = CGRect(
            x: center.x - outerRadius,
            y: center.y - outerRadius,
            width: outerRadius * 2,
            height: outerRadius * 2
        )
        let innerRect = CGRect(
            x: center.x - innerRadius,
            y: center.y - innerRadius,
            width: innerRadius * 2,
            height: innerRadius * 2
        )
        let leftWidth = max(0, innerRect.minX - outerRect.minX)
        let rightWidth = max(0, outerRect.maxX - innerRect.maxX)
        let topHeight = max(0, innerRect.minY - outerRect.minY)
        let bottomHeight = max(0, outerRect.maxY - innerRect.maxY)
        
        var imageContext = context
        imageContext.clip(to: outerPath)
        
        // Corner pixels extend in both axes and fill all four diagonal quadrants.
        imageContext.draw(topLeft, in: CGRect(
            x: outerRect.minX,
            y: outerRect.minY,
            width: leftWidth,
            height: topHeight
        ))
        imageContext.draw(topRight, in: CGRect(
            x: innerRect.maxX,
            y: outerRect.minY,
            width: rightWidth,
            height: topHeight
        ))
        imageContext.draw(bottomLeft, in: CGRect(
            x: outerRect.minX,
            y: innerRect.maxY,
            width: leftWidth,
            height: bottomHeight
        ))
        imageContext.draw(bottomRight, in: CGRect(
            x: innerRect.maxX,
            y: innerRect.maxY,
            width: rightWidth,
            height: bottomHeight
        ))
        
        // One-pixel rows become vertical rays; one-pixel columns become horizontal rays.
        imageContext.draw(top, in: CGRect(
            x: innerRect.minX,
            y: outerRect.minY,
            width: innerRect.width,
            height: topHeight
        ))
        imageContext.draw(bottom, in: CGRect(
            x: innerRect.minX,
            y: innerRect.maxY,
            width: innerRect.width,
            height: bottomHeight
        ))
        imageContext.draw(left, in: CGRect(
            x: outerRect.minX,
            y: innerRect.minY,
            width: leftWidth,
            height: innerRect.height
        ))
        imageContext.draw(right, in: CGRect(
            x: innerRect.maxX,
            y: innerRect.minY,
            width: rightWidth,
            height: innerRect.height
        ))
        
        // The centre tile uses the exact same resolved skin as the normal inner draw. Keeping it
        // beneath that draw prevents circular/deformation seams where the eight strips meet it.
        // For dual-width sheets, offset-draw so only the half being shown lands in the tile.
        if half == .full {
            imageContext.draw(source, in: innerRect)
        } else {
            var centreContext = imageContext
            centreContext.clip(to: Path(innerRect))
            let sheetX = half == .right ? innerRect.minX - innerRect.width : innerRect.minX
            centreContext.draw(source, in: CGRect(x: sheetX, y: innerRect.minY,
                                                  width: innerRect.width * 2,
                                                  height: innerRect.height))
        }
    }
    
    /// True when this owner is a teammate: the offline recruited bot or an online party member.
    private func isTeammateOwner(_ ownerID: UUID) -> Bool {
        if let teammateOwnerID, teammateOwnerID == ownerID { return true }
        return teammateOwnerIDs.contains(ownerID)
    }

    /// A pact/party is active when any teammate exists (offline pact or online party),
    /// or when the local player holds a party code online - being in a party shows
    /// your own border immediately, even while no member is on the server yet.
    private var teamPactActive: Bool {
        teammateOwnerID != nil || !teammateOwnerIDs.isEmpty || localPlayerInParty
    }

    /// Team marker: while a pact is active, the recruited teammate AND the player's own cells
    /// wear the marker, so both sides can see the bond - and both lose it the moment the pact
    /// dissolves. The normal border band is split into two adjacent rings of half the normal
    /// width each - #FFC300 on the outer half, #F7F831 on the inner half - so the whole marker
    /// occupies exactly the band a normal border occupies (same total width, nothing extra dug
    /// into the skin). Every other cell retains the original single border path and colour.
    private func drawCellBorder(context: GraphicsContext,
                                cell: PlayerCell,
                                outerPath: Path,
                                center: CGPoint,
                                radius: CGFloat,
                                coreRadius: CGFloat,
                                borderWidth: CGFloat,
                                hasDeformation: Bool,
                                zoom: CGFloat) {
        let isTeamMember = teamPactActive
        && ((cell.isBot && isTeammateOwner(cell.ownerID))
            || (!cell.isBot && !cell.isFeedBot))
        guard isTeamMember else {
            context.stroke(outerPath, with: .color(cell.borderColor), lineWidth: borderWidth)
            return
        }
        
        // Orange first across the full normal band, then yellow re-covers the inner half.
        // Both strokes follow the same organic deformation as the normal border.
        context.stroke(outerPath,
                       with: .color(teammateOuterBorderColor),
                       lineWidth: borderWidth)
        
        let halfWidth = borderWidth * 0.5
        let innerHalfRadius = max(halfWidth * 0.5, radius - halfWidth * 0.5)
        let innerHalfCoreRadius = max(0, min(innerHalfRadius, coreRadius - halfWidth * 0.5))
        let innerHalfPath = createOrganicPath(center: center,
                                              baseRadius: innerHalfRadius,
                                              deformations: cell.skinDeformation,
                                              hasDeformation: hasDeformation,
                                              zoom: zoom,
                                              minRadius: innerHalfCoreRadius)
        context.stroke(innerHalfPath,
                       with: .color(teammateInnerBorderColor),
                       lineWidth: halfWidth)
    }
    
    // MARK: - LABELS (sprite based: no per-frame glyph layout => no shaking)
    // Geometry is byte-for-byte the old maths: font = max(4, radius * 0.4) locked to physical
    // mass, name nudged up 0.125 em, mass label 1.625 em below it at 0.8 em, mass label only
    // once the font clears 10pt. Only the *rasterisation* changed.
    private func drawCellLabels(context: GraphicsContext, cell: PlayerCell, screenX: CGFloat, screenY: CGFloat) {
        let stableTextRadius = cell.cachedSolidRadius * zoomLevel
        let fontSize = max(4, stableTextRadius * 0.4)
        // The mass label scales with the radius at the normal base ratio, except that
        // pieces born from a >= massFontHalfThreshold split use exactly half that ratio.
        // It still grows/shrinks with the cell - only the ratio changes.
        let massFontSize: CGFloat = max(4, fontSize * cell.massFontScale)
        let displayMass = Int(cell.mass)
        let level = ownerLevels[cell.ownerID]
        
        if cell.isBot || cell.isFeedBot {
            if isTeammateOwner(cell.ownerID) {
                // Teammate layout: pfp above the cell centre, name below it but slightly
                // closer in, so the pair hugs the centre without touching.
                drawFriendPfp(context: context,
                              centre: CGPoint(x: screenX, y: screenY - fontSize * 1.0),
                              fontSize: fontSize)
                let nameFont = fontSize * 0.8
                let nameCentre = CGPoint(x: screenX, y: screenY + fontSize * 0.70)
                if let level = level, !cell.name.isEmpty {
                    drawNameWithBadgeCentred(level, name: cell.name, context: context,
                                             centre: nameCentre, fontSize: nameFont)
                } else {
                    drawNameSprite(cell.name, context: context, centre: nameCentre, fontSize: nameFont)
                }
            } else {
                if let level = level {
                    if cell.name.isEmpty {
                        drawLeagueBadgeCentred(level, context: context,
                                               centre: CGPoint(x: screenX, y: screenY),
                                               screenRadius: stableTextRadius)
                    } else {
                        drawNameWithBadgeCentred(level, name: cell.name, context: context,
                                                 centre: CGPoint(x: screenX, y: screenY),
                                                 fontSize: fontSize)
                    }
                } else {
                    drawNameSprite(cell.name, context: context, centre: CGPoint(x: screenX, y: screenY), fontSize: fontSize)
                }
            }
        } else if cell.name.isEmpty {
            if let level = level {
                // The badge takes the skin's centre; the mass counter drops to the star's
                // lower tip (reference layout) instead of hiding behind the badge.
                drawLeagueBadgeCentred(level, context: context,
                                       centre: CGPoint(x: screenX, y: screenY),
                                       screenRadius: stableTextRadius)
                if showMassText {
                    let badgeHeight = stableTextRadius * 1.3
                    drawNumberSprite(displayMass, context: context,
                                     centre: CGPoint(x: screenX, y: screenY + badgeHeight * 0.47),
                                     fontSize: massFontSize)
                }
            } else if showMassText {
                drawNumberSprite(displayMass, context: context, centre: CGPoint(x: screenX, y: screenY), fontSize: massFontSize)
            }
        } else {
            let nameCentre = CGPoint(x: screenX, y: screenY - fontSize * 0.125)
            if let level = level {
                drawNameWithBadgeCentred(level, name: cell.name, context: context,
                                         centre: nameCentre, fontSize: fontSize)
            } else {
                drawNameSprite(cell.name, context: context, centre: nameCentre, fontSize: fontSize)
            }
            // No minimum font size: small cells kept dropping their mass counter whenever
            // zoom pushed fontSize under the old > 10 gate, which read as it "disappearing".
            if showMassText {
                drawNumberSprite(displayMass, context: context,
                                 centre: CGPoint(x: screenX, y: screenY + fontSize * 1.625),
                                 fontSize: massFontSize * 0.8)
            }
        }
    }
    
    /// No-name cells: the badge sits in the middle of the skin and covers a good chunk of it
    /// (image height = 1.3x the cell's solid radius, like the reference screenshots).
    private func drawLeagueBadgeCentred(_ level: Int, context: GraphicsContext, centre: CGPoint, screenRadius: CGFloat) {
        let height = screenRadius * 1.3
        let width = height * LeagueBadge.imageAspect
        drawLeagueBadge(level, context: context,
                        rect: CGRect(x: centre.x - width / 2, y: centre.y - height / 2,
                                     width: width, height: height))
    }
    
    /// Draws a named cell's name with its league badge hanging off the left edge, but with
    /// the *pair* (badge + name) centred on the given point instead of the name alone: the
    /// name is nudged right by half the badge's net footprint so badge + name together sit
    /// centred on the cell. Every named badge layout (bots, player, teammate) routes here.
    private func drawNameWithBadgeCentred(_ level: Int, name: String, context: GraphicsContext, centre: CGPoint, fontSize: CGFloat) {
        let badgeWidth = fontSize * 1.1475 * LeagueBadge.imageAspect
        let nameCentre = CGPoint(x: centre.x + (badgeWidth - fontSize * 0.06) / 2, y: centre.y)
        drawNameSprite(name, context: context, centre: nameCentre, fontSize: fontSize)
        drawLeagueBadgeBesideName(level, name: name, context: context,
                                  nameCentre: nameCentre, fontSize: fontSize)
    }
    
    /// Named cells: the badge hangs on the very left of the name text, in the same height
    /// band as the text. The name sprite's own padding provides the visual gap. Callers go
    /// through drawNameWithBadgeCentred so the badge+name pair stays centred as a whole.
    private func drawLeagueBadgeBesideName(_ level: Int, name: String, context: GraphicsContext, nameCentre: CGPoint, fontSize: CGFloat) {
        guard let sprite = TextSpriteCache.shared.nameSprite(name) else { return }
        let scale = fontSize / TextSpriteCache.shared.referenceFontSize
        let nameWidth = sprite.size.width * scale
        // 1.35 shrunk 15% (v46): the badge reads slightly lighter next to the name.
        let height = fontSize * 1.1475
        let width = height * LeagueBadge.imageAspect
        drawLeagueBadge(level, context: context,
                        rect: CGRect(x: nameCentre.x - nameWidth / 2 - width + fontSize * 0.06,
                                     y: nameCentre.y - height / 2,
                                     width: width, height: height))
    }
    
    /// League image + level number on the star's centre. The number reuses the outlined
    /// digit sprites, so badges get the exact same look and stability as the mass counter.
    private func drawLeagueBadge(_ level: Int, context: GraphicsContext, rect: CGRect) {
        let asset = LeagueBadge.assetName(forLevel: level)
        guard let image = resolver.resolve("league:" + asset, context: context, make: { Image(asset).resizable() }) else { return }
        context.draw(image, in: rect)
        // Cap height is ~0.7x the nominal font size; 0.40x badge height puts the digits at
        // ~28% of the star, matching the reference. Three digits shrink to stay inside it.
        let clamped = LeagueBadge.clamp(level)
        let numberFontSize = rect.height * (clamped >= 100 ? 0.32 : 0.40)
        drawNumberSprite(clamped, context: context,
                         centre: CGPoint(x: rect.midX, y: rect.midY),
                         fontSize: numberFontSize,
                         badgeAsset: asset)
    }
    
    /// The party pfp, drawn centred on the given point (it occupies the name text's
    /// slot on teammate cells) and scaled with the same font size the name uses.
    private func drawFriendPfp(context: GraphicsContext, centre: CGPoint, fontSize: CGFloat) {
        guard let image = resolver.resolve("img:friend-pfp", context: context,
                                           make: { Image("friend-pfp").resizable() }) else { return }
        let side = fontSize * 1.35
        context.draw(image, in: CGRect(x: centre.x - side / 2,
                                       y: centre.y - side / 2,
                                       width: side, height: side))
    }
    
    /// Squared screen-space distance from the screen centre to a teammate's weighted
    /// centre - or nil when the teammate is dead or ANY of their cells is on screen
    /// (visible teammates need no arrow). Feeds the closest-off-screen pick that
    /// decides which single teammate the party arrow points at.
    private func offscreenTeammateDistSq(size: CGSize, zoom: CGFloat,
                                         cameraOffsetX: CGFloat, cameraOffsetY: CGFloat,
                                         teammateID: UUID) -> CGFloat? {
        var weightedX: CGFloat = 0
        var weightedY: CGFloat = 0
        var totalMass: CGFloat = 0
        let screenBounds = CGRect(origin: .zero, size: size)
        for cell in botCells where cell.ownerID == teammateID {
            let mass = max(cell.mass, 1)
            weightedX += cell.position.x * mass
            weightedY += cell.position.y * mass
            totalMass += mass
            let r = cell.cachedVisualRadius * zoom
            let sx = cell.position.x * zoom + cameraOffsetX
            let sy = cell.position.y * zoom + cameraOffsetY
            if screenBounds.intersects(CGRect(x: sx - r, y: sy - r, width: r * 2, height: r * 2)) {
                return nil
            }
        }
        guard totalMass > 0 else { return nil }
        let dx = (weightedX / totalMass) * zoom + cameraOffsetX - size.width / 2
        let dy = (weightedY / totalMass) * zoom + cameraOffsetY - size.height / 2
        return dx * dx + dy * dy
    }
    
    /// Party arrow: whenever every cell of the recruited teammate is off screen, an arrow
    /// hugs the screen edge (fixed margin), always pointing at the teammate's weighted
    /// centre, circling the border as they move - with their name right underneath in
    /// white text with a grey stroke.
    private func drawPartyArrow(context: GraphicsContext, size: CGSize, zoom: CGFloat,
                                cameraOffsetX: CGFloat, cameraOffsetY: CGFloat,
                                teammateID: UUID) {
        var weightedX: CGFloat = 0
        var weightedY: CGFloat = 0
        var totalMass: CGFloat = 0
        var anyVisible = false
        var name = ""
        let screenBounds = CGRect(origin: .zero, size: size)
        
        for cell in botCells where cell.ownerID == teammateID {
            let mass = max(cell.mass, 1)
            weightedX += cell.position.x * mass
            weightedY += cell.position.y * mass
            totalMass += mass
            if name.isEmpty { name = cell.name }
            let r = cell.cachedVisualRadius * zoom
            let sx = cell.position.x * zoom + cameraOffsetX
            let sy = cell.position.y * zoom + cameraOffsetY
            if screenBounds.intersects(CGRect(x: sx - r, y: sy - r, width: r * 2, height: r * 2)) {
                anyVisible = true
            }
        }
        guard totalMass > 0, !anyVisible else { return }
        
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = (weightedX / totalMass) * zoom + cameraOffsetX - centre.x
        let dy = (weightedY / totalMass) * zoom + cameraOffsetY - centre.y
        guard dx != 0 || dy != 0 else { return }
        
        // Slide from the screen centre along the teammate direction until the inset
        // (margin) rectangle's border is hit - that traces the arrow around the edge.
        let margin: CGFloat = 84
        let inset = screenBounds.insetBy(dx: margin, dy: margin)
        var travel = CGFloat.greatestFiniteMagnitude
        if dx > 0 { travel = min(travel, (inset.maxX - centre.x) / dx) }
        if dx < 0 { travel = min(travel, (inset.minX - centre.x) / dx) }
        if dy > 0 { travel = min(travel, (inset.maxY - centre.y) / dy) }
        if dy < 0 { travel = min(travel, (inset.minY - centre.y) / dy) }
        guard travel.isFinite else { return }
        let arrowPos = CGPoint(x: centre.x + dx * travel, y: centre.y + dy * travel)
        
        let arrowSize: CGFloat = 67
        // The asset's natural orientation points straight up; one rotated layer spins
        // both the arrow AND its name label so the text stays pinned to the arrow's
        // flat bottom edge no matter which way it points.
        var rotated = context
        rotated.translateBy(x: arrowPos.x, y: arrowPos.y)
        rotated.rotate(by: Angle(radians: Double(atan2(dy, dx)) + Double.pi / 2))
        
        if let arrow = resolver.resolve("img:party-arrow-light", context: context,
                                        make: { Image("party-arrow-light").resizable() }) {
            rotated.draw(arrow, in: CGRect(x: -arrowSize / 2, y: -arrowSize / 2,
                                           width: arrowSize, height: arrowSize))
        }
        
        if !name.isEmpty,
           let sprite = TextSpriteCache.shared.partyNameSprite(name),
           let resolved = resolver.resolve("ptxt:" + name, context: context, make: { sprite.image }) {
            let labelFontSize: CGFloat = 18
            let scale = labelFontSize / TextSpriteCache.shared.referenceFontSize
            let w = sprite.size.width * scale
            let h = sprite.size.height * scale
            // Just off the flat base (small gap), positioned in the arrow's rotated
            // frame so it tracks the base exactly. When the arrow points downward the
            // rotation would render the words upside down, so the label spins an extra
            // half turn around its own centre - same spot, readable either way.
            let labelCentreY = arrowSize / 2 + 3.6 + h * 0.288
            var label = rotated
            label.translateBy(x: 0, y: labelCentreY)
            if dy > 0 {
                label.rotate(by: Angle(radians: Double.pi))
            }
            label.draw(resolved, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        }
    }
    
    private func drawNameSprite(_ name: String, context: GraphicsContext, centre: CGPoint, fontSize: CGFloat) {
        guard !name.isEmpty else { return }
        guard let sprite = TextSpriteCache.shared.nameSprite(name) else { return }
        guard let resolved = resolver.resolve("txt:" + name, context: context, make: { sprite.image }) else { return }
        
        let scale = fontSize / TextSpriteCache.shared.referenceFontSize
        let w = sprite.size.width * scale
        let h = sprite.size.height * scale
        context.draw(resolved, in: CGRect(x: centre.x - w / 2, y: centre.y - h / 2, width: w, height: h))
    }
    
    /// Numbers are composed from identical digit tiles, so the glyphs sit on a fixed pitch.
    /// This is what kills the "text shaking" on cells: nothing is ever re-laid-out or
    /// re-hinted while the mass counter runs.
    private func drawNumberSprite(_ value: Int, context: GraphicsContext, centre: CGPoint, fontSize: CGFloat, badgeAsset: String? = nil) {
        let cache = TextSpriteCache.shared
        guard cache.digitSprite(0) != nil else { return }
        
        let scale = fontSize / cache.referenceFontSize
        let tileW = cache.digitTile.width * scale
        let tileH = cache.digitTile.height * scale
        let advance = cache.digitAdvance * scale
        
        var digitsReversed: [Int] = []
        digitsReversed.reserveCapacity(6)
        var v = max(0, value)
        if v == 0 {
            digitsReversed.append(0)
        } else {
            while v > 0 {
                digitsReversed.append(v % 10)
                v /= 10
            }
        }
        
        let count = CGFloat(digitsReversed.count)
        let totalWidth = advance * count
        var centreX = centre.x - totalWidth / 2 + advance / 2 + advance * (count - 1)
        
        for digit in digitsReversed {
            let sprite: TextSpriteCache.Sprite?
            let key: String
            if let asset = badgeAsset {
                sprite = cache.badgeDigitSprite(digit, asset: asset)
                key = "bdig:\(asset):\(digit)"
            } else {
                sprite = cache.digitSprite(digit)
                key = "dig:\(digit)"
            }
            if let sprite = sprite,
               let resolved = resolver.resolve(key, context: context, make: { sprite.image }) {
                context.draw(resolved, in: CGRect(x: centreX - tileW / 2,
                                                  y: centre.y - tileH / 2,
                                                  width: tileW,
                                                  height: tileH))
            }
            centreX -= advance
        }
    }
    
    func drawCellFill(context: GraphicsContext, cell: PlayerCell, path: Path, screenX: CGFloat, screenY: CGFloat, radius: CGFloat, showSkins: Bool) {
        context.fill(path, with: .color(cell.color))
        if showSkins, let skinName = displaySkinName(for: cell),
           let image = resolver.resolve("skin:" + skinName, context: context, make: { Image(skinName).resizable() }) {
            var imageContext = context
            imageContext.clip(to: path)
            let rect = CGRect(x: screenX - radius, y: screenY - radius, width: radius * 2, height: radius * 2)
            if DualSkinCatalog.shared.isDual(skinName) {
                // Dual-width sheet: only its BASE (left) half is the everyday skin. Add a
                // rect clip so the sheet drawn at 2x width can never leak its other half
                // in, then offset-draw sprite-sheet style.
                imageContext.clip(to: Path(rect))
                let sheetWidth = rect.width * 2
                imageContext.draw(image, in: CGRect(x: rect.minX, y: rect.minY,
                                                    width: sheetWidth, height: rect.height))
                // Eat-triggered swap: fade the ALT (right) half in/out on top of the base
                // half inside the same clips, instead of hard-swapping the image.
                let overlayAlpha = dualSkinOverlayAlpha(for: cell)
                if overlayAlpha > 0.001 {
                    imageContext.opacity = Double(overlayAlpha)
                    imageContext.draw(image, in: CGRect(x: rect.minX - rect.width, y: rect.minY,
                                                        width: sheetWidth, height: rect.height))
                }
            } else {
                imageContext.draw(image, in: rect)
            }
        }
        // Emote overlay: drawn INSIDE EVERY split cell owned by the local player,
        // clipped to the cell's circular/organic path, with 3.0s fade-in/fade-out.
        if !cell.isBot && !cell.isFeedBot && !cell.isRemoteHuman,
           let emote = activeEmoteAsset {
            let now = CACurrentMediaTime()
            if now < activeEmoteExpiresAt {
                let elapsed = max(0, now - activeEmoteStartedAt)
                let remaining = max(0, activeEmoteExpiresAt - now)
                let fadeIn = min(1.0, elapsed / 0.18)
                let fadeOut = min(1.0, remaining / 0.30)
                let alpha = min(fadeIn, fadeOut)
                if alpha > 0.01,
                   let emoteImage = resolver.resolve("emote:" + emote, context: context, make: { Image(emote).resizable() }) {
                    var emoteContext = context
                    emoteContext.clip(to: path)
                    emoteContext.opacity = alpha
                    let rect = CGRect(x: screenX - radius, y: screenY - radius, width: radius * 2, height: radius * 2)
                    emoteContext.draw(emoteImage, in: rect)
                }
            }
        }
    }
    
    func createOrganicPath(center: CGPoint, baseRadius: CGFloat, deformations: [CGFloat], hasDeformation: Bool, zoom: CGFloat, minRadius: CGFloat) -> Path {
        if baseRadius < 5 {
            return Path(ellipseIn: CGRect(x: center.x - baseRadius, y: center.y - baseRadius, width: baseRadius * 2, height: baseRadius * 2))
        }
        var path = Path()
        let pointsCount = deformations.count
        guard pointsCount > 2 else { return Path(ellipseIn: CGRect(x: center.x - baseRadius, y: center.y - baseRadius, width: baseRadius * 2, height: baseRadius * 2)) }
        if !hasDeformation {
            return Path(ellipseIn: CGRect(x: center.x - baseRadius, y: center.y - baseRadius, width: baseRadius * 2, height: baseRadius * 2))
        }
        
        let trig = TrigCache.get(count: pointsCount)
        // The quad-curve silhouette through chord midpoints sits slightly *inside* the true
        // circle (up to ~1% at 20 vertices). Untreated, the moment the last dent relaxes under
        // the renderable threshold this path is swapped for the exact ellipse and the border
        // visibly pops outward by that undershoot. Scaling the vertex ring so the curve's
        // midpoint radius equals baseRadius makes organic and ellipse renderings coincide,
        // removing the snap while leaving dent shapes proportionally identical.
        let halfStepCos = cos(.pi / CGFloat(pointsCount))
        let undershootCompensation = 2.0 / (1.0 + halfStepCos)
        var points: [CGPoint] = []
        points.reserveCapacity(pointsCount)
        for i in 0..<pointsCount {
            var r = (baseRadius - (deformations[i] * zoom)) * undershootCompensation
            r = max(r, minRadius)
            let x = center.x + trig[i].cos * r
            let y = center.y + trig[i].sin * r
            points.append(CGPoint(x: x, y: y))
        }
        if let first = points.first {
            let startMid = midPoint(p1: points[pointsCount - 1], p2: first)
            path.move(to: startMid)
            for i in 0..<pointsCount {
                let p1 = points[i]
                let p2 = points[(i + 1) % pointsCount]
                let mid = midPoint(p1: p1, p2: p2)
                path.addQuadCurve(to: mid, control: p1)
            }
            path.closeSubpath()
        }
        return path
    }
    
    func midPoint(p1: CGPoint, p2: CGPoint) -> CGPoint {
        return CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
    }
}

// MARK: - SHARED SPATIAL INDEX FOR CELLS
//
// Built twice per frame (once for AI perception, once after movement for collisions) and
// reused by everything. Replaces: the O(n^2) bot-vs-bot loop, the O(n*m) bot-vs-player loop,
// the per-brain "iterate every cell in the world" AI scan, and the per-frame grid rebuild
// inside the ejected-mass collision pass. With 100 bots x up to 16 cells the old loops were
// over a million distance checks per frame; this is a few thousand.
struct CellSnapshot {
    let isPlayer: Bool
    let index: Int
    let id: UUID
    let ownerID: UUID
    let x: CGFloat
    let y: CGFloat
    let mass: CGFloat
    /// Visual radius (max of mass/lagMass) - used for physics and pellet pickup.
    let radius: CGFloat
    /// Radius from real mass - used for the eat checks, matching the original rules.
    let solidRadius: CGFloat
    let vx: CGFloat
    let vy: CGFloat
    let isBot: Bool
    let isFeedBot: Bool
    let canMerge: Bool
}

final class CellIndex {
    let bucketSize: CGFloat = 700
    /// Centre-bucket indexing is excellent for ordinary cells, but one enormous cell must not
    /// expand every query in the world. Cells above half a bucket use footprint buckets instead.
    private let footprintThreshold: CGFloat = 350
    
    private(set) var items: [CellSnapshot] = []
    private var centreBuckets: [GridKey: [Int]] = [:]
    private var oversizedItemIndices: [Int] = []
    private var maxCentreRadius: CGFloat = 0
    private var footprintStamps: [Int] = []
    private var generation: Int = 0
    
    func rebuild(playerCells: [PlayerCell], botCells: [PlayerCell]) {
        items.removeAll(keepingCapacity: true)
        centreBuckets.removeAll(keepingCapacity: true)
        oversizedItemIndices.removeAll(keepingCapacity: true)
        maxCentreRadius = 0
        
        appendAll(playerCells, isPlayer: true)
        appendAll(botCells, isPlayer: false)
        
        // A handful of giants is cheaper to exact-test directly than to probe a second hash
        // grid on every pellet query. At larger counts, footprints win decisively.
        if oversizedItemIndices.count > 8 {
            for itemIndex in oversizedItemIndices {
                let snapshot = items[itemIndex]
                let minX = Int((snapshot.x - snapshot.radius) / bucketSize)
                let maxX = Int((snapshot.x + snapshot.radius) / bucketSize)
                let minY = Int((snapshot.y - snapshot.radius) / bucketSize)
                let maxY = Int((snapshot.y + snapshot.radius) / bucketSize)
                for gx in gridRange(minX, maxX) {
                    for gy in gridRange(minY, maxY) {
                        centreBuckets[GridKey(x: gx, y: gy), default: []]
                            .append(itemIndex)
                    }
                }
            }
        }
        
        if footprintStamps.count < items.count {
            footprintStamps = [Int](repeating: 0, count: max(items.count * 2, 64))
        }
    }
    
    private func appendAll(_ cells: [PlayerCell], isPlayer: Bool) {
        for (i, c) in cells.enumerated() {
            let visual = c.cachedVisualRadius
            let solid = c.cachedSolidRadius
            let snapshot = CellSnapshot(isPlayer: isPlayer, index: i, id: c.id, ownerID: c.ownerID,
                                        x: c.position.x, y: c.position.y, mass: c.mass,
                                        radius: visual, solidRadius: solid,
                                        vx: c.velocity.width, vy: c.velocity.height,
                                        isBot: c.isBot, isFeedBot: c.isFeedBot, canMerge: c.canMerge)
            let itemIndex = items.count
            items.append(snapshot)
            
            if visual <= footprintThreshold {
                maxCentreRadius = max(maxCentreRadius, visual)
                let key = GridKey(x: Int(snapshot.x / bucketSize),
                                  y: Int(snapshot.y / bucketSize))
                centreBuckets[key, default: []].append(itemIndex)
            } else {
                oversizedItemIndices.append(itemIndex)
            }
        }
    }
    
    /// Visits every geometrically possible candidate once. Ordinary cells use compact
    /// centre-point buckets; oversized cells use exact footprints and generation stamps.
    func forEach(near point: CGPoint, radius: CGFloat, _ body: (CellSnapshot) -> Void) {
        let usesFootprints = oversizedItemIndices.count > 8
        var stamp = 0
        if usesFootprints {
            if generation == Int.max {
                for index in footprintStamps.indices { footprintStamps[index] = 0 }
                generation = 1
            } else {
                generation += 1
            }
            stamp = generation
        }
        
        let expandedRadius = radius + maxCentreRadius
        let minX = Int((point.x - expandedRadius) / bucketSize)
        let maxX = Int((point.x + expandedRadius) / bucketSize)
        let minY = Int((point.y - expandedRadius) / bucketSize)
        let maxY = Int((point.y + expandedRadius) / bucketSize)
        
        for gx in gridRange(minX, maxX) {
            for gy in gridRange(minY, maxY) {
                guard let bucket = centreBuckets[GridKey(x: gx, y: gy)] else { continue }
                for itemIndex in bucket {
                    let item = items[itemIndex]
                    if usesFootprints, item.radius > footprintThreshold,
                       itemIndex < footprintStamps.count {
                        if footprintStamps[itemIndex] == stamp { continue }
                        footprintStamps[itemIndex] = stamp
                    }
                    let candidateReach = radius + item.radius
                    let dx = item.x - point.x
                    if dx < -candidateReach || dx > candidateReach { continue }
                    let dy = item.y - point.y
                    if dy < -candidateReach || dy > candidateReach { continue }
                    body(item)
                }
            }
        }
        
        if oversizedItemIndices.count <= 8 {
            for itemIndex in oversizedItemIndices {
                let item = items[itemIndex]
                let candidateReach = radius + item.radius
                let dx = item.x - point.x
                if dx < -candidateReach || dx > candidateReach { continue }
                let dy = item.y - point.y
                if dy < -candidateReach || dy > candidateReach { continue }
                body(item)
            }
            return
        }
    }
}

// MARK: - TOKEN / VIRUS SPATIAL INDEX
//
// Bot plans previously walked all 80 viruses and all 150 tokens per think. With 100 owners
// planning several times a second, that became one of the largest off-screen costs. These
// centre-point buckets are rebuilt in O(230) and turn every local lookup into a few buckets.
final class WorldObjectIndex {
    private let bucketSize: CGFloat = 650
    private var virusBuckets: [GridKey: [Int]] = [:]
    private var tokenBuckets: [GridKey: [Int]] = [:]
    
    private func key(for point: CGPoint) -> GridKey {
        return GridKey(x: Int(point.x / bucketSize), y: Int(point.y / bucketSize))
    }
    
    func rebuildTokens(_ tokens: [Token]) {
        tokenBuckets.removeAll(keepingCapacity: true)
        tokenBuckets.reserveCapacity(min(tokens.count, 230))
        for (index, token) in tokens.enumerated() {
            tokenBuckets[key(for: token.position), default: []].append(index)
        }
    }
    
    func rebuildViruses(_ viruses: [Virus]) {
        virusBuckets.removeAll(keepingCapacity: true)
        virusBuckets.reserveCapacity(min(viruses.count, 120))
        for (index, virus) in viruses.enumerated() {
            virusBuckets[key(for: virus.position), default: []].append(index)
        }
    }
    
    func forEachVirus(near point: CGPoint,
                      radius: CGFloat,
                      viruses: [Virus],
                      perform action: (Int, Virus) -> Void) {
        let minX = Int((point.x - radius) / bucketSize)
        let maxX = Int((point.x + radius) / bucketSize)
        let minY = Int((point.y - radius) / bucketSize)
        let maxY = Int((point.y + radius) / bucketSize)
        let radiusSq = radius * radius
        
        for x in gridRange(minX, maxX) {
            for y in gridRange(minY, maxY) {
                guard let bucket = virusBuckets[GridKey(x: x, y: y)] else { continue }
                for index in bucket where index < viruses.count {
                    let virus = viruses[index]
                    let dx = virus.position.x - point.x
                    let dy = virus.position.y - point.y
                    if dx * dx + dy * dy <= radiusSq {
                        action(index, virus)
                    }
                }
            }
        }
    }
    
    /// Candidate-only variant for collision code that mutates the live virus array. Avoids
    /// passing that array by value while it is being changed (and therefore avoids CoW copies).
    func forEachVirusIndex(near point: CGPoint,
                           radius: CGFloat,
                           perform action: (Int) -> Void) {
        let minX = Int((point.x - radius) / bucketSize)
        let maxX = Int((point.x + radius) / bucketSize)
        let minY = Int((point.y - radius) / bucketSize)
        let maxY = Int((point.y + radius) / bucketSize)
        for x in gridRange(minX, maxX) {
            for y in gridRange(minY, maxY) {
                guard let bucket = virusBuckets[GridKey(x: x, y: y)] else { continue }
                for index in bucket { action(index) }
            }
        }
    }
    
    func nearestToken(near point: CGPoint,
                      radius: CGFloat,
                      tokens: [Token]) -> CGPoint? {
        let minX = Int((point.x - radius) / bucketSize)
        let maxX = Int((point.x + radius) / bucketSize)
        let minY = Int((point.y - radius) / bucketSize)
        let maxY = Int((point.y + radius) / bucketSize)
        var bestDistanceSq = radius * radius
        var best: CGPoint? = nil
        
        for x in gridRange(minX, maxX) {
            for y in gridRange(minY, maxY) {
                guard let bucket = tokenBuckets[GridKey(x: x, y: y)] else { continue }
                for index in bucket where index < tokens.count {
                    let token = tokens[index]
                    let dx = token.position.x - point.x
                    let dy = token.position.y - point.y
                    let distanceSq = dx * dx + dy * dy
                    if distanceSq < bestDistanceSq {
                        bestDistanceSq = distanceSq
                        best = token.position
                    }
                }
            }
        }
        return best
    }
}

/// One hash lookup per owner replaces six parallel UUID dictionaries in the per-frame bot pass.
private struct BotOwnerFrame {
    var brainIndex: Int
    var mass: CGFloat
    var weightedX: CGFloat
    var weightedY: CGFloat
    var count: Int
    var skill: CGFloat
}

// MARK: - XELAHOT MOD MENU (visual clone of xelahot/iOS-Mod-Menu-Base)
//
// Faithful port of the jailbreak menu base's UI, measured straight from Menu.mm:
// 200x250 panel, black @ 0.75, square corners, 2.5pt pure-green border drawn OUTSIDE
// the bounds, 50pt header (white 100x2 grab bar at y=4, centred light 17pt title,
// 20x20 back/close buttons at x=10 / width-30, 1.25pt green divider), scroll list of
// 200pt-wide rows each outlined 0.5pt white: toggles/pages 40pt tall, sliders and
// textfields 60pt. Row ON state = rgb(0.35,0.35,0.35) @ 0.75. Labels are
// AppleSDGothicNeo-Light 15 at x=10; the i-in-a-circle sits 15x15 at (width-30, 12.5)
// and pops a "Description :" alert; page rows carry a chevron at (width-30, 10).
// Sliders sit at (10, 30, 110, 20) with BOTH track sides white and the value text to
// the right; textfields are underline style (0.5pt white bottom rule + 20pt left tick).
// Header drag moves the panel, double-tap closes it, everything fades 0.5s.

private enum XelahotStyle {
    static let panelSize = CGSize(width: 200, height: 250)
    static let headerHeight: CGFloat = 50
    static let green = Color(red: 0, green: 1, blue: 0)          // UIColor.greenColor
    static let background = Color.black.opacity(0.75)
    static let rowOn = Color(red: 0.35, green: 0.35, blue: 0.35).opacity(0.75)
    static func font(_ size: CGFloat) -> Font {
        Font.custom("AppleSDGothicNeo-Light", size: size)
    }
}

/// UISlider wrapper so both track sides render white like the base
/// (SwiftUI's Slider can't tint the maximum track).
private struct XelahotSlider: UIViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    
    final class Coordinator: NSObject {
        var value: Binding<Double>
        var step: Double
        init(value: Binding<Double>, step: Double) { self.value = value; self.step = step }
        @objc func changed(_ slider: UISlider) {
            let stepped = (Double(slider.value) / step).rounded() * step
            slider.value = Float(stepped)
            value.wrappedValue = stepped
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator(value: $value, step: step) }
    
    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider()
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.minimumTrackTintColor = .white
        slider.maximumTrackTintColor = .white
        slider.value = Float(value)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return slider
    }
    
    func updateUIView(_ slider: UISlider, context: Context) {
        context.coordinator.value = $value
        context.coordinator.step = step
        if abs(Double(slider.value) - value) > 0.0001 { slider.value = Float(value) }
    }
}

private struct XelahotToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool
    let onInfo: (String) -> Void
    
    var body: some View {
        ZStack(alignment: .leading) {
            (isOn ? XelahotStyle.rowOn : Color.clear)
            HStack(spacing: 0) {
                Text(title)
                    .font(XelahotStyle.font(15))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.leading, 10)
                Spacer(minLength: 5)
                Button(action: { onInfo(description) }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 40)   // slightly padded hit target
                }
                .padding(.trailing, 8)
            }
        }
        .frame(width: XelahotStyle.panelSize.width, height: 40)
        .overlay(Rectangle().stroke(Color.white, lineWidth: 0.5))
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
    }
}

private struct XelahotPageRow: View {
    let title: String
    let onTap: () -> Void
    
    var body: some View {
        ZStack(alignment: .leading) {
            Color.clear
            HStack(spacing: 0) {
                Text(title)
                    .font(XelahotStyle.font(15))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.leading, 10)
                Spacer(minLength: 5)
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .padding(.trailing, 10)
            }
        }
        .frame(width: XelahotStyle.panelSize.width, height: 40)
        .overlay(Rectangle().stroke(Color.white, lineWidth: 0.5))
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

private struct XelahotSliderRow: View {
    let title: String
    let description: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueText: String
    let onInfo: (String) -> Void
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            Text(title)
                .font(XelahotStyle.font(15))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(height: 35)
                .padding(.leading, 10)
            HStack {
                Spacer()
                Button(action: { onInfo(description) }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                        .frame(width: 15, height: 15)
                }
                .padding(.trailing, 15)
            }
            .padding(.top, 7.5)
            HStack(spacing: 10) {
                XelahotSlider(value: $value, range: range, step: step)
                    .frame(width: 110, height: 20)
                Text(valueText)
                    .font(XelahotStyle.font(15))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            }
            .padding(.leading, 10)
            .padding(.top, 30)
        }
        .frame(width: XelahotStyle.panelSize.width, height: 60)
        .overlay(Rectangle().stroke(Color.white, lineWidth: 0.5))
    }
}

private struct XelahotTextfieldRow: View {
    let title: String
    let description: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    let onInfo: (String) -> Void
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            Text(title)
                .font(XelahotStyle.font(15))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(height: 35)
                .padding(.leading, 10)
            HStack {
                Spacer()
                Button(action: { onInfo(description) }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                        .frame(width: 15, height: 15)
                }
                .padding(.trailing, 15)
            }
            .padding(.top, 7.5)
            // Underline-style field: 0.5pt white bottom rule + a 20pt left tick.
            TextField("", text: $text)
                .font(XelahotStyle.font(14))
                .foregroundColor(.white)
                .accentColor(.white)
                .keyboardType(keyboard)
                .autocorrectionDisabled(true)
                .frame(width: 140, height: 16)
                .padding(.leading, 15)
                .padding(.top, 32)
            Rectangle().fill(Color.white)
                .frame(width: 150, height: 0.5)
                .padding(.leading, 10)
                .padding(.top, 50)
            Rectangle().fill(Color.white)
                .frame(width: 0.5, height: 20)
                .padding(.leading, 9.5)
                .padding(.top, 30)
        }
        .frame(width: XelahotStyle.panelSize.width, height: 60)
        .overlay(Rectangle().stroke(Color.white, lineWidth: 0.5))
    }
}

struct XelahotModMenuPanel: View {
    let title: String
    @Binding var macroInterval: TimeInterval
    @Binding var macroBullets: Int
    @Binding var zoomSliderValue: Double
    @Binding var allowPlayerTeaming: Bool
    @Binding var showGrid: Bool
    @Binding var showSkins: Bool
    @Binding var showFPS: Bool
    @Binding var botSkill: Double
    @Binding var randomizeBotStartMass: Bool
    @Binding var spawnFeedBots: Bool
    @Binding var feedBotName: String
    @Binding var feedBotSkinID: String
    /// Dark mode: inverts the grid colours (shared with the renderer + main menu).
    @AppStorage("macro.darkModeGrid") private var darkModeGrid: Bool = false
    let botSkillLabel: String
    let onClose: () -> Void
    let onHeaderDragChanged: (CGSize) -> Void
    let onHeaderDragEnded: () -> Void
    
    // Page 1 = root, like the base's paged scrollview with a back button on subpages.
    @State private var page: Int = 1
    @State private var infoText: String = ""
    @State private var showInfo = false
    
    private func info(_ text: String) {
        infoText = text
        showInfo = true
    }
    
    private func goTo(_ target: Int) {
        withAnimation(.easeInOut(duration: 0.25)) { page = target }
    }
    
    private var header: some View {
        ZStack {
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white)
                    .frame(width: XelahotStyle.panelSize.width - 100, height: 2)
                    .padding(.top, 4)
                Spacer()
            }
            Text(title)
                .font(XelahotStyle.font(17))
                .foregroundColor(.white)
                .lineLimit(1)
            HStack {
                if page != 1 {
                    Button(action: { goTo(1) }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 20, height: 20)
                    }
                    .padding(.leading, 10)
                    .transition(.opacity)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                }
                .padding(.trailing, 10)
            }
        }
        .frame(width: XelahotStyle.panelSize.width, height: XelahotStyle.headerHeight)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onClose() }
        .gesture(
            DragGesture(coordinateSpace: .global)
                .onChanged { val in onHeaderDragChanged(val.translation) }
                .onEnded { _ in onHeaderDragEnded() }
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(XelahotStyle.green).frame(height: 1.25)
        }
    }
    
    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case 2:   // Macro
            XelahotSliderRow(title: "Fire Interval", description: "Delay between ejected mass shots while the feed button is held.",
                             value: $macroInterval, range: 0.005...0.1, step: 0.005,
                             valueText: String(format: "%.3f s", macroInterval), onInfo: info)
            XelahotSliderRow(title: "Eject Amount", description: "How many bullets one feed tap fires.",
                             value: Binding(get: { Double(macroBullets) },
                                            set: { macroBullets = Int($0.rounded()) }),
                             range: 1...150, step: 1,
                             valueText: "\(macroBullets)", onInfo: info)
        case 3:   // Gameplay
            XelahotSliderRow(title: "Zoom Out Multiplier", description: "Extra camera zoom-out on top of the default view.",
                             value: $zoomSliderValue, range: 1...50, step: 1,
                             valueText: "\(Int(zoomSliderValue))", onInfo: info)
        case 4:   // Bots
            XelahotSliderRow(title: "Bot Skill", description: "Raises bot awareness, reaction speed, aim precision and available advanced mechanics.",
                             value: $botSkill, range: 0.4...1.6, step: 0.1,
                             valueText: botSkillLabel, onInfo: info)
            XelahotToggleRow(title: "Random Bot Mass", description: "Next match starts its bots anywhere from 40 to 10000 mass, like a server already in progress. Bots that die respawn at 40-140.",
                             isOn: $randomizeBotStartMass, onInfo: info)
        case 5:   // Feed Bots
            XelahotToggleRow(title: "Enable Feed Bots", description: "Spawns feeder bots that chase you and pump you with mass.",
                             isOn: $spawnFeedBots, onInfo: info)
            XelahotTextfieldRow(title: "Bot Name", description: "The name shown on your feed bots.",
                                text: $feedBotName, onInfo: info)
            XelahotTextfieldRow(title: "Skin ID (1-387)", description: "Skin number the feed bots wear (1-387).",
                                text: $feedBotSkinID, keyboard: .numberPad, onInfo: info)
        default:  // Root
            XelahotToggleRow(title: "Enable Teaming", description: "Lets a bot pair up with you as a teammate. Turning it off dissolves any active pact.",
                             isOn: $allowPlayerTeaming, onInfo: info)
            XelahotToggleRow(title: "Show Grid", description: "Draws the background grid.",
                             isOn: $showGrid, onInfo: info)
            XelahotToggleRow(title: "Dark Mode", description: "Inverts the grid colors (background + lines).",
                             isOn: $darkModeGrid, onInfo: info)
            XelahotToggleRow(title: "Show Skins", description: "Draws cell skins. Off shows plain colors.",
                             isOn: $showSkins, onInfo: info)
            XelahotToggleRow(title: "Show FPS", description: "Shows the frames-per-second readout.",
                             isOn: $showFPS, onInfo: info)
            XelahotPageRow(title: "Macro") { goTo(2) }
            XelahotPageRow(title: "Gameplay") { goTo(3) }
            XelahotPageRow(title: "Bots") { goTo(4) }
            XelahotPageRow(title: "Feed Bots") { goTo(5) }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    pageContent
                }
                .id(page)
                .transition(.opacity)
            }
        }
        .frame(width: XelahotStyle.panelSize.width, height: XelahotStyle.panelSize.height)
        .background(XelahotStyle.background)
        // The base's green border strips sit fully OUTSIDE the 200x250 frame
        // (top at y = -2.5 etc.), so stroke an inset(-1.25) rect at 2.5pt.
        .overlay(
            Rectangle()
                .inset(by: -1.25)
                .stroke(XelahotStyle.green, lineWidth: 2.5)
        )
        .alert("Description :", isPresented: $showInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(infoText)
        }
    }
}

// MARK: - Main ContentView
struct ContentView: View {
    private let maxPlayerMass: CGFloat = 22500
    /// FFA-style teams coordinate socially; they are not collision-immune. Keeping this true
    /// enables player↔bot and bot↔bot trick-splits, transfers and accidental friendly fire.
    private let teamFriendlyFireEnabled: Bool = true
    
    // Start Menu Modifiable Settings
    @State private var targetBotCount: Int = 25
    @State private var targetFeedBotCount: Int = 15
    @State private var botStartMass: CGFloat = 132
    /// "Randomize Bot Start Mass": the lobby's opening wave of bots spawns anywhere from
    /// 40 to 10,000 mass (skewed toward the low/mid range like a real in-progress server),
    /// while every bot that dies and respawns afterwards re-enters at a fresh-spawn
    /// 40-140. Off = every bot uses the Bot Start Mass slider, exactly as before.
    @State private var randomizeBotStartMass: Bool = false
    /// True while the match's opening bot wave is still filling to targetBotCount; flips
    /// false the moment the lobby is full so later spawns count as respawns.
    @State private var initialBotFillActive: Bool = true
    @State private var playerStartMass: CGFloat = 294
    
    @State private var isPlaying = false
    /// PLAY ONLINE full-screen cover (server-hosted multiplayer).
    /// Offline play below is completely untouched.
    @State private var showOnlinePlay = false
    /// Kept separate from `isPlaying`: the world remains mounted and continues simulating.
    @State private var isLeavePopupPresented = false
    /// Mounting is tracked separately from input blocking. After No commits, gameplay input is
    /// restored immediately while the popup stays mounted (non-hit-testable) purely to finish
    /// its exit animation.
    @State private var leavePopupMounted = false
    @State private var playerCells:[PlayerCell] = []
    @State private var botCells: [PlayerCell] = []
    @State private var animatingEatenCells: [PlayerCell] = []
    /// Food/ejected-mass/token pickups mid magnet-suck into their eater (cosmetic).
    @State private var consumeAnimations: [ConsumedPickupAnimation] = []
    /// Dark mode: keeps the safe-area backdrop in step with the inverted grid.
    @AppStorage("macro.darkModeGrid") private var darkModeGrid: Bool = false
    @State private var smoothedTotalMass: CGFloat = 1300
    @State private var smoothedPlayerPosition: CGPoint = .zero
    /// The camera target is the mass-weighted centre of the player's cells, which jumps
    /// discontinuously the instant a cell is lost (eaten, popped piece consumed). Tracking the
    /// jump in this offset and decaying it keeps the camera glide as smooth as every other
    /// camera behaviour while normal frame-to-frame tracking stays exact.
    @State private var cameraJumpOffset: CGSize = .zero
    @State private var lastCameraTargetPos: CGPoint? = nil
    @State private var lastCameraCellCount: Int = 0
    @State private var selectedSkinName: String? = nil
    @State private var playerName: String = ""
    // League level badges: bots roll theirs at spawn (15%); the player opts in from the menu.
    @State private var botLevels: [UUID: Int] = [:]
    @State private var showPlayerLevel: Bool = false
    @State private var playerLevel: Int = 1
    
    // MOD MENU STATE
    @State private var showModMenu = false
    @State private var modMenuIconOffset: CGSize = .zero
    @State private var lastModMenuIconOffset: CGSize = .zero
    
    @State private var modMenuPanelOffset: CGSize = .zero
    @State private var lastModMenuPanelOffset: CGSize = .zero
    
    // Zoom Value: 1 (normal) to 50 (far away)
    @State private var zoomSliderValue: Double = 1.0 
    @State private var showGrid: Bool = true
    @AppStorage("macro.showSkins") private var showSkins: Bool = true
    @AppStorage("macro.showArrow") private var showArrow: Bool = true
    @AppStorage("macro.showEmojiWidget") private var showEmojiWidget: Bool = true
    @AppStorage("macro.showMinimap") private var showMinimap: Bool = false
    @AppStorage("macro.offlineQuestStage") private var offlineQuestStage: Int = 0
    @AppStorage("macro.offlineQuestProgress") private var offlineQuestProgress: Int = 0
    @State private var allowPlayerTeaming: Bool = true
    @State private var spawnFeedBots: Bool = false
    @State private var feedBotName: String = "Feeder"
    @State private var feedBotSkinID: String = ""
    /// Prevents a disabled feed-bot option from scanning the full bot array every frame.
    @State private var feedBotsWereEnabled: Bool = false
    
    // MANAGERS
    @StateObject private var massManager = EjectedMassManager()
    @StateObject private var foodManager = FoodManager()
    
    var botSkillLabel: String {
        if botSkill < 0.65 { return "Chill" }
        if botSkill < 0.95 { return "Normal" }
        if botSkill < 1.25 { return "Sharp" }
        return "Ruthless"
    }
    
    var totalPlayerMass: CGFloat {
        var total: CGFloat = 0
        for cell in playerCells { total += cell.targetMass }
        return total
    }
    
    /// Top-5 owners by total mass plus the player's own row for the leaderboard HUD
    /// panel. Bots with no skin list as "Unnamed Cell"; the player row shows their
    /// nickname ("You" only when blank; gold row). Feed bots are pellets with a
    /// pulse, not competitors - excluded.
    private func computeLeaderboardRows() -> [LeaderboardHUDRow] {
        var botMass: [UUID: CGFloat] = [:]
        var botLabel: [UUID: String] = [:]
        for cell in botCells where !cell.isFeedBot {
            botMass[cell.ownerID, default: 0] += cell.targetMass
            if botLabel[cell.ownerID] == nil {
                botLabel[cell.ownerID] = cell.skinName == nil ? "Unnamed Cell" : cell.name
            }
        }
        var entries: [(label: String, mass: CGFloat, isPlayer: Bool, ownerID: UUID?)] = botMass.map {
            (botLabel[$0.key] ?? "Unnamed Cell", $0.value, false, $0.key)
        }
        if !playerCells.isEmpty {
            // v5.9.3: the own row lists the actual nickname; "You" only as
            // the blank-name fallback.
            let trimmedName = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
            entries.append((trimmedName.isEmpty ? "You" : trimmedName, totalPlayerMass, true, nil))
        }
        entries.sort { $0.mass > $1.mass }
        // Party = you + recruited teammates while a pact is active. Party rows get
        // the team pfp; party members outside the top 5 earn the below-5th spots.
        let partyActive = playerTeammateOwnerID != nil
        func inParty(_ entry: (label: String, mass: CGFloat, isPlayer: Bool, ownerID: UUID?)) -> Bool {
            partyActive && (entry.isPlayer || entry.ownerID == playerTeammateOwnerID)
        }
        var rows: [LeaderboardHUDRow] = []
        for (index, entry) in entries.prefix(5).enumerated() {
            rows.append(LeaderboardHUDRow(rank: index + 1, name: entry.label,
                                          isPlayer: entry.isPlayer,
                                          isPartyMember: inParty(entry)))
        }
        // Below the top 5: up to 3 spots for party members (you and/or teammates,
        // in rank order). Outside a party this is just your own row, as before.
        var extraSpots = 0
        for (index, entry) in entries.enumerated() where index >= 5 && extraSpots < 3 {
            guard entry.isPlayer || (partyActive && entry.ownerID == playerTeammateOwnerID) else { continue }
            rows.append(LeaderboardHUDRow(rank: index + 1, name: entry.label,
                                          isPlayer: entry.isPlayer,
                                          isPartyMember: inParty(entry)))
            extraSpots += 1
        }
        return rows
    }
    
    var playerCenter: CGPoint {
        var totalMass: CGFloat = 0
        var weightedX: CGFloat = 0
        var weightedY: CGFloat = 0
        for cell in playerCells {
            totalMass += cell.mass
            weightedX += cell.position.x * cell.mass
            weightedY += cell.position.y * cell.mass
        }
        guard totalMass > 0 else { return .zero }
        return CGPoint(x: weightedX / totalMass, y: weightedY / totalMass)
    }
    
    @State private var zoomLevel: CGFloat = 1.0
    @State private var joystickOffset = CGSize.zero
    @State private var joystickBasePosition: CGPoint? = nil
    @State private var joystickIsDragging = false
    @State private var lastJoystickDirection = CGSize.zero
    /// Set by the popup's No action and cleared only by the next world pointer gesture.
    @State private var centerAimUntilCursorMoves = false
    
    @State private var anchorPoint: CGPoint? = nil
    @State private var lastFrameTimestamp: CFTimeInterval = 0
    @State private var frameCount: Int = 0
    @State private var fps: Int = 60
    @State private var lastFpsCheckTime: TimeInterval = 0
    @State private var showFPS: Bool = false
    /// 0.4 (dumb) ... 1.6 (ruthless). Scales bot reaction speed, prediction and split appetite.
    @State private var botSkill: Double = 1.0
    
    // vsync-locked game clock (replaces Timer.publish, unlocks 120Hz ProMotion)
    @StateObject private var displayLink = DisplayLinkDriver()
    
    /// One spatial index shared by the AI, cell collisions and the ejected-mass pass.
    @State private var cellIndex = CellIndex()
    /// Shared local lookups for AI token/virus awareness and flying-mass virus collisions.
    @State private var worldObjectIndex = WorldObjectIndex()
    @State private var tokenIndexDirty: Bool = true
    @State private var virusIndexDirty: Bool = true
    /// World rect currently on screen (+ margin). Used to skip simulation detail you can't see.
    @State private var visibleWorldRect: CGRect = .zero
    
    @State private var tokens: [Token] = []
    @State private var viruses:[Virus] = []
    
    private let baseAnimationFactor: CGFloat = 0.15
    
    @State private var isFeedingHeld: Bool = false
    @State private var feedHoldStartTime: Date? = nil
    private let feedHoldThreshold: TimeInterval = 1.4
    private let spamFeedInterval: TimeInterval = 0.076
    @State private var lastSpamFeedTime: TimeInterval = 0.0
    @State private var feedButtonScale: CGFloat = 1.0
    
    @State private var isMacroHeld: Bool = false
    @State private var macroButtonScale: CGFloat = 1.0
    @State private var lastMacroFeedTime: TimeInterval = 0.0
    @State private var macroInterval: TimeInterval = 0.02
    @State private var macroBullets: Int = 15
    /// Forces fresh raw touch recognizers after the leave modal returns control to the HUD.
    @State private var ejectControlSession: UInt = 0
    
    @State private var highScore: Int = 0
    @State private var tokenCount: Int = 0
    @State private var isGameOverPresented: Bool = false
    @State private var isDeathSequencePending: Bool = false
    @State private var matchStartTime: TimeInterval = 0
    @State private var matchSurvivalSeconds: Int = 0
    @State private var showEmotePicker: Bool = false
    @State private var activeEmoteAsset: String? = nil
    @State private var activeEmoteStartedAt: TimeInterval = 0
    @State private var activeEmoteExpiresAt: TimeInterval = 0
    @State private var emoteCooldownUntil: TimeInterval = 0
    
    // DUAL-WIDTH SKIN eat-triggered swap. Triggers are accepted only in .idle, so anything
    // eaten while the alternate art is showing (or during the return delay) is ignored -
    // swaps can never queue up back-to-back.
    @State private var dualSkinSwapPhase: DualSkinSwapPhase = .idle
    @State private var dualSkinSwapPhaseEndsAt: TimeInterval = 0
    /// When the current swap fired; the renderer derives the overlay fade from this.
    @State private var dualSkinSwapStartedAt: TimeInterval = 0
    
    @State private var pendingBotSplits:[(ownerID: UUID, direction: CGSize)] = []
    /// Splitting does not change owner membership, so these only need updates on spawn/death.
    @State private var regularBotOwners = Set<UUID>()
    @State private var feedBotOwners = Set<UUID>()
    @State private var botVirusCommitments: [UUID: BotVirusCommitment] = [:]
    /// Owner -> the cell it committed to hunting last plan. Humans finish a chase they have
    /// invested in instead of flicking between whichever snack scores best each frame; the
    /// remembered target gets a scoring bonus while the hunt continues.
    @State private var botPreyFocus: [UUID: UUID] = [:]
    /// v8: plan-based utility brain state for classic bots (BotMindBox).
    @State private var botMind = BotMindBox()
    
    // MARK: - TEAMMATE / LOBBY STATE
    // Recruitment is deliberately ephemeral: every new lobby and either partner's death
    // clears it. There is never more than one player teammate.
    @State private var playerTeammateOwnerID: UUID? = nil
    /// The pact now survives the teammate's death: while true, the friend counter reads 0
    /// and the very next regular bot spawn is the same friend re-entering the lobby.
    @State private var teammateRespawnPending: Bool = false
    /// Identity snapshot taken at recruitment, so the respawned friend keeps their name,
    /// skin and league badge across deaths.
    @State private var teammateProfileName: String? = nil
    @State private var teammateProfileSkinName: String? = nil
    @State private var teammateProfileLevel: Int? = nil
    @State private var botAlliancePartners: [UUID: UUID] = [:]
    @State private var recruitmentFeedCounts: [UUID: Int] = [:]
    @State private var recruitmentGestureArmed: Bool = false
    @State private var recruitmentGestureStartedAt: TimeInterval? = nil
    @State private var recruitmentGestureLastSampleAt: TimeInterval? = nil
    @State private var recruitmentLastAngle: CGFloat? = nil
    @State private var recruitmentAbsoluteTurn: CGFloat = 0
    @State private var recruitmentSignedTurn: CGFloat = 0
    
    // The elite teammate reacts to the player's attack, not merely to the current camera.
    @State private var playerLastSplitTime: TimeInterval = -100
    @State private var playerLastSplitDirection: CGSize = .zero
    @State private var playerSplitTargetID: UUID? = nil
    @State private var teammateVirusCommitment: TeamVirusCommitment? = nil
    @State private var teammateVirusRecoveryUntil: TimeInterval = 0
    /// Player-owned ejected mass currently held by the teammate and available to return into
    /// a contested player cell. This is advisory; the real mass remains on the bot cells.
    @State private var teammateReturnCredit: CGFloat = 0
    /// Keeps a bot-overlap handoff alive briefly while the teammate peels into feeding range.
    @State private var teammateOverlapHandoff: TeamOverlapHandoff? = nil
    /// Authentic split-running alternates a catcher and a multi-splitting leader. This state
    /// survives individual AI thinks so the bot completes a burst instead of mirroring one tap.
    @State private var teammateSplitRunState: TeamSplitRunState? = nil
    @State private var teammatePursuitState: TeamPursuitState? = nil
    @State private var teammatePursuitRecoveryUntil: TimeInterval = 0
    /// Explicit teammate order: three full joystick rotations arm it; the third subsequent
    /// player pellet caught by the teammate starts a twelve-second feed-back override.
    @State private var forceFeedGestureArmed: Bool = false
    @State private var forceFeedPelletCount: Int = 0
    @State private var forceFeedGestureStartedAt: TimeInterval? = nil
    @State private var forceFeedGestureLastSampleAt: TimeInterval? = nil
    @State private var forceFeedLastAngle: CGFloat? = nil
    @State private var forceFeedAbsoluteTurn: CGFloat = 0
    @State private var forceFeedSignedTurn: CGFloat = 0
    @State private var teammateForcedFeedUntil: TimeInterval = 0
    
    private var isRunningInPlaygrounds: Bool {
        Bundle.main.bundleIdentifier?.contains("swift-playgrounds-") ?? false
    }
    
    var body: some View {
        // if isRunningInPlaygrounds {
        //      ExportView()
        //     }
        GeometryReader { geometry in
            ZStack {
                Color(hex: darkModeGrid ? 0x000000 : 0xFFFFFF).edgesIgnoringSafeArea(.all)
                
                if isPlaying {
                    GameWorldView(
                        screenSize: CGSize(width: geometry.size.width, height: geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom),
                        smoothedPlayerPosition: $smoothedPlayerPosition,
                        zoomLevel: $zoomLevel,
                        playerCells: $playerCells,
                        botCells: $botCells,
                        animatingEatenCells: $animatingEatenCells,
                        tokens: tokens,
                        foodManager: foodManager,
                        massManager: massManager,
                        viruses: viruses,
                        showGrid: showGrid,
                        showSkins: showSkins,
                        teammateOwnerID: playerTeammateOwnerID,
                        dualSkinSwapShowingSince: dualSkinSwapPhase == .showing ? dualSkinSwapStartedAt : nil,
                        ownerLevels: renderedOwnerLevels,
                        consumeAnimations: consumeAnimations,
                        activeEmoteAsset: activeEmoteAsset,
                        activeEmoteStartedAt: activeEmoteStartedAt,
                        activeEmoteExpiresAt: activeEmoteExpiresAt
                    )
                    .offset(y: -(geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom) / 2)
                    .onAppear(perform: spawnInitialObjects)
                    .zIndex(0)
                } else {
                    MainMenu(
                        isPlaying: $isPlaying, 
                        zoomLevel: $zoomLevel, 
                        selectedSkinName: $selectedSkinName, 
                        playerName: $playerName,
                        showPlayerLevel: $showPlayerLevel,
                        playerLevel: $playerLevel,
                        playerStartMass: $playerStartMass,
                        botStartMass: $botStartMass,
                        randomizeBotStartMass: $randomizeBotStartMass,
                        targetBotCount: $targetBotCount,
                        feedBotCount: $targetFeedBotCount,
                        botSkill: $botSkill,
                        onPlayOnline: { showOnlinePlay = true }
                    )
                }
                
                if isPlaying && !isLeavePopupPresented {
                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onChanged { value in
                                if centerAimUntilCursorMoves {
                                    centerAimUntilCursorMoves = false
                                }
                                if !joystickIsDragging {
                                    joystickBasePosition = value.startLocation
                                    joystickIsDragging = true
                                }
                                let maxDistance: CGFloat = 130 / 2
                                // IPA ControlsWidget::followJoystickToPoint (0x1000ec4a8):
                                // maxDPadDetectionRadiusFactor = 1.7 -> base follows finger past 1.7 * radius.
                                let basePos = joystickBasePosition ?? value.startLocation
                                let dx = value.location.x - basePos.x
                                let dy = value.location.y - basePos.y
                                let distance = sqrt(dx * dx + dy * dy)
                                let followLimit = maxDistance * 1.7
                                if distance > followLimit && distance > 0.001 {
                                    let ux = dx / distance
                                    let uy = dy / distance
                                    joystickBasePosition = CGPoint(
                                        x: value.location.x - ux * followLimit,
                                        y: value.location.y - uy * followLimit
                                    )
                                    joystickOffset = CGSize(width: ux * maxDistance, height: uy * maxDistance)
                                } else if distance > maxDistance && distance > 0.001 {
                                    let ratio = maxDistance / distance
                                    joystickOffset = CGSize(width: dx * ratio, height: dy * ratio)
                                } else {
                                    joystickOffset = CGSize(width: dx, height: dy)
                                }
                                lastJoystickDirection = joystickOffset
                                trackRecruitmentCircle(offset: joystickOffset, now: CACurrentMediaTime())
                                trackForcedFeedCircle(offset: joystickOffset, now: CACurrentMediaTime())
                                anchorPoint = nil
                            }
                            .onEnded { value in
                                finishRecruitmentCircleAttempt()
                                finishForcedFeedCircleAttempt()
                                joystickIsDragging = false
                                joystickBasePosition = nil
                                anchorPoint = playerCenter
                                let isTap = value.translation.width.magnitude < 5 && value.translation.height.magnitude < 5
                                if isTap {
                                    let playerScreenCenter = CGPoint(x: geometry.size.width / 2, y: (geometry.size.height + geometry.safeAreaInsets.top - geometry.safeAreaInsets.bottom) / 2)
                                    lastJoystickDirection = CGSize(width: value.startLocation.x - playerScreenCenter.x, height: value.startLocation.y - playerScreenCenter.y)
                                }
                                joystickOffset = .zero
                            }
                        )
                    
                    if showArrow && lastJoystickDirection != .zero {
                        PlayerArrow(geometry: geometry, joystickIsDragging: joystickIsDragging, joystickOffset: joystickOffset, lastJoystickDirection: lastJoystickDirection, playerCells: playerCells, playerCenter: playerCenter, zoomLevel: $zoomLevel)
                    }
                    if joystickIsDragging {
                        JoystickView(joystickOffset: $joystickOffset, joystickBasePosition: $joystickBasePosition)
                    }
                }
                
                // MARK: - UI OVERLAY (Score, Pause, FPS)
                // Both HUD clusters are now Equatable child views. The game loop touches
                // @State 60-120x/s, which re-evaluated this entire body - buttons, images,
                // gestures and all - every single tick. Now SwiftUI skips them unless a
                // value they actually display changed.
                // The top bar stays MOUNTED (just hidden) while the leave popup is up:
                // unmounting it would reset the leaderboard panel's expansion state,
                // collapsing it after tapping "No".
                if isPlaying {
                    TopBarHUD(score: highScore,
                              tokenCount: tokenCount,
                              fps: fps,
                              showFPS: showFPS,
                              friendCount: playerTeammateOwnerID != nil ? 1 : 0,
                              inParty: playerTeammateOwnerID != nil,
                              leaderboardRows: computeLeaderboardRows(),
                              showEmojiWidget: showEmojiWidget,
                              onPause: { pause() },
                              onEmotes: {
                        SoundManager.shared.play(.menuClick)
                        withAnimation(.easeInOut(duration: 0.15)) { showEmotePicker.toggle() }
                    })
                    .equatable()
                    .zIndex(1)
                    .opacity(isLeavePopupPresented ? 0 : 1)
                    .allowsHitTesting(!isLeavePopupPresented)

                    if showEmotePicker && !isLeavePopupPresented {
                        EmotePickerBar(
                            isOnCooldown: CACurrentMediaTime() < emoteCooldownUntil,
                            onSelect: { asset in
                                let now = CACurrentMediaTime()
                                guard now >= emoteCooldownUntil else { return }
                                SoundManager.shared.play(.menuClick)
                                activeEmoteAsset = asset
                                activeEmoteStartedAt = now
                                activeEmoteExpiresAt = now + 3.0
                                emoteCooldownUntil = now + 3.0
                                withAnimation(.easeInOut(duration: 0.15)) { showEmotePicker = false }
                            }
                        )
                        .zIndex(2)
                    }
                }
                
                if isPlaying && !isLeavePopupPresented {
                    if showMinimap {
                        MinimapHUD(
                            playerPosition: playerCenter,
                            teammatePositions: playerTeammateOwnerID.map { tid in
                                let tCells = botCells.filter { $0.ownerID == tid }
                                guard !tCells.isEmpty else { return [] }
                                let total = tCells.reduce(CGFloat(0)) { $0 + $1.mass }
                                guard total > 0 else { return [] }
                                let x = tCells.reduce(CGFloat(0)) { $0 + $1.position.x * $1.mass } / total
                                let y = tCells.reduce(CGFloat(0)) { $0 + $1.position.y * $1.mass } / total
                                return [CGPoint(x: x, y: y)]
                            } ?? [],
                            worldSize: 11000
                        )
                        .zIndex(1)
                    }

                    // Bottom-center Offline Quest Tracker pill (Hud::setupOfflineHud -> addQuestTrackerWidget)
                    VStack {
                        Spacer()
                        let questTarget = offlineQuestStage == 0 ? 70 : (offlineQuestStage == 1 ? 150 : 300)
                        let shownProgress = min(offlineQuestProgress, questTarget)
                        Text("Eat pellets \(shownProgress)/\(questTarget)")
                            .font(.custom("UbuntuSans-Bold", size: 15))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.45), radius: 1, x: 0, y: 1)
                            .padding(.horizontal, 26)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color(white: 0.78, opacity: 0.52))
                                    .overlay(Capsule().stroke(Color(white: 0.62, opacity: 0.55), lineWidth: 1.5))
                            )
                            .padding(.bottom, 12)
                    }
                    .allowsHitTesting(false)
                    .zIndex(1)

                    ActionButtonsHUD(canSplit: canSplit(),
                                     canFeed: canFeed(),
                                     isFeedingHeld: isFeedingHeld,
                                     feedButtonScale: feedButtonScale,
                                     macroButtonScale: macroButtonScale,
                                     feedHoldThreshold: feedHoldThreshold,
                                     onSplit: { split() },
                                     onMacroDown: {
                        if !isMacroHeld {
                            isMacroHeld = true
                            let pressTime = CACurrentMediaTime()
                            fireMacro()
                            // Backdate the cadence clock by one interval. A
                            // tap still emits exactly the press burst because
                            // onMacroUp clears the held state, while a true
                            // hold receives its first repeat on the very next
                            // display tick instead of waiting.
                            lastMacroFeedTime = pressTime - macroInterval
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { macroButtonScale = 1.15 }
                        }
                    },
                                     onMacroUp: {
                        isMacroHeld = false
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { macroButtonScale = 1.0 }
                    },
                                     onFeedDown: {
                        if !isFeedingHeld {
                            isFeedingHeld = true
                            // This timestamp is now captured by the raw
                            // touch-down gesture. The intentional 1.4-second
                            // threshold remains, but no Button recognizer can
                            // add another delay after the popup is removed.
                            feedHoldStartTime = Date()
                        }
                    },
                                     onFeedUp: {
                        let holdDuration = feedHoldStartTime.map {
                            Date().timeIntervalSince($0)
                        } ?? 0
                        let isTap = holdDuration < feedHoldThreshold
                        isFeedingHeld = false
                        feedHoldStartTime = nil
                        if isTap { feedMass() }
                    })
                    .equatable()
                    .id(ejectControlSession)
                    .zIndex(1)
                }
                
                if isPlaying && !isLeavePopupPresented {
                    // Floating launcher: draggable "mod-menu-btn" asset (the base's menuIcon.png slot).
                    Image("mod-menu-btn")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                        .contentShape(Rectangle())
                        .offset(modMenuIconOffset)
                        .position(x: geometry.size.width - 50, y: 150)
                        .gesture(
                            DragGesture(coordinateSpace: .global)
                                .onChanged { val in
                                    modMenuIconOffset = CGSize(
                                        width: lastModMenuIconOffset.width + val.translation.width,
                                        height: lastModMenuIconOffset.height + val.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastModMenuIconOffset = modMenuIconOffset
                                }
                        )
                        .onTapGesture {
                            // The base fades the menu in/out over 0.5s.
                            withAnimation(.easeInOut(duration: 0.5)) { showModMenu.toggle() }
                        }
                        .zIndex(99)
                    
                    if showModMenu {
                        XelahotModMenuPanel(
                            title: "Mod Menu",
                            macroInterval: $macroInterval,
                            macroBullets: $macroBullets,
                            zoomSliderValue: $zoomSliderValue,
                            allowPlayerTeaming: $allowPlayerTeaming,
                            showGrid: $showGrid,
                            showSkins: $showSkins,
                            showFPS: $showFPS,
                            botSkill: $botSkill,
                            randomizeBotStartMass: $randomizeBotStartMass,
                            spawnFeedBots: $spawnFeedBots,
                            feedBotName: $feedBotName,
                            feedBotSkinID: $feedBotSkinID,
                            botSkillLabel: botSkillLabel,
                            onClose: {
                                withAnimation(.easeInOut(duration: 0.5)) { showModMenu = false }
                            },
                            onHeaderDragChanged: { translation in
                                modMenuPanelOffset = CGSize(
                                    width: lastModMenuPanelOffset.width + translation.width,
                                    height: lastModMenuPanelOffset.height + translation.height
                                )
                            },
                            onHeaderDragEnded: {
                                lastModMenuPanelOffset = modMenuPanelOffset
                            }
                        )
                        .onChange(of: allowPlayerTeaming) { enabled in
                            if !enabled { resetPlayerTeammateState() }
                        }
                        .offset(modMenuPanelOffset)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        .zIndex(100)
                        .transition(.opacity)
                    }
                }
                
                if isPlaying && isGameOverPresented {
                    MatchResultsModalView(
                        highScore: highScore,
                        tokensCollected: tokenCount,
                        survivalSeconds: matchSurvivalSeconds,
                        onPlayAgain: {
                            isGameOverPresented = false
        isDeathSequencePending = false
                            spawnInitialObjects()
                        },
                        onMainMenu: {
                            isGameOverPresented = false
        isDeathSequencePending = false
                            exitMatchToMainMenu()
                        }
                    )
                    .zIndex(1000)
                }
                
                if isPlaying && leavePopupMounted {
                    LeavePopupModal(
                        onNo: { resumeFromLeavePopup() },
                        onNoExitComplete: { leavePopupMounted = false },
                        onYes: { confirmLeaveGame() }
                    )
                    .zIndex(1000)
                }
            }
            .edgesIgnoringSafeArea(.all)
            .fullScreenCover(isPresented: $showOnlinePlay) {
                OnlinePlayView(playerName: $playerName,
                               selectedSkinName: $selectedSkinName,
                               showPlayerLevel: $showPlayerLevel,
                               playerLevel: $playerLevel)
            }
            .onAppear {
                TextSpriteCache.shared.warmUp()
                if isPlaying { displayLink.start() }
            }
            .onDisappear { displayLink.stop() }
            .onChange(of: isPlaying) { playing in
                if playing {
                    lastFrameTimestamp = 0
                    displayLink.start()
                } else {
                    displayLink.stop()
                }
            }
            .onReceive(displayLink.frames) { timestamp in
                guard isPlaying else {
                    lastFrameTimestamp = 0
                    return
                }
                
                // MARK: - GAME TICK
                let currentTime = CACurrentMediaTime()
                if showFPS {
                    if lastFpsCheckTime == 0 {
                        lastFpsCheckTime = currentTime
                        frameCount = 0
                    }
                    frameCount += 1
                    if currentTime - lastFpsCheckTime >= 1.0 {
                        fps = frameCount
                        frameCount = 0
                        lastFpsCheckTime = currentTime
                    }
                } else if frameCount != 0 || lastFpsCheckTime != 0 {
                    frameCount = 0
                    lastFpsCheckTime = 0
                }
                
                var deltaTime: CGFloat = 1.0 / 60.0
                if lastFrameTimestamp > 0 {
                    deltaTime = CGFloat(min(max(timestamp - lastFrameTimestamp, 0.0005), 0.05))
                }
                lastFrameTimestamp = timestamp
                
                updateDualSkinSwap(now: currentTime)
                
                let currTotalPlayerMass = totalPlayerMass
                if currTotalPlayerMass > CGFloat(highScore) { highScore = Int(currTotalPlayerMass) }
                
                spawnBotsIfNeeded()
                if spawnFeedBots {
                    feedBotsWereEnabled = true
                    spawnFeedBotsIfNeeded()
                } else if feedBotsWereEnabled {
                    // Transition-only cleanup, rather than removeAll(where:) across every
                    // split bot on every display-link tick while the toggle is off.
                    botCells.removeAll(where: { $0.isFeedBot })
                    feedBotOwners.removeAll(keepingCapacity: true)
                    feedBotsWereEnabled = false
                    cleanupTeamRelationships()
                }
                
                // Bot split plans are produced from the prior post-movement snapshot. Applying
                // them here removes the old pre-movement index build without changing a
                // rendered object; movement, AI perception and collisions share one fresh
                // snapshot below.
                for splitCmd in pendingBotSplits {
                    executeSplit(on: &botCells, for: splitCmd.ownerID, direction: splitCmd.direction)
                }
                pendingBotSplits.removeAll(keepingCapacity: true)
                
                updateVisibleObjects(screenSize: geometry.size)
                
                movePlayer(dt: deltaTime)
                moveBots(dt: deltaTime)
                let virusesMoved = moveViruses(dt: deltaTime)
                
                updateCellDeformation(dt: deltaTime)
                updateVirusMasses(dt: deltaTime)
                
                handleCellSelfCollisions(cells: &playerCells)
                handleCellSelfCollisions(cells: &botCells)
                
                if tokenIndexDirty {
                    worldObjectIndex.rebuildTokens(tokens)
                    tokenIndexDirty = false
                }
                if virusIndexDirty || virusesMoved {
                    worldObjectIndex.rebuildViruses(viruses)
                    virusIndexDirty = false
                }
                
                // One post-movement snapshot is shared by AI and every collision pass.
                cellIndex.rebuild(playerCells: playerCells, botCells: botCells)
                updateBotAI(dt: deltaTime, index: cellIndex)
                let cellTopologyChanged = handleCellVsCellCollisions(index: cellIndex)
                // Losing the final player cell now exits the match. Do not run the remainder of
                // this display tick against an empty player array while the menu transition is
                // being committed.
                if !isPlaying { return }
                
                updateEatenCellsAnimation(dt: deltaTime)
                
                var foodsEaten = 0
                if playerCells.count < 4 {
                    for index in playerCells.indices {
                        foodsEaten += foodManager.checkCollisions(with: &playerCells[index],
                                                                  onEaten: registerConsumedFood)
                    }
                } else {
                    foodsEaten += foodManager.checkCollisions(
                        with: &playerCells,
                        indices: Array(playerCells.indices),
                        onEaten: registerConsumedFood
                    )
                }
                if !botCells.isEmpty {
                    // V5 grouped every singleton owner into fresh dictionaries every frame,
                    // making the default lobby slower even though there was no overlap to
                    // deduplicate. Pay that setup cost only after the world is genuinely split.
                    let expectedOwners = targetBotCount
                    + (spawnFeedBots ? targetFeedBotCount : 0)
                    let groupingThreshold = expectedOwners + max(8, expectedOwners / 4)
                    if botCells.count <= groupingThreshold {
                        for index in botCells.indices {
                            foodsEaten += foodManager.checkCollisions(with: &botCells[index],
                                                                      onEaten: registerConsumedFood)
                        }
                    } else {
                        var ownerOrder: [UUID] = []
                        var ownerIndices: [UUID: [Int]] = [:]
                        ownerOrder.reserveCapacity(min(botCells.count, max(16, expectedOwners)))
                        ownerIndices.reserveCapacity(min(botCells.count, max(16, expectedOwners)))
                        for index in botCells.indices {
                            let ownerID = botCells[index].ownerID
                            if ownerIndices[ownerID] == nil {
                                ownerOrder.append(ownerID)
                                ownerIndices[ownerID] = []
                            }
                            ownerIndices[ownerID]?.append(index)
                        }
                        for ownerID in ownerOrder {
                            guard let indices = ownerIndices[ownerID] else { continue }
                            if indices.count < 4 {
                                for index in indices {
                                    foodsEaten += foodManager.checkCollisions(
                                        with: &botCells[index],
                                        onEaten: registerConsumedFood
                                    )
                                }
                            } else {
                                foodsEaten += foodManager.checkCollisions(
                                    with: &botCells,
                                    indices: indices,
                                    onEaten: registerConsumedFood
                                )
                            }
                        }
                    }
                }
                if foodsEaten > 0 { foodManager.spawn(count: foodsEaten) }
                
                // Food changes only targetMass. Rebuild indices only when cell eating actually
                // removed/spawned array elements; otherwise the post-movement snapshot remains
                // exact and avoids a third full world hash rebuild on almost every frame.
                if cellTopologyChanged {
                    cellIndex.rebuild(playerCells: playerCells, botCells: botCells)
                }
                handleTokenCollision(index: cellIndex)
                handleVirusCollision(index: cellIndex)
                // Virus collision may remove/respawn viruses, so refresh before flying-mass
                // shots query the shared buckets.
                if virusIndexDirty {
                    worldObjectIndex.rebuildViruses(viruses)
                    virusIndexDirty = false
                }
                performOptimizedMassCollisions(nowTS: currentTime, index: cellIndex)
                
                updateMassAbsorption(dt: deltaTime)
                massManager.update(dt: deltaTime, worldSize: 11000)
                
                updateCellState(cells: &playerCells, dt: deltaTime)
                updateCellState(cells: &botCells, dt: deltaTime)
                
                handleCellMerging(cells: &playerCells, dt: deltaTime)
                handleCellMerging(cells: &botCells, dt: deltaTime)
                
                let targetPos = playerCenter
                // When the cell roster changes, the mass-weighted centre teleports. Bank the
                // teleport into an offset (so this frame renders from the same place as the
                // last one) and let the offset decay smoothly instead of snapping the camera.
                // Splits keep the weighted centre, so their banked offset is ~one frame of
                // ordinary movement - negligible. Normal frames still track exactly as before.
                if playerCells.count != lastCameraCellCount, let previous = lastCameraTargetPos {
                    cameraJumpOffset.width += previous.x - targetPos.x
                    cameraJumpOffset.height += previous.y - targetPos.y
                }
                lastCameraCellCount = playerCells.count
                lastCameraTargetPos = targetPos
                let jumpDecay = getLerpFactor(base: 0.10, dt: deltaTime)
                cameraJumpOffset.width *= (1.0 - jumpDecay)
                cameraJumpOffset.height *= (1.0 - jumpDecay)
                if abs(cameraJumpOffset.width) < 0.05 { cameraJumpOffset.width = 0 }
                if abs(cameraJumpOffset.height) < 0.05 { cameraJumpOffset.height = 0 }
                
                let camSmooth = getLerpFactor(base: 1.0, dt: deltaTime)
                smoothedPlayerPosition.x += (targetPos.x + cameraJumpOffset.width - smoothedPlayerPosition.x) * camSmooth
                smoothedPlayerPosition.y += (targetPos.y + cameraJumpOffset.height - smoothedPlayerPosition.y) * camSmooth
                
                updateCameraZoom(dt: deltaTime)
                
                if !canFeed() {
                    if isFeedingHeld { isFeedingHeld = false }
                    if isMacroHeld { isMacroHeld = false }
                    if feedHoldStartTime != nil { feedHoldStartTime = nil }
                    // Only open an animation transaction when something actually changes.
                    if feedButtonScale != 1.0 || macroButtonScale != 1.0 {
                        withAnimation { feedButtonScale = 1.0; macroButtonScale = 1.0 }
                    }
                } else {
                    if isFeedingHeld,
                       let start = feedHoldStartTime,
                       Date().timeIntervalSince(start) >= feedHoldThreshold {
                        if feedButtonScale != 1.15 {
                            withAnimation { feedButtonScale = 1.15 }
                        }
                        if currentTime - lastSpamFeedTime >= spamFeedInterval { feedMass(); lastSpamFeedTime = currentTime }
                    } else if !isFeedingHeld, feedButtonScale != 1.0 {
                        withAnimation { feedButtonScale = 1.0 }
                    }
                    if isMacroHeld, currentTime - lastMacroFeedTime >= macroInterval {
                        fireMacro(); lastMacroFeedTime = currentTime
                    }
                }
            }
        }.edgesIgnoringSafeArea(.all).statusBar(hidden: true)
    }
    
    // MARK: - TEAMMATE RECRUITMENT / RELATIONSHIPS
    
    private var currentPlayerOwnerID: UUID? {
        return playerCells.first?.ownerID
    }
    
    /// Everything the renderer needs for badges: leveled bots plus the player's opt-in level.
    private var renderedOwnerLevels: [UUID: Int] {
        var levels = botLevels
        if showPlayerLevel, let playerID = currentPlayerOwnerID {
            levels[playerID] = LeagueBadge.clamp(playerLevel)
        }
        return levels
    }
    
    /// Player + recruited bot and the rare bot pairs are the only friendly relationships.
    /// Keeping this owner-based means every split piece inherits the relationship for free.
    private func areOwnersAllied(_ first: UUID, _ second: UUID) -> Bool {
        if first == second { return true }
        
        if allowPlayerTeaming,
           let playerID = currentPlayerOwnerID,
           let teammateID = playerTeammateOwnerID {
            if (first == playerID && second == teammateID)
                || (first == teammateID && second == playerID) {
                return true
            }
        }
        
        return botAlliancePartners[first] == second || botAlliancePartners[second] == first
    }
    
    private func resetRecruitmentMotion() {
        recruitmentGestureStartedAt = nil
        recruitmentGestureLastSampleAt = nil
        recruitmentLastAngle = nil
        recruitmentAbsoluteTurn = 0
        recruitmentSignedTurn = 0
    }
    
    /// A real circular signal must stay outside the joystick dead zone, last at least 500ms,
    /// turn through almost a complete revolution and remain mostly one-directional. That
    /// rejects ordinary steering, zig-zags and a quick flick across the -pi/pi seam.
    private func trackRecruitmentCircle(offset: CGSize, now: TimeInterval) {
        guard allowPlayerTeaming,
              playerTeammateOwnerID == nil,
              !recruitmentGestureArmed else { return }
        
        let magnitude = sqrt(offset.width * offset.width + offset.height * offset.height)
        guard magnitude >= 28 else {
            resetRecruitmentMotion()
            return
        }
        
        if let lastSample = recruitmentGestureLastSampleAt, now - lastSample > 0.24 {
            resetRecruitmentMotion()
        }
        
        if recruitmentGestureStartedAt == nil {
            recruitmentGestureStartedAt = now
        }
        
        let angle = CGFloat(atan2(Double(offset.height), Double(offset.width)))
        if let previous = recruitmentLastAngle {
            var delta = angle - previous
            while delta > CGFloat.pi { delta -= 2 * CGFloat.pi }
            while delta < -CGFloat.pi { delta += 2 * CGFloat.pi }
            
            // Ignore touch jitter while preserving slow, deliberate circles.
            if abs(delta) >= 0.012 {
                recruitmentAbsoluteTurn += abs(delta)
                recruitmentSignedTurn += delta
            }
        }
        
        recruitmentLastAngle = angle
        recruitmentGestureLastSampleAt = now
        
        guard let start = recruitmentGestureStartedAt else { return }
        let duration = now - start
        let consistency = abs(recruitmentSignedTurn) / max(recruitmentAbsoluteTurn, 0.001)
        
        if duration >= 0.50,
           recruitmentAbsoluteTurn >= CGFloat.pi * 1.75,
           abs(recruitmentSignedTurn) >= CGFloat.pi * 1.45,
           consistency >= 0.72 {
            recruitmentGestureArmed = true
            recruitmentFeedCounts.removeAll(keepingCapacity: true)
            resetRecruitmentMotion()
        }
    }
    
    private func finishRecruitmentCircleAttempt() {
        // Once armed, the signal remains valid until one bot has eaten ten pellets. The user
        // asked for an ordered gesture, not a short timeout that could expire mid-feed.
        resetRecruitmentMotion()
    }
    
    private func resetForcedFeedMotion() {
        forceFeedGestureStartedAt = nil
        forceFeedGestureLastSampleAt = nil
        forceFeedLastAngle = nil
        forceFeedAbsoluteTurn = 0
        forceFeedSignedTurn = 0
    }
    
    /// Once a teammate exists, three deliberate same-direction rotations arm a direct order.
    /// It is deliberately separate from the one-rotation recruitment handshake.
    private func trackForcedFeedCircle(offset: CGSize, now: TimeInterval) {
        guard allowPlayerTeaming,
              playerTeammateOwnerID != nil,
              !forceFeedGestureArmed,
              now >= teammateForcedFeedUntil else { return }
        
        let magnitude = hypot(offset.width, offset.height)
        guard magnitude >= 28 else {
            resetForcedFeedMotion()
            return
        }
        
        if let lastSample = forceFeedGestureLastSampleAt, now - lastSample > 0.24 {
            resetForcedFeedMotion()
        }
        if forceFeedGestureStartedAt == nil {
            forceFeedGestureStartedAt = now
        }
        
        let angle = CGFloat(atan2(Double(offset.height), Double(offset.width)))
        if let previous = forceFeedLastAngle {
            var delta = angle - previous
            while delta > CGFloat.pi { delta -= 2 * CGFloat.pi }
            while delta < -CGFloat.pi { delta += 2 * CGFloat.pi }
            if abs(delta) >= 0.012 {
                forceFeedAbsoluteTurn += abs(delta)
                forceFeedSignedTurn += delta
            }
        }
        
        forceFeedLastAngle = angle
        forceFeedGestureLastSampleAt = now
        
        guard let start = forceFeedGestureStartedAt else { return }
        let duration = now - start
        let consistency = abs(forceFeedSignedTurn) / max(forceFeedAbsoluteTurn, 0.001)
        if duration >= 1.0,
           forceFeedAbsoluteTurn >= CGFloat.pi * 5.75,
           abs(forceFeedSignedTurn) >= CGFloat.pi * 5.35,
           consistency >= 0.76 {
            forceFeedGestureArmed = true
            forceFeedPelletCount = 0
            resetForcedFeedMotion()
        }
    }
    
    private func finishForcedFeedCircleAttempt() {
        // Like recruitment, an armed command waits for its pellet confirmation sequence.
        resetForcedFeedMotion()
    }
    
    private func breakBotAlliance(for ownerID: UUID) {
        if let partner = botAlliancePartners.removeValue(forKey: ownerID) {
            botAlliancePartners.removeValue(forKey: partner)
        }
    }
    
    private func resetPlayerTeammateState() {
        playerTeammateOwnerID = nil
        teammateRespawnPending = false
        teammateProfileName = nil
        teammateProfileSkinName = nil
        teammateProfileLevel = nil
        recruitmentGestureArmed = false
        recruitmentFeedCounts.removeAll(keepingCapacity: true)
        resetRecruitmentMotion()
        playerLastSplitTime = -100
        playerLastSplitDirection = .zero
        playerSplitTargetID = nil
        teammateVirusCommitment = nil
        teammateVirusRecoveryUntil = 0
        teammateReturnCredit = 0
        teammateOverlapHandoff = nil
        teammateSplitRunState = nil
        teammatePursuitState = nil
        teammatePursuitRecoveryUntil = 0
        forceFeedGestureArmed = false
        forceFeedPelletCount = 0
        resetForcedFeedMotion()
        teammateForcedFeedUntil = 0
    }
    
    private func resetLobbyTeamState() {
        resetPlayerTeammateState()
        botAlliancePartners.removeAll(keepingCapacity: true)
        botVirusCommitments.removeAll(keepingCapacity: true)
    }
    
    /// Called only when owners can have disappeared, not every frame.
    private func cleanupTeamRelationships() {
        let liveOwners = Set(botCells.map { $0.ownerID })
        
        if let teammateID = playerTeammateOwnerID, !liveOwners.contains(teammateID) {
            // The friend died. Clear every tactical state (they have no cells to command),
            // but keep the party alive: the counter reads 0 until they respawn, and the
            // next regular bot spawn re-enters the lobby as the same friend.
            let keepPact = allowPlayerTeaming && !playerCells.isEmpty
            let savedName = teammateProfileName
            let savedSkin = teammateProfileSkinName
            let savedLevel = teammateProfileLevel
            resetPlayerTeammateState()
            if keepPact {
                teammateRespawnPending = true
                teammateProfileName = savedName
                teammateProfileSkinName = savedSkin
                teammateProfileLevel = savedLevel
            }
        }
        
        var cleanedPartners: [UUID: UUID] = [:]
        cleanedPartners.reserveCapacity(botAlliancePartners.count)
        for (owner, partner) in botAlliancePartners {
            if owner != partner, liveOwners.contains(owner), liveOwners.contains(partner) {
                cleanedPartners[owner] = partner
            }
        }
        botAlliancePartners = cleanedPartners
        
        if !recruitmentFeedCounts.isEmpty {
            var liveCounts: [UUID: Int] = [:]
            liveCounts.reserveCapacity(recruitmentFeedCounts.count)
            for (owner, count) in recruitmentFeedCounts where liveOwners.contains(owner) {
                liveCounts[owner] = count
            }
            recruitmentFeedCounts = liveCounts
        }
    }
    
    /// The tenth player-owned ejected pellet consumed after the circular signal recruits the
    /// entire bot owner (all current and future split pieces). Feed bots are intentionally
    /// excluded: they are a separate mod-menu utility rather than a lobby opponent.
    private func registerRecruitmentPellet(_ mass: EjectedMass, consumedBy consumer: CellSnapshot) {
        guard allowPlayerTeaming,
              recruitmentGestureArmed,
              playerTeammateOwnerID == nil,
              !consumer.isPlayer,
              consumer.isBot,
              !consumer.isFeedBot,
              let playerID = currentPlayerOwnerID,
              mass.ownerID == playerID else { return }
        
        let nextCount = min(10, (recruitmentFeedCounts[consumer.ownerID] ?? 0) + 1)
        recruitmentFeedCounts[consumer.ownerID] = nextCount
        
        guard nextCount >= 10 else { return }
        
        // A bot cannot belong to two teams. A rare bot-pair pact is dissolved when the player
        // completes the explicit recruitment handshake.
        breakBotAlliance(for: consumer.ownerID)
        playerTeammateOwnerID = consumer.ownerID
        // Snapshot the friend's identity so death + respawn brings back the same
        // name, skin and badge instead of dissolving the party.
        teammateRespawnPending = false
        if let member = botCells.first(where: { $0.ownerID == consumer.ownerID }) {
            teammateProfileName = member.name
            teammateProfileSkinName = member.skinName
        }
        teammateProfileLevel = botLevels[consumer.ownerID]
        botVirusCommitments.removeValue(forKey: consumer.ownerID)
        recruitmentGestureArmed = false
        recruitmentFeedCounts.removeAll(keepingCapacity: true)
        resetRecruitmentMotion()
        
        // Force an immediate elite plan instead of waiting on the bot's old solo think timer.
        for i in botCells.indices where botCells[i].ownerID == consumer.ownerID {
            botCells[i].aiThinkTimer = 0
            botCells[i].aiFeedCooldown = 0
            botCells[i].aiSplitCooldown = 0
        }
    }
    
    /// Remember player mass the recruited bot has actually caught. In a contested overlap it
    /// preferentially returns this bank into the player's finishing cell instead of wandering
    /// away with the donation.
    private func registerTeammateMassReceipt(_ mass: EjectedMass,
                                             consumedBy consumer: CellSnapshot) {
        guard allowPlayerTeaming,
              let playerID = currentPlayerOwnerID,
              let teammateID = playerTeammateOwnerID,
              mass.ownerID == playerID,
              consumer.ownerID == teammateID else { return }
        teammateReturnCredit = min(2400, teammateReturnCredit + mass.mass)
    }
    
    private func registerForcedFeedCommandPellet(_ mass: EjectedMass,
                                                 consumedBy consumer: CellSnapshot,
                                                 now: TimeInterval) {
        guard allowPlayerTeaming,
              forceFeedGestureArmed,
              let playerID = currentPlayerOwnerID,
              let teammateID = playerTeammateOwnerID,
              mass.ownerID == playerID,
              consumer.ownerID == teammateID else { return }
        
        forceFeedPelletCount = min(3, forceFeedPelletCount + 1)
        guard forceFeedPelletCount >= 3 else { return }
        
        forceFeedGestureArmed = false
        forceFeedPelletCount = 0
        teammateForcedFeedUntil = now + 12.0
        teammateVirusCommitment = nil
        teammateVirusRecoveryUntil = now + 1.0
        teammateOverlapHandoff = nil
        teammateSplitRunState = nil
        teammatePursuitState = nil
        teammatePursuitRecoveryUntil = now + 1.0
        resetForcedFeedMotion()
        
        for index in botCells.indices where botCells[index].ownerID == teammateID {
            botCells[index].aiThinkTimer = 0
            botCells[index].aiFeedCooldown = 0
        }
    }
    
    /// Roughly 8% of a large lobby may be in two-bot pairs, and each new owner only has an 8%
    /// chance to form one. Everyone else remains solo.
    private func maybeCreateBotAlliance(for newOwnerID: UUID) {
        guard targetBotCount >= 10, playerTeammateOwnerID != newOwnerID else { return }
        
        var maxAlliedOwners = Int(floor(Double(targetBotCount) * 0.08))
        if maxAlliedOwners % 2 != 0 { maxAlliedOwners -= 1 }
        guard maxAlliedOwners >= 2 else { return }
        
        var liveRegularOwners = Set<UUID>()
        for cell in botCells where !cell.isFeedBot {
            liveRegularOwners.insert(cell.ownerID)
        }
        let currentlyAllied = Set(botAlliancePartners.keys.filter { liveRegularOwners.contains($0) })
        guard currentlyAllied.count + 2 <= maxAlliedOwners else { return }
        guard Int.random(in: 0..<100) < 8 else { return }
        
        let candidates = liveRegularOwners.filter {
            $0 != newOwnerID
            && $0 != playerTeammateOwnerID
            && botAlliancePartners[$0] == nil
        }
        guard let partner = candidates.randomElement() else { return }
        
        botAlliancePartners[newOwnerID] = partner
        botAlliancePartners[partner] = newOwnerID
    }
    
    /// Capture the intended target before the player's cells split. A teammate can then tell
    /// an attack split from travel and macro-feed the front player piece only when the target
    /// was genuinely small enough for the launch.
    private func recordPlayerSplitIntent(direction: CGSize, now: TimeInterval) {
        playerLastSplitTime = now
        playerLastSplitDirection = direction.normalized()
        playerSplitTargetID = nil
        
        guard let playerID = currentPlayerOwnerID else { return }
        let launchMass = playerCells.map { $0.targetMass / 2.0 }.max() ?? 0
        guard launchMass >= 20 else { return }
        
        let origin = playerCenter
        var bestScore: CGFloat = -CGFloat.greatestFiniteMagnitude
        
        for other in cellIndex.items {
            if other.ownerID == playerID || areOwnersAllied(playerID, other.ownerID) { continue }
            if launchMass <= other.mass * 1.27 { continue }
            
            let dx = other.x - origin.x
            let dy = other.y - origin.y
            let distance = sqrt(dx * dx + dy * dy)
            if distance < 40 || distance > 1900 { continue }
            
            let dot = (dx / distance) * playerLastSplitDirection.width
            + (dy / distance) * playerLastSplitDirection.height
            if dot < 0.72 { continue }
            
            let score = dot * 2.0 - distance / 1900.0 + min(other.mass / launchMass, 1.0) * 0.35
            if score > bestScore {
                bestScore = score
                playerSplitTargetID = other.id
            }
        }
    }
    
    /// Where a player cell will roughly be a fraction of a second from now: steady joystick
    /// travel plus the decaying split impulse (velocity is stored per-frame at 60 fps, and
    /// decays fast, so only about half its nominal distance is integrated). Ejecting at this
    /// point makes support pellets land ON the receiver instead of trailing in its wake -
    /// the difference between "fed the tricksplit" and "left a snack for the enemy".
    private func predictedFeedPoint(for cell: PlayerCell, lead: CGFloat = 0.22) -> CGPoint {
        var steer: CGSize = .zero
        if joystickIsDragging { steer = lastJoystickDirection.normalized() }
        let travel = cell.cachedMovementSpeed * lead
        let point = CGPoint(
            x: cell.position.x + steer.width * travel + cell.velocity.width * 60 * lead * 0.5,
            y: cell.position.y + steer.height * travel + cell.velocity.height * 60 * lead * 0.5
        )
        return clampToWorld(point, margin: 40)
    }
    
    @inline(__always)
    private func clampToWorld(_ point: CGPoint, margin: CGFloat = 120) -> CGPoint {
        let worldSize: CGFloat = 11000
        return CGPoint(x: min(worldSize - margin, max(margin, point.x)),
                       y: min(worldSize - margin, max(margin, point.y)))
    }
    
    // MARK: - BOT LOGIC
    private func spawnBotsIfNeeded() {
        if regularBotOwners.count < targetBotCount {
            spawnSingleBot()
        } else if initialBotFillActive {
            // Lobby reached its target once: everything from here on is a respawn.
            initialBotFillActive = false
        }
    }
    
    /// Owner membership changes only when an owner is born/dies or feed bots are toggled.
    /// Splits and merges preserve owner IDs, so rebuilding these sets every frame was wasted.
    private func refreshLiveBotOwnerSets() {
        regularBotOwners.removeAll(keepingCapacity: true)
        feedBotOwners.removeAll(keepingCapacity: true)
        for cell in botCells {
            if cell.isFeedBot {
                feedBotOwners.insert(cell.ownerID)
            } else {
                regularBotOwners.insert(cell.ownerID)
            }
        }
        
        let liveOwners = regularBotOwners.union(feedBotOwners)
        // Levels die with their owner; this runs only on owner membership changes.
        if !botLevels.isEmpty {
            botLevels = botLevels.filter { regularBotOwners.contains($0.key) }
        }
        if !botPreyFocus.isEmpty {
            botPreyFocus = botPreyFocus.filter { regularBotOwners.contains($0.key) }
        }
        if !botVirusCommitments.isEmpty {
            var liveCommitments: [UUID: BotVirusCommitment] = [:]
            liveCommitments.reserveCapacity(botVirusCommitments.count)
            for (ownerID, commitment) in botVirusCommitments
            where liveOwners.contains(ownerID) {
                liveCommitments[ownerID] = commitment
            }
            botVirusCommitments = liveCommitments
        }
    }
    
    private func spawnSingleBot() {
        let worldSize: CGFloat = 11000
        let spawnMass: CGFloat
        if randomizeBotStartMass {
            if initialBotFillActive {
                // Opening wave: 40-10000, skewed low/mid (pow 2.3 puts the median near
                // ~2000 with a believable handful of giants) so the lobby looks like a
                // server that has already been running for a while.
                let roll = CGFloat.random(in: 0...1)
                spawnMass = 40 + pow(roll, 2.3) * (10000 - 40)
            } else {
                // Every later spawn is a death respawn: fresh-spawn sized.
                spawnMass = CGFloat.random(in: 40...140)
            }
        } else {
            spawnMass = botStartMass
        }
        let botRadius = sqrt(spawnMass) * 6.3245
        var safePos: CGPoint = .zero
        var found = false
        let pCenter = playerCenter
        let safeDistance = sqrt(totalPlayerMass) * 10
        
        for _ in 0..<10 {
            let x = CGFloat.random(in: botRadius...worldSize-botRadius)
            let y = CGFloat.random(in: botRadius...worldSize-botRadius)
            safePos = CGPoint(x: x, y: y)
            
            let dx = safePos.x - pCenter.x
            let dy = safePos.y - pCenter.y
            let distToPlayer = sqrt(dx*dx + dy*dy)
            if distToPlayer > safeDistance { found = true; break }
        }
        if !found { safePos = CGPoint(x: CGFloat.random(in: 0...worldSize), y: CGFloat.random(in: 0...worldSize)) }
        
        let useSkin = Int.random(in: 1...100) <= 90
        let skinName = useSkin ? String(Int.random(in: 1...387)) : nil
        
        let colors: [Color] = [
            Color(hex: 0xFF0820), Color(hex: 0x0851FF), Color(hex: 0xFF6D08),
            Color(hex: 0x01FFBD), Color(hex: 0xFFCC00), Color(hex: 0x07FF63),
            Color(hex: 0x7B08FF), Color(hex: 0xFF2001), Color(hex: 0xFF08E7)
        ]
        
        let ownerID = UUID()
        // 15% of bots wear an agar.io-style league badge; the level picks the league image.
        if Int.random(in: 1...100) <= 15 {
            botLevels[ownerID] = Int.random(in: 1...150)
        }
        
        // A dead friend rejoins through the normal respawn pipeline: the next regular
        // bot spawned while the pact is pending IS the friend - same name, same skin,
        // same badge - and walks straight back into the player's party.
        let rejoiningTeammate = teammateRespawnPending && allowPlayerTeaming && !playerCells.isEmpty
        let botName: String
        let botSkin: String?
        if rejoiningTeammate {
            botName = teammateProfileName ?? (botNames.randomElement() ?? "Bot")
            botSkin = teammateProfileSkinName
            if let level = teammateProfileLevel {
                botLevels[ownerID] = level
            } else {
                botLevels.removeValue(forKey: ownerID)
            }
        } else {
            botName = botNames.randomElement() ?? "Bot"
            botSkin = skinName
        }
        
        let newBot = PlayerCell(
            ownerID: ownerID,
            position: safePos,
            mass: spawnMass,
            targetMass: spawnMass,
            color: colors.randomElement() ?? .red,
            name: botName,
            skinName: botSkin,
            isBot: true,
            isFeedBot: false
        )
        botCells.append(newBot)
        regularBotOwners.insert(ownerID)
        if rejoiningTeammate {
            playerTeammateOwnerID = ownerID
            teammateRespawnPending = false
        }
        maybeCreateBotAlliance(for: ownerID)
    }
    
    private func spawnFeedBotsIfNeeded() {
        guard spawnFeedBots else { return }
        if feedBotOwners.count < targetFeedBotCount {
            spawnSingleFeedBot()
        }
    }
    
    private func spawnSingleFeedBot() {
        let worldSize: CGFloat = 11000
        let botRadius = sqrt(100.0) * 6.3245
        var safePos: CGPoint = .zero
        var found = false
        let pCenter = playerCenter
        let safeDistance = sqrt(totalPlayerMass) * 10
        
        for _ in 0..<10 {
            let x = CGFloat.random(in: botRadius...worldSize-botRadius)
            let y = CGFloat.random(in: botRadius...worldSize-botRadius)
            safePos = CGPoint(x: x, y: y)
            let dx = safePos.x - pCenter.x
            let dy = safePos.y - pCenter.y
            let distToPlayer = sqrt(dx*dx + dy*dy)
            if distToPlayer > safeDistance { found = true; break }
        }
        if !found { safePos = CGPoint(x: CGFloat.random(in: 0...worldSize), y: CGFloat.random(in: 0...worldSize)) }
        
        let skinName = feedBotSkinID.isEmpty ? nil : feedBotSkinID
        let botMass = CGFloat.random(in: 48...137)
        
        let ownerID = UUID()
        let newBot = PlayerCell(
            ownerID: ownerID,
            position: safePos,
            mass: botMass,
            targetMass: botMass,
            color: Color(hex: 0x01FFBD),
            name: feedBotName,
            skinName: skinName,
            isBot: true,
            isFeedBot: true
        )
        botCells.append(newBot)
        feedBotOwners.insert(ownerID)
    }
    
    // MARK: - BOT BRAIN (rewritten)
    //
    // What was wrong before:
    //  * It was a pure force field: threat, prey and wall vectors were summed every frame
    //    for every bot, and food was only considered when the summed vector was *exactly*
    //    zero - which basically never happened because wall forces are always on. Result:
    //    bots ignored all 4500 pellets and just milled around reacting to each other.
    //  * No idea of split range, so they walked into split kills and never used their own.
    //  * Turning was smoothed with a fixed 0.1 per frame, so their agility depended on fps.
    //  * Every bot behaved identically.
    //
    // Now: each bot plans on its own clock (staggered, ~7-14 plans/sec), perception comes from
    // the shared spatial index, and it picks ONE intent - flee / hunt / forage / regroup /
    // feed - with hysteresis so it commits instead of dithering. Each owner has a stable
    // temperament + weighted skill tier, and `botSkill` in the mod menu scales the whole crew.
    
    /// One shared trajectory generator for human and bot W presses. Keeping spread, travel
    /// variance and convergence here prevents bot feeding from becoming a separate mechanic.
    @discardableResult
    private func emitEjectedMass(from cell: PlayerCell,
                                 aim: MassEjectionAim,
                                 now: TimeInterval,
                                 distanceScale: Double = 1.0) -> Bool {
        let baseDirection: CGSize
        switch aim {
        case .parallel(let direction):
            baseDirection = direction.normalized()
        case .converge(let target):
            baseDirection = CGSize(width: target.x - cell.position.x,
                                   height: target.y - cell.position.y).normalized()
        case .centerConverge(let target):
            let inwardDirection = CGSize(width: target.x - cell.position.x,
                                         height: target.y - cell.position.y).normalized()
            // Off-centre pieces still aim independently inward. Only an exact-centre source,
            // where no geometric direction exists, receives a deterministic visible heading.
            if inwardDirection == .zero {
                baseDirection = CGSize(width: 0, height: 1)
            } else {
                baseDirection = inwardDirection
            }
        }
        guard baseDirection != .zero else { return false }
        
        // One set of pellet physics for EVERYONE. Bots used to get a special low-spread
        // "precise" mode with a computed landing distance, which made their ejected mass
        // visibly behave differently from the player's (no spread, odd travel). Every
        // pellet now uses the player's spread and travel maths, whoever fired it.
        let baseSpread: Double = 0.17
        let referenceRadius: Double = 100
        // The drawn radius follows `mass`, which lags `targetMass` during a fast drain:
        // an insta-speed macro used to fire the whole dump from the still-big rim,
        // landing everything in one short clump, while a slow macro walked the
        // shrinking rim and left a long trail. The pellet still SPAWNS on the drawn
        // rim (visible, and keeps the one-spot burst look), but its travel is trimmed
        // by HALF the drawn rim's overhang over the targetMass rim (flight covers ~2x
        // the nominal travel parameter: speed = travel*5, friction 0.96, stop at 10),
        // so pellet k of a dump LANDS at (targetMass-rim + nominal) at ANY macro speed
        // - equally long trails. Spread also follows the targetMass rim. When the cell
        // is growing (targetMass > mass) the drawn rim stays authoritative for both.
        let solidRadius = min(cell.cachedSolidRadius,
                              sqrt(max(cell.targetMass, 0)) * 6.3245)
        let sizeRatio = referenceRadius
        / max(referenceRadius, Double(solidRadius))
        let dynamicSpread = baseSpread * sqrt(sizeRatio)
        let baseAngle = atan2(Double(baseDirection.height),
                              Double(baseDirection.width))
        let travelAngle = baseAngle + Double.random(in: -dynamicSpread...dynamicSpread)
        let travelDirection = CGSize(width: CGFloat(cos(travelAngle)),
                                     height: CGFloat(sin(travelAngle))).normalized()
        let rimOverhang = cell.cachedSolidRadius - solidRadius
        let travelDistance: CGFloat = max(30, (200 + CGFloat.random(in: -50...50)) * CGFloat(min(1.6, max(0.30, distanceScale))) - rimOverhang * 0.5)
        
        // Physics: the pellet spawns on its spread-rotated drawn-rim spot, flies along
        // the rotated direction and lands where the trail maths above dictate. Only the
        // DRAWN position differs for the first frames: a decaying spawnOffset makes
        // every pellet of a burst appear at the cell's single default eject spot (edge
        // along the raw aim, same rim) and kick out onto its rotated trajectory. Both
        // spots sit on the same rim, so the offset is purely tangential and small - it
        // never stretches the trail radially.
        let edgeDistance = cell.cachedSolidRadius + 1
        let startPosition = CGPoint(
            x: cell.position.x + travelDirection.width * edgeDistance,
            y: cell.position.y + travelDirection.height * edgeDistance
        )
        let defaultSpot = CGPoint(
            x: cell.position.x + baseDirection.width * edgeDistance,
            y: cell.position.y + baseDirection.height * edgeDistance
        )
        let spawnOffset = CGSize(width: defaultSpot.x - startPosition.x,
                                 height: defaultSpot.y - startPosition.y)
        
        massManager.add(position: startPosition,
                        direction: travelDirection,
                        travelDistance: travelDistance,
                        color: cell.color,
                        ownerID: cell.ownerID,
                        sourceCellID: cell.id,
                        borderColor: cell.ejectedMassBorderColor,
                        spawnOffset: spawnOffset,
                        now: now)
        return true
    }
    
    /// Bot equivalent of one or more W presses. Every press emits from EVERY eligible owner
    /// cell with the exact pellet physics the player's control uses (same spread, same
    /// travel) - a player cannot pick which cells fire, so neither can bots. Tactics only
    /// choose cadence and whether the volley is parallel or converges on a receiver.
    /// `reserveMass` prevents suicidal support. A cell sitting exactly on the target simply
    /// emits nothing (zero direction), same as the player's converge behaviour.
    @discardableResult
    private func ejectMassFromBotOwner(_ ownerID: UUID,
                                       toward target: CGPoint,
                                       burstPresses: Int,
                                       reserveMass: CGFloat,
                                       parallelDirection: CGSize? = nil,
                                       centerConverge: Bool = false,
                                       excludeNear: CGPoint? = nil,
                                       onlyNear: CGPoint? = nil,
                                       speedScale: Double = 1.0) -> Int {
        guard burstPresses > 0 else { return 0 }
        
        var ownerIndices: [Int] = []
        ownerIndices.reserveCapacity(16)
        var availableMass: CGFloat = 0
        for i in botCells.indices where botCells[i].ownerID == ownerID {
            availableMass += botCells[i].targetMass
            ownerIndices.append(i)
        }
        // v8 parity with the server: centre-feed is the CONSOLIDATION trick —
        // with a single cell it degenerates into an eject/re-eat loop.
        if centerConverge, ownerIndices.count < 2 { return 0 }
        
        let aim: MassEjectionAim = centerConverge
            ? .centerConverge(target)
            : (parallelDirection.map { .parallel($0) } ?? .converge(target))
        let nowTS = CACurrentMediaTime()
        var emitted = 0
        for _ in 0..<burstPresses {
            let eligible = ownerIndices.filter { idx in
                guard idx < botCells.count && botCells[idx].targetMass >= 32 else { return false }
                if let ex = excludeNear {
                    let dx = botCells[idx].position.x - ex.x, dy = botCells[idx].position.y - ex.y
                    if dx * dx + dy * dy < 4 { return false }
                }
                if let only = onlyNear {
                    let dx = botCells[idx].position.x - only.x, dy = botCells[idx].position.y - only.y
                    if dx * dx + dy * dy >= 4 { return false }
                }
                return true
            }
            guard !eligible.isEmpty else { break }
            
            let roundCost = CGFloat(eligible.count * 16)
            guard availableMass - roundCost >= reserveMass else { break }
            
            var emittedThisPress = 0
            for index in eligible {
                let source = botCells[index]
                if emitEjectedMass(from: source, aim: aim, now: nowTS, distanceScale: speedScale) {
                    botCells[index].targetMass -= 16
                    availableMass -= 16
                    emitted += 1
                    emittedThisPress += 1
                }
            }
            if emittedThisPress == 0 { break }
        }
        return emitted
    }
    
    /// Safe split owners can use one W press from every donor cell toward the strongest cell
    /// nearest their mass-weighted centre. Precise travel makes the pellets settle on that
    /// receiver just after owner immunity expires, so this is real consolidation rather than
    /// decorative feeding past the group.
    @discardableResult
    private func attemptBotCentreConsolidation(brainIndex: Int,
                                               ownerID: UUID,
                                               ownerTotalMass: CGFloat,
                                               ownerCellCount: Int,
                                               groupCentre: CGPoint,
                                               hostileClearance: CGFloat,
                                               skill: CGFloat) -> Bool {
        guard brainIndex < botCells.count,
              ownerCellCount >= 2,
              ownerTotalMass >= 150,
              hostileClearance > max(1250, botCells[brainIndex].cachedVisualRadius * 4.2)
        else { return false }
        
        var receiverIndex: Int? = nil
        var receiverScore = -CGFloat.greatestFiniteMagnitude
        var allMergeEligible = true
        for index in botCells.indices where botCells[index].ownerID == ownerID {
            let cell = botCells[index]
            let centreDistance = hypot(cell.position.x - groupCentre.x,
                                       cell.position.y - groupCentre.y)
            let score = cell.targetMass - centreDistance * 0.045
            if score > receiverScore {
                receiverScore = score
                receiverIndex = index
            }
            if !cell.canMerge { allMergeEligible = false }
        }
        guard let receiverIndex = receiverIndex else { return false }
        let receiver = botCells[receiverIndex]
        
        var farthestDonorDistance: CGFloat = 0
        var hasEligibleDonor = false
        for cell in botCells
        where cell.ownerID == ownerID && cell.id != receiver.id {
            farthestDonorDistance = max(
                farthestDonorDistance,
                hypot(cell.position.x - receiver.position.x,
                      cell.position.y - receiver.position.y)
            )
            if cell.targetMass >= 32 { hasEligibleDonor = true }
        }
        
        botCells[brainIndex].aiMode = .regroup
        botCells[brainIndex].aiFleeing = false
        botCells[brainIndex].aiSteerTarget = clampToWorld(
            receiver.position,
            margin: receiver.cachedVisualRadius * 0.55 + 20
        )
        
        // Once merge timers are open, geometry is faster and lossless. Before then, only own
        // the plan while pieces are genuinely far apart or while a volley is being fired; this
        // prevents consolidation itself from becoming another endless focus.
        if allMergeEligible { return true }
        if farthestDonorDistance >= 1050 { return true }
        guard hasEligibleDonor,
              farthestDonorDistance >= 180,
              botCells[brainIndex].aiFeedCooldown <= 0
        else { return false }
        
        // Recombining is a genuine macro now: skilled owners hammer multi-press volleys at
        // near player-macro cadence into the receiver instead of one polite W every quarter
        // second. Rookies still trickle - cadence and volley size both scale with skill.
        let macroPresses = max(1, min(3, Int(1.0 + skill * 1.4)))
        let fired = ejectMassFromBotOwner(
            ownerID,
            toward: receiver.position,
            burstPresses: macroPresses,
            reserveMass: max(96, ownerTotalMass * 0.58)
        )
        if fired > 0 {
            botCells[brainIndex].aiFeedCooldown = max(0.05, 0.20 - Double(skill) * 0.075)
            return true
        }
        return false
    }
    
    /// A regular bot can lock a virus/target pair and fund the full shot before starting.
    /// Player targets receive a score bonus, so capable bots will genuinely cannon viruses
    /// into the human instead of only using viruses as static obstacles.
    @discardableResult
    private func attemptSoloVirusPlan(brainIndex: Int,
                                      ownerID: UUID,
                                      brain: PlayerCell,
                                      ownerTotalMass: CGFloat,
                                      ownerCellCount: Int,
                                      skill: CGFloat,
                                      preferredTarget: CellSnapshot?,
                                      index: CellIndex,
                                      now: TimeInterval) -> Bool {
        guard brainIndex < botCells.count,
              ownerCellCount <= 12,
              ownerTotalMass >= 230,
              skill >= 0.82,
              !viruses.isEmpty else {
            if botVirusCommitments[ownerID] != nil {
                botVirusCommitments.removeValue(forKey: ownerID)
            }
            return false
        }
        
        var commitment = botVirusCommitments[ownerID]
        if let existing = commitment, existing.expiresAt < now {
            botVirusCommitments.removeValue(forKey: ownerID)
            botCells[brainIndex].aiFeedCooldown = max(
                botCells[brainIndex].aiFeedCooldown,
                0.9
            )
            return false
        }
        if commitment == nil, botCells[brainIndex].aiFeedCooldown > 0 {
            return false
        }
        
        let target: CellSnapshot?
        if let existing = commitment {
            target = index.items.first(where: { $0.id == existing.targetID })
        } else {
            target = preferredTarget
        }
        guard let target = target,
              target.ownerID != ownerID,
              !areOwnersAllied(ownerID, target.ownerID),
              target.mass >= 133,
              target.mass > brain.mass * 0.70 else {
            if botVirusCommitments[ownerID] != nil {
                botVirusCommitments.removeValue(forKey: ownerID)
            }
            return false
        }
        
        // Ordinary bot-vs-bot shots are a personality/skill play; shooting a threatening human
        // is common enough to be visible without turning the whole lobby into synchronized AI.
        if commitment == nil,
           !target.isPlayer,
           brain.aiAggression + skill * 0.20 < 0.92 {
            return false
        }
        
        let predictedTarget = CGPoint(
            x: min(11000, max(0, target.x + target.vx * 16)),
            y: min(11000, max(0, target.y + target.vy * 16))
        )
        var bestShot: (virusIndex: Int, firingPoint: CGPoint, score: CGFloat)? = nil
        
        worldObjectIndex.forEachVirus(
            near: predictedTarget,
            radius: 1550,
            viruses: viruses
        ) { virusIndex, virus in
            if let existing = commitment, virus.id != existing.virusID { return }
            let targetDX = predictedTarget.x - virus.position.x
            let targetDY = predictedTarget.y - virus.position.y
            let targetDistance = hypot(targetDX, targetDY)
            if targetDistance < 250 || targetDistance > 1550 { return }
            
            let shotDirection = CGSize(width: targetDX / targetDistance,
                                       height: targetDY / targetDistance)
            let standOff = virus.radius + brain.cachedVisualRadius + 105
            let firingPoint = CGPoint(
                x: virus.position.x - shotDirection.width * standOff,
                y: virus.position.y - shotDirection.height * standOff
            )
            let margin = brain.cachedVisualRadius * 0.55 + 25
            if firingPoint.x < margin || firingPoint.x > 11000 - margin
                || firingPoint.y < margin || firingPoint.y > 11000 - margin {
                return
            }
            
            let setupDistance = hypot(firingPoint.x - brain.position.x,
                                      firingPoint.y - brain.position.y)
            if setupDistance > 1650 { return }
            var score = targetDistance + setupDistance * 0.62
            if target.isPlayer { score *= 0.74 }
            score -= min(target.mass, 2600) * 0.08
            if bestShot == nil || score < bestShot!.score {
                bestShot = (virusIndex, firingPoint, score)
            }
        }
        
        guard let shot = bestShot, shot.virusIndex < viruses.count else {
            if botVirusCommitments[ownerID] != nil {
                botVirusCommitments.removeValue(forKey: ownerID)
            }
            return false
        }
        let virus = viruses[shot.virusIndex]
        let freshShotsNeeded = max(
            1,
            Int(ceil(Double(max(0, virus.splitThreshold - virus.targetMass) / 16)))
        )
        let shotsRemaining = commitment?.shotsRemaining ?? freshShotsNeeded
        let reserve = max(96, ownerTotalMass * 0.38)
        
        if commitment == nil {
            var projectedMasses = botCells.compactMap { cell -> CGFloat? in
                cell.ownerID == ownerID ? cell.targetMass : nil
            }
            var remaining = shotsRemaining
            var totalCost: CGFloat = 0
            while remaining > 0 {
                let eligible = projectedMasses.indices.filter {
                    projectedMasses[$0] >= 32
                }
                if eligible.isEmpty { break }
                totalCost += CGFloat(eligible.count) * 16
                remaining -= eligible.count
                for sourceIndex in eligible {
                    projectedMasses[sourceIndex] -= 16
                }
            }
            guard remaining <= 0, ownerTotalMass - totalCost >= reserve else {
                return false
            }
            commitment = BotVirusCommitment(
                virusID: virus.id,
                targetID: target.id,
                shotsRemaining: shotsRemaining,
                expiresAt: now + 2.8
            )
        }
        if let commitment = commitment {
            botVirusCommitments[ownerID] = commitment
        }
        
        botCells[brainIndex].aiMode = .teamVirus
        botCells[brainIndex].aiFleeing = false
        botCells[brainIndex].aiSteerTarget = clampToWorld(
            shot.firingPoint,
            margin: brain.cachedVisualRadius * 0.55 + 20
        )
        
        let setupDistance = hypot(shot.firingPoint.x - brain.position.x,
                                  shot.firingPoint.y - brain.position.y)
        if setupDistance < 165, botCells[brainIndex].aiFeedCooldown <= 0 {
            let toVirus = CGSize(width: virus.position.x - brain.position.x,
                                 height: virus.position.y - brain.position.y).normalized()
            let virusToTarget = CGSize(width: target.x - virus.position.x,
                                       height: target.y - virus.position.y).normalized()
            let alignment = toVirus.width * virusToTarget.width
            + toVirus.height * virusToTarget.height
            if alignment > 0.94 {
                let fired = ejectMassFromBotOwner(
                    ownerID,
                    toward: virus.position,
                    burstPresses: 1,
                    reserveMass: reserve
                )
                if fired > 0 {
                    if var liveCommitment = botVirusCommitments[ownerID] {
                        liveCommitment.shotsRemaining -= fired
                        if liveCommitment.shotsRemaining > 0 {
                            botCells[brainIndex].aiFeedCooldown = 0.055
                            botVirusCommitments[ownerID] = liveCommitment
                        } else {
                            botCells[brainIndex].aiFeedCooldown = 0.85
                            botVirusCommitments.removeValue(forKey: ownerID)
                        }
                    }
                }
            }
        }
        return true
    }
    
    /// A virus shot is only worthwhile when (a) the target is large enough to pop, (b) the
    /// team can eat the resulting pieces, (c) a virus has a clean line to the predicted target,
    /// and (d) the teammate can reach a safe firing point behind it.
    private func bestTeamVirusShot(brain: PlayerCell,
                                   teammateTotalMass: CGFloat,
                                   teammateRadius: CGFloat,
                                   index: CellIndex,
                                   lockedVirusID: UUID? = nil,
                                   lockedTargetID: UUID? = nil,
                                   allowDefensive: Bool = false) -> (virusIndex: Int, target: CellSnapshot, firingPoint: CGPoint)? {
        guard let playerID = currentPlayerOwnerID, !viruses.isEmpty else { return nil }
        
        let playerTotal = totalPlayerMass
        let playerLargest = playerCells.map { $0.mass }.max() ?? 0
        let capitalizerMass = max(playerLargest, brain.mass)
        let combinedMass = playerTotal + teammateTotalMass
        let teamCentre = CGPoint(x: (playerCenter.x + brain.position.x) * 0.5,
                                 y: (playerCenter.y + brain.position.y) * 0.5)
        
        var bestPlan: (virusIndex: Int, target: CellSnapshot, firingPoint: CGPoint)? = nil
        var bestScore = CGFloat.greatestFiniteMagnitude
        
        for enemy in index.items {
            if let targetID = lockedTargetID, enemy.id != targetID { continue }
            if enemy.ownerID == playerID || areOwnersAllied(playerID, enemy.ownerID) { continue }
            if enemy.mass < 133 { continue }
            // Offensive pops must be profitable for the duo. A DEFENSIVE pop against a chaser
            // the team cannot outgrow is still worth it: sixteen forced fragments end the
            // chase even when nobody collects them all.
            if !allowDefensive, combinedMass <= enemy.mass * 1.18 { continue }
            // Do not spend seven pellets on something either partner can already eat cleanly.
            if enemy.mass < capitalizerMass * 0.72 { continue }
            // A pop is harmful if neither teammate can collect even typical fragments -
            // unless it is a defensive pop, where a monster splitting into sixteen small,
            // suddenly-eatable pieces is precisely the rescue.
            if !allowDefensive, capitalizerMass <= enemy.mass * 0.28 { continue }
            
            let centreDX = enemy.x - teamCentre.x
            let centreDY = enemy.y - teamCentre.y
            if centreDX * centreDX + centreDY * centreDY > 3_200 * 3_200 { continue }
            
            // Lead a moving/split target modestly; over-leading is worse than a late shot.
            let predicted = CGPoint(x: min(11000, max(0, enemy.x + enemy.vx * 18)),
                                    y: min(11000, max(0, enemy.y + enemy.vy * 18)))
            
            worldObjectIndex.forEachVirus(
                near: predicted,
                radius: 1550,
                viruses: viruses
            ) { virusIndex, virus in
                if let virusID = lockedVirusID, virus.id != virusID { return }
                let vx = predicted.x - virus.position.x
                let vy = predicted.y - virus.position.y
                let targetDistance = sqrt(vx * vx + vy * vy)
                if targetDistance < 260 || targetDistance > 1550 { return }
                
                let shotDirection = CGSize(width: vx / targetDistance, height: vy / targetDistance)
                let standOff = virus.radius + teammateRadius + 110
                let firingPoint = CGPoint(x: virus.position.x - shotDirection.width * standOff,
                                          y: virus.position.y - shotDirection.height * standOff)
                if firingPoint.x < teammateRadius + 20 || firingPoint.x > 11000 - teammateRadius - 20
                    || firingPoint.y < teammateRadius + 20 || firingPoint.y > 11000 - teammateRadius - 20 {
                    return
                }
                
                let botDX = firingPoint.x - brain.position.x
                let botDY = firingPoint.y - brain.position.y
                let botDistance = sqrt(botDX * botDX + botDY * botDY)
                if botDistance > 1800 { return }
                
                // Prefer heavier targets, but never at the expense of a very long setup.
                let score = targetDistance + botDistance * 0.55 - min(enemy.mass, 1800) * 0.12
                if score < bestScore {
                    bestScore = score
                    bestPlan = (virusIndex, enemy, firingPoint)
                }
            }
        }
        return bestPlan
    }
    
    /// Start or continue one locked virus burst. A fresh shot reserves enough mass for every
    /// remaining feed plus 48 mass, then commits to the same virus/target until the launch.
    @discardableResult
    private func attemptTeamVirusPlan(brainIndex: Int,
                                      brain: PlayerCell,
                                      teammateTotalMass: CGFloat,
                                      teammateRadius: CGFloat,
                                      index: CellIndex,
                                      now: TimeInterval,
                                      preferredTargetID: UUID? = nil,
                                      allowDefensive: Bool = false) -> Bool {
        var lockedShot = teammateVirusCommitment
        if lockedShot == nil,
           preferredTargetID == nil,
           now < teammateVirusRecoveryUntil {
            return false
        }
        if let requestedTargetID = preferredTargetID,
           let existing = lockedShot,
           existing.targetID != requestedTargetID {
            // A live contested overlap outranks an older opportunistic shot.
            teammateVirusCommitment = nil
            lockedShot = nil
        }
        guard teammateTotalMass >= 220,
              let shot = bestTeamVirusShot(
                brain: brain,
                teammateTotalMass: teammateTotalMass,
                teammateRadius: teammateRadius,
                index: index,
                lockedVirusID: lockedShot?.virusID,
                lockedTargetID: preferredTargetID ?? lockedShot?.targetID,
                allowDefensive: allowDefensive
              ),
              shot.virusIndex < viruses.count else {
            if teammateVirusCommitment != nil { teammateVirusCommitment = nil }
            return false
        }
        
        let virus = viruses[shot.virusIndex]
        let freshShotsNeeded = max(
            1,
            Int(ceil(Double(max(0, virus.splitThreshold - virus.targetMass) / 16.0)))
        )
        let shotsRemaining = lockedShot?.shotsRemaining ?? freshShotsNeeded
        let safetyReserve = max(96, teammateTotalMass * 0.36)
        var projectedEmitterMasses = botCells.compactMap { cell -> CGFloat? in
            cell.ownerID == brain.ownerID ? cell.targetMass : nil
        }
        let currentVolleyCost = CGFloat(
            projectedEmitterMasses.filter { $0 >= 32 }.count * 16
        )
        var projectedShotsRemaining = shotsRemaining
        var projectedVolleyCost: CGFloat = 0
        while projectedShotsRemaining > 0 {
            let eligibleIndices = projectedEmitterMasses.indices.filter {
                projectedEmitterMasses[$0] >= 32
            }
            if eligibleIndices.isEmpty { break }
            projectedVolleyCost += CGFloat(eligibleIndices.count * 16)
            projectedShotsRemaining -= eligibleIndices.count
            for index in eligibleIndices { projectedEmitterMasses[index] -= 16 }
        }
        let canAffordShot = lockedShot != nil
        ? currentVolleyCost > 0
        && teammateTotalMass >= currentVolleyCost + safetyReserve
        : projectedShotsRemaining <= 0
        && teammateTotalMass >= projectedVolleyCost + safetyReserve
        guard canAffordShot else {
            if teammateVirusCommitment != nil { teammateVirusCommitment = nil }
            return false
        }
        
        if teammateVirusCommitment == nil {
            teammateVirusCommitment = TeamVirusCommitment(
                virusID: virus.id,
                targetID: shot.target.id,
                shotsRemaining: shotsRemaining,
                expiresAt: now + 2.5
            )
        }
        
        let setupDX = shot.firingPoint.x - brain.position.x
        let setupDY = shot.firingPoint.y - brain.position.y
        let setupDistance = hypot(setupDX, setupDY)
        
        botCells[brainIndex].aiMode = .teamVirus
        botCells[brainIndex].aiFleeing = false
        botCells[brainIndex].aiSteerTarget = clampToWorld(
            shot.firingPoint,
            margin: teammateRadius * 0.55 + 20
        )
        
        if setupDistance < 155, botCells[brainIndex].aiFeedCooldown <= 0 {
            let toVirus = CGSize(width: virus.position.x - brain.position.x,
                                 height: virus.position.y - brain.position.y).normalized()
            let virusToTarget = CGSize(width: shot.target.x - virus.position.x,
                                       height: shot.target.y - virus.position.y).normalized()
            let alignment = toVirus.width * virusToTarget.width
            + toVirus.height * virusToTarget.height
            if alignment > 0.94 {
                let fired = ejectMassFromBotOwner(
                    brain.ownerID,
                    toward: virus.position,
                    burstPresses: 1,
                    reserveMass: safetyReserve
                )
                if fired > 0 {
                    botCells[brainIndex].aiFeedCooldown = 0.04
                    if var commitment = teammateVirusCommitment {
                        commitment.shotsRemaining -= fired
                        teammateVirusCommitment = commitment.shotsRemaining > 0
                        ? commitment
                        : nil
                        if commitment.shotsRemaining <= 0 {
                            teammateVirusRecoveryUntil = now + 1.0
                        }
                    }
                }
            }
        }
        return true
    }
    
    /// Number of repeated split presses needed to leave player-catchable pieces, capped at the
    /// practiced two/three-press burst used by real split-runners and by the 16-cell limit.
    private func splitRunBurstCount(brainMass: CGFloat,
                                    teammateCellCount: Int,
                                    teammateTotalMass: CGFloat,
                                    playerLargestMass: CGFloat,
                                    playerTotalMass: CGFloat) -> Int {
        guard brainMass >= 40, teammateCellCount < 16, playerLargestMass > 0 else {
            return 0
        }
        
        var maxPasses = 0
        var projectedCount = max(1, teammateCellCount)
        var projectedPieceMass = brainMass
        while maxPasses < 3,
              projectedCount < 16,
              projectedPieceMass >= 40 {
            projectedCount = min(16, projectedCount * 2)
            projectedPieceMass *= 0.5
            maxPasses += 1
        }
        guard maxPasses > 0 else { return 0 }
        
        var requiredPasses = 1
        var catchableMass = brainMass * 0.5
        while requiredPasses < maxPasses,
              playerLargestMass <= catchableMass * 1.28 {
            requiredPasses += 1
            catchableMass *= 0.5
        }
        guard playerLargestMass > catchableMass * 1.28 else { return 0 }
        
        // A bigger lead can safely lay a longer rotating trail. Near parity uses two presses
        // so neither partner becomes a 16-piece snack without a reason.
        let preferred = teammateTotalMass > playerTotalMass * 1.55 ? 3 : 2
        return min(maxPasses, max(requiredPasses, preferred))
    }
    
    /// Actual split-running is a leapfrog, not "press split whenever the player does":
    /// the catcher eats only trailing pieces, then becomes the leader and lays a rotating
    /// multi-split trail for the other partner. Threat/attack branches cancel this state.
    @discardableResult
    private func planTeamSplitRun(brainIndex: Int,
                                  ownerID: UUID,
                                  brain: PlayerCell,
                                  teammateTotalMass: CGFloat,
                                  teammateCellCount: Int,
                                  playerTotalMass: CGFloat,
                                  playerLargestCell: PlayerCell,
                                  playerCentre: CGPoint,
                                  playerForward: CGSize,
                                  separation: CGFloat,
                                  now: TimeInterval) -> Bool {
        guard brainIndex < botCells.count,
              playerTotalMass + teammateTotalMass >= 200 else {
            teammateSplitRunState = nil
            return false
        }
        
        if separation > 2300 {
            teammateSplitRunState = nil
            return false
        }
        
        var forward = playerForward.normalized()
        if forward == .zero {
            forward = playerLastSplitDirection.normalized()
        }
        if forward == .zero {
            forward = CGSize(width: playerCentre.x - brain.position.x,
                             height: playerCentre.y - brain.position.y).normalized()
        }
        if forward == .zero { forward = CGSize(width: 1, height: 0) }
        
        let splitAge = now - playerLastSplitTime
        let recentTravelSplit = splitAge >= 0
        && splitAge < 2.8
        && playerSplitTargetID == nil
        && playerCells.count > 1
        
        var state = teammateSplitRunState
        
        // A new player travel split always makes the bot the catcher. This also completes the
        // leapfrog after the player splits through a trail the bot offered on the prior phase.
        if recentTravelSplit,
           state == nil || playerLastSplitTime > (state?.lastPlayerSplitAt ?? -100) + 0.005 {
            state = TeamSplitRunState(
                phase: .catchPlayerTrail,
                heading: playerLastSplitDirection.normalized() == .zero
                ? forward
                : playerLastSplitDirection.normalized(),
                turnSign: brain.aiAggression >= 0.625 ? 1 : -1,
                botSplitsRemaining: 0,
                botSplitOrdinal: 0,
                nextBotSplitAt: now,
                phaseStartedAt: now,
                expiresAt: now + 4.2,
                lastPlayerSplitAt: playerLastSplitTime,
                playerPiecesAtStart: playerCells.count,
                botPiecesAtStart: teammateCellCount
            )
        }
        
        // A lead burst now follows a player-initiated travel split and a successful catch.
        // Starting autonomous split-runs from an idle formation made the teammate repeatedly
        // fragment itself and tunnel forward without a live player signal.
        
        guard var run = state else { return false }
        if now > run.expiresAt {
            teammateSplitRunState = nil
            return false
        }
        
        // Follow deliberate steering changes, but never turn the split-run backwards. Forward
        // and shallow circular headings retain momentum; backwards splits destroy it.
        let headingDot = run.heading.width * forward.width + run.heading.height * forward.height
        if headingDot > -0.05 {
            run.heading = CGSize(
                width: run.heading.width * 0.72 + forward.width * 0.28,
                height: run.heading.height * 0.72 + forward.height * 0.28
            ).normalized()
        }
        if run.heading == .zero { run.heading = forward }
        
        if separation > 1550 {
            botCells[brainIndex].aiMode = .teamFormation
            botCells[brainIndex].aiFleeing = false
            botCells[brainIndex].aiSteerTarget = clampToWorld(playerCentre)
            run.expiresAt = max(run.expiresAt, now + 1.0)
            teammateSplitRunState = run
            return true
        }
        
        switch run.phase {
        case .catchPlayerTrail:
            var leadingProjection = -CGFloat.greatestFiniteMagnitude
            var leadingCell = playerLargestCell
            for cell in playerCells {
                let projection = (cell.position.x - playerCentre.x) * run.heading.width
                + (cell.position.y - playerCentre.y) * run.heading.height
                if projection > leadingProjection {
                    leadingProjection = projection
                    leadingCell = cell
                }
            }
            
            var catchTarget: PlayerCell? = nil
            var catchTargetScore = CGFloat.greatestFiniteMagnitude
            var catchTargetDistance = CGFloat.greatestFiniteMagnitude
            var catchNeedsSplit = false
            for cell in playerCells where cell.id != leadingCell.id {
                let projection = (cell.position.x - playerCentre.x) * run.heading.width
                + (cell.position.y - playerCentre.y) * run.heading.height
                // Only take the wake behind the leader; never cross the front and swallow the
                // attacking piece or the player's entire owner.
                if projection > leadingProjection - max(45, cell.cachedVisualRadius * 0.28) {
                    continue
                }
                
                let dx = cell.position.x - brain.position.x
                let dy = cell.position.y - brain.position.y
                let distance = hypot(dx, dy)
                if distance > 1650 { continue }
                
                let canEatNow = brain.targetMass > cell.targetMass * 1.27
                let canEatAfterLaunch = brain.targetMass * 0.5 > cell.targetMass * 1.30
                if !canEatNow && !canEatAfterLaunch { continue }
                
                // Favour a nearby trailing piece and slightly favour the farthest-back piece,
                // which keeps the front player cell intact for the next leap.
                let score = distance + projection * 0.08
                if score < catchTargetScore {
                    catchTargetScore = score
                    catchTargetDistance = distance
                    catchTarget = cell
                    catchNeedsSplit = canEatAfterLaunch
                    && (!canEatNow
                        || distance
                        > brain.cachedVisualRadius
                        + cell.cachedVisualRadius + 420)
                }
            }
            
            botCells[brainIndex].aiMode = .teamSupport
            botCells[brainIndex].aiFleeing = false
            if let target = catchTarget {
                botCells[brainIndex].aiSteerTarget = clampToWorld(target.position)
                
                let direction = CGSize(width: target.position.x - brain.position.x,
                                       height: target.position.y - brain.position.y).normalized()
                let forwardDot = direction.width * run.heading.width
                + direction.height * run.heading.height
                let splitReach = brain.cachedVisualRadius * 3.6 + 190
                if catchNeedsSplit,
                   catchTargetDistance < splitReach,
                   forwardDot > -0.10,
                   teammateCellCount < 8,
                   botCells[brainIndex].aiSplitCooldown <= 0 {
                    pendingBotSplits.append((ownerID: ownerID, direction: direction))
                    botCells[brainIndex].aiSplitCooldown = 0.16
                }
            } else {
                let followPoint = CGPoint(
                    x: leadingCell.position.x
                    - run.heading.width
                    * (leadingCell.cachedVisualRadius + brain.cachedVisualRadius + 90),
                    y: leadingCell.position.y
                    - run.heading.height
                    * (leadingCell.cachedVisualRadius + brain.cachedVisualRadius + 90)
                )
                botCells[brainIndex].aiSteerTarget = clampToWorld(
                    followPoint,
                    margin: brain.cachedVisualRadius * 0.55 + 20
                )
            }
            
            let caughtAPiece = playerCells.count < run.playerPiecesAtStart
            if teammateTotalMass > playerTotalMass * 1.04,
               caughtAPiece || now - run.phaseStartedAt > 1.05 {
                let burstCount = splitRunBurstCount(
                    brainMass: botCells[brainIndex].targetMass,
                    teammateCellCount: teammateCellCount,
                    teammateTotalMass: teammateTotalMass,
                    playerLargestMass: playerLargestCell.targetMass,
                    playerTotalMass: playerTotalMass
                )
                if burstCount > 0 {
                    run.phase = .botLeadBurst
                    run.botSplitsRemaining = burstCount
                    run.botSplitOrdinal = 0
                    run.nextBotSplitAt = now
                    run.phaseStartedAt = now
                    run.expiresAt = now + 3.4
                    run.botPiecesAtStart = teammateCellCount
                }
            }
            
        case .botLeadBurst:
            let side = run.turnSign
            let leadDistance = max(1050,
                                   playerLargestCell.cachedVisualRadius
                                   + brain.cachedVisualRadius + 620)
            let leadPoint = CGPoint(
                x: playerCentre.x + run.heading.width * leadDistance
                - run.heading.height * side * 120,
                y: playerCentre.y + run.heading.height * leadDistance
                + run.heading.width * side * 120
            )
            botCells[brainIndex].aiMode = .teamAttack
            botCells[brainIndex].aiFleeing = false
            botCells[brainIndex].aiSteerTarget = clampToWorld(
                leadPoint,
                margin: brain.cachedVisualRadius * 0.55 + 20
            )
            
            if run.botSplitsRemaining > 0,
               now >= run.nextBotSplitAt,
               teammateCellCount < 16,
               botCells[brainIndex].targetMass >= 40,
               botCells[brainIndex].aiSplitCooldown <= 0 {
                // Three presses describe a forward arc (-24°, 0°, +24°). It creates the
                // circular trail described in split-running guides without ever firing back.
                let angle = (CGFloat(run.botSplitOrdinal) - 1.0) * 0.42 * run.turnSign
                let splitDirection = run.heading.rotated(by: angle)
                pendingBotSplits.append((ownerID: ownerID,
                                         direction: splitDirection))
                botCells[brainIndex].aiSplitCooldown = 0.07
                run.botSplitsRemaining -= 1
                run.botSplitOrdinal += 1
                run.nextBotSplitAt = now + 0.095
                run.expiresAt = now + 3.4
            }
            
            if run.botSplitsRemaining <= 0 {
                run.phase = .offerBotTrail
                run.phaseStartedAt = now
                run.expiresAt = now + 4.0
                run.botPiecesAtStart = max(run.botPiecesAtStart, teammateCellCount)
            }
            
        case .offerBotTrail:
            let leadPoint = CGPoint(
                x: playerCentre.x + run.heading.width
                * (playerLargestCell.cachedVisualRadius + brain.cachedVisualRadius + 470),
                y: playerCentre.y + run.heading.height
                * (playerLargestCell.cachedVisualRadius + brain.cachedVisualRadius + 470)
            )
            botCells[brainIndex].aiMode = .teamFormation
            botCells[brainIndex].aiFleeing = false
            botCells[brainIndex].aiSteerTarget = clampToWorld(
                leadPoint,
                margin: brain.cachedVisualRadius * 0.55 + 20
            )
            
            // The player should take some, not all. Once only the owner’s final cell remains,
            // the existing strong ally-avoidance takes over and the leapfrog safely ends.
            if teammateCellCount == 1
                || playerTotalMass > teammateTotalMass * 1.18 {
                teammateSplitRunState = nil
                return false
            }
        }
        
        teammateSplitRunState = run
        return true
    }
    
    /// Dedicated high-frequency partner brain. It implements the conventions used by strong
    /// FFA Agar teammates: avoid selecting each other as ordinary prey, protect the smaller
    /// partner, keep an attack formation, rebalance mass, split-run, trick-feed the front
    /// attacking piece, and shoot viruses only when the team can capitalize. Collision-level
    /// friendly fire intentionally remains enabled for trick-splits and deliberate transfers.
    private func planPlayerTeammate(brainIndex: Int,
                                    ownerID: UUID,
                                    brain: PlayerCell,
                                    teammateTotalMass: CGFloat,
                                    teammateCentre: CGPoint,
                                    teammateCellCount: Int,
                                    skill: CGFloat,
                                    index: CellIndex,
                                    now: TimeInterval) {
        guard brainIndex < botCells.count,
              allowPlayerTeaming,
              let playerID = currentPlayerOwnerID,
              !playerCells.isEmpty else {
            if brainIndex < botCells.count {
                botCells[brainIndex].aiMode = .forage
                botCells[brainIndex].aiSteerTarget = foodManager.bestFoodCluster(near: brain.position, searchBuckets: 4)
            }
            return
        }
        
        if let commitment = teammateVirusCommitment, commitment.expiresAt < now {
            teammateVirusCommitment = nil
            teammateVirusRecoveryUntil = now + 1.25
        }
        if let handoff = teammateOverlapHandoff, handoff.expiresAt < now {
            teammateOverlapHandoff = nil
        }
        
        let pCentre = playerCenter
        let playerTotal = totalPlayerMass
        let playerLargestCell = playerCells.max(by: { $0.mass < $1.mass }) ?? playerCells[0]
        let playerLargestMass = playerLargestCell.mass
        let brainRadius = brain.cachedVisualRadius
        let splitAge = now - playerLastSplitTime
        let liveJoystickAttack = joystickIsDragging
        && hypot(joystickOffset.width, joystickOffset.height) >= 24
        let recentAttackSplit = splitAge >= 0
        && splitAge < 2.4
        && playerSplitTargetID != nil
        let hasLivePlayerAttackSignal = liveJoystickAttack || recentAttackSplit
        
        // Explicit 3-spin + 3-pellet order. This sits above threat, prey and virus priorities:
        // while active the teammate does nothing except get into a reachable lane and feed the
        // most useful player piece, down to a small last-cell survival reserve.
        if now < teammateForcedFeedUntil {
            teammateSplitRunState = nil
            var receiver = playerLargestCell
            let recentSplitAge = now - playerLastSplitTime
            if recentSplitAge >= 0,
               recentSplitAge < 2.8,
               playerLastSplitDirection != .zero {
                let splitDirection = playerLastSplitDirection.normalized()
                var bestProjection = -CGFloat.greatestFiniteMagnitude
                for cell in playerCells {
                    let projection = (cell.position.x - pCentre.x) * splitDirection.width
                    + (cell.position.y - pCentre.y) * splitDirection.height
                    if projection > bestProjection {
                        bestProjection = projection
                        receiver = cell
                    }
                }
            }
            
            var feedDirection = CGSize(
                width: receiver.position.x - brain.position.x,
                height: receiver.position.y - brain.position.y
            ).normalized()
            if recentSplitAge >= 0,
               recentSplitAge < 2.8,
               playerLastSplitDirection != .zero {
                feedDirection = playerLastSplitDirection.normalized()
            }
            if feedDirection == .zero { feedDirection = CGSize(width: 1, height: 0) }
            
            let stagingPoint = CGPoint(
                x: receiver.position.x
                - feedDirection.width * (receiver.cachedVisualRadius + brainRadius + 120),
                y: receiver.position.y
                - feedDirection.height * (receiver.cachedVisualRadius + brainRadius + 120)
            )
            botCells[brainIndex].aiMode = .feedPlayer
            botCells[brainIndex].aiFleeing = false
            botCells[brainIndex].aiSteerTarget = clampToWorld(
                stagingPoint,
                margin: brainRadius * 0.55 + 20
            )
            
            if botCells[brainIndex].aiFeedCooldown <= 0 {
                let fired = ejectMassFromBotOwner(
                    ownerID,
                    toward: receiver.position,
                    burstPresses: 4,
                    reserveMass: 48
                )
                if fired > 0 {
                    teammateReturnCredit = max(0, teammateReturnCredit - CGFloat(fired) * 16)
                    botCells[brainIndex].aiFeedCooldown = 0.045
                }
            }
            return
        } else if teammateForcedFeedUntil > 0 {
            teammateForcedFeedUntil = 0
        }
        
        let teamMidpoint = CGPoint(x: (pCentre.x + teammateCentre.x) * 0.5,
                                   y: (pCentre.y + teammateCentre.y) * 0.5)
        let separation = hypot(pCentre.x - teammateCentre.x, pCentre.y - teammateCentre.y)
        let perception = min(4300, 2600 + separation * 0.5)
        
        var urgentThreat: CellSnapshot? = nil
        var threatUrgency: CGFloat = 0
        // Which friendly cell the urgent threat is actually bearing down on. Guarding THAT
        // cell (not the owner's centre of mass) is what protects small post-split fragments.
        var threatVictimIsPlayer = false
        var threatVictimIndex = -1
        var nearestHostileDistance = CGFloat.greatestFiniteMagnitude
        var bestPrey: CellSnapshot? = nil
        var bestPreyScore: CGFloat = 0
        var bestPreyBotCanEat = false
        var bestPreyPlayerCanEat = false
        var playerOverlap: (playerIndex: Int, enemy: CellSnapshot,
                            requiredMass: CGFloat, score: CGFloat)? = nil
        var teammateOverlap: (botIndex: Int, enemy: CellSnapshot,
                              requiredMass: CGFloat, score: CGFloat)? = nil
        var playerSupportTarget: (enemy: CellSnapshot,
                                  requiredMass: CGFloat,
                                  score: CGFloat)? = nil
        var playerForward = lastJoystickDirection.normalized()
        if playerForward == .zero {
            playerForward = CGSize(width: playerLargestCell.position.x - brain.position.x,
                                   height: playerLargestCell.position.y - brain.position.y).normalized()
        }
        if playerForward == .zero { playerForward = CGSize(width: 1, height: 0) }
        
        index.forEach(near: teamMidpoint, radius: perception) { other in
            if other.ownerID == playerID || other.ownerID == ownerID
                || areOwnersAllied(ownerID, other.ownerID) {
                return
            }
            
            let botDX = other.x - brain.position.x
            let botDY = other.y - brain.position.y
            let botDistance = max(hypot(botDX, botDY), 1)
            let playerDX = other.x - pCentre.x
            let playerDY = other.y - pCentre.y
            let playerDistance = max(hypot(playerDX, playerDY), 1)
            let nearestDistance = min(botDistance, playerDistance)
            nearestHostileDistance = min(nearestHostileDistance, nearestDistance)
            
            // Player-led cannon/split-kill setup: when the joystick is aimed toward a viable
            // enemy and a modest teammate transfer would cross the required ratio, support the
            // player's piece instead of selecting an unrelated solo chase.
            let attackDX = other.x - playerLargestCell.position.x
            let attackDY = other.y - playerLargestCell.position.y
            let attackDistance = max(hypot(attackDX, attackDY), 1)
            let forwardDot = (attackDX / attackDistance) * playerForward.width
            + (attackDY / attackDistance) * playerForward.height
            if hasLivePlayerAttackSignal,
               forwardDot > 0.55,
               attackDistance < 1600 {
                let playerSplitReach = playerLargestCell.cachedVisualRadius * 3.8 + 220
                let goalMass = attackDistance < playerSplitReach
                ? other.mass * 2.62
                : other.mass * 1.27
                let required = goalMass - playerLargestCell.targetMass
                let transferable = max(0, teammateTotalMass - 64) * 0.72
                if required > 0, required <= transferable {
                    let score = forwardDot * 2.2
                    + min(other.mass, 2400) / (attackDistance + 280)
                    if playerSupportTarget == nil || score > playerSupportTarget!.score {
                        playerSupportTarget = (other, required, score)
                    }
                } else if required <= 0,
                          recentAttackSplit,
                          forwardDot > 0.62,
                          attackDistance < playerSplitReach {
                    // The player already owns the eat ratio and is lunging: stage behind the
                    // launch anyway and drip small top-ups so the attacking piece never
                    // bleeds below the ratio mid-maneuver. Deliberately low score - a real
                    // mass deficit elsewhere still outranks a comfort feed.
                    let score = forwardDot * 0.9
                    + min(other.mass, 2400) / (attackDistance + 280) * 0.5
                    if playerSupportTarget == nil || score > playerSupportTarget!.score {
                        playerSupportTarget = (other, max(32, other.mass * 0.16), score)
                    }
                }
            }
            
            // Detect the deep, near-eat overlaps where a small mass transfer or virus shot
            // decides the fight immediately. Use targetMass for "how much is still needed"
            // so multiple macro bursts do not overspend while visual mass catches up.
            for (playerIndex, cell) in playerCells.enumerated() {
                let dx = other.x - cell.position.x
                let dy = other.y - cell.position.y
                let distance = hypot(dx, dy)
                let deepOverlap = distance < max(cell.cachedSolidRadius, other.solidRadius) * 0.95
                let required = other.mass * 1.27 - cell.targetMass
                if deepOverlap,
                   required > 0,
                   cell.mass >= other.mass * 0.72 {
                    let score = required + distance * 0.04
                    if playerOverlap == nil || score < playerOverlap!.score {
                        playerOverlap = (playerIndex, other, required, score)
                    }
                }
                
                if other.mass > cell.mass * 1.15 {
                    let canSplitKill = other.mass / 2.0 > cell.mass * 1.27
                    let dangerReach = canSplitKill
                    ? other.solidRadius * 4.2 + 260
                    : other.solidRadius + cell.cachedSolidRadius + 380
                    if distance < dangerReach {
                        let urgency = (1.0 - distance / max(dangerReach, 1))
                        * (canSplitKill ? 1.8 : 1.0)
                        * (other.mass / max(cell.mass, 1))
                        if urgency > threatUrgency {
                            threatUrgency = urgency
                            urgentThreat = other
                            threatVictimIsPlayer = true
                            threatVictimIndex = playerIndex
                        }
                    }
                }
            }
            
            for botIndex in botCells.indices where botCells[botIndex].ownerID == ownerID {
                let cell = botCells[botIndex]
                let dx = other.x - cell.position.x
                let dy = other.y - cell.position.y
                let distance = hypot(dx, dy)
                let deepOverlap = distance < max(cell.cachedSolidRadius, other.solidRadius) * 0.95
                let required = other.mass * 1.27 - cell.targetMass
                if deepOverlap,
                   required > 0,
                   cell.mass >= other.mass * 0.72 {
                    let score = required + distance * 0.04
                    if teammateOverlap == nil || score < teammateOverlap!.score {
                        teammateOverlap = (botIndex, other, required, score)
                    }
                }
                
                // The largest owner cell is not a safe proxy for every split piece. Protect
                // vulnerable fragments too; this is what stops a teammate from dragging its
                // tail through a predator while the brain cell is technically safe.
                if other.mass > cell.mass * 1.15 {
                    let canSplitKill = other.mass / 2.0 > cell.mass * 1.27
                    let dangerReach = canSplitKill
                    ? other.solidRadius * 4.2 + 260
                    : other.solidRadius + cell.cachedSolidRadius + 380
                    if distance < dangerReach {
                        let urgency = (1.0 - distance / max(dangerReach, 1))
                        * (canSplitKill ? 1.9 : 1.05)
                        * (other.mass / max(cell.mass, 1))
                        if urgency > threatUrgency {
                            threatUrgency = urgency
                            urgentThreat = other
                            threatVictimIsPlayer = false
                            threatVictimIndex = botIndex
                        }
                    }
                }
            }
            
            let botCanEat = brain.mass > other.mass * 1.27
            let playerCanEat = playerLargestMass > other.mass * 1.27
            if botCanEat || playerCanEat {
                var score = pow(other.mass, 0.58) / (nearestDistance + 180)
                if !botCanEat { score *= 0.70 }
                if other.mass > brain.mass * 0.80,
                   botDistance < playerDistance * 0.85 {
                    score *= 0.42
                }
                if score > bestPreyScore {
                    bestPreyScore = score
                    bestPrey = other
                    bestPreyBotCanEat = botCanEat
                    bestPreyPlayerCanEat = playerCanEat
                }
            }
        }
        
        // A just-escaped teammate is no longer geometrically overlapping on the next think,
        // but still needs a short window to reach a viable firing line back into the player.
        if let liveOverlap = teammateOverlap {
            teammateOverlapHandoff = TeamOverlapHandoff(enemyID: liveOverlap.enemy.id,
                                                        expiresAt: now + 1.6)
        } else if let handoff = teammateOverlapHandoff {
            if let enemy = index.items.first(where: { $0.id == handoff.enemyID }),
               let botIndex = botCells.indices
                .filter({ botCells[$0].ownerID == ownerID })
                .min(by: {
                    let lhsDX = botCells[$0].position.x - enemy.x
                    let lhsDY = botCells[$0].position.y - enemy.y
                    let rhsDX = botCells[$1].position.x - enemy.x
                    let rhsDY = botCells[$1].position.y - enemy.y
                    return lhsDX * lhsDX + lhsDY * lhsDY < rhsDX * rhsDX + rhsDY * rhsDY
                }) {
                let required = max(16, enemy.mass * 1.27 - botCells[botIndex].targetMass)
                teammateOverlap = (botIndex, enemy, required, 0)
            } else {
                teammateOverlapHandoff = nil
            }
        }
        
        if urgentThreat != nil
            || playerOverlap != nil
            || teammateOverlap != nil
            || playerSupportTarget != nil
            || hasLivePlayerAttackSignal {
            if teammatePursuitState != nil {
                teammatePursuitState = nil
                teammatePursuitRecoveryUntil = max(
                    teammatePursuitRecoveryUntil,
                    now + 1.0
                )
            }
        }
        
        // 1a) Classic tricksplit INTO the player. A fresh split aimed straight at the
        // teammate with no enemy in the lane is the human's "give me your mass" gesture:
        // answer by splitting toward the incoming front piece while its launch window is
        // open, so the teammate's flying half lands inside it. Whole-stack transfer in
        // about a second - the move every good duo uses.
        if splitAge >= 0,
           splitAge < 0.95,
           playerLastSplitDirection != .zero,
           playerSplitTargetID == nil,
           separation < 1500,
           teammateCellCount <= 4,
           botCells[brainIndex].aiSplitCooldown <= 0,
           botCells[brainIndex].targetMass >= 76 {
            let splitDirection = playerLastSplitDirection.normalized()
            let towardTeammate = CGSize(width: teammateCentre.x - pCentre.x,
                                        height: teammateCentre.y - pCentre.y).normalized()
            let aimedAtTeammate = splitDirection.width * towardTeammate.width
            + splitDirection.height * towardTeammate.height > 0.82
            
            var frontPiece = playerLargestCell
            var frontProjection = -CGFloat.greatestFiniteMagnitude
            for cell in playerCells {
                let projection = (cell.position.x - pCentre.x) * splitDirection.width
                + (cell.position.y - pCentre.y) * splitDirection.height
                if projection > frontProjection {
                    frontProjection = projection
                    frontPiece = cell
                }
            }
            
            let launchedHalf = botCells[brainIndex].targetMass * 0.5
            if aimedAtTeammate, frontPiece.targetMass > launchedHalf * 1.30 {
                let intercept = CGSize(width: frontPiece.position.x - brain.position.x,
                                       height: frontPiece.position.y - brain.position.y).normalized()
                if intercept != .zero {
                    teammateSplitRunState = nil
                    botCells[brainIndex].aiMode = .teamSupport
                    botCells[brainIndex].aiFleeing = false
                    botCells[brainIndex].aiSteerTarget = clampToWorld(frontPiece.position)
                    pendingBotSplits.append((ownerID: ownerID, direction: intercept))
                    botCells[brainIndex].aiSplitCooldown = 1.2
                    return
                }
            }
        }
        
        // 1) Trick-feed immediately after a genuine attack split. Travel splits deliberately
        // fall through to the alternating split-run state machine below; never mirror a tap.
        if playerOverlap == nil,
           teammateOverlap == nil,
           splitAge >= 0,
           splitAge < 2.40,
           playerLastSplitDirection != .zero {
            let direction = playerLastSplitDirection.normalized()
            var leadingCell = playerCells[0]
            var leadingProjection = -CGFloat.greatestFiniteMagnitude
            for cell in playerCells {
                let projection = (cell.position.x - pCentre.x) * direction.width
                + (cell.position.y - pCentre.y) * direction.height
                if projection > leadingProjection {
                    leadingProjection = projection
                    leadingCell = cell
                }
            }
            
            var liveTarget: CellSnapshot? = nil
            if let targetID = playerSplitTargetID {
                liveTarget = index.items.first(where: { $0.id == targetID })
            }
            if liveTarget == nil {
                liveTarget = playerSupportTarget?.enemy
            }
            let validAttack = liveTarget.map {
                !areOwnersAllied(playerID, $0.ownerID)
                && leadingCell.targetMass + teammateTotalMass * 0.55 > $0.mass * 1.27
            } ?? false
            // The split target often dies (or gets consumed by the launch itself) within the
            // first second; the attack is still live and the front piece still wants mass.
            // Keep supporting through that window instead of instantly standing down.
            let attackStillWarm = playerSplitTargetID != nil && splitAge < 1.6
            
            if validAttack || attackStillWarm {
                teammateSplitRunState = nil
                let side: CGFloat = brain.aiAggression >= 0.625 ? 1 : -1
                let leadRadius = leadingCell.cachedVisualRadius
                let supportPoint = CGPoint(
                    x: leadingCell.position.x
                    - direction.width * (leadRadius + brainRadius + 120)
                    - direction.height * side * 85,
                    y: leadingCell.position.y
                    - direction.height * (leadRadius + brainRadius + 120)
                    + direction.width * side * 85
                )
                botCells[brainIndex].aiMode = .teamSupport
                botCells[brainIndex].aiSteerTarget = clampToWorld(
                    supportPoint,
                    margin: brainRadius * 0.55 + 20
                )
                botCells[brainIndex].aiFleeing = false
                
                let toLeadX = leadingCell.position.x - brain.position.x
                let toLeadY = leadingCell.position.y - brain.position.y
                let distanceToLead = hypot(toLeadX, toLeadY)
                
                if distanceToLead < 950,
                   botCells[brainIndex].aiFeedCooldown <= 0,
                   teammateTotalMass > max(96, playerTotal * 0.16) {
                    let reserve = max(112, teammateTotalMass * 0.42)
                    // Feed the point the attacking piece is flying TOWARD; pellets aimed at
                    // its current position land in the wake of a split launch.
                    let fired = ejectMassFromBotOwner(
                        ownerID,
                        toward: predictedFeedPoint(for: leadingCell),
                        burstPresses: 4,
                        reserveMass: reserve
                    )
                    if fired > 0 {
                        botCells[brainIndex].aiFeedCooldown = 0.035
                    }
                }
                
                let liveBrainMass = botCells[brainIndex].targetMass
                let safeOriginalDistance = max(
                    60,
                    leadRadius - brainRadius * 0.22 + 60
                )
                let canDonateSplitPiece = teammateCellCount == 1
                && liveBrainMass >= 96
                && leadingCell.targetMass > (liveBrainMass * 0.5) * 1.28
                && distanceToLead > safeOriginalDistance
                && distanceToLead < leadRadius + brainRadius + 620
                if canDonateSplitPiece,
                   botCells[brainIndex].aiSplitCooldown <= 0 {
                    let donationDirection = CGSize(width: toLeadX,
                                                   height: toLeadY).normalized()
                    if donationDirection != .zero {
                        pendingBotSplits.append((ownerID: ownerID,
                                                 direction: donationDirection))
                        botCells[brainIndex].aiSplitCooldown = 1.0
                    }
                }
                return
            }
        }
        
        // 2) Player is deeply over an enemy but just under the eat ratio. Prefer a targeted
        // virus if the teammate can safely fund it; otherwise collect any player-owned W mass
        // nearby and macro-return it into that exact contested player piece.
        if let overlap = playerOverlap, overlap.playerIndex < playerCells.count {
            teammateSplitRunState = nil
            let contestedPlayer = playerCells[overlap.playerIndex]
            if attemptTeamVirusPlan(brainIndex: brainIndex,
                                    brain: brain,
                                    teammateTotalMass: teammateTotalMass,
                                    teammateRadius: brainRadius,
                                    index: index,
                                    now: now,
                                    preferredTargetID: overlap.enemy.id) {
                return
            }
            
            if teammateReturnCredit < 16,
               let donatedPile = massManager.nearestStaticMassPosition(
                near: brain.position,
                radius: 1100,
                ownerID: playerID
               ) {
                botCells[brainIndex].aiMode = .teamSupport
                botCells[brainIndex].aiFleeing = false
                botCells[brainIndex].aiSteerTarget = clampToWorld(donatedPile)
                return
            }
            
            let awayFromEnemy = CGSize(
                width: contestedPlayer.position.x - overlap.enemy.x,
                height: contestedPlayer.position.y - overlap.enemy.y
            ).normalized()
            let safeAway = awayFromEnemy == .zero ? CGSize(width: 1, height: 0) : awayFromEnemy
            let stagingPoint = CGPoint(
                x: contestedPlayer.position.x
                + safeAway.width * (contestedPlayer.cachedVisualRadius + brainRadius + 110),
                y: contestedPlayer.position.y
                + safeAway.height * (contestedPlayer.cachedVisualRadius + brainRadius + 110)
            )
            botCells[brainIndex].aiMode = .teamSupport
            botCells[brainIndex].aiFleeing = false
            botCells[brainIndex].aiSteerTarget = clampToWorld(
                stagingPoint,
                margin: brainRadius * 0.55 + 20
            )
            
            let playerDistance = hypot(contestedPlayer.position.x - brain.position.x,
                                       contestedPlayer.position.y - brain.position.y)
            if playerDistance < 950, botCells[brainIndex].aiFeedCooldown <= 0 {
                let pelletsNeeded = max(1, Int(ceil(Double(overlap.requiredMass / 16.0))) + 1)
                let pressesNeeded = max(
                    1,
                    Int(ceil(Double(pelletsNeeded) / Double(max(1, teammateCellCount))))
                )
                let creditedReserve = max(48, teammateTotalMass - teammateReturnCredit)
                let reserve = teammateReturnCredit >= 16
                ? creditedReserve
                : max(96, teammateTotalMass * 0.42)
                let fired = ejectMassFromBotOwner(
                    ownerID,
                    toward: contestedPlayer.position,
                    burstPresses: min(4, pressesNeeded),
                    reserveMass: reserve
                )
                if fired > 0 {
                    teammateReturnCredit = max(0, teammateReturnCredit - CGFloat(fired) * 16)
                    botCells[brainIndex].aiFeedCooldown = 0.032
                }
            }
            return
        }
        
        // 3) The teammate is the cell caught in the same near-eat overlap. Hand mass to the
        // player while peeling away, making the player the finisher/virus shooter instead of
        // sacrificing the bot's last owner cell into the enemy.
        if let overlap = teammateOverlap, overlap.botIndex < botCells.count {
            teammateSplitRunState = nil
            let contestedBot = botCells[overlap.botIndex]
            let playerFinisher = playerCells.max {
                let lhsDistance = hypot($0.position.x - overlap.enemy.x,
                                        $0.position.y - overlap.enemy.y)
                let rhsDistance = hypot($1.position.x - overlap.enemy.x,
                                        $1.position.y - overlap.enemy.y)
                let lhsScore = $0.targetMass - lhsDistance * 0.03
                let rhsScore = $1.targetMass - rhsDistance * 0.03
                return lhsScore < rhsScore
            } ?? playerLargestCell
            
            let escape = CGSize(width: contestedBot.position.x - overlap.enemy.x,
                                height: contestedBot.position.y - overlap.enemy.y).normalized()
            let escapeDirection = escape == .zero
            ? CGSize(width: brain.position.x - overlap.enemy.x,
                     height: brain.position.y - overlap.enemy.y).normalized()
            : escape
            botCells[brainIndex].aiMode = .teamSupport
            botCells[brainIndex].aiFleeing = true
            botCells[brainIndex].aiSteerTarget = clampToWorld(
                CGPoint(x: pCentre.x + escapeDirection.width * (brainRadius + 240),
                        y: pCentre.y + escapeDirection.height * (brainRadius + 240)),
                margin: brainRadius * 0.55 + 20
            )
            
            let distanceToPlayer = hypot(playerFinisher.position.x - brain.position.x,
                                         playerFinisher.position.y - brain.position.y)
            if distanceToPlayer < 1050, botCells[brainIndex].aiFeedCooldown <= 0 {
                let playerNeed = max(16, overlap.enemy.mass * 1.27 - playerFinisher.targetMass)
                let pelletsNeeded = max(1, Int(ceil(Double(playerNeed / 16.0))) + 1)
                let pressesNeeded = max(
                    1,
                    Int(ceil(Double(pelletsNeeded) / Double(max(1, teammateCellCount))))
                )
                let fired = ejectMassFromBotOwner(
                    ownerID,
                    toward: playerFinisher.position,
                    burstPresses: min(4, pressesNeeded),
                    reserveMass: max(96, teammateTotalMass * 0.45)
                )
                if fired > 0 {
                    teammateReturnCredit = max(0, teammateReturnCredit - CGFloat(fired) * 16)
                    botCells[brainIndex].aiFeedCooldown = 0.035
                }
            }
            return
        }
        
        // 4) Save either partner before looking for an attractive attack.
        if let threat = urgentThreat {
            teammateSplitRunState = nil
            let botDX = threat.x - brain.position.x
            let botDY = threat.y - brain.position.y
            let botDistance = max(hypot(botDX, botDY), 1)
            let playerDX = threat.x - pCentre.x
            let playerDY = threat.y - pCentre.y
            let playerDistance = max(hypot(playerDX, playerDY), 1)
            
            // If the teammate can remove the threat safely, counter-split instead of fleeing.
            let counterReach = brainRadius * 3.5 + 180
            if brain.mass / 2.0 > threat.mass * 1.30,
               botDistance < counterReach,
               teammateCellCount < 8,
               botCells[brainIndex].aiSplitCooldown <= 0 {
                let attackDirection = CGSize(width: botDX / botDistance, height: botDY / botDistance)
                botCells[brainIndex].aiMode = .teamAttack
                botCells[brainIndex].aiSteerTarget = clampToWorld(CGPoint(x: threat.x, y: threat.y))
                pendingBotSplits.append((ownerID: ownerID, direction: attackDirection))
                botCells[brainIndex].aiSplitCooldown = 0.95
                return
            }
            
            // Neither partner can simply eat the chaser: try to dismantle it with a virus
            // before conceding ground. A committed volley into a virus sitting in front of a
            // big chaser both ends the chase and opens the pieces up for the player.
            if threat.mass > playerLargestMass * 1.15,
               threat.mass > brain.mass * 1.15,
               botDistance < 1900 || playerDistance < 1900,
               attemptTeamVirusPlan(brainIndex: brainIndex,
                                    brain: brain,
                                    teammateTotalMass: teammateTotalMass,
                                    teammateRadius: brainRadius,
                                    index: index,
                                    now: now,
                                    preferredTargetID: threat.id,
                                    allowDefensive: true) {
                return
            }
            
            // A player fragment is the endangered cell: guard THAT cell, not the owner's
            // centre of mass. The teammate hovers between the enemy and the fragment as a
            // body the enemy must deal with first, and when the fragment itself is starving
            // it pumps emergency mass straight into it - the duo wins by keeping the main
            // player alive and dominant, not by the teammate hoarding its own mass.
            if threatVictimIsPlayer,
               threatVictimIndex >= 0,
               threatVictimIndex < playerCells.count {
                let victim = playerCells[threatVictimIndex]
                var guardDirection = CGSize(width: threat.x - victim.position.x,
                                            height: threat.y - victim.position.y).normalized()
                if guardDirection == .zero { guardDirection = CGSize(width: 1, height: 0) }
                
                if brain.mass > threat.mass * 0.82 {
                    // Big enough that the enemy cannot cheaply eat through: body-block the
                    // lane between the chaser and the fragment.
                    let guardPoint = CGPoint(
                        x: victim.position.x
                        + guardDirection.width * (victim.cachedVisualRadius + brainRadius + 30),
                        y: victim.position.y
                        + guardDirection.height * (victim.cachedVisualRadius + brainRadius + 30)
                    )
                    botCells[brainIndex].aiMode = .teamFormation
                    botCells[brainIndex].aiFleeing = false
                    botCells[brainIndex].aiSteerTarget = clampToWorld(
                        guardPoint,
                        margin: brainRadius * 0.55 + 20
                    )
                } else {
                    // Too small to block: hold the escape lane just ahead of the fragment so
                    // rescue pellets land in its path instead of behind it.
                    let escapePoint = CGPoint(
                        x: victim.position.x
                        - guardDirection.width * (victim.cachedVisualRadius + brainRadius + 170),
                        y: victim.position.y
                        - guardDirection.height * (victim.cachedVisualRadius + brainRadius + 170)
                    )
                    botCells[brainIndex].aiMode = .teamSupport
                    botCells[brainIndex].aiFleeing = false
                    botCells[brainIndex].aiSteerTarget = clampToWorld(
                        escapePoint,
                        margin: brainRadius * 0.55 + 20
                    )
                }
                
                // Self-feed sacrifice: danger plus a mass deficit is exactly when the
                // teammate gives its stack away, down to a small survival reserve.
                let victimDistance = hypot(victim.position.x - brain.position.x,
                                           victim.position.y - brain.position.y)
                let playerNeedsMass = victim.targetMass * 1.27 < threat.mass * 1.05
                || playerTotal < teammateTotalMass * 0.85
                if playerNeedsMass,
                   victimDistance < 1100,
                   botCells[brainIndex].aiFeedCooldown <= 0 {
                    let fired = ejectMassFromBotOwner(
                        ownerID,
                        toward: predictedFeedPoint(for: victim),
                        burstPresses: 4,
                        reserveMass: max(64, teammateTotalMass * 0.22)
                    )
                    if fired > 0 {
                        teammateReturnCredit = max(0, teammateReturnCredit - CGFloat(fired) * 16)
                        botCells[brainIndex].aiFeedCooldown = 0.04
                    }
                }
                return
            }
            
            if playerLargestMass > threat.mass * 1.27, playerDistance < 1250 {
                // Tuck behind the larger player; it becomes a mobile shield while keeping the
                // teammate close enough to return mass after the danger passes.
                let away = CGSize(width: -playerDX / playerDistance, height: -playerDY / playerDistance)
                botCells[brainIndex].aiMode = .teamFormation
                botCells[brainIndex].aiSteerTarget = clampToWorld(
                    CGPoint(x: pCentre.x + away.width * (brainRadius + 180),
                            y: pCentre.y + away.height * (brainRadius + 180))
                )
            } else if brain.mass > threat.mass * 1.27, playerDistance < botDistance {
                // Screen a smaller player by putting the larger teammate between both cells.
                let towardThreat = CGSize(width: playerDX / playerDistance, height: playerDY / playerDistance)
                botCells[brainIndex].aiMode = .teamFormation
                botCells[brainIndex].aiSteerTarget = clampToWorld(
                    CGPoint(x: pCentre.x + towardThreat.width * (brainRadius + 140),
                            y: pCentre.y + towardThreat.height * (brainRadius + 140))
                )
            } else {
                let fleeDirection = CGSize(width: -botDX / botDistance, height: -botDY / botDistance)
                botCells[brainIndex].aiMode = .flee
                botCells[brainIndex].aiFleeing = true
                botCells[brainIndex].aiSteerTarget = clampToWorld(
                    CGPoint(x: brain.position.x + fleeDirection.width * 1450,
                            y: brain.position.y + fleeDirection.height * 1450)
                )
            }
            return
        }
        
        // 4b) Take-my-pieces: the player steering INTO the teammate while eatable
        // fragments sit within reach is the standard "eat these" handoff. Sit ON the
        // offered piece instead of politely orbiting it - collision-level friendly fire
        // is the transfer mechanism, and ally-avoidance only guards the last bot cell
        // against LARGER player cells, so small fragments go down cleanly.
        if playerCells.count > 1, liveJoystickAttack {
            let towardTeammate = CGSize(width: teammateCentre.x - pCentre.x,
                                        height: teammateCentre.y - pCentre.y).normalized()
            let steerDot = playerForward.width * towardTeammate.width
            + playerForward.height * towardTeammate.height
            if steerDot > 0.60 {
                var offered: PlayerCell? = nil
                var offeredDistance = CGFloat.greatestFiniteMagnitude
                for cell in playerCells where cell.id != playerLargestCell.id {
                    guard brain.targetMass > cell.targetMass * 1.32 else { continue }
                    let distance = hypot(cell.position.x - brain.position.x,
                                         cell.position.y - brain.position.y)
                    if distance < brainRadius + cell.cachedVisualRadius + 320,
                       distance < offeredDistance {
                        offeredDistance = distance
                        offered = cell
                    }
                }
                if let piece = offered {
                    teammateSplitRunState = nil
                    botCells[brainIndex].aiMode = .teamSupport
                    botCells[brainIndex].aiFleeing = false
                    botCells[brainIndex].aiSteerTarget = clampToWorld(piece.position, margin: 30)
                    return
                }
            }
        }
        
        // 5) Player-led cannon / split-kill support outranks opportunistic virus play or a bot
        // chase. Stage behind the player's largest piece and transfer only the amount needed.
        if let support = playerSupportTarget {
            teammateSplitRunState = nil
            let attackDirection = CGSize(
                width: support.enemy.x - playerLargestCell.position.x,
                height: support.enemy.y - playerLargestCell.position.y
            ).normalized()
            let safeDirection = attackDirection == .zero
            ? playerForward
            : attackDirection
            let stagingPoint = CGPoint(
                x: playerLargestCell.position.x
                - safeDirection.width
                * (playerLargestCell.cachedVisualRadius + brainRadius + 120),
                y: playerLargestCell.position.y
                - safeDirection.height
                * (playerLargestCell.cachedVisualRadius + brainRadius + 120)
            )
            botCells[brainIndex].aiMode = .teamSupport
            botCells[brainIndex].aiFleeing = false
            botCells[brainIndex].aiSteerTarget = clampToWorld(
                stagingPoint,
                margin: brainRadius * 0.55 + 20
            )
            
            if botCells[brainIndex].aiFeedCooldown <= 0 {
                let pelletsNeeded = max(
                    1,
                    Int(ceil(Double(support.requiredMass / 16.0)))
                )
                let pressesNeeded = max(
                    1,
                    Int(ceil(Double(pelletsNeeded) / Double(max(1, teammateCellCount))))
                )
                let fired = ejectMassFromBotOwner(
                    ownerID,
                    toward: predictedFeedPoint(for: playerLargestCell),
                    burstPresses: min(4, pressesNeeded),
                    reserveMass: max(112, teammateTotalMass * 0.42)
                )
                if fired > 0 {
                    // A real deficit is hammered at macro cadence; comfort top-ups are a
                    // slow drip so support never degenerates into pellet spam.
                    botCells[brainIndex].aiFeedCooldown =
                    support.requiredMass > 48 ? 0.05 : 0.50
                }
            }
            
            let distanceToReceiver = hypot(
                playerLargestCell.position.x - brain.position.x,
                playerLargestCell.position.y - brain.position.y
            )
            let liveBrainMass = botCells[brainIndex].targetMass
            let safeOriginalDistance = max(
                60,
                playerLargestCell.cachedVisualRadius - brainRadius * 0.22 + 60
            )
            if teammateCellCount == 1,
               liveBrainMass >= 96,
               playerLargestCell.targetMass > (liveBrainMass * 0.5) * 1.28,
               distanceToReceiver > safeOriginalDistance,
               distanceToReceiver
                < playerLargestCell.cachedVisualRadius + brainRadius + 620,
               botCells[brainIndex].aiSplitCooldown <= 0 {
                let donationDirection = CGSize(
                    width: playerLargestCell.position.x - brain.position.x,
                    height: playerLargestCell.position.y - brain.position.y
                ).normalized()
                if donationDirection != .zero {
                    pendingBotSplits.append((ownerID: ownerID,
                                             direction: donationDirection))
                    botCells[brainIndex].aiSplitCooldown = 1.0
                }
            }
            return
        }
        
        // 5b) The player ejecting a trail of W mass at the teammate is the other explicit
        // gift gesture. Walk the pile down and actually eat it (building return credit)
        // instead of ignoring it. Only piles clearly closer to the bot than to the player
        // count, so a self-feed or recombine volley is never stolen.
        if nearestHostileDistance > 850,
           let giftPile = massManager.nearestStaticMassPosition(near: brain.position,
                                                                radius: 950,
                                                                ownerID: playerID) {
            let pileToPlayer = hypot(giftPile.x - pCentre.x, giftPile.y - pCentre.y)
            let pileToBot = hypot(giftPile.x - brain.position.x, giftPile.y - brain.position.y)
            if pileToBot < pileToPlayer * 0.9 {
                teammateSplitRunState = nil
                botCells[brainIndex].aiMode = .forage
                botCells[brainIndex].aiFleeing = false
                botCells[brainIndex].aiSteerTarget = clampToWorld(giftPile, margin: 40)
                return
            }
        }
        
        // 6) Between engagements, pull a fragmented owner back through a precise centre macro.
        // This makes a strong receiver before the teammate volunteers for another chase.
        if !hasLivePlayerAttackSignal,
           attemptBotCentreConsolidation(
            brainIndex: brainIndex,
            ownerID: ownerID,
            ownerTotalMass: teammateTotalMass,
            ownerCellCount: teammateCellCount,
            groupCentre: teammateCentre,
            hostileClearance: nearestHostileDistance,
            skill: skill
           ) {
            teammateSplitRunState = nil
            return
        }
        
        // 7) Committed seven-feed virus shot only while both partners are still in the play.
        if separation < 1450,
           attemptTeamVirusPlan(brainIndex: brainIndex,
                                brain: brain,
                                teammateTotalMass: teammateTotalMass,
                                teammateRadius: brainRadius,
                                index: index,
                                now: now) {
            teammateSplitRunState = nil
            return
        }
        
        // 8) Coordinated hunts have both a distance envelope and a short progress budget. A
        // target that is not getting closer is released instead of owning the teammate forever.
        let splitRunOwnsTravel = teammateSplitRunState != nil
        || (splitAge >= 0 && splitAge < 2.8 && playerSplitTargetID == nil)
        var pursuitAllowed = false
        var pursuitBotDistance: CGFloat = 0
        var pursuitPlayerDistance: CGFloat = 0
        if let prey = bestPrey, !hasLivePlayerAttackSignal {
            pursuitBotDistance = hypot(prey.x - brain.position.x,
                                       prey.y - brain.position.y)
            pursuitPlayerDistance = hypot(prey.x - pCentre.x,
                                          prey.y - pCentre.y)
            let geometryIsSafe = separation < 1125
            && pursuitBotDistance < 1500
            && pursuitPlayerDistance < 1550
            && (bestPreyBotCanEat
                || (bestPreyPlayerCanEat
                    && pursuitPlayerDistance < pursuitBotDistance * 1.20))
            && (!splitRunOwnsTravel
                || pursuitBotDistance < brainRadius * 3.5 + 170)
            
            if geometryIsSafe, now >= teammatePursuitRecoveryUntil {
                if var pursuit = teammatePursuitState {
                    if pursuit.targetID == prey.id {
                        if pursuitBotDistance < pursuit.bestDistance - 85 {
                            pursuit.bestDistance = pursuitBotDistance
                            pursuit.lastProgressAt = now
                        }
                        let expired = now - pursuit.startedAt > 2.6
                        let stalled = now - pursuit.lastProgressAt > 0.90
                        if !expired && !stalled {
                            pursuitAllowed = true
                            teammatePursuitState = pursuit
                        } else {
                            teammatePursuitState = nil
                            teammatePursuitRecoveryUntil = now + 1.5
                        }
                    } else {
                        teammatePursuitState = nil
                        teammatePursuitRecoveryUntil = now + 1.0
                    }
                } else {
                    teammatePursuitState = TeamPursuitState(
                        targetID: prey.id,
                        startedAt: now,
                        bestDistance: pursuitBotDistance,
                        lastProgressAt: now
                    )
                    pursuitAllowed = true
                }
            } else if teammatePursuitState != nil {
                teammatePursuitState = nil
                teammatePursuitRecoveryUntil = now + 1.2
            }
        } else if teammatePursuitState != nil {
            teammatePursuitState = nil
            teammatePursuitRecoveryUntil = now + 1.0
        }
        
        if pursuitAllowed, let prey = bestPrey {
            teammateSplitRunState = nil
            let botDX = prey.x - brain.position.x
            let botDY = prey.y - brain.position.y
            let botDistance = max(pursuitBotDistance, 1)
            let playerDistance = pursuitPlayerDistance
            let splitReach = (brainRadius * 3.5 + 170) * min(1.25, skill)
            
            if bestPreyBotCanEat,
               brain.mass / 2.0 > prey.mass * 1.30,
               botDistance < splitReach,
               teammateCellCount < 8,
               botCells[brainIndex].aiSplitCooldown <= 0 {
                botCells[brainIndex].aiMode = .teamAttack
                botCells[brainIndex].aiSteerTarget = clampToWorld(CGPoint(x: prey.x, y: prey.y))
                pendingBotSplits.append((
                    ownerID: ownerID,
                    direction: CGSize(width: botDX / botDistance, height: botDY / botDistance)
                ))
                botCells[brainIndex].aiSplitCooldown = 0.92
                return
            }
            
            if !bestPreyBotCanEat, bestPreyPlayerCanEat {
                // The player owns the eat ratio; flank from behind instead of walking a bot
                // that the prey can consume directly into the same target.
                let preyDirection = CGSize(width: (prey.x - pCentre.x) / max(playerDistance, 1),
                                           height: (prey.y - pCentre.y) / max(playerDistance, 1))
                let side: CGFloat = brain.aiAggression > 0.62 ? 1 : -1
                botCells[brainIndex].aiMode = .teamSupport
                botCells[brainIndex].aiSteerTarget = clampToWorld(
                    CGPoint(
                        x: pCentre.x - preyDirection.width
                        * (playerLargestCell.cachedVisualRadius + brainRadius + 90)
                        - preyDirection.height * side * 190,
                        y: pCentre.y - preyDirection.height
                        * (playerLargestCell.cachedVisualRadius + brainRadius + 90)
                        + preyDirection.width * side * 190
                    )
                )
            } else {
                botCells[brainIndex].aiMode = .teamAttack
                botCells[brainIndex].aiSteerTarget = clampToWorld(CGPoint(x: prey.x, y: prey.y))
            }
            botCells[brainIndex].aiFleeing = false
            return
        }
        
        // 8b) Virus farming: with the owner already fragmented to 14+ pieces a virus is
        // (nearly) free +100 mass - the pop can only shed a piece or two, and at 16 it
        // sheds none. Real duos hoover viruses between fights exactly like this.
        if teammateCellCount >= 14,
           brain.targetMass >= 150,
           nearestHostileDistance > 1100 {
            var nearestVirus: CGPoint? = nil
            var nearestVirusDistance: CGFloat = 1300
            worldObjectIndex.forEachVirus(near: brain.position,
                                          radius: 1300,
                                          viruses: viruses) { _, virus in
                let distance = hypot(virus.position.x - brain.position.x,
                                     virus.position.y - brain.position.y)
                if distance < nearestVirusDistance {
                    nearestVirusDistance = distance
                    nearestVirus = virus.position
                }
            }
            if let virusMeal = nearestVirus {
                teammateSplitRunState = nil
                botCells[brainIndex].aiMode = .forage
                botCells[brainIndex].aiFleeing = false
                botCells[brainIndex].aiSteerTarget = clampToWorld(virusMeal, margin: 30)
                return
            }
        }
        
        // 9) With no fight to resolve, run the real alternating leader/catcher cycle. This
        // replaces routine W-tax transfers; split-feeding is faster and conserves mass.
        if planTeamSplitRun(
            brainIndex: brainIndex,
            ownerID: ownerID,
            brain: brain,
            teammateTotalMass: teammateTotalMass,
            teammateCellCount: teammateCellCount,
            playerTotalMass: playerTotal,
            playerLargestCell: playerLargestCell,
            playerCentre: pCentre,
            playerForward: playerForward,
            separation: separation,
            now: now
        ) {
            return
        }
        
        // 10) Human-like formation between engagements.
        var forward = lastJoystickDirection.normalized()
        if forward == .zero {
            forward = CGSize(width: pCentre.x - brain.position.x,
                             height: pCentre.y - brain.position.y).normalized()
        }
        if forward == .zero { forward = CGSize(width: 1, height: 0) }
        
        let side: CGFloat = brain.aiAggression >= 0.625 ? 1 : -1
        let botIsLeader = teammateCellCount == 1
        && liveJoystickAttack
        && teammateTotalMass > playerTotal * 1.45
        let formationClearance = playerLargestCell.cachedVisualRadius + brainRadius + 125
        let longitudinal: CGFloat = botIsLeader ? formationClearance : -formationClearance
        let lateral: CGFloat = min(250, formationClearance * 0.32) * side
        // While the player is split, bias the escort toward the smallest fragment: hovering
        // near the vulnerable bits deters opportunists before anyone enters true danger range.
        var formationAnchor = pCentre
        if playerCells.count > 1,
           let smallest = playerCells.min(by: { $0.mass < $1.mass }) {
            formationAnchor = CGPoint(x: (pCentre.x + smallest.position.x) * 0.5,
                                      y: (pCentre.y + smallest.position.y) * 0.5)
        }
        let formationPoint = CGPoint(
            x: formationAnchor.x + forward.width * longitudinal - forward.height * lateral,
            y: formationAnchor.y + forward.height * longitudinal + forward.width * lateral
        )
        
        botCells[brainIndex].aiMode = .teamFormation
        botCells[brainIndex].aiFleeing = false
        botCells[brainIndex].aiSteerTarget = clampToWorld(formationPoint,
                                                          margin: brainRadius * 0.55 + 20)
        
        // Quiet-time mass balancing: when the teammate is sitting on a clearly larger stack
        // with no hostiles around, trickle it down toward the player so the PLAYER is always
        // the one loaded for the next tricksplit. Slow single presses with hysteresis
        // (enter above 1.5x, the reserve floor releases back to ~1.25x) - this is deliberate
        // rebalancing toward the carry, not the old routine W-tax spam.
        if !botIsLeader,
           teammateTotalMass > playerTotal * 1.5,
           nearestHostileDistance > 1000,
           separation < 1150,
           botCells[brainIndex].aiFeedCooldown <= 0 {
            let fired = ejectMassFromBotOwner(
                ownerID,
                toward: predictedFeedPoint(for: playerLargestCell),
                burstPresses: 1,
                reserveMass: max(160, playerTotal * 1.25)
            )
            if fired > 0 {
                teammateReturnCredit = max(0, teammateReturnCredit - CGFloat(fired) * 16)
                botCells[brainIndex].aiFeedCooldown = 0.22
            }
        }
    }
    
    // MARK: - v8 BotMind methods (client port — keep in lockstep with server)

    private func botMindPersona(for brain: PlayerCell, oid: UUID, skill: CGFloat) -> BotMindBox.Persona {
        let u = oid.uuid
        let seed = UInt64(u.0) | (UInt64(u.1) << 8) | (UInt64(u.2) << 16) | (UInt64(u.3) << 24)
                 | (UInt64(u.4) << 32) | (UInt64(u.5) << 40) | (UInt64(u.6) << 48) | (UInt64(u.7) << 56)
        let baseTier: Int
        switch brain.aiSkillTier {
        case .rookie: baseTier = 0
        case .casual: baseTier = 1
        case .skilled: baseTier = 2
        case .expert: baseTier = 3
        case .elite: baseTier = 4
        }
        // The lobby slider raises actual competence, not merely reaction
        // speed. Normal guarantees core mechanics; Ruthless guarantees elite.
        let floorTier = skill >= 1.45 ? 4 : skill >= 1.20 ? 3
                      : skill >= 0.90 ? 2 : skill >= 0.65 ? 1 : 0
        let tier = max(baseTier, floorTier)
        return BotMindBox.makePersona(seed: seed, tier: tier,
                                      aggression: Double(brain.aiAggression),
                                      caution: Double(brain.aiCaution),
                                      skill: Double(skill))
    }

    private func botMindPerceive(oid: UUID, brain: PlayerCell, skill: Double,
                                 index: CellIndex) -> BotMindBox.Sense {
        let worldSize = 11000.0
        var s = BotMindBox.Sense()
        let myPos = BMVec(brain.position)
        let myMass = Double(brain.mass)
        let myR = Double(brain.cachedSolidRadius)
        let caution = Double(brain.aiCaution)
        let perceptionScale = min(1.22, max(0.74, 0.74 + skill * 0.28))
        let perception = min(4200, (1450 + myR * 7) * perceptionScale)
        var enemyOwnerMass: [UUID: (mass: Double, count: Int)] = [:]

        index.forEach(near: myPos.cg, radius: CGFloat(perception)) { other in
            if other.ownerID == oid || areOwnersAllied(oid, other.ownerID) { return }
            let rawDX = Double(other.x) - myPos.x, rawDY = Double(other.y) - myPos.y
            let rawDistSq = rawDX * rawDX + rawDY * rawDY
            if rawDistSq > perception * perception { return }
            let rawDist = max(rawDistSq.squareRoot(), 1)
            var e = enemyOwnerMass[other.ownerID] ?? (0, 0)
            e.mass += Double(other.mass); e.count += 1
            enemyOwnerMass[other.ownerID] = e
            s.crowdMass += Double(other.mass)
            let lead = min(rawDist / 700.0, 1.2) * min(1.5, skill)
            let px = min(worldSize, max(0, Double(other.x) + Double(other.vx) * 60.0 * lead))
            let py = min(worldSize, max(0, Double(other.y) + Double(other.vy) * 60.0 * lead))
            let dx = px - myPos.x, dy = py - myPos.y
            let dist = max((dx * dx + dy * dy).squareRoot(), 40)
            let otherR = Double(other.solidRadius)
            let otherMass = Double(other.mass)

            if otherMass > myMass * 1.15 {
                if otherMass >= 200 {
                    s.giants.append((other.ownerID, BMVec(x: Double(other.x), y: Double(other.y)),
                                     otherMass, dist))
                }
                let contact = otherR + myR
                let canSplitKill = (otherMass / 2.0) > myMass * 1.30
                let reach = canSplitKill ? (otherR * 4.2 + 240) : (contact * 1.7)
                if dist < reach {
                    var t = BotMindBox.Threat()
                    t.pos = BMVec(x: Double(other.x), y: Double(other.y))
                    t.vel = BMVec(x: Double(other.vx), y: Double(other.vy))
                    t.mass = otherMass; t.dist = dist
                    t.canSplitKill = canSplitKill
                    t.ownerID = other.ownerID
                    var severity = (1.0 - dist / reach) * (0.55 + caution * 0.9)
                    if canSplitKill { severity *= 1.7 }
                    if !other.isBot { severity *= 1.15 }
                    t.severity = severity
                    s.threats.append(t)
                    s.threatScore += severity
                    s.fleeDir.x -= (dx / dist) * severity
                    s.fleeDir.y -= (dy / dist) * severity
                    if s.worst == nil || t.mass > s.worst!.mass { s.worst = t }
                }
            } else if myMass > otherMass * 1.22 {
                var p = BotMindBox.Prey()
                p.id = other.id; p.ownerID = other.ownerID
                p.pos = BMVec(x: px, y: py)
                p.vel = BMVec(x: Double(other.vx), y: Double(other.vy))
                p.mass = otherMass; p.dist = dist
                p.isBot = other.isBot; p.isFeedBot = other.isFeedBot
                s.prey.append(p)
            } else if dist < myR + otherR + 900 {
                var n = BotMindBox.Neutral()
                n.ownerID = other.ownerID
                n.pos = BMVec(x: Double(other.x), y: Double(other.y))
                n.radius = otherR
                n.dist = dist
                s.neutrals.append(n)
            }
        }
        for i in s.prey.indices {
            let e = enemyOwnerMass[s.prey[i].ownerID] ?? (0, 0)
            s.prey[i].ownerTotalNearby = e.mass
            s.prey[i].ownerCellsNearby = e.count
        }
        s.prey.sort { $0.dist < $1.dist }
        if s.prey.count > 10 { s.prey.removeLast(s.prey.count - 10) }
        s.neutrals.sort { $0.dist < $1.dist }
        if s.neutrals.count > 6 { s.neutrals.removeLast(s.neutrals.count - 6) }

        for v in viruses {
            let d = BMVec(v.position).dist(myPos)
            if d < 2200 {
                s.viruses.append((v.id, BMVec(v.position), Double(v.targetMass), d, Double(v.radius)))
            }
        }
        s.viruses.sort { $0.dist < $1.dist }
        s.food = foodManager.bestFoodCluster(near: myPos.cg, searchBuckets: 4).map { BMVec($0) }
        s.pile = massManager.nearestStaticMassPosition(near: myPos.cg, radius: 1100).map { BMVec($0) }
        s.token = worldObjectIndex.nearestToken(near: myPos.cg, radius: 1300, tokens: tokens).map { BMVec($0) }
        s.wallDist = min(myPos.x, worldSize - myPos.x, myPos.y, worldSize - myPos.y)
        return s
    }

    private func botMindVirusBlockingLane(_ sense: BotMindBox.Sense, from: BMVec, dir: BMVec,
                                          length: Double, myR: Double) -> (id: UUID, pos: BMVec, radius: Double)? {
        guard dir != .zero else { return nil }
        for v in sense.viruses {
            let rel = BMVec(x: v.pos.x - from.x, y: v.pos.y - from.y)
            let along = rel.x * dir.x + rel.y * dir.y
            if along < 0 || along > length { continue }
            let perp = abs(rel.x * dir.y - rel.y * dir.x)
            if perp < v.radius + myR + 24 { return (v.id, v.pos, v.radius) }
        }
        return nil
    }

    private func botMindClamp(_ t: BMVec) -> CGPoint {
        let m = 120.0, ws = 11000.0
        return CGPoint(x: min(ws - m, max(m, t.x)), y: min(ws - m, max(m, t.y)))
    }

    private func botMindForwardWaypoint(from p: BMVec, heading: BMVec,
                                        reach: ClosedRange<Double> = 1200...2600) -> BMVec {
        let ws = 11000.0
        var base: Double
        if heading == .zero {
            let seed = sin(p.x * 0.013 + p.y * 0.021) * 43758.5453
            base = (seed - floor(seed)) * 2 * .pi
        }
        else { base = atan2(heading.y, heading.x) }
        let centreDir = atan2(ws / 2 - p.y, ws / 2 - p.x)
        let wallDist = min(p.x, ws - p.x, p.y, ws - p.y)
        if wallDist < 900 {
            let t = 1.0 - wallDist / 900
            var d = centreDir - base
            while d > .pi { d -= 2 * .pi }
            while d < -.pi { d += 2 * .pi }
            base += d * t * 0.8
        }
        let a = base + Double.random(in: -0.62...0.62)
        let dist = Double.random(in: reach)
        return BMVec(x: min(ws - 400, max(400, p.x + cos(a) * dist)),
                     y: min(ws - 400, max(400, p.y + sin(a) * dist)))
    }

    private func botMindNearestWallPoint(_ p: BMVec) -> BMVec {
        let ws = 11000.0
        let d = [p.x, ws - p.x, p.y, ws - p.y]
        switch d.firstIndex(of: d.min()!)! {
        case 0: return BMVec(x: 130, y: p.y)
        case 1: return BMVec(x: ws - 130, y: p.y)
        case 2: return BMVec(x: p.x, y: 130)
        default: return BMVec(x: p.x, y: ws - 130)
        }
    }

    private func botMindWallRunDest(from: BMVec, dest: BMVec) -> BMVec {
        let ws = 11000.0
        let d = [from.x, ws - from.x, from.y, ws - from.y]
        switch d.firstIndex(of: d.min()!)! {
        case 0: return BMVec(x: 130, y: dest.y)
        case 1: return BMVec(x: ws - 130, y: dest.y)
        case 2: return BMVec(x: dest.x, y: 130)
        default: return BMVec(x: dest.x, y: ws - 130)
        }
    }

    /// v8 think entry — called from updateBotAI on the brain cell's cadence.
    private func botMindThink(oid: UUID, brainIdx: Int, frame: BotOwnerFrame,
                              skill: CGFloat, index: CellIndex, now: Double,
                              allyCentre: CGPoint?, allyMass: CGFloat) {
        let brain = botCells[brainIdx]
        var st = botMind.states[oid] ?? BotMindBox.BotState(
            persona: botMindPersona(for: brain, oid: oid, skill: skill))
        let dtThink = st.lastThinkAt > 0 ? min(0.5, now - st.lastThinkAt) : 0.1
        st.lastThinkAt = now
        st.thinkSeconds += dtThink
        let sense = botMindPerceive(oid: oid, brain: brain, skill: Double(skill), index: index)

        // anti-jitter sampling (kept for parity with the server soak harness)
        st.sampleT += dtThink
        if st.sampleT >= 0.30 {
            let d = BMVec(x: Double(brain.aiMovementDirection.width),
                          y: Double(brain.aiMovementDirection.height))
            if d != .zero && st.lastDir != .zero {
                let dn = d.normalized()
                if dn.x * st.lastDir.x + dn.y * st.lastDir.y < -0.65 {
                    st.reversals += 1
                    if now - st.lastReversalAt < 1.5 { st.oscillations += 1 }
                    st.lastReversalAt = now
                }
            }
            st.lastDir = d.normalized()
            st.sampleT = 0
        }

        // virus-camp meter + hard ban
        let myRLoiter = Double(brain.cachedSolidRadius)
        if let v = sense.viruses.first,
           v.dist < min(myRLoiter + v.radius + 220, max(420, myRLoiter * 0.55 + v.radius + 160)) {
            let excused = st.plan.kind == .virusShoot && st.plan.virusID == v.id
            if st.loiterVirus == v.id && !excused {
                if v.dist > st.loiterDist + 2 {
                    st.loiter = max(0, st.loiter - dtThink * 2)
                } else {
                    st.loiter += dtThink
                }
            } else if st.loiterVirus != v.id {
                st.loiterVirus = v.id
                st.loiter = excused ? 0 : st.loiter * 0.5
            }
            st.loiterDist = v.dist
            if st.loiter > min(st.persona.patience, 4.0) + 1.5 {
                st.banVirus = v.id; st.banUntil = now + 10.0
            }
            if st.loiter > 3.0 && st.plan.kind != .escape {
                var away = BMVec(x: Double(brain.position.x) - v.pos.x,
                                 y: Double(brain.position.y) - v.pos.y).normalized()
                if away == .zero { away = BMVec(x: 1, y: 0) }
                var exit = BotMindBox.Plan()
                exit.kind = .travel; exit.variant = BotMindBox.tvPlain
                exit.bornAt = now; exit.commitUntil = now + 2.0
                exit.target = BMVec(botMindClamp(BMVec(
                    x: Double(brain.position.x) + away.x * 1200,
                    y: Double(brain.position.y) + away.y * 1200)))
                st.plan = exit
                st.forcedVirusExitUntil = now + 2.0
            }
        } else {
            st.loiter = max(0, st.loiter - dtThink * 2.0)
            if st.loiter == 0 {
                st.loiterVirus = nil
                st.loiterDist = 1e9
            }
        }

        // escape override with hysteresis
        let fleeing = st.plan.kind == .escape
        let fleeEnter = fleeing ? 0.16 : 0.30
        if sense.threatScore > fleeEnter {
            botMindEscape(oid: oid, brainIdx: brainIdx, frame: frame,
                          sense: sense, st: &st, now: now)
            botMind.states[oid] = st
            return
        } else if fleeing {
            st.plan = BotMindBox.Plan()
            st.postEscapeUntil = now + 2.5
        }
        // ---- v8.6 pressure drift: a bigger cell parked at contact range is
        // never something to idle beside. Below the flee threshold nothing
        // used to force motion, so an arrived roam/forage damped the bot to a
        // vibrating standstill right next to a big player. If a close giant
        // is watching and the current plan is not actively taking us
        // anywhere, swap in a committed walk-away.
        do {
            let brain = botCells[brainIdx]
            let myPosP = BMVec(brain.position)
            if sense.threatScore <= fleeEnter,
               let g = sense.giants.min(by: { $0.dist < $1.dist }),
               g.dist < Double(brain.cachedSolidRadius) * 2.6 + 420 {
                let toTarget = BMVec(x: st.plan.target.x - myPosP.x,
                                     y: st.plan.target.y - myPosP.y)
                let tLen = (toTarget.x * toTarget.x + toTarget.y * toTarget.y).squareRoot()
                let awayG = BMVec(x: myPosP.x - g.pos.x, y: myPosP.y - g.pos.y).normalized()
                let idleKinds: Bool
                switch st.plan.kind {
                case .roam, .forage, .regroup, .travel: idleKinds = true
                default: idleKinds = false
                }
                let goingNowhere = tLen < 300
                let walkingIn = tLen >= 300 &&
                    (toTarget.x / tLen) * awayG.x + (toTarget.y / tLen) * awayG.y < -0.5
                if idleKinds, goingNowhere || (st.plan.kind == .roam && walkingIn) {
                    var drift = BotMindBox.Plan()
                    drift.kind = .travel; drift.variant = BotMindBox.tvPlain
                    drift.bornAt = now; drift.commitUntil = now + 1.6
                    let m = 120.0, wsz = 11000.0
                    drift.target = BMVec(x: min(wsz - m, max(m, myPosP.x + awayG.x * 1100)),
                                         y: min(wsz - m, max(m, myPosP.y + awayG.y * 1100)))
                    st.plan = drift
                    botMind.bump("pressure_drift")
                }
            }
        }
        if now < st.forcedVirusExitUntil {
            botMindExecute(oid: oid, brainIdx: brainIdx, frame: frame, sense: sense,
                           st: &st, now: now, dtThink: dtThink)
            botMind.states[oid] = st
            return
        }

        if st.plan.kind != .roam || st.plan.commitUntil > now {
            if botMindPlanStillValid(oid: oid, brainIdx: brainIdx, sense: sense, st: st, now: now) {
                botMindExecute(oid: oid, brainIdx: brainIdx, frame: frame, sense: sense,
                               st: &st, now: now, dtThink: dtThink)
                botMind.states[oid] = st
                return
            }
        }

        var best = botMindCandidates(oid: oid, brainIdx: brainIdx, frame: frame,
                                     sense: sense, st: &st, now: now,
                                     allyCentre: allyCentre, allyMass: allyMass)
        best.bornAt = now
        st.plan = best
        st.planLockUntil = now + (best.kind == .forage ? 0.32 :
                                  best.kind == .hunt ? 0.18 :
                                  botMindIsTrick(best) ? 0.45 : 0.30)
        if best.kind == .roam {
            st.roamTarget = best.target
            st.roamUntil = best.commitUntil
        }
        botMindExecute(oid: oid, brainIdx: brainIdx, frame: frame, sense: sense,
                       st: &st, now: now, dtThink: dtThink)
        botMind.states[oid] = st
    }

    /// An armed, immediately-cashable kill: prey basically touching us, or
    /// prey inside a ready split's reach. Pausable plans (regroup, travel,
    /// a recombine that has not fed yet) must yield to this.
    private func botMindArmedOpportunity(_ sense: BotMindBox.Sense, brainIdx: Int) -> Bool {
        let brain = botCells[brainIdx]
        let myR = Double(brain.cachedSolidRadius)
        let half = Double(brain.targetMass) / 2
        for p in sense.prey {
            // A morsel is not an opportunity: pausing a recombine or travel
            // trick for a 25-mass dot suppressed the whole trick vocabulary
            // in crowded lobbies (v8.5 regression Hudson reported).
            let worthwhile = p.mass >= 40 || p.mass > Double(brain.targetMass) * 0.10
            guard worthwhile else { continue }
            if p.dist < myR * 2.6 + 140, Double(brain.mass) > p.mass * 1.35 { return true }
            if brain.aiSplitCooldown <= 0, Double(brain.targetMass) >= 80,
               half > p.mass * 1.30, p.dist < myR * 3.4 + 160,
               // an "armed split" the punish check would veto anyway is not
               // armed — near a bigger player it froze every other plan.
               !botMindSplitPunishable(sense, brainIdx: brainIdx, pieces: 2, toward: p.pos) {
                return true
            }
        }
        return false
    }

    /// Committing halves/quarters into a lane where a bigger cell can punish
    /// them is the classic over-split. Directional: only cells near the piece
    /// landing zone veto — a giant safely behind us is not a reason to pass
    /// up a clean split.
    private func botMindSplitPunishable(_ sense: BotMindBox.Sense, brainIdx: Int,
                                        pieces: Double, toward t: BMVec) -> Bool {
        let brain = botCells[brainIdx]
        let pieceMass = Double(brain.targetMass) / pieces
        let myPos = BMVec(brain.position)
        let mid = BMVec(x: (myPos.x + t.x) * 0.5, y: (myPos.y + t.y) * 0.5)
        func nearLane(_ pos: BMVec, _ range: Double) -> Bool {
            min(pos.dist(t), pos.dist(mid)) < range
        }
        for g in sense.giants where g.mass > pieceMass * 1.20 {
            let canSplitPiece = g.mass / 2 > pieceMass * 1.30
            if nearLane(g.pos, canSplitPiece ? 1250 : 720) { return true }
        }
        for p in sense.prey where p.mass > pieceMass * 1.15 && nearLane(p.pos, 700) {
            return true
        }
        if pieces >= 4, sense.neutrals.contains(where: { nearLane($0.pos, 780) }) {
            return true
        }
        return false
    }

    private func botMindPlanStillValid(oid: UUID, brainIdx: Int, sense: BotMindBox.Sense,
                                       st: BotMindBox.BotState, now: Double) -> Bool {
        let p = st.plan
        let budget: Double
        switch p.kind {
        case .bait: budget = st.persona.patience * 4
        case .virusShoot: budget = st.persona.patience * 2.5
        case .recombine: budget = 2.5 + st.persona.patience * 2
        default: budget = st.persona.patience * 3
        }
        if now - p.bornAt > budget { return false }
        let locked = now < st.planLockUntil
        switch p.kind {
        case .roam:
            return p.commitUntil > now && sense.prey.isEmpty && sense.threats.isEmpty
        case .forage:
            if p.commitUntil <= now { return false }
            if locked { return true }
            if !sense.prey.isEmpty {
                return false
            }
            var owned = 0
            for c in botCells where c.ownerID == oid { owned += 1 }
            if owned > 1 { return false }
            return p.variant == 1 ? sense.pile != nil
                 : p.variant == 0 ? sense.food != nil : sense.token != nil
        case .hunt, .splitKill, .bait:
            if locked { return true }
            guard let eo = p.enemyOwner else { return false }
            if !sense.prey.contains(where: { $0.ownerID == eo }) &&
               !sense.threats.contains(where: { $0.ownerID == eo }) { return false }
            if p.kind == .hunt { return now - p.bornAt < 0.42 }
            return true
        case .virusShoot:
            guard let vid = p.virusID else { return false }
            if st.banVirus == vid && st.banUntil > now { return false }
            return sense.viruses.contains { $0.id == vid }
        case .recombine:
            if sense.threatScore > 0.30 { return false }   // consolidate later, live now
            // Before any pellet is committed, a recombine is pausable: an
            // armed kill right next to us always outranks tidying up.
            if !st.recombineFeedDone, st.plan.stage == 0,
               botMindArmedOpportunity(sense, brainIdx: brainIdx) {
                return false
            }
            if now - st.lastSplitAt <= 1.05 { return false }
            if now - st.bornAt <= 3.0 { return false }
            var count = 0
            for c in botCells where c.ownerID == oid { count += 1 }
            return count > 1
        case .travel, .regroup:
            // Neither is a reason to walk past free mass: yield to an armed
            // kill as soon as the short lock lapses. Regroup also expires
            // like any plan instead of running to its whole time budget.
            if !locked, botMindArmedOpportunity(sense, brainIdx: brainIdx) { return false }
            return p.commitUntil > now
        case .escape:
            return true
        }
    }

    private func botMindEscape(oid: UUID, brainIdx: Int, frame: BotOwnerFrame,
                               sense: BotMindBox.Sense, st: inout BotMindBox.BotState,
                               now: Double) {
        let ws = 11000.0
        let brain = botCells[brainIdx]
        let myPos = BMVec(brain.position)
        let myR = Double(brain.cachedSolidRadius)
        let myMass = Double(brain.mass)
        let popsOnVirus = myMass >= 133
        let persona = st.persona

        if st.plan.kind == .escape, st.plan.commitUntil > now {
            botMindExecuteEscape(oid: oid, brainIdx: brainIdx, sense: sense, st: &st, now: now)
            return
        }
        // sticky hide: stay ducked while the budget lasts
        if st.plan.kind == .escape, st.plan.variant == BotMindBox.esHide,
           st.loiter < min(st.persona.patience, 3.5),
           let w0 = sense.worst,
           let hv = sense.viruses.first(where: { $0.id == st.plan.virusID }) {
            let away = BMVec(x: hv.pos.x - w0.pos.x, y: hv.pos.y - w0.pos.y).normalized()
            let orbitR = hv.radius + myR * 0.4
            let fresh = BMVec(x: hv.pos.x + away.x * orbitR, y: hv.pos.y + away.y * orbitR)
            // STRAFE around the virus toward the safe side (rotation-limited)
            // instead of jumping across it (oscillation source).
            if fresh.dist(st.plan.target) > 150 {
                let cur = atan2(st.plan.target.y - hv.pos.y, st.plan.target.x - hv.pos.x)
                let want = atan2(fresh.y - hv.pos.y, fresh.x - hv.pos.x)
                var d = want - cur
                while d > .pi { d -= 2 * .pi }
                while d < -.pi { d += 2 * .pi }
                let a = cur + max(-0.95, min(0.95, d))
                st.plan.target = BMVec(x: hv.pos.x + cos(a) * orbitR,
                                       y: hv.pos.y + sin(a) * orbitR)
            }
            st.plan.commitUntil = now + 0.5
            botMindExecuteEscape(oid: oid, brainIdx: brainIdx, sense: sense, st: &st, now: now)
            return
        }

        var dir = sense.fleeDir
        let edge = 900.0
        if myPos.x < edge { dir.x += (1 - myPos.x / edge) * 1.4 }
        if myPos.x > ws - edge { dir.x -= (1 - (ws - myPos.x) / edge) * 1.4 }
        if myPos.y < edge { dir.y += (1 - myPos.y / edge) * 1.4 }
        if myPos.y > ws - edge { dir.y -= (1 - (ws - myPos.y) / edge) * 1.4 }
        var lane = dir.normalized()
        if lane == .zero { lane = BMVec(x: ws / 2 - myPos.x, y: ws / 2 - myPos.y).normalized() }
        // v8.6 gap lane: when threats surround the bot the summed flee vector
        // cancels toward zero (ring) or points into a wall (corner pin), and
        // the bot froze in place / dived into a mouth. A weak or wall-blocked
        // resultant now picks the lane with the most CLEARANCE instead.
        let rawMag = (dir.x * dir.x + dir.y * dir.y).squareRoot()
        let laneAhead = BMVec(x: myPos.x + lane.x * 700, y: myPos.y + lane.y * 700)
        let laneWallD = min(laneAhead.x, ws - laneAhead.x, laneAhead.y, ws - laneAhead.y)
        if !sense.threats.isEmpty,
           rawMag < max(0.45, sense.threatScore * 0.8) || laneWallD < myR + 60 {
            var bestLane = lane
            var bestScore = -1e18
            for k in 0..<16 {
                let a = Double(k) * .pi / 8
                let cand = BMVec(x: cos(a), y: sin(a))
                var sc = 0.0
                for f in [300.0, 650.0, 1000.0] {
                    let probe = BMVec(x: myPos.x + cand.x * f, y: myPos.y + cand.y * f)
                    var nearest = 1e9
                    for t in sense.threats { nearest = min(nearest, probe.dist(t.pos)) }
                    sc += min(nearest, 1400)
                    let wallD = min(probe.x, ws - probe.x, probe.y, ws - probe.y)
                    if wallD < myR + 40 { sc -= 4000 } else { sc += min(wallD, 420) * 0.4 }
                }
                if cand.x * st.escapeLane.x + cand.y * st.escapeLane.y > 0.5 { sc += 350 }
                if sc > bestScore { bestScore = sc; bestLane = cand }
            }
            lane = bestLane
        }
        // hard anti-camp: a banned (over-loitered) virus repels the flee lane.
        if let bv = st.banVirus, st.banUntil > now,
           let v = sense.viruses.first(where: { $0.id == bv }), v.dist < 620 {
            let awayV = BMVec(x: myPos.x - v.pos.x, y: myPos.y - v.pos.y).normalized()
            lane = BMVec(x: lane.x + awayV.x * 0.9, y: lane.y + awayV.y * 0.9).normalized()
        }
        if st.plan.kind == .escape, st.escapeLane != .zero {
            let dot = lane.x * st.escapeLane.x + lane.y * st.escapeLane.y
            if dot < -0.15 {
                let ahead = BMVec(x: myPos.x + st.escapeLane.x * 420,
                                  y: myPos.y + st.escapeLane.y * 420)
                let wallAhead = min(ahead.x, ws - ahead.x, ahead.y, ws - ahead.y) < 160
                if !wallAhead { lane = st.escapeLane }
            } else {
                lane = BMVec(x: st.escapeLane.x * 0.65 + lane.x * 0.35,
                             y: st.escapeLane.y * 0.65 + lane.y * 0.35).normalized()
            }
        }
        st.escapeLane = lane

        var plan = BotMindBox.Plan()
        plan.kind = .escape
        plan.bornAt = st.plan.kind == .escape ? st.plan.bornAt : now
        plan.variant = BotMindBox.esRun
        plan.commitUntil = now + 0.8

        let cornered = sense.wallDist < myR * 1.8 && sense.threatScore > 0.55
        let worst = sense.worst

        if let blocker = botMindVirusBlockingLane(sense, from: myPos, dir: lane,
                                                  length: 760, myR: myR) {
            let banned = st.banVirus == blocker.id && st.banUntil > now
            if !popsOnVirus && !banned {
                plan.variant = BotMindBox.esThrough
                plan.virusID = blocker.id
                plan.target = BMVec(x: blocker.pos.x + lane.x * 620,
                                    y: blocker.pos.y + lane.y * 620)
            } else if persona.trickLevel >= 3, cornered, blocker.pos.dist(myPos) < 500,
                      let w = worst, w.canSplitKill {
                plan.variant = BotMindBox.esSurf
                plan.virusID = blocker.id
                plan.target = blocker.pos
            } else {
                let toV = BMVec(x: blocker.pos.x - myPos.x, y: blocker.pos.y - myPos.y)
                let cross = lane.x * toV.y - lane.y * toV.x
                var side: Double = cross > 0 ? -1 : 1
                if st.plan.kind == .escape, st.plan.variant == BotMindBox.esDetour,
                   st.plan.virusID == blocker.id { side = st.plan.side }
                plan.variant = BotMindBox.esDetour
                plan.virusID = blocker.id
                plan.side = side
                let perp = BMVec(x: -lane.y * side, y: lane.x * side)
                let clearance = blocker.radius + myR + 170
                plan.target = BMVec(x: blocker.pos.x + perp.x * clearance + lane.x * 260,
                                    y: blocker.pos.y + perp.y * clearance + lane.y * 260)
                plan.commitUntil = now + 1.1
            }
        } else if persona.trickLevel >= 2, let w = worst, !w.canSplitKill,
                  w.mass < myMass * 1.55, w.dist < myR * 3.2,
                  frame.count * 2 <= 16,
                  Double(brain.targetMass) >= 80, sense.wallDist > 700,
                  botMindVirusBlockingLane(sense, from: myPos, dir: lane, length: 900, myR: myR * 0.7) == nil {
            plan.variant = BotMindBox.esSplitAway
            plan.target = BMVec(x: myPos.x + lane.x * 1200, y: myPos.y + lane.y * 1200)
            plan.commitUntil = now + 1.2
        } else {
            // No virus hiding/orbiting: committed run/detour/through lanes
            // are cleaner, don't resemble farming, and avoid direction flips.
            plan.target = BMVec(x: myPos.x + lane.x * 1400, y: myPos.y + lane.y * 1400)
            if let w = worst, w.canSplitKill {
                let vMag = (w.vel.x * w.vel.x + w.vel.y * w.vel.y).squareRoot()
                if vMag > 0.30 {
                    let lx = w.vel.x / vMag, ly = w.vel.y / vMag
                    let toMe = BMVec(x: myPos.x - w.pos.x, y: myPos.y - w.pos.y).normalized()
                    if toMe.x * lx + toMe.y * ly > 0.72 {
                        var px = -ly, py = lx
                        if toMe.x * px + toMe.y * py < 0 { px = -px; py = -py }
                        let dodge = BMVec(x: lane.x + px * 1.2, y: lane.y + py * 1.2).normalized()
                        plan.target = BMVec(x: myPos.x + dodge.x * 1400, y: myPos.y + dodge.y * 1400)
                    }
                }
            }
        }
        if st.plan.kind == .escape, st.plan.variant == plan.variant,
           st.plan.virusID == plan.virusID {
            plan.stage = st.plan.stage
            plan.stageT = st.plan.stageT
        }
        st.plan = plan
        botMindExecuteEscape(oid: oid, brainIdx: brainIdx, sense: sense, st: &st, now: now)
    }

    private func botMindExecuteEscape(oid: UUID, brainIdx: Int, sense: BotMindBox.Sense,
                                      st: inout BotMindBox.BotState, now: Double) {
        let brain = botCells[brainIdx]
        botCells[brainIdx].aiMode = .flee
        botCells[brainIdx].aiFleeing = true
        botCells[brainIdx].aiSteerTarget = botMindClamp(st.plan.target)
        switch st.plan.variant {
        case BotMindBox.esSplitAway:
            if st.plan.stage == 0 {
                let lane = BMVec(x: st.plan.target.x - Double(brain.position.x),
                                 y: st.plan.target.y - Double(brain.position.y)).normalized()
                executeSplit(on: &botCells, for: oid, direction: lane.cgSize)
                st.lastSplitAt = now
                st.plan.stage = 1
            }
        case BotMindBox.esHide:
            if st.loiter > min(st.persona.patience, 3.5) {
                st.plan.variant = BotMindBox.esRun
                let wPos = sense.worst?.pos ?? BMVec.zero
                let away = BMVec(x: Double(brain.position.x) - wPos.x,
                                 y: Double(brain.position.y) - wPos.y).normalized()
                st.plan.target = BMVec(x: Double(brain.position.x) + away.x * 1500,
                                       y: Double(brain.position.y) + away.y * 1500)
                botCells[brainIdx].aiSteerTarget = botMindClamp(st.plan.target)
            }
        default: break
        }
    }

    private struct BMCandidate {
        var plan: BotMindBox.Plan
        var massEV: Double
        var risk: Double
        var time: Double
        var style: Double
        var priority: Double
    }

    private func botMindPlanKey(_ p: BotMindBox.Plan) -> String {
        switch p.kind {
        case .recombine:
            return p.variant == BotMindBox.recWall ? "wallrecombine" : "centrerecombine"
        case .splitKill:
            if p.variant == BotMindBox.skMacroDouble { return "macrodouble" }
            if p.variant == BotMindBox.skDouble { return "doublesplit" }
            return "splitkill"
        case .travel:
            if p.variant == BotMindBox.tvMacroSplitRun { return "macrosplitrun" }
            if p.variant == BotMindBox.tvWallRun { return "wallrun" }
            if p.variant == BotMindBox.tvSplitRun { return "splitrun" }
            return "travel"
        case .bait: return "bait"
        default: return "ordinary"
        }
    }

    private func botMindIsTrick(_ p: BotMindBox.Plan) -> Bool {
        p.kind == .recombine || p.kind == .splitKill || p.kind == .bait ||
        (p.kind == .travel && p.variant != BotMindBox.tvPlain &&
         p.variant != BotMindBox.tvAlly)
    }

    private func botMindCandidates(oid: UUID, brainIdx: Int, frame: BotOwnerFrame,
                                   sense: BotMindBox.Sense, st: inout BotMindBox.BotState,
                                   now: Double, allyCentre: CGPoint?, allyMass: CGFloat)
        -> BotMindBox.Plan {
        let ws = 11000.0
        let brain = botCells[brainIdx]
        let myPos = BMVec(brain.position)
        let myMass = Double(brain.mass)
        let myTotal = Double(frame.mass)
        let myR = Double(brain.cachedSolidRadius)
        let myCells = frame.count
        let persona = st.persona
        let aggression = Double(brain.aiAggression)
        let heading = BMVec(x: Double(brain.aiMovementDirection.width),
                            y: Double(brain.aiMovementDirection.height))
        let baseRisk = min(1.0, sense.threatScore * 2.2)
        var cands: [BMCandidate] = []
        let trickDeck = [
            "splitkill", "doublesplit", "macrodouble", "centrerecombine",
            "macrosplitrun", "wallrecombine", "splitrun", "wallrun", "bait"
        ]

        let neutralAvoid = sense.neutrals.first

        func add(_ inputPlan: BotMindBox.Plan, ev: Double, risk: Double,
                 time: Double, style: Double, priority: Double = 0) {
            var plan = inputPlan
            var r = risk
            let toT = BMVec(x: plan.target.x - myPos.x, y: plan.target.y - myPos.y).normalized()
            if let n = neutralAvoid, plan.kind != .splitKill, plan.kind != .escape,
               plan.kind != .bait, toT != .zero {
                let rel = BMVec(x: n.pos.x - myPos.x, y: n.pos.y - myPos.y)
                let along = rel.x * toT.x + rel.y * toT.y
                let perp = abs(rel.x * toT.y - rel.y * toT.x)
                if along > 0, along < max(700, n.dist + 260),
                   perp < myR + n.radius + 90 {
                    let side = (toT.x * rel.y - toT.y * rel.x) >= 0 ? -1.0 : 1.0
                    let tangent = BMVec(x: -toT.y * side, y: toT.x * side)
                    let clearance = myR + n.radius + 150
                    plan.target = BMVec(botMindClamp(BMVec(
                        x: n.pos.x + tangent.x * clearance + toT.x * 240,
                        y: n.pos.y + tangent.y * clearance + toT.y * 240)))
                    r += 0.04
                }
            }
            if now < st.postEscapeUntil, st.escapeLane != .zero {
                if toT.x * st.escapeLane.x + toT.y * st.escapeLane.y < -0.30 { r += 0.40 }
            }
            if heading != .zero {
                let h = heading.normalized()
                let dot = toT.x * h.x + toT.y * h.y
                if dot < -0.35 { r += 0.26 * (-dot) }
            }
            cands.append(BMCandidate(plan: plan, massEV: ev,
                                     risk: min(1, max(0, r)), time: max(0.2, time),
                                     style: style, priority: priority))
        }

        if let f = sense.food {
            var p = BotMindBox.Plan(); p.kind = .forage; p.target = f; p.commitUntil = now + 2.2
            add(p, ev: 26, risk: baseRisk, time: f.dist(myPos) / 260, style: 0)
        }
        if let pile = sense.pile {
            // direction-aware: pellets AHEAD are near-free, pellets BEHIND are
            // not worth a U-turn
            let toPile = BMVec(x: pile.x - myPos.x, y: pile.y - myPos.y).normalized()
            let ahead = heading == .zero ? 1.0
                : max(0.0, heading.normalized().x * toPile.x + heading.normalized().y * toPile.y)
            var p = BotMindBox.Plan(); p.kind = .forage; p.variant = 1; p.target = pile
            p.commitUntil = now + 2.2
            add(p, ev: 24 + 44 * ahead, risk: baseRisk, time: pile.dist(myPos) / 260, style: 0)
        }
        if let t = sense.token {
            var p = BotMindBox.Plan(); p.kind = .forage; p.variant = 2; p.target = t
            p.commitUntil = now + 2.2
            add(p, ev: 12, risk: baseRisk, time: t.dist(myPos) / 280, style: 0)
        }

        let halfMass = Double(brain.targetMass) / 2
        for prey in sense.prey.prefix(6) {
            let wallDistP = min(prey.pos.x, ws - prey.pos.x, prey.pos.y, ws - prey.pos.y)
            var evBoost = 1.0
            if prey.isFeedBot { evBoost = 1.6 }
            if !prey.isBot { evBoost *= 1.0 + aggression * 0.7 }
            if wallDistP < 700 { evBoost *= 1.25 }
            if prey.mass < myTotal * 0.02 { evBoost *= 0.35 }
            let hunterBoost = persona.archetype == .hunter ? 1.3 : 1.0
            let preyRisk = min(1.0, baseRisk + (prey.ownerTotalNearby > myTotal * 0.8 ? 0.35 : 0))

            let ratio = prey.mass / max(myMass, 1)
            let catchF = max(0.06, min(1.0, (0.85 - ratio) * 1.6))
            var chaseTime = prey.dist / (230 * catchF)
            if wallDistP < 500 { chaseTime *= 0.55 }
            // consciousness: prey practically touching us is near-free mass
            if prey.dist < myR * 2.6 + 120 { evBoost *= 1.55 }
            var hp = BotMindBox.Plan(); hp.kind = .hunt; hp.enemyOwner = prey.ownerID
            hp.enemyCell = prey.id; hp.target = prey.pos; hp.commitUntil = now + 1.2
            add(hp, ev: prey.mass * evBoost * hunterBoost, risk: preyRisk,
                time: chaseTime, style: 0)

            let reach = (myR * 3.4 + 160) * (0.75 + aggression * 0.5)
            let laneDir = BMVec(x: prey.pos.x - myPos.x, y: prey.pos.y - myPos.y).normalized()
            let laneBlocked = botMindVirusBlockingLane(sense, from: myPos, dir: laneDir,
                                                       length: min(prey.dist, reach * 1.1),
                                                       myR: myR * 0.62) != nil
            if brain.aiSplitCooldown <= 0, myCells < 8, myMass >= 90, !laneBlocked,
               Double(brain.targetMass) >= 80 {
                let punish2 = botMindSplitPunishable(sense, brainIdx: brainIdx, pieces: 2, toward: prey.pos)
                let punish4 = botMindSplitPunishable(sense, brainIdx: brainIdx, pieces: 4, toward: prey.pos)
                if halfMass > prey.mass * 1.30, prey.dist < reach, !punish2 {
                    var p = BotMindBox.Plan(); p.kind = .splitKill; p.variant = BotMindBox.skSingle
                    p.enemyOwner = prey.ownerID; p.enemyCell = prey.id; p.target = prey.pos
                    add(p, ev: prey.mass * evBoost * hunterBoost,
                        risk: preyRisk + 0.08, time: 0.75, style: 0.25,
                        priority: persona.trickLevel >= 3 ? 0.34 : 0.18)
                }
                if persona.trickLevel >= 2, halfMass / 2 > prey.mass * 1.30,
                   prey.dist < reach * 1.9, prey.dist > reach * 0.9, myCells < 5, !punish4 {
                    var p = BotMindBox.Plan(); p.kind = .splitKill; p.variant = BotMindBox.skDouble
                    p.enemyOwner = prey.ownerID; p.enemyCell = prey.id; p.target = prey.pos
                    add(p, ev: prey.mass * evBoost * hunterBoost,
                        risk: preyRisk + 0.20, time: 1.05, style: 0.55,
                        priority: 0.42)
                }
                if persona.trickLevel >= 3, halfMass / 2 > prey.mass * 1.15,
                   prey.dist < reach * 3.0, prey.dist > reach * 1.05, myCells < 5,
                   myTotal > 220, prey.dist < myR + 1050, !punish4 {
                    var p = BotMindBox.Plan(); p.kind = .splitKill; p.variant = BotMindBox.skMacroDouble
                    p.enemyOwner = prey.ownerID; p.enemyCell = prey.id; p.target = prey.pos
                    add(p, ev: prey.mass * evBoost * hunterBoost,
                        risk: preyRisk + 0.22, time: 1.35, style: 0.85,
                        priority: 0.48)
                }
            }

        }

        if persona.trickLevel >= 4, myCells <= 2, sense.threatScore < 0.08,
           brain.aiSplitCooldown <= 0 {
            for prey in sense.prey.prefix(6) {
                let vMass = prey.mass
                guard prey.ownerCellsNearby == 1, vMass > 60,
                      myTotal > vMass * 3.4, myTotal < vMass * 9.5,
                      prey.dist < 1100,
                      // bait pieces are victim-sized: a covering giant makes
                      // the whole ruse free food.
                      !botMindSplitPunishable(sense, brainIdx: brainIdx,
                                              pieces: max(4.0, myTotal / max(vMass, 40)),
                                              toward: prey.pos) else { continue }
                var p = BotMindBox.Plan(); p.kind = .bait
                p.enemyOwner = prey.ownerID; p.enemyCell = prey.id; p.target = prey.pos
                p.baseCellCount = prey.ownerCellsNearby
                add(p, ev: vMass * 1.6, risk: 0.35, time: 4.5, style: 1.0)
            }
        }

        // Scripted-bot virus farming is deliberately absent. Tactical virus
        // shots stay disabled until a deterministic hit-outcome contract can
        // prove that a specific target, rather than empty space, receives it.

        let recCentreNow = BMVec(x: Double(frame.weightedX) / max(myTotal, 0.0001),
                                 y: Double(frame.weightedY) / max(myTotal, 0.0001))
        let recSpreadNow = recCentreNow.dist(myPos)
        // Consolidation is an occasional deliberate move, not a metronome:
        // over-offering it froze bots into visible stop-feed loops.
        if myCells >= 2, sense.threatScore < 0.14, now - st.lastSplitAt > 1.05,
           now - st.bornAt > 3.0,
           myCells >= 3 || recSpreadNow > myR * 1.2,
           !botMindArmedOpportunity(sense, brainIdx: brainIdx),
           now - st.lastRecombineAt > max(7.0, persona.patience * 2.5) {
            let spread = recSpreadNow
            let consolidationValue = min(220.0, myTotal * 0.14) * (1.0 + spread / (myR * 4))
            if persona.trickLevel >= 1, myTotal >= 180, spread > myR * 0.35 {
                var p = BotMindBox.Plan(); p.kind = .recombine; p.variant = BotMindBox.recCentre
                p.target = myPos
                add(p, ev: consolidationValue, risk: baseRisk + 0.10,
                    time: 2.4, style: 0.8,
                    priority: persona.trickLevel >= 3 ? 0.22 : 0.08)
            }
            if persona.trickLevel >= 2, myTotal >= 220,
               sense.wallDist < 650, spread < myR * 3.2 {
                var p = BotMindBox.Plan(); p.kind = .recombine
                p.variant = BotMindBox.recWall
                p.target = botMindNearestWallPoint(myPos)
                add(p, ev: consolidationValue * 1.10,
                    risk: baseRisk + 0.05, time: 2.0, style: 0.7,
                    priority: 0.30)
            }
            // Moving/insta remain disabled until receiver-verified.
        }
        if myCells > 1, brain.canMerge {
            let centre = BMVec(x: Double(frame.weightedX) / max(myTotal, 0.0001),
                               y: Double(frame.weightedY) / max(myTotal, 0.0001))
            if centre.dist(myPos) > myR * 2.5 {
                var p = BotMindBox.Plan(); p.kind = .regroup; p.target = centre
                p.commitUntil = now + 1.2
                add(p, ev: 30, risk: baseRisk, time: 1.6, style: 0)
            }
        }

        // allied pair: stay in formation when the partner drifts far
        if let ac = allyCentre, allyMass > 0 {
            let acv = BMVec(ac)
            let d = acv.dist(myPos)
            if d > 820 {
                var p = BotMindBox.Plan(); p.kind = .travel; p.variant = BotMindBox.tvAlly
                p.target = acv; p.commitUntil = now + 1.6
                add(p, ev: 40, risk: baseRisk * 0.5, time: d / 260, style: 0)
            }
        }

        let farJourney = (sense.food.map { $0.dist(myPos) } ?? 9e9) > 1400
        let dest = botMindForwardWaypoint(from: myPos, heading: heading,
                                          reach: 2200...3800)
        if sense.food == nil || sense.crowdMass > myTotal * 6 || farJourney {
            var p = BotMindBox.Plan(); p.kind = .travel; p.variant = BotMindBox.tvPlain
            p.target = dest; p.commitUntil = now + 3.0
            add(p, ev: 30, risk: baseRisk * 0.6, time: dest.dist(myPos) / 240, style: 0)
        }
        // v8.6: the blanket giant-free-screen requirement erased travel
        // tricks exactly where Hudson watches (near his own big cell). The
        // directional punish check is the correct safety: pieces may fly
        // anywhere no bigger cell covers the landing lane.
        let runDir = BMVec(x: dest.x - myPos.x, y: dest.y - myPos.y).normalized()
        let runLanding = BMVec(x: myPos.x + runDir.x * 600, y: myPos.y + runDir.y * 600)
        // Travel tricks are for GOING somewhere: with a worthwhile prey in
        // hunting range, split-running away is itself a missed opportunity.
        let preyNearby = sense.prey.contains {
            ($0.mass >= 40 || $0.mass > myTotal * 0.10) && $0.dist < 1200
        }
        let runSafe = !preyNearby &&
                      !botMindSplitPunishable(sense, brainIdx: brainIdx, pieces: 2, toward: runLanding)
        if persona.trickLevel >= 3, myCells <= 2, myTotal > 260, runSafe,
           sense.threatScore < 0.05, brain.aiSplitCooldown <= 0 {
            var q = BotMindBox.Plan(); q.kind = .travel
            q.variant = BotMindBox.tvMacroSplitRun
            q.target = dest; q.commitUntil = now + 2.2
            add(q, ev: 30, risk: 0.15, time: dest.dist(myPos) / 420,
                style: 0.9, priority: 0.34)
        }
        if persona.trickLevel >= 3, sense.wallDist < max(950, myR * 2.2),
           myCells <= 3, myTotal > 220, runSafe, sense.threatScore < 0.05,
           brain.aiSplitCooldown <= 0 {
            var q = BotMindBox.Plan(); q.kind = .travel
            q.variant = BotMindBox.tvWallRun
            q.target = botMindWallRunDest(from: myPos, dest: dest)
            q.commitUntil = now + 3.0
            add(q, ev: 26, risk: 0.14, time: dest.dist(myPos) / 400,
                style: 0.85, priority: 0.38)
        }
        if persona.trickLevel >= 2, myCells <= 2, myTotal > 220, runSafe,
           sense.threatScore < 0.04, brain.aiSplitCooldown <= 0 {
            var q = BotMindBox.Plan(); q.kind = .travel
            q.variant = BotMindBox.tvSplitRun
            q.target = dest; q.commitUntil = now + 2.2
            add(q, ev: 26, risk: 0.18, time: dest.dist(myPos) / 380,
                style: 0.6, priority: 0.26)
        }

        var roam = BotMindBox.Plan(); roam.kind = .roam
        let keepRoam = st.roamUntil > now && st.roamTarget != .zero &&
                       myPos.dist(st.roamTarget) > 280
        roam.target = keepRoam ? st.roamTarget
                               : botMindForwardWaypoint(from: myPos, heading: heading)
        roam.commitUntil = keepRoam ? st.roamUntil : now + Double.random(in: 6...10)
        add(roam, ev: 8, risk: baseRisk * 0.5, time: 4, style: 0)

        var bestPlan = roam
        var bestScore = -1e9
        var scored: [(candidate: BMCandidate, score: Double)] = []
        for c in cands {
            let evN = c.massEV / (c.massEV + max(60, myTotal * 0.5))
            let speedN = 1.0 / (1.0 + c.time / 6.0)
            var s = persona.wMass * evN + persona.wSpeed * speedN * 0.55
                  + persona.wStyle * c.style * 0.22 - persona.wSafety * c.risk
                  + c.priority
            if c.plan.kind == st.plan.kind && c.plan.enemyOwner == st.plan.enemyOwner
                && c.plan.virusID == st.plan.virusID { s += 0.18 }
            if st.loiter > 2.0, c.plan.kind == .virusShoot {
                s -= (st.loiter - 2.0) * 0.25
            }
            scored.append((c, s))
            if s > bestScore { bestScore = s; bestPlan = c.plan }
        }
        let deckCooldown: Double = persona.trickLevel >= 3 ? 1.8 : 4.2
        // While a kill is armed, only kill-family tricks may be forced —
        // rotating in a recombine/travel filler over free mass was the top
        // "missed opportunity" source.
        let killFamilies: Set<String> = ["splitkill", "doublesplit", "macrodouble"]
        let armedNow = botMindArmedOpportunity(sense, brainIdx: brainIdx)
        if persona.trickLevel >= 2, now - st.lastVisibleTrickAt > deckCooldown {
            let available = scored.filter {
                botMindIsTrick($0.candidate.plan) &&
                (!armedNow || killFamilies.contains(botMindPlanKey($0.candidate.plan)))
            }
            if !available.isEmpty {
                var forced: (candidate: BMCandidate, score: Double)? = nil
                for offset in 0..<trickDeck.count {
                    let idx = (st.trickDeckIndex + offset) % trickDeck.count
                    let key = trickDeck[idx]
                    if let pick = available.filter({
                        botMindPlanKey($0.candidate.plan) == key
                    }).max(by: { $0.score < $1.score }) {
                        forced = pick
                        st.trickDeckIndex = (idx + 1) % trickDeck.count
                        break
                    }
                }
                if let forced = forced {
                    bestPlan = forced.candidate.plan
                    bestScore = forced.score
                }
            }
        }
        // Any SHOWY trick that ends up chosen — forced OR won on utility —
        // charges the deck cooldown. Plain splitkills are everyday play:
        // letting them recharge the cooldown starved the deck rotation and
        // Hudson stopped seeing tricks (v8.5 regression).
        if botMindIsTrick(bestPlan), botMindPlanKey(bestPlan) != "splitkill" {
            st.lastVisibleTrickAt = now
        }
        bestPlan.score = bestScore
        return bestPlan
    }

    private func botMindExecute(oid: UUID, brainIdx: Int, frame: BotOwnerFrame,
                                sense: BotMindBox.Sense, st: inout BotMindBox.BotState,
                                now: Double, dtThink: Double) {
        let brain = botCells[brainIdx]
        let myPos = BMVec(brain.position)
        let myR = Double(brain.cachedSolidRadius)
        let myTotal = Double(frame.mass)
        let persona = st.persona
        let aggression = Double(brain.aiAggression)
        st.plan.stageT += dtThink

        func steer(_ t: BMVec, _ mode: BotMode) {
            var target = BMVec(botMindClamp(t))
            var dir = BMVec(x: target.x - myPos.x,
                            y: target.y - myPos.y).normalized()
            if mode != .flee, mode != .hold, dir != .zero,
               st.lastTargetDir != .zero,
               dir.x * st.lastTargetDir.x + dir.y * st.lastTargetDir.y < -0.55 {
                dir = BMVec(x: st.lastTargetDir.x * 0.82 + dir.x * 0.18,
                            y: st.lastTargetDir.y * 0.82 + dir.y * 0.18).normalized()
                let reach = max(500, myPos.dist(target))
                target = BMVec(botMindClamp(BMVec(
                    x: myPos.x + dir.x * reach,
                    y: myPos.y + dir.y * reach)))
            }
            if dir != .zero { st.lastTargetDir = dir }
            st.moveTarget = target
            botCells[brainIdx].aiSteerTarget = target.cg
            botCells[brainIdx].aiMode = mode
            botCells[brainIdx].aiFleeing = false
        }
        func hold() {
            st.moveTarget = myPos
            botCells[brainIdx].aiSteerTarget = brain.position
            botCells[brainIdx].aiMode = .hold
            botCells[brainIdx].aiFleeing = false
        }
        /// hold with the cursor pinned on a specific point (the recombine
        /// receiver/pile): pieces converge onto it at full speed and stop there.
        func holdAt(_ t: BMVec) {
            let target = BMVec(botMindClamp(t))
            st.moveTarget = target
            botCells[brainIdx].aiSteerTarget = CGPoint(x: target.x, y: target.y)
            botCells[brainIdx].aiMode = .hold
            botCells[brainIdx].aiFleeing = false
        }
        func finish() {
            st.plan = BotMindBox.Plan(); st.plan.commitUntil = now
            st.recombineReceiver = nil
            st.recombineFeedDone = false
        }
        func splitAt(_ t: BMVec, cooldown: Double) {
            var dir = BMVec(x: t.x - myPos.x, y: t.y - myPos.y).normalized()
            if persona.aimJitter > 0.005, dir != .zero {
                let a = atan2(dir.y, dir.x) + Double.random(in: -persona.aimJitter...persona.aimJitter)
                dir = BMVec(x: cos(a), y: sin(a))
            }
            executeSplit(on: &botCells, for: oid, direction: dir.cgSize, toward: t.cg)
            botCells[brainIdx].aiSplitCooldown = cooldown
            st.lastSplitAt = now
        }
        @discardableResult
        func macro(toward t: BMVec, presses: Int, reserve: Double, speed: Double,
                   centre: Bool = false, exclude: BMVec? = nil, only: BMVec? = nil) -> Int {
            guard botCells[brainIdx].aiFeedCooldown <= 0 else { return 0 }
            let jitteredSpeed = min(1.6, max(0.35,
                speed + (1.0 - persona.ejectControl) * Double.random(in: -0.18...0.18)))
            let n = ejectMassFromBotOwner(oid, toward: t.cg, burstPresses: presses,
                                          reserveMass: CGFloat(reserve),
                                          centerConverge: centre,
                                          excludeNear: exclude?.cg,
                                          onlyNear: only?.cg,
                                          speedScale: jitteredSpeed)
            if n > 0 {
                botCells[brainIdx].aiFeedCooldown =
                    max(0.045, 0.17 - Double(persona.trickLevel) * 0.028)
            }
            return n
        }
        func preyNow() -> BotMindBox.Prey? {
            guard let eo = st.plan.enemyOwner else { return nil }
            if let cid = st.plan.enemyCell,
               let exact = sense.prey.first(where: { $0.id == cid }) { return exact }
            return sense.prey.filter { $0.ownerID == eo }.min { $0.dist < $1.dist }
        }
        func ownCellIndices() -> [Int] {
            var out: [Int] = []
            for i in botCells.indices where botCells[i].ownerID == oid { out.append(i) }
            return out
        }

        switch st.plan.kind {

        case .roam:
            steer(st.plan.target, .wander)

        case .forage:
            let fresh = st.plan.variant == 1 ? sense.pile : (st.plan.variant == 0 ? sense.food : sense.token)
            if let f = fresh, f.dist(st.plan.target) < 320,
               myPos.dist(st.plan.target) > 500 {
                st.plan.target = f
            }
            steer(st.plan.target, .forage)
            if myPos.dist(st.plan.target) < max(60, myR * 0.7) || st.plan.stageT > 5 { finish() }

        case .regroup:
            steer(st.plan.target, .regroup)
            if myPos.dist(st.plan.target) < myR { finish() }

        case .travel:
            switch st.plan.variant {
            case BotMindBox.tvAlly:
                steer(st.plan.target, .teamFormation)
                if myPos.dist(st.plan.target) < 680 { finish() }
            case BotMindBox.tvSplitRun:
                steer(st.plan.target, .travel)
                if st.plan.stage == 0 { botMind.bump("splitrun"); st.plan.stage = 1 }
                if frame.count <= 2, brain.aiSplitCooldown <= 0,
                   Double(brain.targetMass) >= 80, sense.threatScore < 0.06 {
                    let d = BMVec(x: st.plan.target.x - myPos.x,
                                  y: st.plan.target.y - myPos.y).normalized()
                    let landing = BMVec(x: myPos.x + d.x * 600, y: myPos.y + d.y * 600)
                    if !botMindSplitPunishable(sense, brainIdx: brainIdx, pieces: 2, toward: landing) {
                        splitAt(st.plan.target, cooldown: 1.2)
                    }
                }
            case BotMindBox.tvMacroSplitRun:
                steer(st.plan.target, .travel)
                if st.plan.stage == 0 {
                    if brain.aiSplitCooldown <= 0, Double(brain.targetMass) >= 80 {
                        let d = BMVec(x: st.plan.target.x - myPos.x,
                                      y: st.plan.target.y - myPos.y).normalized()
                        let landing = BMVec(x: myPos.x + d.x * 600, y: myPos.y + d.y * 600)
                        guard !botMindSplitPunishable(sense, brainIdx: brainIdx, pieces: 2, toward: landing) else {
                            finish(); return
                        }
                        splitAt(st.plan.target, cooldown: 1.0)
                        botMind.bump("macrosplitrun")
                        st.plan.stage = 1; st.plan.stageT = 0
                    }
                } else if st.plan.stageT > 1.4 {
                    finish()
                }
            case BotMindBox.tvWallRun:
                steer(st.plan.target, .travel)
                if st.plan.stage == 0 { botMind.bump("wallrun"); st.plan.stage = 1; st.plan.stageT = 0 }
                let lane = BMVec(x: st.plan.target.x - myPos.x,
                                 y: st.plan.target.y - myPos.y).normalized()
                if st.plan.stageT > 0.65, frame.count <= 4, brain.aiSplitCooldown <= 0,
                   Double(brain.targetMass) >= 80, sense.threatScore < 0.06 {
                    let landing = BMVec(x: myPos.x + lane.x * 600, y: myPos.y + lane.y * 600)
                    if !botMindSplitPunishable(sense, brainIdx: brainIdx, pieces: 2, toward: landing) {
                        splitAt(BMVec(x: myPos.x + lane.x * 900, y: myPos.y + lane.y * 900),
                                cooldown: 1.1)
                        st.plan.stageT = 0
                    }
                }
            default:
                steer(st.plan.target, .travel)
            }
            if myPos.dist(st.plan.target) < 300 { finish() }

        case .hunt:
            guard let prey = preyNow() else { finish(); return }
            if st.huntOwner != prey.ownerID {
                st.huntOwner = prey.ownerID
                st.huntTarget = prey.pos
            } else {
                st.huntTarget = BMVec(
                    x: st.huntTarget.x * 0.72 + prey.pos.x * 0.28,
                    y: st.huntTarget.y * 0.72 + prey.pos.y * 0.28)
            }
            st.plan.target = st.huntTarget
            steer(st.huntTarget, .hunt)
            botPreyFocus[oid] = prey.id

        case .splitKill:
            guard let prey = preyNow() else { finish(); return }
            st.plan.target = prey.pos
            steer(prey.pos, .hunt)
            let reach = (myR * 3.4 + 160) * (0.75 + aggression * 0.5)
            let laneDir = BMVec(x: prey.pos.x - myPos.x, y: prey.pos.y - myPos.y).normalized()
            if botMindVirusBlockingLane(sense, from: myPos, dir: laneDir,
                                        length: min(prey.dist, reach * 1.1), myR: myR * 0.62) != nil {
                finish(); return
            }
            switch st.plan.variant {
            case BotMindBox.skDouble:
                if st.plan.stage == 0, prey.dist < reach * 1.9,
                   Double(brain.targetMass) >= 80 {
                    guard !botMindSplitPunishable(sense, brainIdx: brainIdx, pieces: 4, toward: prey.pos) else {
                        finish(); return
                    }
                    splitAt(prey.pos, cooldown: 0.4)
                    st.plan.stage = 1; st.plan.stageT = 0
                } else if st.plan.stage == 1, st.plan.stageT > 0.22 {
                    // The second launch is not a promise. Re-verify the mark
                    // is still inside the follow-up envelope and still loses
                    // to a quarter — firing blind at where it USED to be was
                    // the visible over-commit.
                    if prey.dist < reach * 1.35, Double(brain.targetMass) / 2 > prey.mass * 1.30,
                       !botMindSplitPunishable(sense, brainIdx: brainIdx, pieces: 2, toward: prey.pos) {
                        splitAt(prey.pos, cooldown: 1.6 - aggression * 0.6)
                        botMind.bump("doublesplit"); finish()
                    } else if st.plan.stageT > 0.7 {
                        botMind.bump("doublesplit_held"); finish()
                    }
                }
            case BotMindBox.skMacroDouble:
                if st.plan.stage == 0 {
                    // Atomic contract: only invest pellets when both split
                    // presses can immediately reach the intended opponent.
                    guard prey.dist < reach * 2.6,
                          Double(brain.targetMass) / 4 > prey.mass * 1.30 else {
                        finish(); return
                    }
                    let n = macro(toward: prey.pos,
                                  presses: min(3, persona.macroPresses),
                                  reserve: myTotal * 0.68, speed: 1.0)
                    if n > 0 {
                        st.plan.stage = 1; st.plan.stageT = 0
                    } else if st.plan.stageT > 0.6 { finish() }
                } else if st.plan.stage == 1, prey.dist < reach * 1.9,
                          st.plan.stageT > 0.24 {
                    guard Double(brain.targetMass) / 2 > prey.mass * 1.25,
                          !botMindSplitPunishable(sense, brainIdx: brainIdx, pieces: 2, toward: prey.pos) else {
                        botMind.bump("macrodouble_held"); finish(); return
                    }
                    splitAt(prey.pos, cooldown: 1.6 - aggression * 0.6)
                    botMind.bump("macrodouble"); finish()
                } else if st.plan.stage == 1, st.plan.stageT > 0.65 {
                    finish()
                }
            default:
                if prey.dist < reach, Double(brain.targetMass) / 2 > prey.mass * 1.30,
                   !botMindSplitPunishable(sense, brainIdx: brainIdx, pieces: 2, toward: prey.pos) {
                    splitAt(prey.pos, cooldown: 1.4 - aggression * 0.6)
                    botMind.bump("splitkill"); finish()
                } else if st.plan.stageT > 2.0 { finish() }
            }

        case .bait:
            guard let prey = preyNow() else { finish(); return }
            switch st.plan.stage {
            case 0:
                let want = max(4, min(8, Int((myTotal / max(prey.mass, 40)).rounded())))
                if frame.count < want, brain.aiSplitCooldown <= 0,
                   Double(brain.targetMass) >= 80 {
                    let a = Double.random(in: 0...(2 * .pi))
                    executeSplit(on: &botCells, for: oid,
                                 direction: CGSize(width: cos(a), height: sin(a)))
                    botCells[brainIdx].aiSplitCooldown = 0.25
                } else if frame.count >= want {
                    st.plan.stage = 1; st.plan.stageT = 0
                    st.plan.baseCellCount = prey.ownerCellsNearby
                    botMind.bump("bait_set")
                }
                steer(BMVec(x: prey.pos.x + (myPos.x - prey.pos.x) * 0.6,
                            y: prey.pos.y + (myPos.y - prey.pos.y) * 0.6), .trick)
            case 1:
                steer(BMVec(x: prey.pos.x + (myPos.x - prey.pos.x) * 0.55,
                            y: prey.pos.y + (myPos.y - prey.pos.y) * 0.55), .trick)
                if prey.ownerCellsNearby > st.plan.baseCellCount {
                    st.plan.stage = 2; st.plan.stageT = 0
                }
            default:
                let own = ownCellIndices()
                guard let receiver = own.min(by: {
                    let a = BMVec(botCells[$0].position).distSq(prey.pos)
                    let b = BMVec(botCells[$1].position).distSq(prey.pos)
                    return a < b }) else { finish(); return }
                let rPos = BMVec(botCells[receiver].position)
                macro(toward: rPos, presses: persona.macroPresses,
                      reserve: myTotal * 0.15, speed: 0.8, centre: true, exclude: rPos)
                steer(prey.pos, .trick)
                if st.plan.stageT > 1.6 { botMind.bump("bait_flip"); finish() }
            }

        case .virusShoot:
            // No candidate emits this until a deterministic victim-hit
            // contract exists; never donate pellets speculatively.
            finish()

        case .recombine:
            let own = ownCellIndices()
            guard own.count > 1 else { finish(); return }
            var largest = own[0]
            for i in own where botCells[i].targetMass > botCells[largest].targetMass { largest = i }
            if let receiverID = st.recombineReceiver,
               let pinned = own.first(where: { botCells[$0].id == receiverID }) {
                largest = pinned
            } else {
                st.recombineReceiver = botCells[largest].id
            }
            let lPos = BMVec(botCells[largest].position)
            switch st.plan.variant {
            case BotMindBox.recWall:
                if st.plan.stage == 0 {
                    // Charge the attempt on ENTRY so an aborted compact can
                    // never re-offer instantly and freeze the bot in a loop.
                    st.lastRecombineAt = now
                    steer(st.plan.target, .trick)
                    if sense.wallDist < myR * 1.3 {
                        st.plan.stage = 1; st.plan.stageT = 0
                        botMind.bump("recombine_wall")
                        st.recombineFeedDone = false
                    }
                } else {
                    let compact = own.allSatisfy {
                        BMVec(botCells[$0].position).dist(lPos) <
                        Double(botCells[largest].cachedSolidRadius) +
                        Double(botCells[$0].cachedSolidRadius) + 120
                    }
                    if !st.recombineFeedDone {
                        holdAt(lPos)
                        if compact {
                            let n = macro(toward: lPos,
                                          presses: min(3, persona.macroPresses),
                                          reserve: max(80, myTotal * 0.42),
                                          speed: 0.35, centre: true, exclude: lPos)
                            if n > 0 {
                                // Pin the cursor on the PILE, not the live
                                // receiver: converging pieces shove the receiver
                                // off its own pellets. It walks back onto the
                                // pinned pile and absorbs it after the 1.0s grace.
                                st.plan.target = lPos
                                st.recombineFeedDone = true
                                st.plan.stageT = 0
                            }
                        } else if st.plan.stageT > 2.4 { finish() }
                    } else {
                        holdAt(st.plan.target)
                        if st.plan.stageT > 2.6 {
                            botMind.bump("recombine_wall_ok"); finish()
                        }
                    }
                }
            case BotMindBox.recMoving:
                // pellets only fly ~200u from each cell's rim and no own cell
                // may eat one for 1.0s. Human rhythm: tighten the stack while
                // rolling, burst forward, then COAST onto the pellet trail.
                steer(st.plan.target, .trick)
                let lane = BMVec(x: st.plan.target.x - myPos.x,
                                 y: st.plan.target.y - myPos.y).normalized()
                var lead = own[0]; var leadDot = -1e9
                for i in own {
                    let d = (Double(botCells[i].position.x) - myPos.x) * lane.x +
                            (Double(botCells[i].position.y) - myPos.y) * lane.y
                    if d > leadDot { leadDot = d; lead = i }
                }
                let leadPos = BMVec(botCells[lead].position)
                let leadR = Double(botCells[lead].cachedSolidRadius)
                var spreadM = 0.0
                for i in own { spreadM = max(spreadM, BMVec(botCells[i].position).dist(leadPos)) }
                if st.plan.stage == 0 {
                    botMind.bump("recombine_moving"); st.lastRecombineAt = now
                    st.plan.stage = 1; st.plan.stageT = 0
                }
                if st.plan.stage == 1 {
                    // .trick cohesion pulls the stack tight while we roll
                    if spreadM < leadR + 340 || st.plan.stageT > 1.6 { st.plan.stage = 2; st.plan.stageT = 0 }
                } else if st.plan.stage == 2 {
                    macro(toward: BMVec(x: leadPos.x + lane.x * 1200,
                                        y: leadPos.y + lane.y * 1200),
                          presses: persona.macroPresses,
                          reserve: max(60, myTotal * 0.25), speed: 1.45,
                          exclude: leadPos)
                    if st.plan.stageT > 1.1 {
                        st.plan.target = BMVec(x: leadPos.x + lane.x * (leadR + 170),
                                               y: leadPos.y + lane.y * (leadR + 170))
                        st.plan.stage = 3; st.plan.stageT = 0
                    }
                } else {
                    steer(st.plan.target, .trick)
                    if st.plan.stageT > 1.9 { finish() }
                }
            case BotMindBox.recInsta:
                let heading = BMVec(x: Double(brain.aiMovementDirection.width),
                                    y: Double(brain.aiMovementDirection.height))
                let dir = heading == .zero ? BMVec(x: 0, y: 1) : heading.normalized()
                var lead = own[0]; var leadDot = -1e9
                for i in own {
                    let d = (Double(botCells[i].position.x) - myPos.x) * dir.x +
                            (Double(botCells[i].position.y) - myPos.y) * dir.y
                    if d > leadDot { leadDot = d; lead = i }
                }
                let leadPos = BMVec(botCells[lead].position)
                if st.plan.stage == 0 {
                    botMind.bump("recombine_insta"); st.lastRecombineAt = now; st.plan.stage = 1
                }
                steer(BMVec(x: myPos.x + dir.x * 700, y: myPos.y + dir.y * 700), .trick)
                macro(toward: leadPos, presses: persona.macroPresses,
                      reserve: max(60, myTotal * 0.18), speed: 1.0,
                      centre: true, exclude: leadPos)
                if st.plan.stageT > 2.2 { finish() }
            default:
                // centre feed is a STOP trick: pin the cursor on the receiver —
                // every piece converges onto it at full speed and stops on
                // arrival, exactly like a human parking the mouse.
                if st.plan.stage == 0 {
                    // Charge the attempt on ENTRY (see recWall).
                    st.lastRecombineAt = now
                    holdAt(lPos)
                    let compact = own.allSatisfy {
                        BMVec(botCells[$0].position).dist(lPos) <
                        Double(botCells[largest].cachedSolidRadius) +
                        Double(botCells[$0].cachedSolidRadius) + 90
                    }
                    if compact {
                        st.plan.stage = 1; st.plan.stageT = 0
                        botMind.bump("recombine_centre")
                        st.recombineFeedDone = false
                    } else if st.plan.stageT > 2.4 { finish() }
                } else {
                    if !st.recombineFeedDone {
                        holdAt(lPos)
                        let n = macro(toward: lPos,
                                      presses: min(3, persona.macroPresses),
                                      reserve: max(80, myTotal * 0.45),
                                      speed: 0.35, centre: true, exclude: lPos)
                        if n > 0 {
                            // Pin the pile (see recWall).
                            st.plan.target = lPos
                            st.recombineFeedDone = true
                            st.plan.stageT = 0
                        } else if st.plan.stageT > 1.2 { finish() }
                    } else {
                        holdAt(st.plan.target)
                        if st.plan.stageT > 2.6 {
                            botMind.bump("recombine_centre_ok"); finish()
                        }
                    }
                }
            }

        case .escape:
            break
        }
        if st.plan.kind != .hunt { botPreyFocus.removeValue(forKey: oid) }
    }

    private func updateBotAI(dt: CGFloat, index: CellIndex) {
        guard !botCells.isEmpty else { return }
        let worldSize: CGFloat = 11000
        let globalSkill = CGFloat(max(0.3, min(2.0, botSkill)))
        
        // ---- 1. Group bookkeeping (single pass, one UUID dictionary) ----
        var owners = [UUID: BotOwnerFrame]()
        let estimatedOwners = min(botCells.count, max(16, targetBotCount + targetFeedBotCount))
        owners.reserveCapacity(estimatedOwners)
        var timedCells = botCells
        
        for i in timedCells.indices {
            let cell = timedCells[i]
            let oid = cell.ownerID
            var ownerSkill = globalSkill * cell.aiSkillTier.multiplier
            if playerTeammateOwnerID == oid {
                // A recruited teammate is always elite, regardless of the lobby-wide slider.
                ownerSkill = max(ownerSkill, 1.72)
            }
            ownerSkill = min(2.25, max(0.30, ownerSkill))
            
            if var owner = owners[oid] {
                owner.mass += cell.mass
                owner.weightedX += cell.position.x * cell.mass
                owner.weightedY += cell.position.y * cell.mass
                owner.count += 1
                if timedCells[owner.brainIndex].mass < cell.mass {
                    owner.brainIndex = i
                }
                owners[oid] = owner
            } else {
                owners[oid] = BotOwnerFrame(
                    brainIndex: i,
                    mass: cell.mass,
                    weightedX: cell.position.x * cell.mass,
                    weightedY: cell.position.y * cell.mass,
                    count: 1,
                    skill: ownerSkill
                )
            }
            
            // Timers tick on every cell: any of them can become the brain next frame.
            timedCells[i].aiThinkTimer -= dt
            if timedCells[i].aiSplitCooldown > 0 { timedCells[i].aiSplitCooldown -= dt }
            if timedCells[i].aiFeedCooldown > 0 { timedCells[i].aiFeedCooldown -= dt }
        }
        botCells = timedCells
        
        let pCenter = playerCenter
        let planningNow = CACurrentMediaTime()
        
        // ---- 2. Planning (only the brains whose clock fired this frame) ----
        for (oid, owner) in owners {
            let brainIdx = owner.brainIndex
            guard botCells[brainIdx].aiThinkTimer <= 0 else { continue }
            // Only this frame's brain owns the per-owner cursor; clear targets
            // left behind on former largest pieces so they cannot appear to
            // steer independently after a split/feed changes the brain.
            for i in botCells.indices where botCells[i].ownerID == oid && i != brainIdx {
                botCells[i].aiSteerTarget = nil
            }
            
            let brain = botCells[brainIdx]
            let skill = owner.skill
            let isPlayerTeammate = playerTeammateOwnerID == oid
            // Personal tiers produce ~230ms rookies through ~40ms elites. A recruited partner
            // stays in the elite band so macro and virus timing is genuinely responsive.
            let reaction = 0.145 - 0.072 * Double(min(1.6, skill))
            let reactionFloor = isPlayerTeammate ? 0.025 : 0.032
            
            let myPos = brain.position
            let myMass = brain.mass
            let myTotal = owner.mass
            let myR = brain.cachedSolidRadius
            let myCells = owner.count
            let groupTotalMass = max(owner.mass, 0.0001)
            let groupCentre = CGPoint(x: owner.weightedX / groupTotalMass,
                                      y: owner.weightedY / groupTotalMass)
            let groupSpread = sqrt(pow(groupCentre.x - myPos.x, 2) + pow(groupCentre.y - myPos.y, 2))
            
            // Keep movement/physics full-rate, but ordinary bots far outside the camera plan
            // less often. This removes most world-wide AI queries in high-bot lobbies without
            // changing a single rendered frame or slowing the recruited teammate/feed bots.
            let nearCamera = visibleWorldRect.isEmpty
            || visibleWorldRect.insetBy(dx: -1400, dy: -1400).contains(myPos)
            let offscreenPlanningMultiplier: Double
            if !nearCamera && !isPlayerTeammate && !brain.isFeedBot {
                offscreenPlanningMultiplier = botAlliancePartners[oid] == nil ? 2.6 : 1.7
            } else {
                offscreenPlanningMultiplier = 1.0
            }
            let reactionJitter = skill >= 1.2 ? Double.random(in: 0.94...1.06)
                                               : Double.random(in: 0.86...1.14)
            let randomizedReaction = max(reactionFloor, reaction) *
                                     offscreenPlanningMultiplier * reactionJitter
            botCells[brainIdx].aiThinkTimer = randomizedReaction
            
            if isPlayerTeammate {
                planPlayerTeammate(brainIndex: brainIdx,
                                   ownerID: oid,
                                   brain: brain,
                                   teammateTotalMass: myTotal,
                                   teammateCentre: groupCentre,
                                   teammateCellCount: myCells,
                                   skill: skill,
                                   index: index,
                                   now: planningNow)
                continue
            }
            
            // ---- 2a. v5.8 feed bots: run at the player and ALL-IN — close the
            // gap, then spam splits into them so the player inhales the pieces;
            // leftovers too small to split get ejected point-blank instead.
            if brain.isFeedBot {
                let dx = pCenter.x - myPos.x
                let dy = pCenter.y - myPos.y
                let dist = sqrt(dx * dx + dy * dy)
                botCells[brainIdx].aiFleeing = false
                
                if myTotal >= 60 {
                    botCells[brainIdx].aiMode = .feedPlayer
                    botCells[brainIdx].aiSteerTarget = pCenter
                    // a split piece launches ~3.6 radii + a bit; only all-in
                    // once the payload actually lands on the player
                    let splitReach = myR * 3.6 + 200
                    if dist > 1, dist < splitReach, botCells[brainIdx].aiFeedCooldown <= 0 {
                        if myCells < 16, brain.targetMass >= 40 {
                            executeSplit(on: &botCells, for: oid,
                                         direction: .zero, toward: pCenter)
                            botCells[brainIdx].aiFeedCooldown = 0.12
                        } else if dist < myR + 120 {
                            // on top of the player, nothing left to split:
                            // drain the rest as point-blank pellets
                            let fired = ejectMassFromBotOwner(
                                oid,
                                toward: pCenter,
                                burstPresses: 2,
                                reserveMass: 16
                            )
                            if fired > 0 { botCells[brainIdx].aiFeedCooldown = 0.08 }
                        }
                    }
                } else {
                    // Refill first, otherwise feeders starve themselves down to nothing
                    // and just trail the player uselessly (which is what they did before).
                    botCells[brainIdx].aiMode = .forage
                    botCells[brainIdx].aiSteerTarget = foodManager.bestFoodCluster(near: myPos, searchBuckets: 4) ?? pCenter
                }
                continue
            }
            
            // ---- 2b-2d. v8 BotMind: plan-based utility brain (perception,
            // candidate scoring, committed plans, trick state machines).
            var allyCentre: CGPoint? = nil
            var allyMass: CGFloat = 0
            if let partnerID = botAlliancePartners[oid],
               let partner = owners[partnerID], partner.mass > 0 {
                let pc = CGPoint(x: partner.weightedX / partner.mass,
                                 y: partner.weightedY / partner.mass)
                allyCentre = pc
                allyMass = partner.mass
                // allied pairs still rebalance mass with a real macro burst
                let allyDistance = hypot(pc.x - myPos.x, pc.y - myPos.y)
                if myTotal > partner.mass * 1.65, allyDistance < 680,
                   botCells[brainIdx].aiFeedCooldown <= 0 {
                    let fired = ejectMassFromBotOwner(
                        oid, toward: pc,
                        burstPresses: skill >= 1.0 ? 2 : 1,
                        reserveMass: max(64, partner.mass * 1.12))
                    if fired > 0 { botCells[brainIdx].aiFeedCooldown = max(0.06, 0.16 - Double(skill) * 0.05) }
                }
            }
            botMindThink(oid: oid, brainIdx: brainIdx, frame: owner, skill: skill,
                         index: index, now: planningNow,
                         allyCentre: allyCentre, allyMass: allyMass)
        }
        
        // v8: prune BotMind state for owners that no longer exist
        if botMind.states.count > owners.count + 24 {
            for key in botMind.states.keys where owners[key] == nil {
                botMind.forget(key)
            }
        }
        
        // ---- 3. Steering (every cell, every frame, framerate independent) ----
        var ownerCursors = [UUID: CGPoint]()
        ownerCursors.reserveCapacity(owners.count)
        for (oid, owner) in owners {
            if let target = botMind.states[oid]?.moveTarget, target != .zero {
                ownerCursors[oid] = target.cg
            } else if let target = botCells[owner.brainIndex].aiSteerTarget {
                ownerCursors[oid] = target
            }
        }
        for i in botCells.indices {
            let oid = botCells[i].ownerID
            guard let owner = owners[oid] else { continue }
            let brainIdx = owner.brainIndex
            let mode = botCells[brainIdx].aiMode
            let skill = owner.skill
            
            var desired = CGSize.zero
            if let t = ownerCursors[oid] {
                desired = CGSize(width: t.x - botCells[i].position.x, height: t.y - botCells[i].position.y)
                // Normalize early so cohesion below is weighted consistently.
                desired = desired.normalized()
            }
            
            if owner.count > 1, owner.mass > 0 {
                let cx = (owner.weightedX / owner.mass) - botCells[i].position.x
                let cy = (owner.weightedY / owner.mass) - botCells[i].position.y
                let cohesionDir = CGSize(width: cx, height: cy).normalized()
                
                var pull: CGFloat = 0.04
                switch mode {
                case .regroup: pull = botCells[i].canMerge ? 2.2 : 0.45
                case .flee: pull = botCells[i].canMerge ? 0.9 : 0.06
                case .hunt: pull = botCells[i].canMerge ? 0.5 : 0.05
                case .travel: pull = 0
                case .hold, .trick: pull = botCells[i].canMerge ? 1.6 : 0.30
                default: pull = botCells[i].canMerge ? 1.2 : 0.04
                }
                desired.width += cohesionDir.width * pull
                desired.height += cohesionDir.height * pull
            }
            
            // Friendly fire stays enabled, but a team's final bot cell should not volunteer
            // itself to a larger ally. Loose split pieces remain available for trick transfers.
            if owner.count == 1 {
                func addLastCellAvoidance(from allyPosition: CGPoint,
                                          allyMass: CGFloat,
                                          allyRadius: CGFloat) {
                    guard allyMass > botCells[i].mass * 1.12 else { return }
                    var dx = botCells[i].position.x - allyPosition.x
                    var dy = botCells[i].position.y - allyPosition.y
                    var distance = hypot(dx, dy)
                    let safetyDistance = botCells[i].cachedVisualRadius + allyRadius + 95
                    guard distance < safetyDistance else { return }
                    if distance < 1 {
                        dx = botCells[i].position.x - pCenter.x
                        dy = botCells[i].position.y - pCenter.y
                        distance = max(hypot(dx, dy), 1)
                        if dx == 0 && dy == 0 { dx = 1 }
                    }
                    let strength = 4.5 * (1.0 - distance / safetyDistance)
                    desired.width += (dx / distance) * strength
                    desired.height += (dy / distance) * strength
                }
                
                if playerTeammateOwnerID == oid {
                    for playerCell in playerCells {
                        addLastCellAvoidance(from: playerCell.position,
                                             allyMass: playerCell.mass,
                                             allyRadius: playerCell.cachedVisualRadius)
                    }
                } else if let partnerID = botAlliancePartners[oid] {
                    index.forEach(near: botCells[i].position, radius: 900) { ally in
                        guard ally.ownerID == partnerID else { return }
                        addLastCellAvoidance(from: CGPoint(x: ally.x, y: ally.y),
                                             allyMass: ally.mass,
                                             allyRadius: ally.radius)
                    }
                }
            }
            
            // v8.4 hold: hold PINS the cursor, it does not freeze the owner.
            // Every piece keeps walking onto the cursor at full speed and only
            // pieces that have actually arrived stand still — the old blanket
            // damp froze whole bots and centre-feed stacks never compacted.
            var bmArrived = false
            if let t = ownerCursors[oid] {
                let ddx = botCells[i].position.x - t.x
                let ddy = botCells[i].position.y - t.y
                if mode == .hold {
                    let stopR = max(CGFloat(30), botCells[i].cachedVisualRadius * 0.30)
                    if ddx * ddx + ddy * ddy < stopR * stopR { bmArrived = true }
                } else if i == brainIdx, ddx * ddx + ddy * ddy < 900 {
                    bmArrived = true
                }
            }
            if bmArrived && (mode == .hold || desired.width * desired.width + desired.height * desired.height < 0.05) {
                let damp = 1.0 - getLerpFactor(base: 0.35, dt: dt)
                botCells[i].aiMovementDirection = CGSize(
                    width: botCells[i].aiMovementDirection.width * damp,
                    height: botCells[i].aiMovementDirection.height * damp
                )
                continue
            }
            if desired.width == 0 && desired.height == 0 {
                desired = botCells[i].aiMovementDirection == .zero
                    ? CGSize(width: 1, height: 0)
                    : botCells[i].aiMovementDirection
            }
            
            let targetDir = desired.normalized()
            let currentVel = botCells[i].aiMovementDirection
            // Framerate independent turn rate (was a flat 0.1 per frame).
            let turnBase = min(0.55, (mode == .flee ? 0.30 : 0.18) * max(0.5, min(1.6, skill)))
            let turn = getLerpFactor(base: turnBase, dt: dt)
            var bmApproachCap: CGFloat = 1.0
            // Gentle final approach onto a pinned hold cursor: full speed in,
            // easing over the last stretch, so pieces don't overshoot, get
            // shoved, and ping-pong back.
            if mode == .hold, let t = ownerCursors[oid] {
                let stopR = max(CGFloat(30), botCells[i].cachedVisualRadius * 0.30)
                let dd = hypot(botCells[i].position.x - t.x, botCells[i].position.y - t.y)
                bmApproachCap = min(1.0, dd / (stopR * 2.5))
            }
            botCells[i].aiMovementDirection = CGSize(
                width: (currentVel.width + (targetDir.width - currentVel.width) * turn) * bmApproachCap,
                height: (currentVel.height + (targetDir.height - currentVel.height) * turn) * bmApproachCap
            )
        }
    }
    
    private func moveBots(dt: CGFloat) {
        let worldSize: CGFloat = 11000
        let timeScale = dt * 60.0
        // Mutate one uniquely owned local array, then publish one State write. Directly
        // subscript-mutating @State dozens of times per cell repeatedly entered its modify
        // accessor even though SwiftUI coalesced the eventual redraw.
        var cells = botCells
        
        var idToIndex = [UUID: Int]()
        if cells.contains(where: { $0.splitImmunityTimer <= 0 && $0.immuneToCellID != nil }) {
            idToIndex.reserveCapacity(cells.count)
            for i in cells.indices { idToIndex[cells[i].id] = i }
        }
        
        for i in cells.indices {
            if cells[i].splitImmunityTimer > 0 {
                cells[i].splitImmunityTimer -= dt
                if cells[i].splitImmunityTimer <= 0 { cells[i].immuneToCellID = nil }
            } else if let targetID = cells[i].immuneToCellID {
                if let tIdx = idToIndex[targetID] {
                    let targetCell = cells[tIdx]
                    let r1 = cells[i].cachedVisualRadius
                    let r2 = targetCell.cachedVisualRadius
                    let dx = cells[i].position.x - targetCell.position.x
                    let dy = cells[i].position.y - targetCell.position.y
                    let distSq = dx*dx + dy*dy
                    let totalR = r1 + r2
                    if distSq > totalR * totalR { cells[i].immuneToCellID = nil }
                } else { cells[i].immuneToCellID = nil }
            }
            
            let distanceThisFrame = cells[i].cachedMovementSpeed * dt
            let moveDir = cells[i].aiMovementDirection.normalized()
            
            cells[i].position.x += moveDir.width * distanceThisFrame
            cells[i].position.y += moveDir.height * distanceThisFrame
            
            cells[i].position.x += cells[i].velocity.width * timeScale
            cells[i].position.y += cells[i].velocity.height * timeScale
            
            let decayFactor = pow(0.92, timeScale)
            let splitDecayFactor = pow(0.96, timeScale)
            
            if cells[i].splitTimer > 0 {
                cells[i].velocity.width *= splitDecayFactor
                cells[i].velocity.height *= splitDecayFactor
                cells[i].splitTimer -= dt
            } else {
                cells[i].velocity.width *= decayFactor
                cells[i].velocity.height *= decayFactor
            }
            
            let visualRadius = cells[i].cachedVisualRadius
            let hardPhysicsRadius = visualRadius * 0.55
            
            if cells[i].position.x < hardPhysicsRadius { cells[i].position.x = hardPhysicsRadius; cells[i].velocity.width = 0 }
            else if cells[i].position.x > worldSize - hardPhysicsRadius { cells[i].position.x = worldSize - hardPhysicsRadius; cells[i].velocity.width = 0 }
            
            if cells[i].position.y < hardPhysicsRadius { cells[i].position.y = hardPhysicsRadius; cells[i].velocity.height = 0 }
            else if cells[i].position.y > worldSize - hardPhysicsRadius { cells[i].position.y = worldSize - hardPhysicsRadius; cells[i].velocity.height = 0 }
        }
        botCells = cells
    }
    
    // MARK: - CELL vs CELL (unified, spatially indexed)
    //
    // Replaces handleBotVsPlayerCollisions() + handleBotVsBotCollisions(). Those were two
    // nested loops over every cell in the world (with 100 bots x up to 16 cells that is
    // ~1.2M distance checks per frame, every frame). Same eat rules, one pass, grid-limited.
    @discardableResult
    private func handleCellVsCellCollisions(index: CellIndex) -> Bool {
        let playerOwnerBeforeCollisions = currentPlayerOwnerID
        var botsToRemove = Set<Int>()
        var playersToRemove = Set<Int>()
        var dyingCells: [PlayerCell] = []
        // victim -> immediate eater. Resolving this graph after detection preserves mass when
        // A eats B in the same tick that C eats A: C receives both A and B instead of B's gain
        // being applied to an array element that is about to be removed.
        var eaterByVictimID: [UUID: UUID] = [:]
        var eatenMassByVictimID: [UUID: CGFloat] = [:]
        
        for eater in index.items {
            if eater.isPlayer {
                if playersToRemove.contains(eater.index) { continue }
            } else if botsToRemove.contains(eater.index) {
                continue
            }
            
            index.forEach(near: CGPoint(x: eater.x, y: eater.y), radius: eater.radius) { victim in
                if victim.id == eater.id { return }
                if victim.ownerID == eater.ownerID { return }
                if !teamFriendlyFireEnabled && areOwnersAllied(eater.ownerID, victim.ownerID) {
                    return
                }
                if eater.mass <= victim.mass * (4.0 / 3.0) { return }
                if victim.isPlayer {
                    if playersToRemove.contains(victim.index) { return }
                } else if botsToRemove.contains(victim.index) {
                    return
                }
                
                let overlapFactor: CGFloat = 0.5
                let threshold = eater.solidRadius - victim.solidRadius * overlapFactor
                if threshold <= 0 { return }
                
                let dx = eater.x - victim.x
                if dx < -threshold || dx > threshold { return }
                let dy = eater.y - victim.y
                if dy < -threshold || dy > threshold { return }
                if dx * dx + dy * dy >= threshold * threshold { return }
                
                eaterByVictimID[victim.id] = eater.id
                eatenMassByVictimID[victim.id] = victim.mass
                
                if victim.isPlayer {
                    if victim.index < playerCells.count {
                        var dying = playerCells[victim.index]
                        dying.eaterID = eater.id
                        dyingCells.append(dying)
                    }
                    playersToRemove.insert(victim.index)
                } else {
                    if victim.index < botCells.count {
                        var dying = botCells[victim.index]
                        dying.eaterID = eater.id
                        dyingCells.append(dying)
                    }
                    botsToRemove.insert(victim.index)
                }
            }
        }
        
        if !eaterByVictimID.isEmpty {
            func terminalEater(startingAt eaterID: UUID) -> UUID {
                var terminal = eaterID
                var remainingHops = eaterByVictimID.count + 1
                // Mass strictly increases along an eat edge, so a cycle is impossible. The
                // hop guard still keeps this robust against future rule changes.
                while remainingHops > 0, let next = eaterByVictimID[terminal] {
                    terminal = next
                    remainingHops -= 1
                }
                return terminal
            }
            
            var terminalGains: [UUID: CGFloat] = [:]
            terminalGains.reserveCapacity(eaterByVictimID.count)
            for (victimID, immediateEaterID) in eaterByVictimID {
                let terminalID = terminalEater(startingAt: immediateEaterID)
                terminalGains[terminalID, default: 0] += eatenMassByVictimID[victimID] ?? 0
            }
            
            var snapshotsByID: [UUID: CellSnapshot] = [:]
            snapshotsByID.reserveCapacity(index.items.count)
            for snapshot in index.items { snapshotsByID[snapshot.id] = snapshot }
            
            // Dual-width skins: a player cell directly swallowing another player's/bot's
            // cell this frame arms the artwork swap (accepted only while the swap is idle).
            for eaterID in eaterByVictimID.values where snapshotsByID[eaterID]?.isPlayer == true {
                triggerDualSkinSwap(now: CACurrentMediaTime())
                SoundManager.shared.play(.eatCell)
                break
            }
            
            for (terminalID, mass) in terminalGains {
                guard let terminal = snapshotsByID[terminalID] else { continue }
                if terminal.isPlayer {
                    if terminal.index < playerCells.count {
                        playerCells[terminal.index].targetMass += mass
                    }
                } else if terminal.index < botCells.count {
                    botCells[terminal.index].targetMass += mass
                }
            }
            
            // Animation also follows the surviving terminal eater rather than a cell that may
            // itself vanish later in this collision pass.
            for i in dyingCells.indices {
                if let immediate = dyingCells[i].eaterID {
                    dyingCells[i].eaterID = terminalEater(startingAt: immediate)
                }
            }
        }
        
        if !dyingCells.isEmpty {
            animatingEatenCells.append(contentsOf: dyingCells)
        }
        
        if !playersToRemove.isEmpty {
            for i in playersToRemove.sorted(by: >) where i < playerCells.count {
                playerCells.remove(at: i)
            }
            let playerDied: Bool
            if let oldOwner = playerOwnerBeforeCollisions {
                playerDied = !playerCells.contains(where: { $0.ownerID == oldOwner })
            } else {
                playerDied = false
            }
            if playerDied || playerCells.isEmpty {
                // The old teammate pact and handshake never carry into the next match.
                resetPlayerTeammateState()
            }
            if playerCells.isEmpty && !isGameOverPresented && !isDeathSequencePending {
                isDeathSequencePending = true
                SoundManager.shared.play(.gameOver)
                matchSurvivalSeconds = max(0, Int(CACurrentMediaTime() - matchStartTime))
                joystickIsDragging = false
                joystickOffset = .zero
                joystickBasePosition = nil
                isFeedingHeld = false
                isMacroHeld = false
                withAnimation(.easeOut(duration: 0.5)) {
                    zoomLevel = max(0.35, zoomLevel * 0.72)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard isPlaying, playerCells.isEmpty else {
                        isDeathSequencePending = false
                        return
                    }
                    isDeathSequencePending = false
                    isGameOverPresented = true
                }
            }
        }
        
        if !botsToRemove.isEmpty {
            for i in botsToRemove.sorted(by: >) where i < botCells.count {
                botCells.remove(at: i)
            }
            refreshLiveBotOwnerSets()
            // If the recruited owner lost its final split, or one member of a rare bot pair
            // died, relationships reset immediately as requested.
            cleanupTeamRelationships()
        }
        return !playersToRemove.isEmpty || !botsToRemove.isEmpty
    }
    
    
    /// Hook for FoodManager.checkCollisions: starts one magnet-suck animation for a
    /// pellet the given cell just consumed.
    private func registerConsumedFood(_ food: Food, eaterCellID: UUID) {
        consumeAnimations.append(ConsumedPickupAnimation(
            kind: .food(colorIndex: food.colorIndex),
            position: food.position,
            eaterCellID: eaterCellID))
        if playerCells.contains(where: { $0.id == eaterCellID }) {
            let target = offlineQuestStage == 0 ? 70 : (offlineQuestStage == 1 ? 150 : 300)
            offlineQuestProgress += 1
            if offlineQuestProgress >= target {
                offlineQuestProgress = 0
                offlineQuestStage = (offlineQuestStage + 1) % 3
                let prevCoins = UserDefaults.standard.integer(forKey: "macro.coins")
                UserDefaults.standard.set(prevCoins + 50, forKey: "macro.coins")
            }
        }
    }
    
    private func updateEatenCellsAnimation(dt: CGFloat) {
        // The pickup magnet-suck shares the eaten-cell glide factor exactly.
        updateConsumedPickupAnimations(&consumeAnimations,
                                       playerCells: playerCells,
                                       botCells: botCells,
                                       glideSpeedFactor: getLerpFactor(base: 0.25, dt: dt),
                                       dt: dt)
        guard !animatingEatenCells.isEmpty else { return }
        // Massively increase glide speed factor so eaten cells disappear extremely fast natively 
        let glideSpeedFactor = getLerpFactor(base: 0.20, dt: dt) 
        
        var allPositions = [UUID: CGPoint]()
        var allRadii = [UUID: CGFloat]()
        for c in playerCells { 
            allPositions[c.id] = c.position
            allRadii[c.id] = c.cachedVisualRadius
        }
        for c in botCells { 
            allPositions[c.id] = c.position 
            allRadii[c.id] = c.cachedVisualRadius
        }
        
        var i = animatingEatenCells.count - 1
        while i >= 0 {
            var targetPos: CGPoint? = nil
            var targetRad: CGFloat = 0
            
            if let eID = animatingEatenCells[i].eaterID { 
                targetPos = allPositions[eID] 
                targetRad = allRadii[eID] ?? 20
            }
            
            if let tPos = targetPos {
                // Exact IPA AgarCellView::onBeingEaten (0x1002801b0): 0.12s move to eater center.
                let eatDuration: CGFloat = 0.12
                animatingEatenCells[i].splitImmunityTimer += dt
                let elapsed = animatingEatenCells[i].splitImmunityTimer
                let dx = tPos.x - animatingEatenCells[i].position.x
                let dy = tPos.y - animatingEatenCells[i].position.y
                let distanceSq = dx*dx + dy*dy

                if elapsed >= eatDuration || distanceSq < 16.0 {
                    animatingEatenCells.swapAt(i, animatingEatenCells.count - 1)
                    animatingEatenCells.removeLast()
                } else {
                    let frac = min(1.0, dt / max(0.001, eatDuration - elapsed))
                    animatingEatenCells[i].position.x += dx * frac
                    animatingEatenCells[i].position.y += dy * frac
                }
            } else {
                animatingEatenCells.swapAt(i, animatingEatenCells.count - 1)
                animatingEatenCells.removeLast()
            }
            i -= 1
        }
    }
    
    
    // MARK: - EJECTED MASS COLLISIONS
    //
    // The old version rebuilt a full cell grid every frame AND then iterated
    // `massManager.staticGrid.keys` - i.e. every settled pellet in the entire world, forever,
    // even the ones nobody is anywhere near. After a few macro bursts that alone was
    // thousands of dictionary lookups per frame. Now: shared cell index, and only the
    // buckets that actually touch a cell get inspected.
    private func feedVirusAndLaunchIfReady(
        at virusIndex: Int,
        with mass: EjectedMass,
        launchedViruses: inout [Virus]
    ) {
        guard virusIndex >= 0, virusIndex < viruses.count else { return }
        
        let launchRadius = viruses[virusIndex].radius
        viruses[virusIndex].targetMass += mass.mass
        viruses[virusIndex].mass += mass.mass * 0.35 // Tactile hit-pulse expansion before settling
        viruses[virusIndex].fedMass += mass.mass
        guard viruses[virusIndex].targetMass
                >= viruses[virusIndex].splitThreshold else { return }
        
        viruses[virusIndex].mass = 220
        viruses[virusIndex].targetMass = 220
        viruses[virusIndex].fedMass = 0
        
        let normalizedMassDirection = mass.direction.normalized()
        let shootDirection: CGSize
        if normalizedMassDirection == .zero {
            shootDirection = CGSize(width: 0, height: 1)
        } else {
            shootDirection = normalizedMassDirection
        }
        let offsetDistance = launchRadius + 60
        let startPosition = CGPoint(
            x: viruses[virusIndex].position.x
            + shootDirection.width * offsetDistance,
            y: viruses[virusIndex].position.y
            + shootDirection.height * offsetDistance
        )
        var newVirus = Virus(position: startPosition, mass: 220)
        newVirus.targetMass = 220
        newVirus.velocity = CGSize(
            width: shootDirection.width * 1200,
            height: shootDirection.height * 1200
        )
        launchedViruses.append(newVirus)
    }
    
    private func performOptimizedMassCollisions(nowTS: TimeInterval, index: CellIndex) {
        let gracePeriod: TimeInterval = 1.0
        
        // --- 1. Flying mass vs cells, then viruses ---
        // One reverse walk preserves the old priority (cells first, virus second) while
        // eliminating a second full active-pellet pass and a second round of removals.
        var launchedViruses: [Virus] = []
        var i = massManager.activeMasses.count - 1
        while i >= 0 {
            let mass = massManager.activeMasses[i]
            let isImmune = (nowTS - mass.creationTime) < gracePeriod
            var eaten = false
            
            index.forEach(near: mass.position, radius: 1) { c in
                if eaten { return }
                // Player parity: the 1.0s grace blocks EVERY own cell —
                // the original game's self-feed pickup delay.
                if isImmune && c.ownerID == mass.ownerID { return }
                // v5.8: a sub-21-mass cell can never re-eat its own pellet
                if c.ownerID == mass.ownerID && c.mass < 21 { return }
                // v5.9.3: pickup needs ~30% of the pellet's circle covered
                // (chord rule: reach = R_cell + 8.1) — a rim graze no longer
                // consumes. Mass still credits instantly at the trigger.
                let reach = c.radius + 8.1
                let dx = mass.position.x - c.x
                if dx < -reach || dx > reach { return }
                let dy = mass.position.y - c.y
                if dy < -reach || dy > reach { return }
                if dx * dx + dy * dy < reach * reach {
                    if c.isPlayer {
                        if c.index < playerCells.count { playerCells[c.index].massToAbsorb += mass.mass }
                    } else {
                        if c.index < botCells.count {
                            botCells[c.index].massToAbsorb += mass.mass
                            registerRecruitmentPellet(mass, consumedBy: c)
                            registerTeammateMassReceipt(mass, consumedBy: c)
                            registerForcedFeedCommandPellet(mass, consumedBy: c, now: nowTS)
                        }
                    }
                    consumeAnimations.append(ConsumedPickupAnimation(
                        kind: .ejected(styleID: mass.styleID),
                        position: mass.renderPosition,
                        eaterCellID: c.id))
                    eaten = true
                }
            }
            
            if !eaten, !viruses.isEmpty {
                worldObjectIndex.forEachVirusIndex(
                    near: mass.position,
                    radius: 130
                ) { virusIndex in
                    if eaten { return }
                    guard virusIndex < viruses.count else { return }
                    let virus = viruses[virusIndex]
                    let dx = mass.position.x - virus.position.x
                    let virusRadius = virus.radius
                    if dx < -virusRadius || dx > virusRadius { return }
                    let dy = mass.position.y - virus.position.y
                    if dy < -virusRadius || dy > virusRadius { return }
                    
                    let virusRadiusSq = virus.mass * 28.09
                    if dx * dx + dy * dy < virusRadiusSq {
                        feedVirusAndLaunchIfReady(
                            at: virusIndex,
                            with: mass,
                            launchedViruses: &launchedViruses
                        )
                        eaten = true
                    }
                }
            }
            
            if eaten {
                massManager.activeMasses.swapAt(i, massManager.activeMasses.count - 1)
                massManager.activeMasses.removeLast()
            }
            i -= 1
        }
        // --- 2. Settled mass vs cells (only buckets near a cell) ---
        if !massManager.staticGrid.isEmpty {
            var keysNearCells = Set<GridKey>()
            keysNearCells.reserveCapacity(min(massManager.staticGrid.count, index.items.count * 4))
            for c in index.items {
                massManager.forEachStaticBucketKey(near: CGPoint(x: c.x, y: c.y), radius: c.radius) { key in
                    keysNearCells.insert(key)
                }
            }
            
            for key in keysNearCells {
                guard var bucket = massManager.staticGrid[key], !bucket.isEmpty else { continue }
                var changed = false
                
                var j = bucket.count - 1
                while j >= 0 {
                    let mass = bucket[j]
                    let isImmune = (nowTS - mass.creationTime) < gracePeriod
                    var eaten = false
                    
                    index.forEach(near: mass.position, radius: 1) { c in
                        if eaten { return }
                        // Player parity: the 1.0s grace blocks EVERY own cell —
                // the original game's self-feed pickup delay.
                if isImmune && c.ownerID == mass.ownerID { return }
                        // v5.8: a sub-21-mass cell can never re-eat its own pellet
                        if c.ownerID == mass.ownerID && c.mass < 21 { return }
                        // v5.9.3: ~30% pellet coverage required (reach = R_cell + 8.1)
                        let reach = c.radius + 8.1
                        let dx = mass.position.x - c.x
                        if dx < -reach || dx > reach { return }
                        let dy = mass.position.y - c.y
                        if dy < -reach || dy > reach { return }
                        if dx * dx + dy * dy < reach * reach {
                            if c.isPlayer {
                                if c.index < playerCells.count { playerCells[c.index].massToAbsorb += mass.mass }
                            } else {
                                if c.index < botCells.count {
                                    botCells[c.index].massToAbsorb += mass.mass
                                    registerRecruitmentPellet(mass, consumedBy: c)
                                    registerTeammateMassReceipt(mass, consumedBy: c)
                                    registerForcedFeedCommandPellet(mass, consumedBy: c, now: nowTS)
                                }
                            }
                            consumeAnimations.append(ConsumedPickupAnimation(
                                kind: .ejected(styleID: mass.styleID),
                                position: mass.position,
                                eaterCellID: c.id))
                            eaten = true
                        }
                    }
                    
                    if eaten {
                        bucket.swapAt(j, bucket.count - 1)
                        bucket.removeLast()
                        changed = true
                    }
                    j -= 1
                }
                
                if changed {
                    if bucket.isEmpty { massManager.staticGrid.removeValue(forKey: key) }
                    else { massManager.staticGrid[key] = bucket }
                }
            }
        }
        
        // --- 3. Viruses swallow settled mass (feeding a virus to split it) ---
        var v = viruses.count - 1
        while v >= 0 {
            let vPos = viruses[v].position
            let vRad = viruses[v].radius
            let vRadSq = vRad * vRad
            
            let minX = Int((vPos.x - vRad) / massManager.gridSize)
            let maxX = Int((vPos.x + vRad) / massManager.gridSize)
            let minY = Int((vPos.y - vRad) / massManager.gridSize)
            let maxY = Int((vPos.y + vRad) / massManager.gridSize)
            
            for x in gridRange(minX, maxX) {
                for y in gridRange(minY, maxY) {
                    let key = GridKey(x: x, y: y)
                    guard var bucket = massManager.staticGrid[key] else { continue }
                    var changed = false
                    
                    var j = bucket.count - 1
                    while j >= 0 {
                        let mass = bucket[j]
                        let dx = mass.position.x - vPos.x
                        if dx < -vRad || dx > vRad { j -= 1; continue }
                        let dy = mass.position.y - vPos.y
                        if dy < -vRad || dy > vRad { j -= 1; continue }
                        
                        if dx*dx + dy*dy < vRadSq {
                            feedVirusAndLaunchIfReady(
                                at: v,
                                with: mass,
                                launchedViruses: &launchedViruses
                            )
                            bucket.swapAt(j, bucket.count - 1)
                            bucket.removeLast()
                            changed = true
                        }
                        j -= 1
                    }
                    if changed {
                        if bucket.isEmpty { massManager.staticGrid.removeValue(forKey: key) }
                        else { massManager.staticGrid[key] = bucket }
                    }
                }
            }
            v -= 1
        }
        
        // Append only after both flying and settled collision passes. Newly launched viruses
        // therefore cannot recursively consume the same pile in the frame that creates them.
        if !launchedViruses.isEmpty {
            viruses.append(contentsOf: launchedViruses)
            virusIndexDirty = true
        }
    }
    
    @discardableResult
    private func moveViruses(dt: CGFloat) -> Bool {
        let worldSize: CGFloat = 11000
        let timeScale = dt * 60.0
        var movedAny = false
        for i in viruses.indices {
            if viruses[i].velocity.width != 0 || viruses[i].velocity.height != 0 {
                movedAny = true
                viruses[i].position.x += viruses[i].velocity.width * dt
                viruses[i].position.y += viruses[i].velocity.height * dt
                
                let decay = pow(0.95, timeScale)
                viruses[i].velocity.width *= decay
                viruses[i].velocity.height *= decay
                
                if abs(viruses[i].velocity.width) < 5 && abs(viruses[i].velocity.height) < 5 { viruses[i].velocity = .zero }
                
                let vRadius = viruses[i].radius
                viruses[i].position.x = max(vRadius, min(worldSize - vRadius, viruses[i].position.x))
                viruses[i].position.y = max(vRadius, min(worldSize - vRadius, viruses[i].position.y))
            }
        }
        return movedAny
    }
    
    private func updateVirusMasses(dt: CGFloat) {
        let t = getLerpFactor(base: baseAnimationFactor, dt: dt)
        for i in viruses.indices { viruses[i].mass += (viruses[i].targetMass - viruses[i].mass) * t }
    }
    
    private func handleCellSelfCollisions(cells: inout[PlayerCell]) {
        guard cells.count > 1 else { return }
        var groups:[UUID: [Int]] = [:]
        var radii = [CGFloat](repeating: 0, count: cells.count)
        groups.reserveCapacity(min(cells.count, 64))
        for i in cells.indices {
            groups[cells[i].ownerID, default:[]].append(i)
            radii[i] = cells[i].cachedVisualRadius
        }
        
        for _ in 0..<2 {
            var resolvedAnyOverlap = false
            for (_, indices) in groups {
                guard indices.count > 1 else { continue }
                for i in 0..<indices.count {
                    for j in (i + 1)..<indices.count {
                        let idx1 = indices[i]
                        let idx2 = indices[j]
                        guard cells[idx1].mergeTimer > 0 || cells[idx2].mergeTimer > 0 else { continue }
                        
                        let cell1 = cells[idx1]
                        let cell2 = cells[idx2]
                        
                        let totalRadius = radii[idx1] + radii[idx2]
                        let dx = cell2.position.x - cell1.position.x
                        if dx < -totalRadius || dx > totalRadius { continue }
                        let dy = cell2.position.y - cell1.position.y
                        if dy < -totalRadius || dy > totalRadius { continue }
                        
                        let distSq = dx*dx + dy*dy
                        
                        if distSq < (totalRadius * totalRadius) {
                            resolvedAnyOverlap = true
                            var distance = sqrt(distSq)
                            var safeDx = dx
                            var safeDy = dy
                            if distance == 0 { distance = 1.0; safeDx = 1.0; safeDy = 0.0 }
                            
                            let overlap = totalRadius - distance
                            let direction = CGSize(width: safeDx / distance, height: safeDy / distance)
                            let totalMass = cell1.mass + cell2.mass
                            guard totalMass > 0 else { continue }
                            
                            let timer1 = cells[idx1].splitTimer
                            let timer2 = cells[idx2].splitTimer
                            let maxTimer = max(timer1, timer2)
                            let normalizedTimer = min(max(maxTimer, 0.0), 1.0)
                            let resolutionForce: CGFloat = 1.0 - (normalizedTimer * 0.95)
                            
                            let actualPush = overlap * resolutionForce
                            // v5.8: a piece fully ENGULFED by a bigger cell used
                            // to shove it around (overlap ≈ both radii → even a
                            // tiny mass share moved the giant fast). Contained
                            // piece now slides out on its own; the big cell
                            // holds its ground.
                            let contained = distance + min(radii[idx1], radii[idx2])
                                <= max(radii[idx1], radii[idx2])
                            if contained {
                                if radii[idx1] >= radii[idx2] {
                                    cells[idx2].position.x += direction.width * actualPush
                                    cells[idx2].position.y += direction.height * actualPush
                                } else {
                                    cells[idx1].position.x -= direction.width * actualPush
                                    cells[idx1].position.y -= direction.height * actualPush
                                }
                            } else {
                                let pushback1 = (cell2.mass / totalMass) * actualPush
                                let pushback2 = (cell1.mass / totalMass) * actualPush
                                
                                cells[idx1].position.x -= direction.width * pushback1
                                cells[idx1].position.y -= direction.height * pushback1
                                cells[idx2].position.x += direction.width * pushback2
                                cells[idx2].position.y += direction.height * pushback2
                            }
                        }
                    }
                }
            }
            if !resolvedAnyOverlap { break }
        }
    }
    
    private func getLerpFactor(base: CGFloat, dt: CGFloat) -> CGFloat {
        return 1.0 - pow(1.0 - base, dt * 60.0)
    }
    
    private func updateCameraZoom(dt: CGFloat) {
        let smoothFactor = getLerpFactor(base: 0.15, dt: dt)
        smoothedTotalMass += (totalPlayerMass - smoothedTotalMass) * smoothFactor
        
        let baseZoom = 2.2 / pow(max(1, smoothedTotalMass), 0.2)
        let center = playerCenter
        // v5.8: satellites are weighted by their mass ratio to the LARGEST
        // cell — one giant with a few crumbs keeps a tight camera (the crumbs
        // barely zoom you out), while an even 16-split still reads exactly
        // like before (all weights 1).
        let largestMass = playerCells.map { $0.mass }.max() ?? 1
        var maxWeightedSpread: CGFloat = 0
        var weightedExtraCells: CGFloat = 0
        var skippedLargest = false
        for cell in playerCells {
            let ratio = max(0, min(1, cell.mass / max(largestMass, 1)))
            let dx = cell.position.x - center.x
            let dy = cell.position.y - center.y
            let weightedDist = sqrt(dx * dx + dy * dy) * sqrt(ratio)
            if weightedDist > maxWeightedSpread { maxWeightedSpread = weightedDist }
            if !skippedLargest && cell.mass == largestMass {
                skippedLargest = true
            } else {
                weightedExtraCells += ratio
            }
        }
        let spreadFactor = 1.0 + min(maxWeightedSpread / 6000.0, 0.2)
        let cellCountFactor = 1.0 + weightedExtraCells * 0.01
        
        let customZoomMultiplier = 1.0 - ((CGFloat(zoomSliderValue) - 1.0) / 49.0) * 0.9
        var targetZoom = ((baseZoom / spreadFactor) / cellCountFactor) * customZoomMultiplier

        // Multi-cell bounding box framing: ensure wide splits stay framed with padding.
        if playerCells.count > 1 {
            var minX = CGFloat.greatestFiniteMagnitude
            var maxX = -CGFloat.greatestFiniteMagnitude
            var minY = CGFloat.greatestFiniteMagnitude
            var maxY = -CGFloat.greatestFiniteMagnitude
            for cell in playerCells {
                let r = cell.cachedSolidRadius
                minX = min(minX, cell.position.x - r)
                maxX = max(maxX, cell.position.x + r)
                minY = min(minY, cell.position.y - r)
                maxY = max(maxY, cell.position.y + r)
            }
            let bboxW = max(1, maxX - minX)
            let bboxH = max(1, maxY - minY)
            let screen = UIScreen.main.bounds.size
            let fitZoom = min(screen.width / (bboxW * 1.25), screen.height / (bboxH * 1.25)) * customZoomMultiplier
            if fitZoom < targetZoom {
                targetZoom = max(0.18 * customZoomMultiplier, fitZoom)
            }
        }
        
        let zoomSmooth = getLerpFactor(base: 0.07, dt: dt)
        zoomLevel += (targetZoom - zoomLevel) * zoomSmooth
    }
    
    private func updateVisibleObjects(screenSize: CGSize) {
        let cameraOffsetX = -smoothedPlayerPosition.x * zoomLevel + screenSize.width / 2
        let cameraOffsetY = -smoothedPlayerPosition.y * zoomLevel + screenSize.height / 2
        let visibleRect = CGRect(
            origin: CGPoint(x: (0 - cameraOffsetX) / zoomLevel, y: (0 - cameraOffsetY) / zoomLevel),
            size: CGSize(width: screenSize.width / zoomLevel, height: screenSize.height / zoomLevel)
        ).insetBy(dx: -400, dy: -400)
        
        // Tokens and viruses are culled from the full arrays by their exact draw rectangles in
        // Canvas. The old duplicate @State arrays caused two array writes every display tick.
        visibleWorldRect = visibleRect
    }
    
    private func movePlayer(dt: CGFloat) {
        let worldSize: CGFloat = 11000
        let timeScale = dt * 60.0
        
        var joystickTargetPoint: CGPoint? = nil
        var globalDirectionNorm: CGSize = .zero
        
        if joystickIsDragging {
            let joyX = joystickOffset.width
            let joyY = joystickOffset.height
            let joyMagnitude = sqrt(joyX * joyX + joyY * joyY)
            let maxJoy: CGFloat = 65.0
            let fraction = min(max(joyMagnitude / maxJoy, 0.0), 1.0)
            if joyMagnitude > 0 {
                globalDirectionNorm = CGSize(width: joyX / joyMagnitude, height: joyY / joyMagnitude)
            }
            let center = playerCenter
            
            if fraction > 0.95 {
                joystickTargetPoint = CGPoint(x: center.x + globalDirectionNorm.width * 100000, y: center.y + globalDirectionNorm.height * 100000)
            } else {
                let minTargetDistance: CGFloat = 50
                let maxTargetDistance: CGFloat = 1500
                let curve = fraction * fraction
                let targetDistance = minTargetDistance + (maxTargetDistance - minTargetDistance) * curve
                joystickTargetPoint = CGPoint(x: center.x + globalDirectionNorm.width * targetDistance, y: center.y + globalDirectionNorm.height * targetDistance)
            }
        }
        
        var idToIndex = [UUID: Int]()
        if playerCells.contains(where: { $0.splitImmunityTimer <= 0 && $0.immuneToCellID != nil }) {
            idToIndex.reserveCapacity(playerCells.count)
            for i in playerCells.indices { idToIndex[playerCells[i].id] = i }
        }
        
        for i in playerCells.indices {
            if playerCells[i].splitImmunityTimer > 0 {
                playerCells[i].splitImmunityTimer -= dt
                if playerCells[i].splitImmunityTimer <= 0 { playerCells[i].immuneToCellID = nil }
            } else if let targetID = playerCells[i].immuneToCellID {
                if let tIdx = idToIndex[targetID] {
                    let targetCell = playerCells[tIdx]
                    let r1 = playerCells[i].cachedVisualRadius
                    let r2 = targetCell.cachedVisualRadius
                    let dx = playerCells[i].position.x - targetCell.position.x
                    let dy = playerCells[i].position.y - targetCell.position.y
                    let distSq = dx*dx + dy*dy
                    let totalR = r1 + r2
                    if distSq > totalR * totalR { playerCells[i].immuneToCellID = nil }
                } else { playerCells[i].immuneToCellID = nil }
            }
            
            let distanceThisFrame = playerCells[i].cachedMovementSpeed * dt
            
            if joystickIsDragging, let target = joystickTargetPoint {
                let dirToTarget = CGSize(width: target.x - playerCells[i].position.x, height: target.y - playerCells[i].position.y)
                let distToTarget = sqrt(dirToTarget.width * dirToTarget.width + dirToTarget.height * dirToTarget.height)
                let moveDir = distToTarget > 5 ? dirToTarget.normalized() : globalDirectionNorm
                
                playerCells[i].position.x += moveDir.width * distanceThisFrame
                playerCells[i].position.y += moveDir.height * distanceThisFrame
            } else if let anchor = anchorPoint {
                let directionToAnchor = CGSize(width: anchor.x - playerCells[i].position.x, height: anchor.y - playerCells[i].position.y)
                let distanceToAnchor = sqrt(directionToAnchor.width * directionToAnchor.width + directionToAnchor.height * directionToAnchor.height)
                if distanceToAnchor > 1 {
                    let normalizedDirection = directionToAnchor.normalized()
                    let travelDistance = min(distanceThisFrame, distanceToAnchor)
                    playerCells[i].position.x += normalizedDirection.width * travelDistance
                    playerCells[i].position.y += normalizedDirection.height * travelDistance
                }
            }
            
            playerCells[i].position.x += playerCells[i].velocity.width * timeScale
            playerCells[i].position.y += playerCells[i].velocity.height * timeScale
            
            let decayFactor = pow(0.92, timeScale)
            let splitDecayFactor = pow(0.96, timeScale)
            
            if playerCells[i].splitTimer > 0 {
                playerCells[i].velocity.width *= splitDecayFactor
                playerCells[i].velocity.height *= splitDecayFactor
                playerCells[i].splitTimer -= dt
            } else {
                playerCells[i].velocity.width *= decayFactor
                playerCells[i].velocity.height *= decayFactor
            }
            
            let visualRadius = playerCells[i].cachedVisualRadius
            let hardPhysicsRadius = visualRadius * 0.55
            
            if playerCells[i].position.x < hardPhysicsRadius { playerCells[i].position.x = hardPhysicsRadius; playerCells[i].velocity.width = 0 }
            else if playerCells[i].position.x > worldSize - hardPhysicsRadius { playerCells[i].position.x = worldSize - hardPhysicsRadius; playerCells[i].velocity.width = 0 }
            
            if playerCells[i].position.y < hardPhysicsRadius { playerCells[i].position.y = hardPhysicsRadius; playerCells[i].velocity.height = 0 }
            else if playerCells[i].position.y > worldSize - hardPhysicsRadius { playerCells[i].position.y = worldSize - hardPhysicsRadius; playerCells[i].velocity.height = 0 }
        }
    }
    
    // UNIVERSAL SPLIT SYSTEM - Used identically by Players and Bots
    private func executeSplit(on cells: inout [PlayerCell],
                              for ownerID: UUID,
                              direction: CGSize,
                              toward targetPoint: CGPoint? = nil) {
        let worldSize: CGFloat = 11000
        var splitDirection = direction.normalized()
        if splitDirection == .zero { splitDirection = CGSize(width: 0, height: 1) }
        var newCells:[PlayerCell] = []
        
        var eligible = [(index: Int, mass: CGFloat)]()
        for i in cells.indices {
            if cells[i].ownerID == ownerID {
                eligible.append((i, cells[i].mass))
            }
        }
        eligible.sort { $0.mass > $1.mass }
        let currentCount = eligible.count
        
        for item in eligible {
            if currentCount + newCells.count < 16 && cells[item.index].targetMass >= 36 {
                let index = item.index
                let newMass = cells[index].targetMass / 2
                let dynamicMergeTime = 30.0 + (Double(newMass) * 0.02)
                let visualRadius = sqrt(newMass) * 6.3245
                let ejectionForce: CGFloat = 26
                var launchDirection = splitDirection
                if let targetPoint = targetPoint {
                    let targetVector = CGSize(
                        width: targetPoint.x - cells[index].position.x,
                        height: targetPoint.y - cells[index].position.y
                    )
                    if targetVector.width.magnitude >= 0.1 ||
                        targetVector.height.magnitude >= 0.1 {
                        launchDirection = targetVector.normalized()
                    } else {
                        // Exact centre aim: split in place rather than inventing a stale/default
                        // heading. Normal split immunity still keeps the two pieces valid.
                        launchDirection = .zero
                    }
                }
                
                let spawnOffset = visualRadius * 0.4
                var spawnPos = cells[index].position
                spawnPos.x += launchDirection.width * spawnOffset
                spawnPos.y += launchDirection.height * spawnOffset
                
                let physicsRadius = visualRadius * 0.55
                if spawnPos.x < physicsRadius { spawnPos.x = physicsRadius }
                if spawnPos.x > worldSize - physicsRadius { spawnPos.x = worldSize - physicsRadius }
                if spawnPos.y < physicsRadius { spawnPos.y = physicsRadius }
                if spawnPos.y > worldSize - physicsRadius { spawnPos.y = worldSize - physicsRadius }
                
                var newCell = PlayerCell(
                    ownerID: cells[index].ownerID,
                    position: spawnPos, mass: newMass, targetMass: newMass, velocity: cells[index].velocity,
                    mergeTimer: dynamicMergeTime, canMerge: false, splitTimer: 1.0, color: cells[index].color,
                    name: cells[index].name, skinName: cells[index].skinName, isBot: cells[index].isBot,
                    isFeedBot: cells[index].isFeedBot, aiSkillTier: cells[index].aiSkillTier
                )
                newCell.splitImmunityTimer = 0.2
                newCell.immuneToCellID = cells[index].id
                // Font lineage: ONLY the new piece coming out of an at/above-threshold
                // cell is born at the half ratio. The splitting cell itself keeps
                // whatever ratio it already had, and below the threshold the child is
                // always born normal - even from a half-ratio parent.
                if cells[index].targetMass >= massFontHalfThreshold {
                    newCell.massFontHalved = true
                    newCell.massFontScale = 0.5
                }
                
                cells[index].targetMass = newMass
                cells[index].mergeTimer = dynamicMergeTime
                cells[index].canMerge = false
                
                let splitVelocity = CGSize(width: launchDirection.width * ejectionForce,
                                           height: launchDirection.height * ejectionForce)
                newCell.velocity.width += splitVelocity.width
                newCell.velocity.height += splitVelocity.height
                newCells.append(newCell)
            }
        }
        cells.append(contentsOf: newCells)
    }
    
    private func split() {
        guard isPlaying, !isLeavePopupPresented,
              canSplit(), let pCell = playerCells.first else { return }
        let currentCenter = playerCenter
        
        if centerAimUntilCursorMoves {
            // A centred cursor is a world point, not one global heading: every split piece aims
            // independently toward the flock centre. A cell already at the exact centre splits
            // in place, so no old/default heading leaks through the pause transition.
            playerLastSplitDirection = .zero
            playerSplitTargetID = nil
            SoundManager.shared.play(.split, minInterval: 0.005)
            executeSplit(
                on: &playerCells,
                for: pCell.ownerID,
                direction: .zero,
                toward: currentCenter
            )
            return
        }
        
        var splitDirection: CGSize
        
        if joystickIsDragging, lastJoystickDirection != .zero {
            splitDirection = lastJoystickDirection.normalized()
        } else {
            let directionToCenter = CGSize(width: currentCenter.x - pCell.position.x, height: currentCenter.y - pCell.position.y)
            if directionToCenter.width.magnitude < 0.1 && directionToCenter.height.magnitude < 0.1 {
                splitDirection = CGSize(width: 0, height: 1)
            } else {
                splitDirection = directionToCenter.normalized()
            }
        }
        SoundManager.shared.play(.split, minInterval: 0.005)
        recordPlayerSplitIntent(direction: splitDirection, now: CACurrentMediaTime())
        executeSplit(on: &playerCells, for: pCell.ownerID, direction: splitDirection)
    }
    
    private func updateCellDeformation(dt: CGFloat) {
        let worldSize: CGFloat = 11000
        let visRect = visibleWorldRect
        let relax = 1.0 - pow(0.05, dt)
        
        // Old cost: 3 fresh arrays per cell per frame, the full vertex maths for every cell in
        // the world (including bots miles off camera), and the wall pass even in open space.
        func processDeformation(cells: inout [PlayerCell], isPlayerGroup: Bool) {
            let count = cells.count
            guard count > 0 else { return }
            
            // Player cells get the detailed silhouette; bots don't need 64 verts each.
            let targetVertexCount = max(20, 128 / max(1, count))   // unchanged from before
            let trig = TrigCache.get(count: targetVertexCount)
            
            // Scratch buffers reused across every cell (was 3 allocations per cell per frame).
            var objectBuf = [CGFloat](repeating: 0, count: targetVertexCount)
            var smoothBuf = [CGFloat](repeating: 0, count: targetVertexCount)
            var tmpBuf = [CGFloat](repeating: 0, count: targetVertexCount)
            let zeroBuf = [CGFloat](repeating: 0, count: targetVertexCount)
            
            for i in cells.indices {
                let pos = cells[i].position
                let visualRadius = cells[i].cachedSolidRadius
                
                if cells[i].skinDeformation.count != targetVertexCount {
                    // The vertex budget follows the cell count, so it changes right when a
                    // merge finishes or a piece is lost - moments when a squish dent is often
                    // still live. Zeroing the buffer here snapped that dent away in one frame
                    // (a visible instant outward border pop). Resample the old ring onto the
                    // new one instead; the dents then relax on the normal smooth path.
                    let old = cells[i].skinDeformation
                    if cells[i].hasActiveDeformation, old.count > 2 {
                        var resampled = [CGFloat](repeating: 0, count: targetVertexCount)
                        let ratio = CGFloat(old.count) / CGFloat(targetVertexCount)
                        for v in 0..<targetVertexCount {
                            let srcPos = CGFloat(v) * ratio
                            let base = Int(srcPos)
                            let t = srcPos - CGFloat(base)
                            let a = old[base % old.count]
                            let b = old[(base + 1) % old.count]
                            resampled[v] = a * (1.0 - t) + b * t
                        }
                        cells[i].skinDeformation = resampled
                    } else {
                        cells[i].skinDeformation = zeroBuf
                        cells[i].hasActiveDeformation = false
                    }
                }
                
                let onScreen = visRect.isEmpty || visRect.insetBy(dx: -visualRadius - 50, dy: -visualRadius - 50).contains(pos)
                let nearWall = (pos.x - visualRadius) < 0 || (pos.y - visualRadius) < 0
                || (pos.x + visualRadius) > worldSize || (pos.y + visualRadius) > worldSize
                let complexIndentations = !cells[i].isBot && onScreen && count <= 20
                
                // O(1) for the common case: an untouched cell off-screen or in open space.
                // Cells with an existing deformation still run the exact old relaxation math,
                // so a quick camera re-entry cannot reveal a snapped silhouette.
                if !onScreen || (!complexIndentations && !nearWall) {
                    guard cells[i].hasActiveDeformation else { continue }
                    var stillActive = false
                    for v in 0..<targetVertexCount {
                        let d = cells[i].skinDeformation[v]
                        let relaxed = d > 0.01 ? lerp(start: d, end: 0.0, t: relax) : 0
                        cells[i].skinDeformation[v] = relaxed
                        if relaxed > 0.01 { stillActive = true }
                    }
                    cells[i].hasActiveDeformation = stillActive
                    continue
                }
                
                let maxCompression = visualRadius * 3.0
                
                for v in 0..<targetVertexCount {
                    cells[i].skinDeformation[v] = lerp(start: cells[i].skinDeformation[v], end: 0.0, t: relax)
                }
                
                var nearbyMass:[EjectedMass] = []
                if complexIndentations {
                    let searchRadius = visualRadius + 100
                    let searchRect = CGRect(x: pos.x - searchRadius, y: pos.y - searchRadius, width: searchRadius * 2, height: searchRadius * 2)
                    nearbyMass = massManager.getLimitedVisibleMassesArray(in: searchRect, limit: 12)
                }
                
                for v in 0..<targetVertexCount {
                    var overlap: CGFloat = 0
                    if !nearbyMass.isEmpty {
                        let uncompressedX = pos.x + trig[v].cos * visualRadius
                        let uncompressedY = pos.y + trig[v].sin * visualRadius
                        for mass in nearbyMass {
                            let massRad: CGFloat = 4.0 * 6.3245
                            let dx = uncompressedX - mass.position.x
                            let dy = uncompressedY - mass.position.y
                            let distSq = dx * dx + dy * dy
                            if distSq < massRad * massRad {
                                overlap = max(overlap, massRad - sqrt(distSq))
                            }
                        }
                    }
                    objectBuf[v] = min(overlap, maxCompression)
                    smoothBuf[v] = objectBuf[v]
                }
                
                if !nearbyMass.isEmpty {
                    for _ in 0..<2 {
                        for v in 0..<targetVertexCount { tmpBuf[v] = smoothBuf[v] }
                        for v in 0..<targetVertexCount {
                            let prev = tmpBuf[(v - 1 + targetVertexCount) % targetVertexCount]
                            let next = tmpBuf[(v + 1) % targetVertexCount]
                            smoothBuf[v] = (prev * 0.25) + (tmpBuf[v] * 0.5) + (next * 0.25)
                        }
                    }
                }
                
                var stillActive = false
                for v in 0..<targetVertexCount {
                    var wallOverlap: CGFloat = 0
                    if nearWall {
                        let cosAngle = trig[v].cos
                        let sinAngle = trig[v].sin
                        let uncompressedX = pos.x + cosAngle * visualRadius
                        let uncompressedY = pos.y + sinAngle * visualRadius
                        if cosAngle < -0.01 { wallOverlap = max(wallOverlap, -uncompressedX) }
                        if cosAngle > 0.01 { wallOverlap = max(wallOverlap, uncompressedX - worldSize) }
                        if sinAngle < -0.01 { wallOverlap = max(wallOverlap, -uncompressedY) }
                        if sinAngle > 0.01 { wallOverlap = max(wallOverlap, uncompressedY - worldSize) }
                    }
                    let finalVal = max(smoothBuf[v], min(wallOverlap, maxCompression))
                    let result = max(cells[i].skinDeformation[v], finalVal)
                    cells[i].skinDeformation[v] = result
                    if result > 0.01 { stillActive = true }
                }
                cells[i].hasActiveDeformation = stillActive
            }
        }
        
        processDeformation(cells: &playerCells, isPlayerGroup: true)
        processDeformation(cells: &botCells, isPlayerGroup: false)
    }
    
    
    private func lerp(start: CGFloat, end: CGFloat, t: CGFloat) -> CGFloat {
        return start + (end - start) * t
    }
    
    // Tokens and viruses now use the shared index and check the WHOLE world, not just what
    // happens to be on the player's screen. Previously off-camera bots could never pop on a
    // virus, so they farmed up to absurd sizes unpunished - part of why they felt "wrong".
    // MARK: - DUAL SKIN SWAP
    
    /// Arms the dual-skin artwork swap. Only fires while the player wears a dual-width
    /// skin and the swap is fully idle: eats that land during the alternate art or the
    /// post-swap delay are dropped, never queued.
    private func triggerDualSkinSwap(now: TimeInterval) {
        guard DualSkinCatalog.shared.isDual(selectedSkinName) else { return }
        guard dualSkinSwapPhase == .idle else { return }
        dualSkinSwapPhase = .showing
        dualSkinSwapStartedAt = now
        dualSkinSwapPhaseEndsAt = now + DualSkin.altShowDuration
    }
    
    private func updateDualSkinSwap(now: TimeInterval) {
        switch dualSkinSwapPhase {
        case .idle:
            break
        case .showing:
            if now >= dualSkinSwapPhaseEndsAt {
                dualSkinSwapPhase = .cooldown
                dualSkinSwapPhaseEndsAt = now + DualSkin.retriggerDelay
            }
        case .cooldown:
            if now >= dualSkinSwapPhaseEndsAt {
                dualSkinSwapPhase = .idle
            }
        }
    }
    
    private func handleTokenCollision(index: CellIndex) {
        guard !tokens.isEmpty else { return }
        var collected: [Int] = []
        
        for (tokenIdx, token) in tokens.enumerated() {
            var taken = false
            index.forEach(near: token.position, radius: 1) { c in
                if taken { return }
                let eatDistance = max(0, c.radius - 3)
                if eatDistance <= 0 { return }
                let dx = c.x - token.position.x
                if dx < -eatDistance || dx > eatDistance { return }
                let dy = c.y - token.position.y
                if dy < -eatDistance || dy > eatDistance { return }
                if dx * dx + dy * dy < eatDistance * eatDistance {
                    if c.isPlayer {
                        if c.index < playerCells.count {
                            playerCells[c.index].targetMass += 4
                            tokenCount += 1
                            triggerDualSkinSwap(now: CACurrentMediaTime())
                        }
                    } else if c.index < botCells.count {
                        botCells[c.index].targetMass += 4
                    }
                    consumeAnimations.append(ConsumedPickupAnimation(
                        kind: .token,
                        position: token.position,
                        eaterCellID: c.id))
                    taken = true
                }
            }
            if taken { collected.append(tokenIdx) }
        }
        
        if !collected.isEmpty {
            for i in collected.sorted(by: >) where i < tokens.count {
                tokens.remove(at: i)
            }
            let missingTokens = 200 - tokens.count
            if missingTokens > 0 {
                for _ in 0..<missingTokens { tokens.append(spawnSingleToken(existing: tokens)) }
            }
            tokenIndexDirty = true
        }
    }
    
    private func handleVirusCollision(index: CellIndex) {
        guard !viruses.isEmpty else { return }
        var virusIndicesToRemove: [Int] = []
        var splitActions:[(isBot: Bool, cellIndex: Int, massDistribution: [CGFloat])] = []
        var poppedCellIDs = Set<UUID>()
        
        for (virusIdx, virus) in viruses.enumerated() {
            var popped = false
            // A fed virus is a bigger virus, so the mass needed to eat (pop on) it
            // grows with it: 133 at the base 220 mass, scaled by the fed size.
            let popThreshold = 133 * (virus.targetMass / 220)
            index.forEach(near: virus.position, radius: 1) { c in
                if popped { return }
                if c.mass < popThreshold { return }
                if poppedCellIDs.contains(c.id) { return }
                let dx = c.x - virus.position.x
                if dx < -c.radius || dx > c.radius { return }
                let dy = c.y - virus.position.y
                if dy < -c.radius || dy > c.radius { return }
                guard dx * dx + dy * dy < c.radius * c.radius else { return }
                
                popped = true
                poppedCellIDs.insert(c.id)
                
                if c.isPlayer {
                    guard c.index < playerCells.count else { return }
                    let newTotalMass = playerCells[c.index].targetMass + 100
                    let maxSplits = 16 - playerCells.count + 1
                    var masses = calculateVirusSplitMass(mass: newTotalMass, maxSplits: maxSplits)
                    if masses.count > 1 {
                        var massesMix: [CGFloat] = [masses[0]]
                        for k in stride(from: 1, to: masses.count, by: 2) { massesMix.append(masses[k]) }
                        for k in stride(from: 2, to: masses.count, by: 2) { massesMix.append(masses[k]) }
                        masses = massesMix
                    }
                    splitActions.append((isBot: false, cellIndex: c.index, massDistribution: masses))
                } else {
                    guard c.index < botCells.count else { return }
                    let newTotalMass = botCells[c.index].targetMass + 100
                    let ownerID = botCells[c.index].ownerID
                    var currentOwnerCellCount = 0
                    for b in botCells where b.ownerID == ownerID { currentOwnerCellCount += 1 }
                    let maxSplits = 16 - currentOwnerCellCount + 1
                    let masses = calculateVirusSplitMass(mass: newTotalMass, maxSplits: maxSplits)
                    splitActions.append((isBot: true, cellIndex: c.index, massDistribution: masses))
                }
            }
            if popped { virusIndicesToRemove.append(virusIdx) }
        }
        
        if !virusIndicesToRemove.isEmpty {
            for i in virusIndicesToRemove.sorted(by: >) where i < viruses.count {
                viruses.remove(at: i)
            }
            let missingViruses = 80 - viruses.count
            if missingViruses > 0 {
                for _ in 0..<missingViruses {
                    viruses.append(spawnSingleVirusSafely())
                }
            }
            virusIndexDirty = true
        }
        
        for action in splitActions {
            let cellIdx = action.cellIndex
            let massList = action.massDistribution
            let isBot = action.isBot
            
            if isBot {
                if cellIdx < botCells.count {
                    // Same font lineage rule as executeSplit, using the pre-pop mass
                    // (current targetMass + the virus's 100 bonus): only the NEW pieces
                    // go half - the popped cell itself keeps its own ratio.
                    let poppedHalvesFont = botCells[cellIdx].targetMass + 100 >= massFontHalfThreshold
                    botCells[cellIdx].targetMass = massList[0]
                    guard massList.count > 1 else { continue }
                    var angle = Double.random(in: 0...(2 * Double.pi))
                    let step = (2 * Double.pi) / Double(massList.count - 1)
                    
                    for k in 1..<massList.count {
                        let mass = massList[k]
                        let dynamicMergeTime = 30.0 + (Double(mass) * 0.02)
                        let direction = CGSize(width: cos(angle), height: sin(angle))
                        let speed: CGFloat = 20
                        
                        var newCell = PlayerCell(
                            ownerID: botCells[cellIdx].ownerID,
                            position: botCells[cellIdx].position,
                            mass: mass * 0.5,
                            targetMass: mass,
                            velocity: CGSize(width: direction.width * speed, height: direction.height * speed),
                            mergeTimer: dynamicMergeTime,
                            canMerge: false,
                            splitTimer: 1.0, 
                            color: botCells[cellIdx].color,
                            name: botCells[cellIdx].name,
                            skinName: botCells[cellIdx].skinName,
                            isBot: true,
                            isFeedBot: botCells[cellIdx].isFeedBot,
                            aiSkillTier: botCells[cellIdx].aiSkillTier
                        )
                        newCell.splitImmunityTimer = 0.2
                        newCell.immuneToCellID = botCells[cellIdx].id
                        newCell.massFontHalved = poppedHalvesFont
                        newCell.massFontScale = poppedHalvesFont ? 0.5 : 1.0
                        newCell.aiAggression = botCells[cellIdx].aiAggression
                        newCell.aiCaution = botCells[cellIdx].aiCaution
                        
                        botCells.append(newCell)
                        angle += step
                        if angle >= 2 * Double.pi { angle -= 2 * Double.pi }
                    }
                }
            } else {
                if cellIdx < playerCells.count {
                    SoundManager.shared.play(.virusPop, minInterval: 0.06)
                    // Same font lineage rule as executeSplit, using the pre-pop mass:
                    // only the NEW pieces go half - the popped cell keeps its own ratio.
                    let poppedHalvesFont = playerCells[cellIdx].targetMass + 100 >= massFontHalfThreshold
                    playerCells[cellIdx].targetMass = massList[0]
                    guard massList.count > 1 else { continue }
                    var angle = Double.random(in: 0...(2 * Double.pi))
                    let step = (2 * Double.pi) / Double(massList.count - 1)
                    
                    for k in 1..<massList.count {
                        let mass = massList[k]
                        let dynamicMergeTime = 30.0 + (Double(mass) * 0.02)
                        let direction = CGSize(width: cos(angle), height: sin(angle))
                        let speed: CGFloat = 20
                        
                        var newCell = PlayerCell(
                            ownerID: playerCells[cellIdx].ownerID,
                            position: playerCells[cellIdx].position,
                            mass: mass * 0.5, targetMass: mass,
                            velocity: CGSize(width: direction.width * speed, height: direction.height * speed),
                            mergeTimer: dynamicMergeTime, canMerge: false, splitTimer: 1.0,
                            color: playerCells[cellIdx].color, name: playerCells[cellIdx].name, skinName: playerCells[cellIdx].skinName
                        )
                        newCell.splitImmunityTimer = 0.2
                        newCell.immuneToCellID = playerCells[cellIdx].id
                        newCell.massFontHalved = poppedHalvesFont
                        newCell.massFontScale = poppedHalvesFont ? 0.5 : 1.0
                        playerCells.append(newCell)
                        angle += step
                        if angle >= 2 * Double.pi { angle -= 2 * Double.pi }
                    }
                }
            }
        }
    }
    
    private func updateMassAbsorption(dt: CGFloat) {
        // Was a flat 0.15 per frame, which absorbed twice as fast at 120Hz as at 60Hz.
        let absorptionRate: CGFloat = getLerpFactor(base: 0.15, dt: dt)
        for i in playerCells.indices {
            if playerCells[i].massToAbsorb > 0 {
                let massToAdd = playerCells[i].massToAbsorb * absorptionRate
                playerCells[i].targetMass += massToAdd
                playerCells[i].massToAbsorb -= massToAdd
                if playerCells[i].massToAbsorb < 0.1 { playerCells[i].massToAbsorb = 0 }
            }
        }
        for i in botCells.indices {
            if botCells[i].massToAbsorb > 0 {
                let massToAdd = botCells[i].massToAbsorb * absorptionRate
                botCells[i].targetMass += massToAdd
                botCells[i].massToAbsorb -= massToAdd
                if botCells[i].massToAbsorb < 0.1 { botCells[i].massToAbsorb = 0 }
            }
        }
    }
    
    
    private func updateCellState(cells: inout [PlayerCell], dt: CGFloat) {
        let animFactor = getLerpFactor(base: baseAnimationFactor, dt: dt)
        let lagFactor = getLerpFactor(base: 0.15, dt: dt)
        let decayFactor = 1.0 - getLerpFactor(base: 0.1, dt: dt)
        
        // --- DECAY CONFIGURATION (exact IPA adapted decay from agar.io 0x10004b8a4 + 0x10004bfc8) ---
        let minDecayThreshold: CGFloat = 10 // Mass below this doesn't decay
        // ---------------------------
        
        for i in cells.indices {
            // 1. Apply IPA Adapted Mass Decay
            if cells[i].targetMass > minDecayThreshold {
                let massSqrt = sqrt(cells[i].targetMass)
                let t = min(1.0, max(0.0, (massSqrt - 20.0) / 130.0))
                let rate = 0.99998 + (0.99922 - 0.99998) * t
                cells[i].targetMass *= pow(rate, 100.0 * dt)
            }
            
            // 2. Handle Merge Timers
            if cells[i].mergeTimer > 0 {
                cells[i].mergeTimer -= dt
                if cells[i].mergeTimer <= 0 { 
                    cells[i].canMerge = true
                    cells[i].mergeTimer = 0 
                }
            } else { 
                cells[i].canMerge = true 
            }
            
            // 3. v5.8 soft cap, v5.8.2 fix: hold the full spike until the
            // animated mass has climbed most of it (so a huge bite shows its
            // true peak instead of ~cap+300), THEN burn the excess off fast
            // (~0.1s), snapping the animated mass down along with it.
            if cells[i].targetMass > maxPlayerMass {
                let excess = cells[i].targetMass - maxPlayerMass
                if cells[i].mass >= maxPlayerMass + excess * 0.6 {
                    // v5.8.4: snappier deflate — excess halves every tick and the
                    // animated mass is yanked down with it (~0.1s descent).
                    cells[i].targetMass = maxPlayerMass + excess * pow(1e-18, dt)
                    cells[i].mass += (cells[i].targetMass - cells[i].mass) * getLerpFactor(base: 0.5, dt: dt)
                }
            }
            
            // 4. Existing Bot-Specific Logic 
            // We keep this to ensure bots have a slightly different weight feeling
            if cells[i].isBot && cells[i].mass > 500 { 
                cells[i].targetMass *= (1.0 - (0.0001 * dt)) 
            }
            
            // 5. Animate mass changes (Visual smoothing)
            cells[i].mass += (cells[i].targetMass - cells[i].mass) * animFactor
            cells[i].lagMass += (cells[i].mass - cells[i].lagMass) * lagFactor
            
            // 5b. v5.8.5: label ratio is fixed by lineage — half for pieces
            // born from a big split, full otherwise. No resets, no ramps.
            cells[i].massFontScale = cells[i].massFontHalved ? 0.5 : 1.0
            
            // 6. Handle Merging Animation Shrinkage
            if cells[i].isMerging {
                cells[i].mass *= decayFactor
                cells[i].lagMass *= decayFactor
            }
            cells[i].refreshCachedRadii()
        }
        
        // 7. Cleanup cells that have fully merged/vanished
        var i = cells.count - 1
        while i >= 0 {
            if cells[i].isMerging && cells[i].mass < 1 {
                cells.swapAt(i, cells.count - 1)
                cells.removeLast()
            }
            i -= 1
        }
    }
    
    
    // Same merge rules, but without the `cells.filter` copy, the index/identity mismatch it
    // created, and the `firstIndex(where:)` UUID scans that ran inside a nested loop.
    private func handleCellMerging(cells: inout [PlayerCell], dt: CGFloat) {
        guard cells.count > 1 else {
            if anchorPoint != nil { anchorPoint = playerCenter }
            return
        }
        
        // Split pieces spend most of their 30s merge delay ineligible. Do not put those cells
        // into an O(k²) candidate loop just to reject every pair again.
        var groups:[UUID: [Int]] = [:]
        groups.reserveCapacity(min(cells.count, 64))
        var hasMerging = false
        for i in cells.indices {
            if cells[i].isMerging {
                hasMerging = true
            } else if cells[i].mergeTimer <= 0 && cells[i].canMerge {
                groups[cells[i].ownerID, default: []].append(i)
            }
        }
        
        if groups.isEmpty && !hasMerging {
            if anchorPoint != nil { anchorPoint = playerCenter }
            return
        }
        
        var mergedMasses:[UUID: CGFloat] = [:]
        
        for (_, groupIndices) in groups {
            guard groupIndices.count > 1 else { continue }
            for first in 0..<(groupIndices.count - 1) {
                let a = groupIndices[first]
                if cells[a].isMerging { continue }
                for second in (first + 1)..<groupIndices.count {
                    let b = groupIndices[second]
                    if cells[a].isMerging || cells[b].isMerging { continue }
                    
                    let bigIdx: Int
                    let smallIdx: Int
                    if cells[a].mass >= cells[b].mass {
                        bigIdx = a; smallIdx = b
                    } else {
                        bigIdx = b; smallIdx = a
                    }
                    
                    let bigRadius = cells[bigIdx].cachedSolidRadius
                    let smallRadius = cells[smallIdx].cachedSolidRadius
                    let threshold = bigRadius - (smallRadius * 0.3)
                    guard threshold > 0 else { continue }
                    
                    let dx = cells[smallIdx].position.x - cells[bigIdx].position.x
                    if dx < -threshold || dx > threshold { continue }
                    let dy = cells[smallIdx].position.y - cells[bigIdx].position.y
                    if dy < -threshold || dy > threshold { continue }
                    if dx * dx + dy * dy >= threshold * threshold { continue }
                    
                    let bigID = cells[bigIdx].id
                    cells[smallIdx].isMerging = true
                    cells[smallIdx].mergeTargetID = bigID
                    mergedMasses[bigID, default: 0] += cells[smallIdx].targetMass
                    cells[smallIdx].targetMass = 0
                    hasMerging = true
                }
            }
        }
        
        if !mergedMasses.isEmpty {
            var indexByID = [UUID: Int]()
            indexByID.reserveCapacity(cells.count)
            for i in cells.indices { indexByID[cells[i].id] = i }
            
            for (id, mass) in mergedMasses {
                if let index = indexByID[id] {
                    cells[index].targetMass += mass
                    // v5.8: no hard clamp — the soft cap decays the overshoot
                }
            }
        }
        
        if hasMerging {
            let mergeSpeedFactor = getLerpFactor(base: 0.25, dt: dt)
            var positions = [UUID: CGPoint]()
            positions.reserveCapacity(cells.count)
            for c in cells { positions[c.id] = c.position }
            
            var i = cells.count - 1
            while i >= 0 {
                if cells[i].isMerging {
                    if let targetID = cells[i].mergeTargetID, let targetPos = positions[targetID] {
                        let dx = targetPos.x - cells[i].position.x
                        let dy = targetPos.y - cells[i].position.y
                        let distSq = dx * dx + dy * dy
                        if distSq < 25.0 {
                            if !cells[i].isBot && !cells[i].isFeedBot {
                                SoundManager.shared.play(.eatOwnCell, minInterval: 0.06)
                            }
                            cells.swapAt(i, cells.count - 1)
                            cells.removeLast()
                        } else {
                            cells[i].position.x += dx * mergeSpeedFactor
                            cells[i].position.y += dy * mergeSpeedFactor
                            cells[i].mass *= (1.0 - mergeSpeedFactor)
                            cells[i].refreshCachedRadii()
                        }
                    } else {
                        cells.swapAt(i, cells.count - 1)
                        cells.removeLast()
                    }
                }
                i -= 1
            }
        }
        
        if anchorPoint != nil { anchorPoint = playerCenter }
    }
    
    
    private func feedMass(times: Int = 1) {
        guard isPlaying, !isLeavePopupPresented, canFeed() else { return }
        let nowTS = CACurrentMediaTime()
        
        let joyX = Double(lastJoystickDirection.width)
        let joyY = Double(lastJoystickDirection.height)
        let magnitude = sqrt(joyX * joyX + joyY * joyY)
        let maxJoystickRadius: Double = 65.0
        let isParallel = !centerAimUntilCursorMoves &&
        magnitude > (maxJoystickRadius * 0.9)
        
        var minX: CGFloat = playerCells[0].position.x
        var maxX: CGFloat = playerCells[0].position.x
        var minY: CGFloat = playerCells[0].position.y
        var maxY: CGFloat = playerCells[0].position.y
        
        for cell in playerCells {
            let r = cell.cachedSolidRadius
            if cell.position.x - r < minX { minX = cell.position.x - r }
            if cell.position.x + r > maxX { maxX = cell.position.x + r }
            if cell.position.y - r < minY { minY = cell.position.y - r }
            if cell.position.y + r > maxY { maxY = cell.position.y + r }
        }
        
        let flockWidth = maxX - minX
        let flockHeight = maxY - minY
        let flockRadius = max(flockWidth, flockHeight) / 2.0
        let center = playerCenter
        var targetPoint = center
        
        if !isParallel && !centerAimUntilCursorMoves {
            let convergenceScaling: Double = 15.0
            var dist = magnitude * convergenceScaling
            let minSafeDist = Double(flockRadius + 50)
            if dist < minSafeDist { dist = minSafeDist }
            let dirNorm = lastJoystickDirection.normalized()
            targetPoint.x += dirNorm.width * CGFloat(dist)
            targetPoint.y += dirNorm.height * CGFloat(dist)
        }
        
        let aim: MassEjectionAim
        if isParallel {
            aim = .parallel(lastJoystickDirection)
        } else if centerAimUntilCursorMoves {
            aim = .centerConverge(center)
        } else {
            aim = .converge(targetPoint)
        }
        
        var didEject = false
        for _ in 0..<times {
            for i in playerCells.indices {
                guard playerCells[i].targetMass >= 32 else { continue }
                let source = playerCells[i]
                if emitEjectedMass(from: source, aim: aim, now: nowTS) {
                    playerCells[i].targetMass -= 16
                    didEject = true
                }
            }
        }
        if didEject {
            SoundManager.shared.play(.shoot, minInterval: 0.060)
        }
    }
    
    private func fireMacro() { feedMass(times: macroBullets) }
    
    private func canSplit() -> Bool {
        guard playerCells.count < 16 else { return false }
        return playerCells.contains(where: { $0.targetMass >= 36 })
    }
    
    private func canFeed() -> Bool {
        // Ejecting is per-cell: a cell needs >= 32 to fire a pellet. Gating the buttons on
        // *total* mass lit them up even when every individual cell was under the threshold
        // (e.g. many small split pieces) and a press would do nothing. Grey out unless at
        // least one cell can actually eject. A match now spawns in centre-aim mode, so the
        // direction term is always satisfied from frame one - the buttons never start grey.
        return playerCells.contains(where: { $0.targetMass >= 32 }) &&
        (centerAimUntilCursorMoves || lastJoystickDirection != .zero)
    }
    
    private func spawnInitialObjects() {
        isLeavePopupPresented = false
        leavePopupMounted = false
        isGameOverPresented = false
        isDeathSequencePending = false
        matchStartTime = CACurrentMediaTime()
        matchSurvivalSeconds = 0
        // Start every match in explicit centre-aim mode (the same proven mode the pause popup
        // resumes into). canFeed() treats it as a valid heading, so feed/macro are live from
        // the very first frame instead of greying out until the cursor first moves; pellets
        // converge on the flock centre and split() aims per-cell toward the centre until then.
        centerAimUntilCursorMoves = true
        joystickIsDragging = false
        joystickOffset = .zero
        joystickBasePosition = nil
        lastJoystickDirection = .zero
        anchorPoint = nil
        resetLobbyTeamState()
        viruses.removeAll()
        tokens.removeAll()
        massManager.clearAll()
        foodManager.removeAll()
        playerCells.removeAll()
        botCells.removeAll()
        animatingEatenCells.removeAll()
        consumeAnimations.removeAll()
        pendingBotSplits.removeAll(keepingCapacity: true)
        isFeedingHeld = false
        feedHoldStartTime = nil
        isMacroHeld = false
        feedButtonScale = 1.0
        macroButtonScale = 1.0
        ejectControlSession &+= 1
        regularBotOwners.removeAll(keepingCapacity: true)
        feedBotOwners.removeAll(keepingCapacity: true)
        initialBotFillActive = true
        feedBotsWereEnabled = spawnFeedBots
        tokenIndexDirty = true
        virusIndexDirty = true
        tokenCount = 0
        highScore = 0
        dualSkinSwapPhase = .idle
        dualSkinSwapPhaseEndsAt = 0
        dualSkinSwapStartedAt = 0
        spawnInitialFood()
        spawnInitialViruses()
        spawnInitialTokens()
        spawnPlayerSafely()
    }
    
    private func spawnPlayerSafely() {
        let worldSize: CGFloat = 11000
        let boost = CGFloat(UserDefaults.standard.integer(forKey: "macro.activeStartBoost"))
        if boost > 0 { UserDefaults.standard.set(0, forKey: "macro.activeStartBoost") }
        let startMass: CGFloat = playerStartMass + boost
        let playerRadius = sqrt(startMass) * 6.3245
        let safetyBuffer: CGFloat = 400
        var safePosition: CGPoint = .zero
        var foundSafeSpot = false
        var attempts = 0
        
        let availableColors = [
            Color(hex: 0x67DD00), Color(hex: 0xFFCC00), Color(hex: 0xFF7E00), Color(hex: 0xFF3C3C),
            Color(hex: 0xB608FF), Color(hex: 0xFF3ED3), Color(hex: 0x0078FE), Color(hex: 0x01DDFE)
        ]
        let chosenColor = availableColors.randomElement() ?? .red
        
        while !foundSafeSpot && attempts < 50 {
            let randomX = CGFloat.random(in: (playerRadius + 50)...(worldSize - playerRadius - 50))
            let randomY = CGFloat.random(in: (playerRadius + 50)...(worldSize - playerRadius - 50))
            let candidate = CGPoint(x: randomX, y: randomY)
            var isOverlappingVirus = false
            for virus in viruses {
                let dx = candidate.x - virus.position.x
                let dy = candidate.y - virus.position.y
                let distance = sqrt(dx * dx + dy * dy)
                let minSafeDistance = virus.radius + playerRadius + safetyBuffer
                if distance < minSafeDistance { isOverlappingVirus = true; break }
            }
            if !isOverlappingVirus { safePosition = candidate; foundSafeSpot = true }
            attempts += 1
        }
        if !foundSafeSpot { safePosition = CGPoint(x: worldSize / 2, y: worldSize / 2) }
        
        let newPlayer = PlayerCell(
            ownerID: UUID(), position: safePosition, mass: startMass, targetMass: startMass,
            color: chosenColor, name: playerName, skinName: selectedSkinName
        )
        self.playerCells = [newPlayer]
        self.smoothedPlayerPosition = safePosition
        self.smoothedTotalMass = startMass
        self.cameraJumpOffset = .zero
        self.lastCameraTargetPos = nil
        self.lastCameraCellCount = playerCells.count
    }
    
    private func spawnInitialFood() { foodManager.spawn(count: 4500) }
    
    /// Random virus replacements must not materialize on top of ejected mass. Besides looking
    /// wrong, the entire settled bucket could be swallowed in one collision pass. This path is
    /// used only for the initial 80 and rare replacements, so the bounded safety search has no
    /// per-frame cost.
    private func spawnSingleVirusSafely() -> Virus {
        var fallback = spawnSingleVirus()
        
        for _ in 0..<48 {
            let candidate = spawnSingleVirus()
            fallback = candidate
            let massClearance = candidate.radius + 40
            if massManager.containsMass(
                near: candidate.position,
                radius: massClearance
            ) {
                continue
            }
            
            let virusClearance = candidate.radius * 2 + 30
            let virusClearanceSq = virusClearance * virusClearance
            var overlapsVirus = false
            for virus in viruses {
                let dx = virus.position.x - candidate.position.x
                let dy = virus.position.y - candidate.position.y
                if dx * dx + dy * dy < virusClearanceSq {
                    overlapsVirus = true
                    break
                }
            }
            if overlapsVirus { continue }
            
            var overlapsCell = false
            for cell in playerCells {
                let dx = cell.position.x - candidate.position.x
                let dy = cell.position.y - candidate.position.y
                let clearance = candidate.radius + cell.cachedVisualRadius + 80
                if dx * dx + dy * dy < clearance * clearance {
                    overlapsCell = true
                    break
                }
            }
            if overlapsCell { continue }
            for cell in botCells {
                let dx = cell.position.x - candidate.position.x
                let dy = cell.position.y - candidate.position.y
                let clearance = candidate.radius + cell.cachedVisualRadius + 80
                if dx * dx + dy * dy < clearance * clearance {
                    overlapsCell = true
                    break
                }
            }
            if !overlapsCell { return candidate }
        }
        
        // A practically unreachable world-saturation fallback. The threshold-safe collision
        // path still prevents unbounded growth even if every sampled point was occupied.
        return fallback
    }
    
    private func spawnInitialViruses() {
        for _ in 0..<80 { viruses.append(spawnSingleVirusSafely()) }
    }
    private func spawnInitialTokens() { for _ in 0..<200 { tokens.append(spawnSingleToken(existing: tokens)) } }
    
    private func calculateVirusSplitMass(mass: CGFloat, maxSplits: Int) ->[CGFloat] {
        let playerMinSize: CGFloat = 32
        let minMass: CGFloat = (playerMinSize * playerMinSize) / 100
        let throwSize: CGFloat = playerMinSize + 12
        let throwMass: CGFloat = (throwSize * throwSize) / 100
        var curMass = mass
        var maxCount = maxSplits
        
        while maxCount > 1 && (curMass / CGFloat(maxCount - 1)) < throwMass { maxCount = maxCount / 2 }
        if maxCount < 2 { return [mass] }
        let splitMassBase = curMass / CGFloat(maxCount)
        if splitMassBase < minMass { return [mass] }
        var masses:[CGFloat] = []
        if maxCount < 3 || maxCount < maxSplits || (curMass / throwMass) <= 30 {
            for _ in 0..<maxCount { masses.append(splitMassBase) }
            return masses
        }
        var restCount = maxCount
        while restCount > 2 {
            let sMass = curMass / 2
            if sMass <= throwMass { break }
            let maxSafety = curMass - (throwMass * CGFloat(restCount - 1))
            if maxSafety <= throwMass || sMass >= maxSafety { break }
            masses.append(sMass)
            curMass -= sMass
            restCount -= 1
        }
        var sMass = curMass / 4
        if sMass > throwMass {
            while restCount > 2 {
                let maxSafety = curMass - (throwMass * CGFloat(restCount - 1))
                if maxSafety <= throwMass || sMass >= maxSafety { break }
                masses.append(sMass)
                curMass -= sMass
                restCount -= 1
            }
        }
        sMass = curMass / 8
        if sMass > throwMass {
            while restCount > 2 {
                let maxSafety = curMass - (throwMass * CGFloat(restCount - 1))
                if maxSafety <= throwMass || sMass >= maxSafety { break }
                masses.append(sMass)
                curMass -= sMass
                restCount -= 1
            }
        }
        if restCount > 1 {
            sMass = curMass - (throwMass * CGFloat(restCount - 1))
            if sMass > throwMass {
                masses.append(sMass)
                curMass -= sMass
                restCount -= 1
            }
        }
        if restCount > 0 {
            sMass = curMass / CGFloat(restCount)
            while restCount > 0 {
                masses.append(sMass)
                restCount -= 1
            }
        }
        return masses
    }
    
    private func pause() {
        guard isPlaying, !isLeavePopupPresented else { return }
        
        // This state assignment is deliberately not animated: HUD, controls, cursor and mod UI
        // disappear immediately. The display link is intentionally left running so movement,
        // AI, collisions and all other physics continue underneath the input-blocking modal.
        isLeavePopupPresented = true
        leavePopupMounted = true
        showModMenu = false
        joystickIsDragging = false
        joystickOffset = .zero
        joystickBasePosition = nil
        isFeedingHeld = false
        feedHoldStartTime = nil
        isMacroHeld = false
        feedButtonScale = 1.0
        macroButtonScale = 1.0
        resetRecruitmentMotion()
        resetForcedFeedMotion()
    }
    
    private func resumeFromLeavePopup() {
        guard isPlaying, isLeavePopupPresented else { return }
        
        // Defensive focus reset for Swift Playgrounds/UIKit hosting. The controls no longer
        // depend on focus, but an abandoned nickname TextField must not retain first responder
        // across the modal transition.
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        
        // A centred screen cursor is represented as an explicit mode instead of a fake nonzero
        // heading. Feed/macro therefore converge on the current (still-live) flock centre, and
        // split calculates a separate centre-facing direction for every source cell.
        centerAimUntilCursorMoves = true
        lastJoystickDirection = .zero
        joystickIsDragging = false
        joystickOffset = .zero
        joystickBasePosition = nil
        anchorPoint = playerCenter
        // Do not reuse the pre-popup gesture recognizers. A fresh session ensures feed's normal
        // timer and macro's immediate press begin from this touch-down, with no stale hold state.
        ejectControlSession &+= 1
        isLeavePopupPresented = false
    }
    
    private func confirmLeaveGame() {
        guard isPlaying, isLeavePopupPresented else { return }
        exitMatchToMainMenu()
    }
    
    /// Shared by the confirmation popup and final-cell death. Keeping this synchronous lets the
    /// current display-link callback detect `isPlaying == false` and return before any remaining
    /// gameplay systems touch the now-empty player array.
    private func exitMatchToMainMenu() {
        isLeavePopupPresented = false
        leavePopupMounted = false
        centerAimUntilCursorMoves = false
        lastJoystickDirection = .zero
        joystickIsDragging = false
        joystickOffset = .zero
        joystickBasePosition = nil
        anchorPoint = nil
        showModMenu = false
        isFeedingHeld = false
        feedHoldStartTime = nil
        isMacroHeld = false
        feedButtonScale = 1.0
        macroButtonScale = 1.0
        resetRecruitmentMotion()
        resetForcedFeedMotion()
        lastFrameTimestamp = 0
        isPlaying = false
        displayLink.stop()
    }
}

// MARK: - UI Helpers

/// One flat 944x702 asset with two normalized transparent hit regions. Because the image and
/// hit geometry share the same aspect-ratio-locked frame, rotation and iPad size changes cannot
/// make the invisible buttons drift away from the painted red/green buttons.
struct LeavePopupModal: View {
    /// Called the instant No commits: gameplay input must be live again immediately, long
    /// before the exit animation ends.
    let onNo: () -> Void
    /// Called when the No exit animation finishes so the owner can unmount this purely
    /// visual layer.
    let onNoExitComplete: () -> Void
    let onYes: () -> Void
    
    private enum Choice: Equatable {
        case no
        case yes
    }
    
    private enum MotionPhase {
        case belowScreen
        case entranceOvershoot
        case resting
        case exitAnticipation
    }
    
    @State private var motionPhase: MotionPhase = .belowScreen
    @State private var dimmerOpacity: Double = 0
    @State private var entranceComplete = false
    @State private var actionLocked = false
    @State private var dimBothButtons = false
    
    private let sourceAspect: CGFloat = 944.0 / 702.0
    private let noRect = CGRect(
        x: 0.1186, y: 0.5427,
        width: 0.3210, height: 0.3106
    )
    private let yesRect = CGRect(
        x: 0.5604, y: 0.5442,
        width: 0.3199, height: 0.3091
    )
    
    var body: some View {
        GeometryReader { geometry in
            let popupWidth = min(
                470,
                min(
                    geometry.size.width * 0.42,
                    geometry.size.height * 0.58 * sourceAspect
                )
            )
            let popupHeight = popupWidth / sourceAspect
            
            ZStack {
                Color.black
                    .opacity(dimmerOpacity)
                    .ignoresSafeArea()
                
                ZStack {
                    Image("Leave-popup")
                        .resizable()
                        .scaledToFit()
                    
                    GeometryReader { imageGeometry in
                        Button(action: { commit(.no) }) {
                            Color.clear
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(
                            LeavePopupButtonStyle(
                                dimAll: dimBothButtons,
                                cornerRadius: popupWidth * 0.022
                            )
                        )
                        .frame(
                            width: imageGeometry.size.width * noRect.width,
                            height: imageGeometry.size.height * noRect.height
                        )
                        .contentShape(Rectangle())
                        .position(
                            x: imageGeometry.size.width * noRect.midX,
                            y: imageGeometry.size.height * noRect.midY
                        )
                        .accessibilityLabel("No")
                        .accessibilityHint("Return to the current match")
                        
                        Button(action: { commit(.yes) }) {
                            Color.clear
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(
                            LeavePopupButtonStyle(
                                dimAll: dimBothButtons,
                                cornerRadius: popupWidth * 0.022
                            )
                        )
                        .frame(
                            width: imageGeometry.size.width * yesRect.width,
                            height: imageGeometry.size.height * yesRect.height
                        )
                        .contentShape(Rectangle())
                        .position(
                            x: imageGeometry.size.width * yesRect.midX,
                            y: imageGeometry.size.height * yesRect.midY
                        )
                        .accessibilityLabel("Yes")
                        .accessibilityHint("Leave the current match")
                    }
                    .allowsHitTesting(entranceComplete && !actionLocked)
                }
                .frame(width: popupWidth, height: popupHeight)
                .offset(
                    y: verticalOffset(
                        containerHeight: geometry.size.height,
                        popupHeight: popupHeight
                    )
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The entire overlay - dimmer included - stops intercepting touches the moment a
            // choice commits. Previously it stayed hit-testable through the whole exit
            // animation, so a finger that came down on feed/macro right after releasing No was
            // captured by this dying layer and the hold never reached the game until a fresh
            // touch (which is why moving "fixed" it).
            .allowsHitTesting(!actionLocked)
            .onAppear {
                startEntrance()
            }
        }
    }
    
    private func verticalOffset(containerHeight: CGFloat, popupHeight: CGFloat) -> CGFloat {
        switch motionPhase {
        case .belowScreen:
            return (containerHeight + popupHeight) / 2.0 + 24
        case .entranceOvershoot:
            return -popupHeight * 0.06
        case .resting:
            return 0
        case .exitAnticipation:
            return -popupHeight * 0.08
        }
    }
    
    private func startEntrance() {
        motionPhase = .belowScreen
        dimmerOpacity = 0
        entranceComplete = false
        actionLocked = false
        dimBothButtons = false
        
        DispatchQueue.main.async {
            // V15: every movement phase is another 20% shorter than V14.
            // Phase 1: bottom -> slightly above centre (0.192 seconds).
            withAnimation(.easeOut(duration: 0.192)) {
                motionPhase = .entranceOvershoot
                dimmerOpacity = 0.56
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.192) {
                guard !actionLocked else { return }
                
                // Phase 2: overshoot -> centred rest (0.128 seconds).
                withAnimation(.easeInOut(duration: 0.128)) {
                    motionPhase = .resting
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.128) {
                    guard !actionLocked else { return }
                    entranceComplete = true
                }
            }
        }
    }
    
    private func commit(_ choice: Choice) {
        guard entranceComplete, !actionLocked else { return }
        
        // Button fires on release and both painted buttons dim immediately. No gets a very
        // short 50 ms response beat; destructive Yes deliberately retains 200 ms.
        actionLocked = true
        entranceComplete = false
        dimBothButtons = true
        
        if choice == .no {
            // Gameplay resumes accepting input right now: `actionLocked` already disabled hit
            // testing for this whole overlay, so a hold that starts during the remaining exit
            // animation lands directly on the returned HUD instead of dying here. The dimmer
            // also starts clearing immediately so the live game is not shown dimmed.
            onNo()
            withAnimation(.easeOut(duration: 0.22)) {
                dimmerOpacity = 0
            }
        }
        
        let confirmationDelay: Double = choice == .no ? 0.05 : 0.20
        DispatchQueue.main.asyncAfter(deadline: .now() + confirmationDelay) {
            // Shared phase: centre -> upward anticipation nudge (0.128 seconds).
            withAnimation(.easeOut(duration: 0.128)) {
                motionPhase = .exitAnticipation
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.128) {
                let dropDuration: Double = choice == .no ? 0.160 : 0.096
                
                // No: 0.160 s drop (0.288 s motion total).
                // Yes: 0.096 s drop (0.224 s motion total).
                withAnimation(.easeIn(duration: dropDuration)) {
                    motionPhase = .belowScreen
                    dimmerOpacity = 0
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + dropDuration) {
                    if choice == .no {
                        onNoExitComplete()
                    } else {
                        onYes()
                    }
                }
            }
        }
    }
}

/// The source art remains one flat image. This style paints only a clipped translucent overlay
/// over the normalized button rectangle: one while held, or both during the confirmation beat.
private struct LeavePopupButtonStyle: ButtonStyle {
    let dimAll: Bool
    let cornerRadius: CGFloat
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        Color.black.opacity(
                            // Paired normal/held screenshot pixels measure a ~50% black overlay
                            // (for example #C51010 -> #620808 along the button edge).
                            dimAll ? 0.50 : (configuration.isPressed ? 0.50 : 0)
                        )
                    )
            )
            .animation(.linear(duration: 0.05), value: configuration.isPressed)
            .animation(.linear(duration: 0.05), value: dimAll)
    }
}

// MARK: - HUD (extracted + Equatable)
//
// These used to live inline in ContentView.body. The game loop writes @State every tick, so
// the whole body - every Image, Button and gesture in the overlay - was rebuilt 60-120 times
// a second for no reason. As Equatable child views SwiftUI can compare their inputs and skip
// the rebuild entirely, which is free frame time.
struct TopBarHUD: View, Equatable {
    let score: Int
    let tokenCount: Int
    let fps: Int
    let showFPS: Bool
    let friendCount: Int
    /// True while the player is actually in a party (offline pact or online party
    /// code). The friends counter only renders in that state - out of a party the
    /// top bar shows no counter at all, even "0 friends".
    let inParty: Bool
    let leaderboardRows: [LeaderboardHUDRow]
    var showEmojiWidget: Bool = true
    let onPause: () -> Void
    var onEmotes: () -> Void = {}
    
    static func == (lhs: TopBarHUD, rhs: TopBarHUD) -> Bool {
        return lhs.score == rhs.score
        && lhs.tokenCount == rhs.tokenCount
        && lhs.showFPS == rhs.showFPS
        && lhs.friendCount == rhs.friendCount
        && lhs.inParty == rhs.inParty
        && lhs.showEmojiWidget == rhs.showEmojiWidget
        && lhs.leaderboardRows == rhs.leaderboardRows
        && (lhs.showFPS ? lhs.fps == rhs.fps : true)
    }
    
    var body: some View {
        VStack {
            HStack(alignment: .top) {
                
                // 1. Wrap the pause and emotes buttons in a new VStack
                VStack(spacing: 1) {
                    Button(action: onPause) {
                        Image("pause")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 85, height: 85)
                            .padding(6)
                    }
                    
                    // 2. Emotes button
                    if showEmojiWidget {
                        Button(action: onEmotes) {
                            Image("emotes")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 85, height: 85)
                                .padding(6)
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Score: \(String(score))")
                        .font(.custom("UbuntuSans-Bold", size: 32))
                        .foregroundColor(Color.gray)
                    HStack(spacing: 8) {
                        Image("token").resizable().aspectRatio(contentMode: .fit).frame(width: 40, height: 40)
                        Text("\(tokenCount)")
                            .font(.custom("UbuntuSans-Bold", size: 32))
                            .foregroundColor(Color.gray)
                    }
                    .padding(.leading, 18)
                    if showFPS {
                        Text("\(fps) FPS")
                            .font(.custom("UbuntuSans-Bold", size: 22))
                            .foregroundColor(fps >= 100 ? Color.green : (fps >= 55 ? Color.gray : Color.orange))
                            .padding(.leading, 18)
                    }
                }
                .padding(.top, 10)
                
                Spacer()
                
                // Party HUD: friends icon + "(n) friend(s)", vertically centred against
                // the leaderboard button, exactly like the reference screenshot.
                // Hidden entirely while not in a party (no "0 friends" outside one).
                if inParty {
                    HStack(spacing: 8) {
                        Image("friends-count-icon")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 36, height: 36)
                        Text("\(friendCount) friend\(friendCount == 1 ? "" : "s")")
                            .font(.custom("UbuntuSans-Bold", size: 26))
                            .foregroundColor(Color.gray)
                    }
                    .frame(height: 105)
                    .padding(.trailing, 6)
                }
                
                LeaderboardHUDButton(rows: leaderboardRows)
            }
            Spacer() 
        }
        
        .allowsHitTesting(true)
    }
}

/// One row of the leaderboard HUD panel: "#. Name". isPlayer rows render in #FFE38A.
struct LeaderboardHUDRow: Equatable {
    let rank: Int
    let name: String
    let isPlayer: Bool
    /// True for you + your teammates while a party is active: the row shows the
    /// team pfp (with the teammate cell border as an inner border) before the name.
    var isPartyMember: Bool = false
}

/// White-on-grey stroked HUD text, matching the party-arrow name label's look
/// (white fill, 45%-grey outline) but rendered in SwiftUI: eight offset copies
/// in the stroke colour behind the fill copy.
private struct StrokedHUDText: View {
    let text: String
    let fontSize: CGFloat
    let fill: Color

    var body: some View {
        let base = Text(text)
            .font(.custom("UbuntuSans-Bold", size: fontSize))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        return ZStack {
            // Thin all-round stroke ring...
            ForEach(0..<8, id: \.self) { i in
                let angle = CGFloat(i) * .pi / 4
                base.foregroundColor(Color(white: 0.55))
                    .offset(x: cos(angle) * 0.6, y: sin(angle) * 0.6)
            }
            // ...with a slightly heavier (but still thin) edge under the glyphs.
            base.foregroundColor(Color(white: 0.55)).offset(x: -0.35, y: 0.9)
            base.foregroundColor(Color(white: 0.55)).offset(x: 0.35, y: 0.9)
            base.foregroundColor(Color(white: 0.55)).offset(y: 1.05)
            base.foregroundColor(fill)
        }
    }
}

/// Custom-drawn leaderboard button (replaces the old flat "leaderboard" image).
///
/// Collapsed: an 85x85 rounded square (spec metrics 165/83/25.8/8 scaled by 85/165) -
/// #5F5F5F fill at 16% opacity, inside-aligned #8E8E8E outline at 56% - with the
/// leaderboard icon centred. The icon swaps to "leaderboard-clicked" the instant a
/// finger lands and back on lift; dragging off the button un-focuses it (no action).
/// On a completed press: the LEFT side pushes out over 0.2s (right/top/bottom
/// anchored; the friends counter keeps its gap to the moving left edge because the
/// layout slot grows with it) until the label's right edge sits the same icon-inset
/// distance from the button's right side. The label is never faded in: it sits at a
/// fixed offset from the icon and the button's own clip edge un-crops it from the
/// right as the width grows. When the slide finishes the BOTTOM pushes down the same
/// way, auto-sized to the row count (5 slots when the player is in the top 5, 6 when
/// their row is appended) plus breathing room above and below the rows, un-cropping
/// the rows ("#. Name", white with the party-arrow grey stroke; the player row always
/// "You" in #FFE38A). The lower leaderboard area is 10% darker (black @ 10% over the
/// same fill), separated from the header by a straight og-colour band sitting a touch
/// above where the button's bottom edge used to be, so the icon sits closer to the
/// dark part. Tapping again reverses: bottom retracts, then the left side slides in.
struct LeaderboardHUDButton: View {
    let rows: [LeaderboardHUDRow]

    private let collapsedSide: CGFloat = 85
    /// Fallback width factor, only used for the first frame before the label is measured.
    private let expansionFactor: CGFloat = 3.5
    private var specScale: CGFloat { collapsedSide / 165 }
    private var cornerRadius: CGFloat { 25.8 * specScale }
    private var outlineWidth: CGFloat { 8 * specScale }
    private var iconSize: CGFloat { 83 * specScale }
    private var labelFontSize: CGFloat { 60 * specScale }
    /// Icon inset from the (moving) left edge - same as the collapsed centring inset.
    private var iconInset: CGFloat { (collapsedSide - iconSize) / 2 }
    /// Icon-to-label gap: slightly more than the icon-to-left-edge distance.
    private var iconTextGap: CGFloat { iconInset + 2 }
    /// The og-colour band separating the header from the darker leaderboard area.
    private var separatorHeight: CGFloat { 8 * specScale }
    /// Where the header ends and the separator band begins - pulled a little above
    /// the collapsed button's bottom edge so the icon sits closer to the dark area.
    private var headerBottom: CGFloat { collapsedSide - 7 }
    private let rowFontSize: CGFloat = 30   // just under the header label's 33
    /// Fixed height of each ranking row slot.
    private let rowSlot: CGFloat = 40
    /// Breathing room between the dark section's top/bottom edges and the rows.
    private let rowsVerticalMargin: CGFloat = 10
    /// Team pfp shown before party members' names (teammate cell border applied
    /// as an inner border: outer #FFC300 ring at the edge, #F7F831 just inside).
    private let pfpSide: CGFloat = 32
    private let pfpNameGap: CGFloat = 8
    private let pfpRingWidth: CGFloat = 2.5

    private var partyPfp: some View {
        Image("friend-pfp")
            .resizable()
            .scaledToFill()
            .frame(width: pfpSide, height: pfpSide)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(teammateOuterBorderColor, lineWidth: pfpRingWidth))
            .overlay(Circle().inset(by: pfpRingWidth).strokeBorder(teammateInnerBorderColor, lineWidth: pfpRingWidth))
    }
    private let slideDuration: TimeInterval = 0.2
    private let labelText = "Leaderboard"

    @State private var pressed = false
    @State private var pressCancelled = false
    @State private var expandedH = false
    @State private var expandedV = false
    /// Measured intrinsic width of the label so the expanded shape can end exactly
    /// one icon-inset past the text's right edge (same gap as icon-to-left-side).
    @State private var labelWidth: CGFloat = 0

    private var expandedWidth: CGFloat {
        guard labelWidth > 0 else { return collapsedSide * expansionFactor }
        return iconInset + iconSize + iconTextGap + labelWidth + iconInset
    }
    /// Auto-sizes to the row count: 5 slots when the player is in the top 5,
    /// 6 when their own row is appended below.
    private var expandedHeight: CGFloat {
        headerBottom + separatorHeight + rowsVerticalMargin * 2
            + rowSlot * CGFloat(max(rows.count, 1))
    }
    private var currentWidth: CGFloat { expandedH ? expandedWidth : collapsedSide }
    private var currentHeight: CGFloat { expandedV ? expandedHeight : collapsedSide }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(hex: 0x5F5F5F).opacity(0.16))
            // Lower region, 10% darker than the top part. The og-colour band
            // [headerBottom, headerBottom + separatorHeight] stays undarkened.
            // Since the dark area now starts slightly above the collapsed button's
            // bottom edge, it is faded out entirely until the vertical stage runs
            // (the fade shares the slide's withAnimation, so it never pops).
            .overlay(
                VStack(spacing: 0) {
                    Color.clear.frame(height: headerBottom + separatorHeight)
                    Color.black.opacity(0.10)
                }
                .opacity(expandedV ? 1 : 0),
                alignment: .top
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color(hex: 0x8E8E8E).opacity(0.56), lineWidth: outlineWidth)
            )
            // Header: icon + label pinned to the moving left edge, always fully drawn -
            // the animated clip edge does the letter reveal ("un-crop from the right").
            .overlay(
                HStack(spacing: iconTextGap) {
                    Image(pressed ? "leaderboard-clicked" : "leaderboard-icon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: iconSize, height: iconSize)
                    Text(labelText)
                        .font(.custom("UbuntuSans-Bold", size: labelFontSize))
                        .foregroundColor(Color.gray)
                        .lineLimit(1)
                        .fixedSize()
                        .background(
                            GeometryReader { proxy in
                                Color.clear.onAppear { labelWidth = proxy.size.width }
                            }
                        )
                }
                .padding(.leading, iconInset)
                .fixedSize()
                .frame(height: collapsedSide),
                alignment: .topLeading
            )
            // Ranking rows, pinned below the separator; the downward clip un-crops them.
            .overlay(rowsBlock, alignment: .topLeading)
            .frame(width: currentWidth, height: currentHeight)
            // If the row count changes while the panel is open (player enters or
            // leaves the top 5) the height glides instead of snapping.
            .animation(.easeInOut(duration: slideDuration), value: rows.count)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .gesture(pressGesture)
            // The layout slot tracks the expanded WIDTH (so the friends counter keeps
            // its distance from the left side) but stays collapsed-height: the panel
            // overhangs downward without shifting the HUD row.
            .frame(width: currentWidth, height: collapsedSide, alignment: .topTrailing)
            // The old image button was an 85x85 image with 10pt padding; match its slot.
            .padding(10)
    }

    /// v5.9.4: a row may run until its right edge sits the same inset from the
    /// panel's right side as the rows keep from the left. Anything longer ends
    /// in "..." — we keep the LONGEST prefix that still fits with the dots
    /// appended (measured with the real row font), so truncated names fill the
    /// row all the way to the shared inset instead of stopping short.
    private func fittedRowText(_ full: String, maxWidth: CGFloat) -> String {
        guard maxWidth > 0 else { return full }
        let font = UIFont(name: "UbuntuSans-Bold", size: rowFontSize)
            ?? UIFont.systemFont(ofSize: rowFontSize, weight: .heavy)
        func width(_ s: String) -> CGFloat {
            (s as NSString).size(withAttributes: [.font: font]).width
        }
        guard width(full) > maxWidth else { return full }
        var visible = full
        while !visible.isEmpty && width(visible + "...") > maxWidth {
            visible.removeLast()
        }
        // Dots hug the last glyph — a dangling space before "..." looks broken.
        while visible.hasSuffix(" ") { visible.removeLast() }
        return visible + "..."
    }

    private var rowsBlock: some View {
        // While a party is active every row reserves the pfp column, so names line
        // up whether or not their row actually shows a pfp.
        let showPfpColumn = rows.contains { $0.isPartyMember }
        // Usable text width: same breathing room on the right as the left inset,
        // minus the pfp column when it is reserved.
        let rowTextMaxWidth = expandedWidth - iconInset * 2
            - (showPfpColumn ? pfpSide + pfpNameGap : 0)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(rows, id: \.rank) { row in
                HStack(spacing: pfpNameGap) {
                    if showPfpColumn {
                        if row.isPartyMember {
                            partyPfp
                        } else {
                            Color.clear.frame(width: pfpSide, height: pfpSide)
                        }
                    }
                    StrokedHUDText(text: fittedRowText("\(row.rank). \(row.name)",
                                                       maxWidth: rowTextMaxWidth),
                                   fontSize: rowFontSize,
                                   fill: row.isPlayer ? Color(hex: 0xFFE38A) : .white)
                }
                    .frame(height: rowSlot, alignment: .leading)
                    // No fade when a row appears/disappears (dropping out of or
                    // re-entering the top 5): the row is always fully drawn and
                    // only the animated height crop reveals or hides it.
                    .transition(.identity)
            }
        }
        .padding(.leading, iconInset)
        .padding(.top, headerBottom + separatorHeight + rowsVerticalMargin)
        // Row CONTENT never animates: without this, the rank/name Text swaps and
        // the gold<->white fill change crossfade during the height animation,
        // letting the grey stroke copies show through (the "all grey" flash).
        .transaction { $0.animation = nil }
    }

    /// Finger-down highlight + fire-on-lift. Dragging off the button cancels the
    /// press for good (icon reverts, nothing plays), like a native button losing focus.
    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !pressCancelled else { return }
                let inside = value.location.x >= 0 && value.location.x <= currentWidth
                    && value.location.y >= 0 && value.location.y <= currentHeight
                if inside {
                    pressed = true
                } else if pressed {
                    pressed = false
                    pressCancelled = true
                }
            }
            .onEnded { _ in
                let fire = pressed && !pressCancelled
                pressed = false
                pressCancelled = false
                if fire { toggleExpansion() }
            }
    }

    private func toggleExpansion() {
        if !expandedH {
            withAnimation(.easeInOut(duration: slideDuration)) { expandedH = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + slideDuration) {
                guard expandedH else { return }
                withAnimation(.easeInOut(duration: slideDuration)) { expandedV = true }
            }
        } else {
            // Exact reverse: bottom retracts first, then the left side slides back in.
            withAnimation(.easeInOut(duration: slideDuration)) { expandedV = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + slideDuration) {
                guard !expandedV else { return }
                withAnimation(.easeInOut(duration: slideDuration)) { expandedH = false }
            }
        }
    }
}

/// Raw UIKit press surface for the two eject buttons. UIView touch methods are delivered
/// synchronously the moment a finger lands - there is no recognizer arbitration, no speculative
/// wait, and nothing the pause-popup transition can leave behind to defer them. The hit area is
/// restricted to the inscribed circle so the diagonally adjacent buttons cannot overlap.
private final class ImmediateTouchView: UIView {
    var onDown: (() -> Void)?
    var onUp: (() -> Void)?
    private var isPressTracking = false
    
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let radius = min(bounds.width, bounds.height) / 2
        let dx = point.x - bounds.midX
        let dy = point.y - bounds.midY
        return dx * dx + dy * dy <= radius * radius
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard !isPressTracking else { return }
        isPressTracking = true
        onDown?()
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        finishPress()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        finishPress()
    }
    
    private func finishPress() {
        guard isPressTracking else { return }
        isPressTracking = false
        onUp?()
    }
}

private struct ImmediatePressSurface: UIViewRepresentable {
    let onDown: () -> Void
    let onUp: () -> Void
    
    func makeUIView(context: Context) -> ImmediateTouchView {
        let view = ImmediateTouchView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = false
        view.onDown = onDown
        view.onUp = onUp
        return view
    }
    
    func updateUIView(_ view: ImmediateTouchView, context: Context) {
        view.onDown = onDown
        view.onUp = onUp
    }
}

struct ActionButtonsHUD: View, Equatable {
    let canSplit: Bool
    let canFeed: Bool
    let isFeedingHeld: Bool
    let feedButtonScale: CGFloat
    let macroButtonScale: CGFloat
    let feedHoldThreshold: TimeInterval
    let onSplit: () -> Void
    let onMacroDown: () -> Void
    let onMacroUp: () -> Void
    let onFeedDown: () -> Void
    let onFeedUp: () -> Void
    
    // The split button is a plain Button, so the system fades it while held. Feed and
    // macro use ImmediatePressSurface (needed for hold-to-spam), which has no built-in
    // highlight - mirror the same lighten-on-hold manually.
    @State private var macroPressed = false
    @State private var feedPressed = false
    
    static func == (lhs: ActionButtonsHUD, rhs: ActionButtonsHUD) -> Bool {
        return lhs.canSplit == rhs.canSplit
        && lhs.canFeed == rhs.canFeed
        && lhs.isFeedingHeld == rhs.isFeedingHeld
        && lhs.feedButtonScale == rhs.feedButtonScale
        && lhs.macroButtonScale == rhs.macroButtonScale
    }
    
    var body: some View {
        VStack(alignment: .trailing) {
            Spacer()
            Button(action: onSplit) {
                Image("split").resizable().aspectRatio(contentMode: .fit).frame(width: 145, height: 145).padding(10).opacity(canSplit ? 1.0 : 0.5)
            }.disabled(!canSplit).padding(.trailing, 15)
            
            ZStack(alignment: .bottomTrailing) {
                Image("macro")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 145, height: 145)
                    .scaleEffect(macroButtonScale)
                    .padding(10)
                    .overlay(
                        ImmediatePressSurface(onDown: { macroPressed = true; onMacroDown() },
                                              onUp: { macroPressed = false; onMacroUp() })
                    )
                    .opacity(canFeed ? (macroPressed ? 0.55 : 1.0) : 0.5)
                    .allowsHitTesting(canFeed)
                    .offset(x: -100, y: -100)
                    .padding(.trailing, 75)
                    .accessibilityLabel("Fast eject")
                    .accessibilityAddTraits(.isButton)
                
                ZStack {
                    Image("feed")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 145, height: 145)
                    
                    Circle()
                        .fill(Color.black.opacity(0.2))
                        .frame(width: 145, height: 145)
                        .scaleEffect(isFeedingHeld ? 0.8 : 0.0)
                        .opacity(isFeedingHeld ? 1.0 : 0.0)
                        .animation(
                            isFeedingHeld
                            ? .linear(duration: feedHoldThreshold)
                            : .easeOut(duration: 0.1),
                            value: isFeedingHeld
                        )
                }
                .scaleEffect(feedButtonScale)
                .padding(10)
                .overlay(
                    ImmediatePressSurface(onDown: { feedPressed = true; onFeedDown() },
                                          onUp: { feedPressed = false; onFeedUp() })
                )
                .opacity(canFeed ? (feedPressed ? 0.55 : 1.0) : 0.5)
                .allowsHitTesting(canFeed)
                .padding(.trailing, 75)
                .accessibilityLabel("Eject mass")
                .accessibilityAddTraits(.isButton)
            }
        }
        .padding(.bottom, 30).frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct MinimapHUD: View {
    let playerPosition: CGPoint
    let teammatePositions: [CGPoint]
    let worldSize: CGFloat

    private let mapSide: CGFloat = 110

    var body: some View {
        VStack {
            Spacer()
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.25))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                        )
                    Canvas { context, size in
                        let w = max(1, worldSize)
                        for tp in teammatePositions {
                            let tx = min(max(tp.x / w, 0), 1) * size.width
                            let ty = min(max(tp.y / w, 0), 1) * size.height
                            let rect = CGRect(x: tx - 3.5, y: ty - 3.5, width: 7, height: 7)
                            context.fill(Path(ellipseIn: rect), with: .color(Color(hex: 0xFFC300)))
                        }
                        let px = min(max(playerPosition.x / w, 0), 1) * size.width
                        let py = min(max(playerPosition.y / w, 0), 1) * size.height
                        let dotRect = CGRect(x: px - 5, y: py - 5, width: 10, height: 10)
                        context.fill(Path(ellipseIn: dotRect), with: .color(.white))
                    }
                }
                .frame(width: mapSide, height: mapSide)
                .padding(.leading, 16)
                .padding(.bottom, 16)
                Spacer()
            }
        }
        .allowsHitTesting(false)
    }
}

struct EmotePickerBar: View {
    let isOnCooldown: Bool
    let onSelect: (String) -> Void

    private let emotes = ["emoji-tongue", "emoji-scared"]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(spacing: 6) {
                    ForEach(emotes, id: \.self) { asset in
                        Button(action: { onSelect(asset) }) {
                            Image(asset)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(Circle())
                                .padding(10)
                                .frame(width: 85, height: 85)
                                .background(
                                    RoundedRectangle(cornerRadius: 13)
                                        .fill(Color(hex: 0x5F5F5F).opacity(0.16))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 13)
                                                .strokeBorder(Color(hex: 0x8E8E8E).opacity(0.56), lineWidth: 4)
                                        )
                                )
                                .opacity(isOnCooldown ? 0.45 : 1.0)
                        }
                        .disabled(isOnCooldown)
                    }
                }
                .padding(.leading, 6)
                .padding(.top, 192)
                Spacer()
            }
            Spacer()
        }
    }
}

struct ActiveEmoteBubble: View {
    let assetName: String
    let cellPosition: CGPoint
    let cellRadius: CGFloat
    let smoothedCamera: CGPoint
    let zoomLevel: CGFloat
    let screenSize: CGSize

    var body: some View {
        let sx = (cellPosition.x - smoothedCamera.x) * zoomLevel + screenSize.width / 2
        let sy = (cellPosition.y - smoothedCamera.y) * zoomLevel + screenSize.height / 2
        let side = max(36, min(180, cellRadius * 1.45 * zoomLevel))
        Image(assetName)
            .resizable()
            .scaledToFill()
            .frame(width: side, height: side)
            .clipShape(Circle())
            .position(x: sx, y: sy)
            .allowsHitTesting(false)
    }
}

/// The nickname box could end up focused (blinking caret, paste menu working) with no software
/// keyboard: the text-input session was alive, but the keyboard scene never attached, and a
/// plain reloadInputViews() cannot revive a session in that state. This field now *verifies*
/// that the keyboard actually appeared (via keyboardDidShowNotification) shortly after focus,
/// and if it did not, tears the input session down and rebuilds it with a resign/become cycle -
/// the one thing that forces UIKit to open a fresh keyboard connection. Recovery runs at most
/// once per tap, so a connected hardware keyboard (which legitimately suppresses the software
/// keyboard) never causes flicker loops.
private final class ReliableNicknameUITextField: UITextField {
    private var keyboardDidAttach = false
    private var didAttemptKeyboardRecovery = false
    private var keyboardObserver: NSObjectProtocol?
    
    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder {
            inputView = nil
            DispatchQueue.main.async { [weak self] in
                self?.reloadInputViews()
            }
            beginKeyboardAttachmentWatch()
        }
        return becameFirstResponder
    }
    
    override func resignFirstResponder() -> Bool {
        stopKeyboardAttachmentWatch()
        return super.resignFirstResponder()
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        if !isFirstResponder {
            didAttemptKeyboardRecovery = false
            _ = becomeFirstResponder()
        } else if !keyboardDidAttach {
            // Caret is blinking but the keyboard never came up. A fresh tap is the user asking
            // again, so allow another rebuild instead of only reloading input views.
            didAttemptKeyboardRecovery = false
            forceInputSessionRebuild()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.reloadInputViews()
            }
        }
    }
    
    private func beginKeyboardAttachmentWatch() {
        keyboardDidAttach = false
        stopKeyboardAttachmentWatch()
        keyboardObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardDidShowNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.keyboardDidAttach = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.recoverIfKeyboardMissing()
        }
    }
    
    private func stopKeyboardAttachmentWatch() {
        if let observer = keyboardObserver {
            NotificationCenter.default.removeObserver(observer)
            keyboardObserver = nil
        }
    }
    
    private func recoverIfKeyboardMissing() {
        stopKeyboardAttachmentWatch()
        guard isFirstResponder, !keyboardDidAttach else { return }
        forceInputSessionRebuild()
    }
    
    private func forceInputSessionRebuild() {
        guard !didAttemptKeyboardRecovery else { return }
        didAttemptKeyboardRecovery = true
        _ = resignFirstResponder()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.inputView = nil
            _ = self.becomeFirstResponder()
        }
    }
    
    deinit {
        stopKeyboardAttachmentWatch()
    }
}

private struct ReliableNicknameField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    
    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        
        init(text: Binding<String>) {
            self.text = text
        }
        
        @objc func textDidChange(_ field: UITextField) {
            text.wrappedValue = field.text ?? ""
        }
        
        func textFieldDidBeginEditing(_ textField: UITextField) {
            DispatchQueue.main.async {
                textField.reloadInputViews()
            }
        }
        
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(text: $text)
    }
    
    func makeUIView(context: Context) -> ReliableNicknameUITextField {
        let field = ReliableNicknameUITextField(frame: .zero)
        field.delegate = context.coordinator
        field.addTarget(context.coordinator,
                        action: #selector(Coordinator.textDidChange(_:)),
                        for: .editingChanged)
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor(white: 0.62, alpha: 1.0)]
        )
        field.textAlignment = .center
        field.font = UIFont(name: "UbuntuSans-Bold", size: 22)
        ?? UIFont.systemFont(ofSize: 22, weight: .bold)
        field.textColor = .black
        field.tintColor = .systemBlue
        field.borderStyle = .none
        field.backgroundColor = .clear
        field.keyboardType = .default
        field.returnKeyType = .done
        field.autocapitalizationType = .words
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.textContentType = .nickname
        field.clearButtonMode = .never
        field.adjustsFontSizeToFitWidth = true
        field.minimumFontSize = 14
        field.accessibilityLabel = "Nickname"
        return field
    }
    
    func updateUIView(_ field: ReliableNicknameUITextField, context: Context) {
        context.coordinator.text = $text
        if field.text != text {
            field.text = text
        }
        // Never install an empty custom inputView; nil explicitly means the system keyboard.
        if field.inputView != nil {
            field.inputView = nil
            if field.isFirstResponder { field.reloadInputViews() }
        }
    }
}

/// Numeric sibling of ReliableNicknameField: identical first-responder/keyboard-recovery
/// behaviour (it reuses ReliableNicknameUITextField), but with a number pad and live
/// clamping to the 1-150 league range. Values above 150 snap down as they are typed;
/// empty/zero keeps the last valid level and snaps back when editing ends.
private struct ReliableLevelField: UIViewRepresentable {
    @Binding var level: Int
    
    final class Coordinator: NSObject, UITextFieldDelegate {
        var level: Binding<Int>
        
        init(level: Binding<Int>) {
            self.level = level
        }
        
        @objc func textDidChange(_ field: UITextField) {
            var digits = (field.text ?? "").filter { $0.isNumber }
            if digits.count > 3 { digits = String(digits.prefix(3)) }
            if digits != field.text { field.text = digits }
            guard let value = Int(digits) else { return }
            if value > 150 {
                level.wrappedValue = 150
                field.text = "150"
            } else if value >= 1 {
                level.wrappedValue = value
            }
        }
        
        func textFieldDidBeginEditing(_ textField: UITextField) {
            DispatchQueue.main.async {
                textField.reloadInputViews()
            }
        }
        
        func textFieldDidEndEditing(_ textField: UITextField) {
            textField.text = String(level.wrappedValue)
        }
        
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(level: $level)
    }
    
    func makeUIView(context: Context) -> ReliableNicknameUITextField {
        let field = ReliableNicknameUITextField(frame: .zero)
        field.delegate = context.coordinator
        field.addTarget(context.coordinator,
                        action: #selector(Coordinator.textDidChange(_:)),
                        for: .editingChanged)
        field.text = String(level)
        field.textAlignment = .center
        field.font = UIFont(name: "UbuntuSans-Bold", size: 20)
        ?? UIFont.systemFont(ofSize: 20, weight: .bold)
        field.textColor = .black
        field.tintColor = .systemBlue
        field.borderStyle = .none
        field.backgroundColor = .clear
        field.keyboardType = .numberPad
        field.returnKeyType = .done
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.clearButtonMode = .never
        field.accessibilityLabel = "Level"
        return field
    }
    
    func updateUIView(_ field: ReliableNicknameUITextField, context: Context) {
        context.coordinator.level = $level
        // Never rewrite the text mid-typing; the coordinator owns it while editing.
        if !field.isFirstResponder {
            let text = String(level)
            if field.text != text { field.text = text }
        }
        // Never install an empty custom inputView; nil explicitly means the system keyboard.
        if field.inputView != nil {
            field.inputView = nil
            if field.isFirstResponder { field.reloadInputViews() }
        }
    }
}

struct MainMenu: View {
    @Binding var isPlaying: Bool
    @Binding var zoomLevel: CGFloat
    @Binding var selectedSkinName: String?
    @Binding var playerName: String
    @Binding var showPlayerLevel: Bool
    @Binding var playerLevel: Int
    
    @Binding var playerStartMass: CGFloat
    @Binding var botStartMass: CGFloat
    @Binding var randomizeBotStartMass: Bool
    @Binding var targetBotCount: Int
    @Binding var feedBotCount: Int
    @Binding var botSkill: Double
    
    private var menuBotSkillLabel: String {
        let name = botSkill < 0.65 ? "Chill" : botSkill < 0.95 ? "Normal"
                 : botSkill < 1.25 ? "Sharp" : "Ruthless"
        return String(format: "%.1fx  (%@)", botSkill, name)
    }
    
    @State private var showSettings = false
    @State private var showPartyMenu = false
    @State private var partyJoinCode: String = ""
    /// Active party code (6 chars A-Z/0-9), "" = not in a party. Shared with the
    /// online session, which sends it in the hello so the server can group the party.
    @AppStorage("macro.partyCode") private var partyCode: String = ""
    /// Dark mode: inverts the grid colours in matches (shared with the renderer).
    @AppStorage("macro.darkModeGrid") private var darkModeGrid: Bool = false
    /// Show Mass: shows/hides the mass counter on cells (shared with the renderer).
    @AppStorage("macro.showMassText") private var showMassText: Bool = true
    @AppStorage("macro.showMinimap") private var showMinimap: Bool = false
    @AppStorage("macro.showArrow") private var showArrow: Bool = true
    @AppStorage("macro.showSkins") private var showSkins: Bool = true
    @AppStorage("macro.showEmojiWidget") private var showEmojiWidget: Bool = true
    @AppStorage("macro.soundEnabled") private var soundEnabled: Bool = true
    @AppStorage("macro.coins") private var coinsCount: Int = 1000
    @AppStorage("macro.dna") private var dnaCount: Int = 50
    @AppStorage("macro.activeStartBoost") private var activeStartBoost: Int = 0
    @State private var showSkinDrawer: Bool = false
    @State private var showSkinsModal: Bool = false
    @State private var activeInfoTab: String? = nil
    /// Injected by ContentView; opens the PLAY ONLINE server browser.
    var onPlayOnline: () -> Void = {}
    let availableSkins = (1...387).map { String($0) }

    /// Party create/join/leave overlay. Split out of `body` so the main-menu
    /// ZStack stays small enough for the Swift type-checker.
    private var partyOverlay: some View {
            ZStack {
                Color.black.opacity(0.7).edgesIgnoringSafeArea(.all).onTapGesture { withAnimation { showPartyMenu = false } }
                
                VStack(spacing: 18) {
                    Text("Party").font(.custom("UbuntuSans-Bold", size: 28)).foregroundColor(.white)
                    
                    if partyCode.isEmpty {
                        Text("Team up with friends: create a party and share the code, or join one with theirs. Everyone in the party joins the same online server and plays as a team.")
                            .font(.custom("UbuntuSans-Bold", size: 14))
                            .foregroundColor(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                        
                        Button(action: {
                            let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
                            partyCode = String((0..<6).map { _ in alphabet.randomElement()! })
                        }) {
                            Text("Create Party").font(.headline).foregroundColor(.white)
                                .padding().frame(maxWidth: .infinity)
                                .background(Color.orange).cornerRadius(10)
                        }
                        
                        Text("Or join with a code").font(.custom("UbuntuSans-Bold", size: 14)).foregroundColor(.white.opacity(0.8))
                        HStack(spacing: 10) {
                            TextField("ABC123", text: $partyJoinCode)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .font(.custom("UbuntuSans-Bold", size: 20))
                                .multilineTextAlignment(.center)
                                .padding(10)
                                .frame(width: 150)
                                .background(Color.white.opacity(0.85).cornerRadius(8))
                            Button(action: {
                                let cleaned = sanitizedPartyCode(partyJoinCode)
                                if !cleaned.isEmpty { partyCode = cleaned; partyJoinCode = "" }
                            }) {
                                Text("Join").font(.headline).foregroundColor(.white)
                                    .padding(.horizontal, 24).padding(.vertical, 12)
                                    .background(sanitizedPartyCode(partyJoinCode).isEmpty ? Color.gray : Color.blue)
                                    .cornerRadius(10)
                            }
                            .disabled(sanitizedPartyCode(partyJoinCode).isEmpty)
                        }
                    } else {
                        Text("Share this code - friends enter it under Party → join:")
                            .font(.custom("UbuntuSans-Bold", size: 14))
                            .foregroundColor(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                        Text(partyCode.map { String($0) }.joined(separator: " "))
                            .font(.custom("UbuntuSans-Bold", size: 40))
                            .foregroundColor(.white)
                            .padding(.vertical, 6)
                        Text("Everyone in the party joins the same server in Play Online and plays together, just like teaming up in a normal match.")
                            .font(.custom("UbuntuSans-Bold", size: 13))
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                        Button(action: { partyCode = "" }) {
                            Text("Leave Party").font(.headline).foregroundColor(.white)
                                .padding().frame(maxWidth: .infinity)
                                .background(Color.red.opacity(0.85)).cornerRadius(10)
                        }
                    }
                    
                    Button(action: { withAnimation { showPartyMenu = false } }) {
                        Text("Done").font(.headline).foregroundColor(.white).padding().frame(maxWidth: .infinity).background(Color.blue).cornerRadius(10)
                    }
                }
                .padding(24)
                .frame(width: 340)
                .background(Color(white: 0.15))
                .cornerRadius(20)
                .shadow(radius: 20)
            }
    }
    
    private var topMenuBar: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                // Top-Left: Free, Leagues, Quests, Potions squares (matching Screenshot 5)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        topSquareButton(icon: "ui-gift-icon", label: "Free", fill: Color(hex: 0x54C826), bevel: Color(hex: 0x398E17)) {
                            activeInfoTab = "Gifts"
                        }
                        topSquareButton(icon: "ui-leagues-icon", label: "Leagues", fill: Color(hex: 0x00C8F8), bevel: Color(hex: 0x0095BA)) {
                            activeInfoTab = "Leagues"
                        }
                        topSquareButton(icon: "ui-quest-chest", label: "Quests", fill: Color(hex: 0x00C8F8), bevel: Color(hex: 0x0095BA)) {
                            activeInfoTab = "Quests"
                        }
                        topSquareButton(icon: "ui-mystery-potion", label: "Potions", fill: Color(hex: 0x00C8F8), bevel: Color(hex: 0x0095BA)) {
                            activeInfoTab = "Potions"
                        }
                        topSquareButton(icon: "ui-star-icon", label: "VIP", fill: Color(hex: 0x22262E), bevel: Color(hex: 0x111318)) {
                            activeInfoTab = "Shop"
                        }
                    }

                    // Left-side 3X XP & 3X Mass quick boost badges
                    VStack(spacing: 8) {
                        Button(action: { SoundManager.shared.play(.menuClick); activeInfoTab = "Shop" }) {
                            Image("ui-shop-xp3x").resizable().scaledToFit().frame(width: 44, height: 34)
                        }
                        Button(action: { SoundManager.shared.play(.menuClick); activeInfoTab = "Shop" }) {
                            Image("ui-shop-mass3x").resizable().scaledToFit().frame(width: 44, height: 34)
                        }
                    }
                    .padding(.top, 4)
                }

                Spacer()

                // Top-Right: DNA & Coins pills + Collect Reward banner (matching Screenshot 5)
                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 8) {
                        Button(action: { SoundManager.shared.play(.menuClick); activeInfoTab = "Shop" }) {
                            HStack(spacing: 6) {
                                Image("ui-dna-icon").resizable().scaledToFit().frame(width: 22, height: 22)
                                Text("\(dnaCount)")
                                    .font(.custom("UbuntuSans-Bold", size: 15))
                                    .foregroundColor(Color(hex: 0x4A4A4A))
                                    .contentTransition(.numericText())
                                    .animation(.easeOut(duration: 0.25), value: dnaCount)
                                Image("ui-plus-box").resizable().scaledToFit().frame(width: 20, height: 20)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.95))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0x62C92E), lineWidth: 2))
                            )
                        }

                        Button(action: { SoundManager.shared.play(.menuClick); activeInfoTab = "Shop" }) {
                            HStack(spacing: 6) {
                                Image("ui-coin-icon").resizable().scaledToFit().frame(width: 22, height: 22)
                                Text("\(coinsCount)")
                                    .font(.custom("UbuntuSans-Bold", size: 15))
                                    .foregroundColor(Color(hex: 0x4A4A4A))
                                    .contentTransition(.numericText())
                                    .animation(.easeOut(duration: 0.25), value: coinsCount)
                                Image("ui-plus-box").resizable().scaledToFit().frame(width: 20, height: 20)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.95))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0x62C92E), lineWidth: 2))
                            )
                        }
                    }

                    Button(action: { SoundManager.shared.play(.menuClick); activeInfoTab = "Gifts" }) {
                        HStack(spacing: 6) {
                            Image("ui-star-icon").resizable().scaledToFit().frame(width: 22, height: 22)
                            Text("Collect Reward")
                                .font(.custom("UbuntuSans-Bold", size: 13))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(AgarBevelButtonStyle(fill: Color(hex: 0xFFB300), bevel: Color(hex: 0xD98200), cornerRadius: 10))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            Spacer()
        }
    }

    private func topSquareButton(icon: String, label: String, fill: Color, bevel: Color, action: @escaping () -> Void) -> some View {
        Button(action: {
            SoundManager.shared.play(.menuClick)
            withAnimation { action() }
        }) {
            VStack(spacing: 2) {
                Image(icon).resizable().scaledToFit().frame(width: 26, height: 26)
                Text(label)
                    .font(.custom("UbuntuSans-Bold", size: 10))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .frame(width: 54, height: 54)
            .background(AgarBevelButtonStyle(fill: fill, bevel: bevel, cornerRadius: 10))
        }
    }

    private var bottomFeatureDock: some View {
        VStack {
            Spacer()
            HStack(alignment: .center, spacing: 10) {
                // Bottom-Left: Settings (cyan) + Party/Friends (blue)
                Button(action: {
                    SoundManager.shared.play(.menuClick)
                    withAnimation { showSettings = true }
                }) {
                    Image("ui-settings-icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .frame(width: 54, height: 52)
                        .background(AgarBevelButtonStyle(fill: Color(hex: 0x00C8F8), bevel: Color(hex: 0x0095BA), cornerRadius: 10))
                }

                Button(action: {
                    SoundManager.shared.play(.menuClick)
                    partyJoinCode = ""
                    withAnimation { showPartyMenu = true }
                }) {
                    Image("ui-party-icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 24)
                        .frame(width: 54, height: 52)
                        .background(AgarBevelButtonStyle(fill: Color(hex: 0x0088FF), bevel: Color(hex: 0x005EC4), cornerRadius: 10))
                }

                Spacer()

                // Bottom-Right: Shop (green) + Profile/Level (blue)
                Button(action: {
                    SoundManager.shared.play(.menuClick)
                    withAnimation { activeInfoTab = "Shop" }
                }) {
                    HStack(spacing: 8) {
                        Text("Shop")
                            .font(.custom("UbuntuSans-Bold", size: 20))
                            .foregroundColor(.white)
                        Image("ui-shop-icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 26, height: 24)
                    }
                    .frame(width: 132, height: 52)
                    .background(AgarBevelButtonStyle(fill: Color(hex: 0x54C826), bevel: Color(hex: 0x398E17), cornerRadius: 10))
                }

                Button(action: {
                    SoundManager.shared.play(.menuClick)
                    withAnimation { activeInfoTab = "Leagues" }
                }) {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                ZStack {
                                    Image("ui-star-icon").resizable().scaledToFit().frame(width: 20, height: 20)
                                    Text("\(LeagueBadge.clamp(playerLevel))")
                                        .font(.custom("UbuntuSans-Bold", size: 9))
                                        .foregroundColor(.white)
                                }
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white.opacity(0.92))
                                    .frame(width: 80, height: 10)
                            }
                            Text(playerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Guest" : playerName)
                                .font(.custom("UbuntuSans-Bold", size: 13))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        ZStack {
                            Image("ui-profile-guest")
                                .resizable()
                                .scaledToFill()
                                .frame(width: 36, height: 36)
                                .cornerRadius(6)
                            if let skin = selectedSkinName {
                                SkinSelectorPreview(skinName: skin)
                                    .frame(width: 36, height: 36)
                                    .cornerRadius(6)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 52)
                    .background(AgarBevelButtonStyle(fill: Color(hex: 0x0088FF), bevel: Color(hex: 0x005EC4), cornerRadius: 10))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
    }

    private var skinsModalOverlay: some View {
        ZStack {
            Color.black.opacity(0.68).edgesIgnoringSafeArea(.all).onTapGesture { withAnimation { showSkinsModal = false } }
            VStack(spacing: 14) {
                HStack {
                    Spacer()
                    Text("Skins").font(.custom("UbuntuSans-Bold", size: 26)).foregroundColor(.white)
                    Spacer()
                    Button(action: { SoundManager.shared.play(.menuClick); withAnimation { showSkinsModal = false } }) {
                        Image("ui-close-btn").resizable().scaledToFit().frame(width: 28, height: 28)
                    }
                }
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: 12)], spacing: 12) {
                        Button(action: { SoundManager.shared.play(.menuClick); selectedSkinName = nil; showSkinsModal = false }) {
                            ZStack {
                                Circle().fill(LinearGradient(gradient: Gradient(colors: [.red, .orange, .yellow, .green, .blue, .purple]), startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 60, height: 60)
                                Image(systemName: "xmark").font(.title3.bold()).foregroundColor(.white)
                                if selectedSkinName == nil { Circle().stroke(Color.white, lineWidth: 4).frame(width: 66, height: 66) }
                            }
                        }
                        Button(action: { SoundManager.shared.play(.menuClick); selectedSkinName = "Dragon"; showSkinsModal = false }) {
                            ZStack {
                                SkinSelectorPreview(skinName: "Dragon").frame(width: 60, height: 60)
                                if selectedSkinName == "Dragon" { Circle().stroke(Color.white, lineWidth: 4).frame(width: 66, height: 66) }
                            }
                        }
                        ForEach(availableSkins, id: \.self) { skin in
                            Button(action: { SoundManager.shared.play(.menuClick); selectedSkinName = skin; showSkinsModal = false }) {
                                ZStack {
                                    SkinSelectorPreview(skinName: skin).frame(width: 60, height: 60)
                                    if selectedSkinName == skin { Circle().stroke(Color.white, lineWidth: 4).frame(width: 66, height: 66) }
                                }
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 360)
            }
            .padding(20)
            .frame(width: 360)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(hex: 0x1A2E4C))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.18), lineWidth: 2))
            )
            .shadow(radius: 20)
        }
    }

    private func infoModalOverlay(title: String) -> some View {
        ZStack {
            Color.black.opacity(0.68).edgesIgnoringSafeArea(.all).onTapGesture { withAnimation { activeInfoTab = nil } }
            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    Text(title).font(.custom("UbuntuSans-Bold", size: 26)).foregroundColor(.white)
                    Spacer()
                    Button(action: { SoundManager.shared.play(.menuClick); withAnimation { activeInfoTab = nil } }) {
                        Image("ui-close-btn").resizable().scaledToFit().frame(width: 28, height: 28)
                    }
                }
                HStack(spacing: 12) {
                    Image(LeagueBadge.assetName(forLevel: playerLevel)).resizable().scaledToFit().frame(width: 64, height: 60)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Level: \(LeagueBadge.clamp(playerLevel))")
                            .font(.custom("UbuntuSans-Bold", size: 18)).foregroundColor(.white)
                        Text("Adjust your level in the top-left profile bar (1-150).")
                            .font(.custom("UbuntuSans-Bold", size: 13)).foregroundColor(.white.opacity(0.75))
                    }
                }
                Button(action: { SoundManager.shared.play(.menuClick); withAnimation { activeInfoTab = nil } }) {
                    Text("Close").font(.custom("UbuntuSans-Bold", size: 18)).foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(AgarBevelButtonStyle(fill: Color(hex: 0x1E88E5), bevel: Color(hex: 0x125899), cornerRadius: 10))
                }
            }
            .padding(20)
            .frame(width: 340)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(hex: 0x1A2E4C))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.18), lineWidth: 2))
            )
            .shadow(radius: 20)
        }
    }

    var body: some View {
        ZStack {
            Image("background-ipadpro-hd").resizable().scaledToFill().scaleEffect(1).edgesIgnoringSafeArea(.all)
            
            topMenuBar.zIndex(1)
            bottomFeatureDock.zIndex(1)
            
            VStack(spacing: 16) {
                Spacer()
                // Clean grey Agar.io logo matching Screenshot 5
                Image("title")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 250)
                    .padding(.bottom, 2)
                
                // Skin circle with green '+' on LEFT + White Nickname box on RIGHT (Screenshot 5)
                HStack(spacing: 12) {
                    Button(action: {
                        SoundManager.shared.play(.menuClick)
                        showSkinsModal = true
                    }) {
                        ZStack(alignment: .bottomLeading) {
                            ZStack {
                                Circle().fill(Color.white).frame(width: 54, height: 54)
                                if let skin = selectedSkinName {
                                    SkinSelectorPreview(skinName: skin)
                                        .frame(width: 50, height: 50)
                                        .clipShape(Circle())
                                } else {
                                    Image("ui-skins-icon").resizable().scaledToFit().frame(width: 50, height: 50)
                                }
                            }
                            .overlay(Circle().stroke(Color(hex: 0xCCCCCC), lineWidth: 2))
                            Image("ui-plus-box")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .offset(x: -4, y: 4)
                        }
                    }

                    ReliableNicknameField(text: $playerName, placeholder: "Nickname")
                        .frame(width: 270, height: 48)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xCCCCCC), lineWidth: 2))
                        )
                        .multilineTextAlignment(.center)
                }
                
                // Mode Play Row: Classic (orange) + Play Online (green) + Party (blue) (Screenshot 5)
                HStack(spacing: 14) {
                    Button(action: {
                        SoundManager.shared.play(.menuClick)
                        withAnimation(.easeOut(duration: 0.4)) { zoomLevel = 0.8; isPlaying = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { withAnimation(.spring(duration: 1)) { zoomLevel = 1.0 } }
                    }) {
                        VStack(spacing: 8) {
                            Image("ui-play-icon").resizable().scaledToFit().frame(width: 34, height: 36)
                            Text("Classic")
                                .font(.custom("UbuntuSans-Bold", size: 20))
                                .foregroundColor(.white)
                        }
                        .frame(width: 148, height: 116)
                        .background(AgarBevelButtonStyle(fill: Color(hex: 0xF26522), bevel: Color(hex: 0xBA4610), cornerRadius: 12))
                    }

                    Button(action: {
                        SoundManager.shared.play(.menuClick)
                        onPlayOnline()
                    }) {
                        VStack(spacing: 8) {
                            Image("ui-party-icon").resizable().scaledToFit().frame(width: 38, height: 34)
                            Text("Play Online")
                                .font(.custom("UbuntuSans-Bold", size: 19))
                                .foregroundColor(.white)
                        }
                        .frame(width: 148, height: 116)
                        .background(AgarBevelButtonStyle(fill: Color(hex: 0x54C826), bevel: Color(hex: 0x398E17), cornerRadius: 12))
                    }

                    Button(action: {
                        SoundManager.shared.play(.menuClick)
                        partyJoinCode = ""
                        withAnimation { showPartyMenu = true }
                    }) {
                        VStack(spacing: 8) {
                            Image(systemName: "star.fill").font(.system(size: 32)).foregroundColor(.white)
                            Text(partyCode.isEmpty ? "Party" : partyCode)
                                .font(.custom("UbuntuSans-Bold", size: 19))
                                .foregroundColor(.white)
                        }
                        .frame(width: 148, height: 116)
                        .background(AgarBevelButtonStyle(fill: Color(hex: 0x0088FF), bevel: Color(hex: 0x005EC4), cornerRadius: 12))
                    }
                }
                .padding(.top, 6)
                Spacer()
            }
            
            if showPartyMenu { partyOverlay.zIndex(2) }
            if showSkinsModal { skinsModalOverlay.zIndex(2) }
            if let tab = activeInfoTab {
                switch tab {
                case "Shop":
                    ShopModalView(coins: $coinsCount, dna: $dnaCount, activeStartBoost: $activeStartBoost) {
                        withAnimation { activeInfoTab = nil }
                    }
                    .zIndex(2)
                case "Quests":
                    QuestsModalView(coins: $coinsCount, dna: $dnaCount) {
                        withAnimation { activeInfoTab = nil }
                    }
                    .zIndex(2)
                case "Potions":
                    PotionsModalView(coins: $coinsCount, dna: $dnaCount) {
                        withAnimation { activeInfoTab = nil }
                    }
                    .zIndex(2)
                case "Gifts", "News":
                    GiftsNewsModalView(title: tab, coins: $coinsCount, dna: $dnaCount) {
                        withAnimation { activeInfoTab = nil }
                    }
                    .zIndex(2)
                default:
                    infoModalOverlay(title: tab).zIndex(2)
                }
            }
            
            // Full-screen Light Settings matching Screenshot 8
            if showSettings {
                ZStack {
                    Color(hex: 0xF4F6F8).edgesIgnoringSafeArea(.all)
                    VStack(spacing: 0) {
                        HStack {
                            Button(action: { SoundManager.shared.play(.menuClick); withAnimation { showSettings = false } }) {
                                ZStack {
                                    Circle().fill(Color(hex: 0x00C8F8)).frame(width: 34, height: 34)
                                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                                }
                            }
                            Spacer()
                            Text("Settings")
                                .font(.custom("UbuntuSans-Bold", size: 24))
                                .foregroundColor(Color(hex: 0x6E6E6E))
                            Spacer()
                            Color.clear.frame(width: 34, height: 34)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color.white)

                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Game Options")
                                    .font(.custom("UbuntuSans-Bold", size: 18))
                                    .foregroundColor(Color(hex: 0x555555))
                                    .padding(.top, 8)

                                lightSettingToggle("Sound Effects", isOn: $soundEnabled)
                                lightSettingToggle("Show Level Badge", isOn: $showPlayerLevel)
                                lightSettingToggle("Dark Mode Grid", isOn: $darkModeGrid)
                                lightSettingToggle("Show Mass", isOn: $showMassText)
                                lightSettingToggle("Show Arrow", isOn: $showArrow)
                                lightSettingToggle("Show Skins", isOn: $showSkins)
                                lightSettingToggle("Show Emoji Widget", isOn: $showEmojiWidget)
                                lightSettingToggle("Show Minimap", isOn: $showMinimap)

                                Text("Offline Match")
                                    .font(.custom("UbuntuSans-Bold", size: 18))
                                    .foregroundColor(Color(hex: 0x555555))
                                    .padding(.top, 8)

                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Player Start Mass: \(Int(playerStartMass))").font(.custom("UbuntuSans-Bold", size: 15)).foregroundColor(Color(hex: 0x555555))
                                    Slider(value: $playerStartMass, in: 10...5000, step: 10).accentColor(Color(hex: 0x00C8F8))

                                    Text("Bot Start Mass: \(Int(botStartMass))").font(.custom("UbuntuSans-Bold", size: 15)).foregroundColor(Color(hex: 0x555555))
                                    Slider(value: $botStartMass, in: 10...5000, step: 10).accentColor(Color(hex: 0x54C826))
                                        .opacity(randomizeBotStartMass ? 0.4 : 1.0)
                                        .disabled(randomizeBotStartMass)

                                    Toggle("Randomize Bot Start Mass", isOn: $randomizeBotStartMass)
                                        .font(.custom("UbuntuSans-Bold", size: 15))
                                        .foregroundColor(Color(hex: 0x555555))
                                        .tint(Color(hex: 0x54C826))

                                    Text("Bot Count: \(targetBotCount)").font(.custom("UbuntuSans-Bold", size: 15)).foregroundColor(Color(hex: 0x555555))
                                    Slider(value: Binding(get: { Double(targetBotCount) }, set: { targetBotCount = Int($0) }), in: 0...100, step: 1).accentColor(Color(hex: 0xF26522))

                                    Text("Feed Bot Count: \(feedBotCount)").font(.custom("UbuntuSans-Bold", size: 15)).foregroundColor(Color(hex: 0x555555))
                                    Slider(value: Binding(get: { Double(feedBotCount) }, set: { feedBotCount = Int($0) }), in: 0...50, step: 1).accentColor(.pink)

                                    Text("Bot Skill: \(menuBotSkillLabel)").font(.custom("UbuntuSans-Bold", size: 15)).foregroundColor(Color(hex: 0x555555))
                                    Slider(value: $botSkill, in: 0.4...1.6, step: 0.1).accentColor(.red)
                                }
                                .padding(14)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                            }
                            .padding(.horizontal, 18)
                            .padding(.bottom, 24)
                        }
                    }
                }
                .zIndex(3)
            }
        }
    }

    private func lightSettingToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .font(.custom("UbuntuSans-Bold", size: 16))
            .foregroundColor(Color(hex: 0x6E6E6E))
            .tint(Color(hex: 0x54C826))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
    }
}

struct PlayerArrow: View {
    let geometry: GeometryProxy
    let joystickIsDragging: Bool
    let joystickOffset: CGSize
    let lastJoystickDirection: CGSize
    let playerCells: [PlayerCell]
    let playerCenter: CGPoint
    @Binding var zoomLevel: CGFloat
    
    var body: some View {
        let screenCenter = CGPoint(x: geometry.size.width / 2, y: (geometry.size.height + geometry.safeAreaInsets.top) / 2)
        let direction = joystickIsDragging ? joystickOffset : lastJoystickDirection
        let angle = atan2(Double(direction.height), Double(direction.width))
        
        // v44: the arrow rides a CIRCLE around the player - the bounding circle
        // of all cells (farthest cell edge from the centre). v43 projected each
        // cell onto the aim direction, which made the arrow hug the silhouette
        // of the split pieces, so its distance pulsed as the aim rotated.
        // Direction-independent radius = perfect circle path; for a single cell
        // it still reduces to exactly that cell's radius.
        var extent: CGFloat = 0
        for cell in playerCells {
            let dx = cell.position.x - playerCenter.x
            let dy = cell.position.y - playerCenter.y
            extent = max(extent, sqrt(dx * dx + dy * dy) + cell.cachedSolidRadius)
        }
        
        // The gap between the cell edge and the arrow used to be 50 WORLD units,
        // which the zoom then scaled: huge on a small (zoomed-in) single cell,
        // shrinking to almost nothing on a big (zoomed-out) one. Keep it a constant
        // SCREEN distance instead, matched to how it looked at ~2k mass
        // (50 * zoom(2000) ≈ 24pt), which was the sweet spot.
        let rawOffset = extent * zoomLevel + 24
        let rawX = screenCenter.x + (rawOffset * CGFloat(cos(angle)))
        let rawY = screenCenter.y + (rawOffset * CGFloat(sin(angle)))
        
        let padding: CGFloat = 40
        let minX = padding
        let maxX = geometry.size.width - padding
        let minY = padding + geometry.safeAreaInsets.top
        let maxY = geometry.size.height + geometry.safeAreaInsets.top - padding
        
        let clampedX = min(maxX, max(minX, rawX))
        let clampedY = min(maxY, max(minY, rawY))
        
        return Image("arrow")
            .resizable().aspectRatio(contentMode: .fit).frame(width: 24, height: 28).foregroundColor(.white)
            .rotationEffect(Angle(radians: angle + Double.pi / 2)).position(x: clampedX, y: clampedY).opacity(0.5)
    }
}

struct JoystickView: View {
    @Binding var joystickOffset: CGSize
    @Binding var joystickBasePosition: CGPoint?
    
    var body: some View {
        ZStack {
            ZStack {
                Image("joystick-base").resizable().scaledToFit().frame(width: 140.4)
                Circle().fill(Color.black).frame(width: 68).offset(joystickOffset).blendMode(.destinationOut)
            }.compositingGroup()
            Image("joystick-circle").resizable().scaledToFit().frame(width: 70.2).offset(joystickOffset)
        }
        .opacity(0.5)
        .position(joystickBasePosition ?? .zero)
        .animation(.linear(duration: 0.1), value: joystickOffset)
    }
}

private func spawnSingleFood() -> Food {
    let worldSize: CGFloat = 11000
    let randomX = CGFloat.random(in: 0...worldSize)
    let randomY = CGFloat.random(in: 0...worldSize)
    return Food(position: CGPoint(x: randomX, y: randomY))
}

private func spawnSingleVirus() -> Virus {
    let worldSize: CGFloat = 11000
    let randomX = CGFloat.random(in: 100...worldSize - 100)
    let randomY = CGFloat.random(in: 100...worldSize - 100)
    return Virus(position: CGPoint(x: randomX, y: randomY))
}

private func spawnSingleToken(existing:[Token] = []) -> Token {
    let worldSize: CGFloat = 11000
    for _ in 0..<5 {
        let randomX = CGFloat.random(in: 100...worldSize - 100)
        let randomY = CGFloat.random(in: 100...worldSize - 100)
        let pos = CGPoint(x: randomX, y: randomY)
        
        var tooClose = false
        if !existing.isEmpty {
            for _ in 0..<min(10, existing.count) {
                if let randomExisting = existing.randomElement() {
                    let dx = randomExisting.position.x - pos.x
                    let dy = randomExisting.position.y - pos.y
                    if (dx*dx + dy*dy) < 500*500 { tooClose = true; break }
                }
            }
        }
        if !tooClose { return Token(position: pos) }
    }
    let randomX = CGFloat.random(in: 100...worldSize - 100)
    let randomY = CGFloat.random(in: 100...worldSize - 100)
    return Token(position: CGPoint(x: randomX, y: randomY))
}

// MARK: - Useful Extensions
extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
    
    func darker(ratio: CGFloat = 0.9) -> Color {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        
        return Color(red: Double(r * ratio), green: Double(g * ratio), blue: Double(b * ratio), opacity: Double(a))
    }
}

extension CGSize {
    func normalized() -> CGSize {
        let magnitude = sqrt(self.width * self.width + self.height * self.height)
        guard magnitude > 0 else { return .zero }
        return CGSize(width: self.width / magnitude, height: self.height / magnitude)
    }
    
    func rotated(by angle: CGFloat) -> CGSize {
        let c = CGFloat(cos(Double(angle)))
        let s = CGFloat(sin(Double(angle)))
        return CGSize(width: width * c - height * s,
                      height: width * s + height * c)
    }
}

extension Array where Element: Hashable {
    func unique() -> [Element] {
        var set = Set<Element>()
        return filter { set.insert($0).inserted }
    }
}
