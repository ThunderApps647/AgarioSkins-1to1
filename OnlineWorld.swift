//
//  OnlineWorld.swift — client-side replica of the server world.
//
//  Technique: classic snapshot interpolation (Source-engine style).
//  * The server simulates and streams snapshots at 60Hz + event deltas.
//  * The client renders ~110ms in the past, interpolating every cell between
//    the two snapshots that bracket the render time, and replays world events
//    (food eaten, pellets fired, virus pops, cells eaten) exactly when the
//    render timeline crosses the snapshot that carried them. Everything the
//    renderer sees therefore moves on one consistent timeline at the full
//    local frame rate (60/120Hz), regardless of network jitter.
//  * Ejected-pellet flight is deterministic (direction + speed are in the
//    spawn event, and the flight math is identical to the offline build), so
//    pellets are simulated locally through the untouched EjectedMassManager
//    and only their spawn/eat events cross the network.
//
//  The renderer is the ORIGINAL GameWorldView — this file only feeds it the
//  same PlayerCell/Food/EjectedMass/Virus/Token state the offline sim would.
//

import SwiftUI
import QuartzCore

// Palette identical to the offline build.
private let onlineBotColors: [Color] = [
    Color(hex: 0xFF0820), Color(hex: 0x0851FF), Color(hex: 0xFF6D08),
    Color(hex: 0x01FFBD), Color(hex: 0xFFCC00), Color(hex: 0x07FF63),
    Color(hex: 0x7B08FF), Color(hex: 0xFF2001), Color(hex: 0xFF08E7)
]
private let onlinePlayerColors: [Color] = [
    Color(hex: 0x67DD00), Color(hex: 0xFFCC00), Color(hex: 0xFF7E00), Color(hex: 0xFF3C3C),
    Color(hex: 0xB608FF), Color(hex: 0xFF3ED3), Color(hex: 0x0078FE), Color(hex: 0x01DDFE)
]

extension Food {
    /// Server-authoritative pellet with a fixed palette index.
    init(position: CGPoint, fixedColorIndex: Int) {
        self.position = position
        self.colorIndex = min(max(fixedColorIndex, 0), Food.palette.count - 1)
    }
}

/// One resolved leaderboard entry: label already follows the offline rules
/// (skinless bots list as "Unnamed Cell"), and party membership is resolved
/// against the local player's party code.
struct RemoteLeaderboardEntry {
    let name: String
    let mass: Int
    let isMe: Bool
    let isParty: Bool          // a party TEAMMATE (never true for the local player)
}

final class RemoteWorldModel {

    // MARK: identity

    private(set) var myOwnerID: UInt32? = nil
    /// The local player's sanitized party code ("" = no party). Set by the view
    /// right after reset(), before the hello is sent.
    var localPartyCode: String = ""
    /// Client-side UUIDs of every remote owner in the local player's party.
    /// Feeds the teammate visuals (rings, pfp, party arrow) and the friend counter.
    private(set) var teammateUUIDs: Set<UUID> = []
    private var ownerUUIDs: [UInt32: UUID] = [:]
    private var rosterOwnerIDs: Set<UInt32> = []       // owners alive per last server roster
    private var rosterAbsence: [UInt32: Int] = [:]     // consecutive rosters an owner was missing
    private struct OwnerRender {
        let uuid: UUID
        let wire: WireOwner
        let template: PlayerCell     // carries resolved colors for cells + pellets
    }
    private var ownerRender: [UInt32: OwnerRender] = [:]

    // MARK: outputs consumed by the view every frame

    var playerCells: [PlayerCell] = []
    var botCells: [PlayerCell] = []
    var newlyEatenCells: [PlayerCell] = []          // view appends these to animatingEatenCells
    var newlyConsumedPickups: [ConsumedPickupAnimation] = []  // view appends these to consumeAnimations
    var viruses: [Virus] = []
    var tokens: [Token] = []
    let foodManager = FoodManager()
    let massManager = EjectedMassManager()
    var botLevels: [UUID: Int] = [:]
    var eatTriggeredSwap = false                    // own cell ate someone (dual-skin swap)
    /// v5 skin sync: remote HUMAN owners whose cells just ate a player/token —
    /// the view turns these into per-owner dual-skin swaps (drained per tick).
    var remoteEatSwapOwners: [UUID] = []
    var tokenPickups = 0                            // own token count
    var leaderboard: [RemoteLeaderboardEntry] = []

    /// v5.9.5: the player's AUTHORITATIVE total mass, straight from the
    /// server's leaderboard totals (sum of targetMass). The per-cell wire
    /// `mass` is the ANIMATED value — after a split the parent eases down
    /// toward its halved targetMass while the new half already exists, so
    /// summing wire masses briefly reads up to ~1.5x and the high-water
    /// score latched the phantom peak (online-only score inflation bug).
    /// Offline scores always summed targetMass; this restores parity.
    private(set) var myAuthoritativeMass: Double? = nil
    private(set) var isDead = false
    private(set) var lastError: String? = nil

    // MARK: snapshot timeline

    private var frames: [WireSnapshot] = []          // pending, sorted by serverTime
    private var frameA: WireSnapshot? = nil          // last activated
    private var frameACells: [UInt32: WireCell] = [:]
    private var clockOffset: Double? = nil           // serverTime - CACurrentMediaTime()
    // Two snapshots: low latency while retaining enough jitter buffer to keep
    // interpolation continuous. All cells share this authoritative timeline.
    // This adapts to the server-advertised rate, so older 20/30 Hz servers
    // safely fall back to a larger buffer rather than stuttering.
    private var interpDelay = ProtoConst.interpolationDelay

    // MARK: live mirrors

    private var cellMirrors: [UInt32: PlayerCell] = [:]
    private var lagMass: [UInt32: CGFloat] = [:]
    private var pelletZIndex: [UInt32: Int] = [:]    // server pellet id → massManager zIndex
    private var tokenByID: [UInt32: Token] = [:]
    private var foodPosition: [UInt32: CGPoint] = [:]
    private var wireViruses: [WireVirus] = []
    /// v46 anti-ghost census, held until the render timeline reaches its
    /// serverTime (all removal deltas up to that moment are then applied,
    /// so pruning can never race a delta that is still buffered).
    private var pendingCensus: (serverTime: Double, tokens: [WireToken],
                                foodIDs: [UInt32], ejectedIDs: [UInt32])? = nil

    // MARK: - Message intake (main thread)

    func handle(_ message: ServerMessage) {
        switch message {
        case .welcome(let ownerID, _, let snapshotHz, let serverTime):
            myOwnerID = ownerID
            isDead = false
            interpDelay = max(ProtoConst.interpolationDelay,
                              2.0 / Double(max(snapshotHz, 1)))
            clockOffset = serverTime - CACurrentMediaTime()
        case .rejected(let reason), .disconnected(let reason):
            lastError = reason
        case .ownerMeta(let owners):
            applyOwnerMeta(owners)
        case .fullState(let food, let viruses, let tokens, let ejected):
            applyFullState(food: food, wireViruses: viruses, wireTokens: tokens, ejected: ejected)
        case .snapshot(let snap):
            let sample = snap.serverTime - CACurrentMediaTime()
            if let existing = clockOffset {
                clockOffset = existing + (sample - existing) * 0.08   // slewed EMA
            } else {
                clockOffset = sample
            }
            frames.append(snap)
            // Stall safety: after a hitch/pause the buffer can flood. NEVER
            // silently drop the overflow - every snapshot carries removal
            // deltas (food/tokens/pellets), and discarding one leaves ghost
            // entities the server no longer has (drawn forever, un-eatable).
            // Fast-forward through the excess instead: activate() applies the
            // deltas, so the world stays consistent and only the smooth
            // interpolation of those frames is sacrificed.
            while frames.count > 90 { activate(frames.removeFirst()) }
        case .youDied:
            isDead = true
        case .entityCensus(let serverTime, let tokens, let foodIDs, let ejectedIDs):
            pendingCensus = (serverTime, tokens, foodIDs, ejectedIDs)
        case .pong:
            break
        }
    }

    private func applyOwnerMeta(_ owners: [WireOwner]) {
        defer { recomputeTeammates() }
        // The server's roster is authoritative and only lists owners that are
        // alive right now. Track the live set so teammate counting ignores
        // anyone who left, died, or is a previous life of a respawned player;
        // keep the render entry briefly (interpolation may still draw their
        // final frames), then drop it once absent from a few rosters.
        rosterOwnerIDs = Set(owners.map { $0.id })
        for id in Array(ownerRender.keys) {
            if rosterOwnerIDs.contains(id) {
                rosterAbsence[id] = nil
            } else {
                let misses = (rosterAbsence[id] ?? 0) + 1
                rosterAbsence[id] = misses
                if misses >= 3 {
                    ownerRender.removeValue(forKey: id)
                    rosterAbsence[id] = nil
                }
            }
        }
        for wire in owners {
            if let existing = ownerRender[wire.id],
               existing.wire.name == wire.name && existing.wire.skinName == wire.skinName
                && existing.wire.party == wire.party && existing.wire.level == wire.level {
                continue
            }
            let uuid = ownerUUIDs[wire.id] ?? UUID()
            ownerUUIDs[wire.id] = uuid
            let isHuman = wire.kind == 0
            let palette = isHuman ? onlinePlayerColors : onlineBotColors
            let color = palette[Int(wire.colorIndex) % palette.count]
            let template = PlayerCell(
                ownerID: uuid, position: .zero, mass: 100, targetMass: 100,
                color: color, name: wire.name,
                skinName: wire.skinName.isEmpty ? nil : wire.skinName,
                isBot: wire.id != myOwnerID, isFeedBot: wire.kind == 2
            )
            ownerRender[wire.id] = OwnerRender(uuid: uuid, wire: wire, template: template)
            if wire.level >= 0 { botLevels[uuid] = Int(wire.level) }
            // meta arrived after cells: rebuild placeholder mirrors with real identity
            for (cellID, mirror) in cellMirrors where mirror.ownerID == uuid && mirror.name != wire.name {
                cellMirrors[cellID] = nil
            }
        }
    }

    private func recomputeTeammates() {
        guard !localPartyCode.isEmpty else {
            if !teammateUUIDs.isEmpty { teammateUUIDs = [] }
            return
        }
        var next: Set<UUID> = []
        for (id, render) in ownerRender
        where id != myOwnerID && rosterOwnerIDs.contains(id)
            && render.wire.party == localPartyCode {
            // v5: party code alone decides membership - humans are kind 0 and
            // party teammate bots are kind 3 (rlBot) on the wire, and only
            // party members ever carry a non-empty party code.
            next.insert(render.uuid)
        }
        if next != teammateUUIDs { teammateUUIDs = next }
    }

    private func applyFullState(food: [WireFood], wireViruses vs: [WireVirus],
                                wireTokens ts: [WireToken], ejected: [WireEjected]) {
        foodManager.removeAll()
        foodPosition.removeAll()
        for f in food {
            let p = CGPoint(x: CGFloat(f.x), y: CGFloat(f.y))
            foodManager.add(Food(position: p, fixedColorIndex: Int(f.colorIndex)))
            foodPosition[f.id] = p
        }
        wireViruses = vs
        rebuildViruses()
        tokenByID.removeAll()
        for t in ts { tokenByID[t.id] = Token(position: CGPoint(x: CGFloat(t.x), y: CGFloat(t.y))) }
        tokens = Array(tokenByID.values)
        massManager.clearAll()
        pelletZIndex.removeAll()
        for e in ejected { addPellet(e) }
        pendingCensus = nil   // v46: a census older than this full state must not prune it
        frames.removeAll()
        frameA = nil
        frameACells.removeAll()
        cellMirrors.removeAll()
        lagMass.removeAll()
    }

    private func rebuildViruses() {
        viruses = wireViruses.map { wv in
            var v = Virus(position: CGPoint(x: CGFloat(wv.x), y: CGFloat(wv.y)))
            v.mass = CGFloat(wv.mass)
            v.targetMass = CGFloat(wv.mass)
            v.velocity = CGSize(width: CGFloat(wv.vx), height: CGFloat(wv.vy))
            return v
        }
    }

    private func addPellet(_ e: WireEjected, spawnOffset: CGSize = .zero) {
        guard let render = ownerRender[e.ownerID] else { return }
        let t = render.template
        massManager.add(position: CGPoint(x: CGFloat(e.x), y: CGFloat(e.y)),
                        direction: CGSize(width: CGFloat(e.dirX), height: CGFloat(e.dirY)),
                        initialSpeed: CGFloat(e.speed),
                        color: t.color,
                        ownerID: t.ownerID,
                        borderColor: t.color.darker(ratio: 0.9),
                        spawnOffset: spawnOffset,
                        now: CACurrentMediaTime())
        if let z = massManager.activeMasses.last?.zIndex {
            pelletZIndex[e.id] = z
        }
    }
    
    /// Snapshot pellets get the same "one default spot" eject visual the offline game
    /// applies, for EVERY owner on screen (you, other players, bots). The server sends
    /// each pellet already spread-rotated. Each pellet is first matched to the cell
    /// that fired it, then the shooter's raw aim is approximated by the mean direction
    /// of THAT CELL's pellets in this snapshot, so a burst is drawn leaving a single
    /// rim point and kicking out instantly onto its rotated trajectory. The mean must
    /// be per cell, not per owner: after a split, a center feed has several cells
    /// ejecting in different (even opposite) directions in the same snapshot, and an
    /// owner-wide mean anchored every burst at a bogus averaged spot - drawing a
    /// doubled/ghosted macro stream. Physics (position/direction/speed) stay exactly
    /// as the server sent them - the offset is the same draw-only decaying
    /// spawnOffset used offline.
    private func activatePellets(_ added: [WireEjected]) {
        guard !added.isEmpty else { return }
        struct Anchor {
            var cellID: UUID
            var center: CGPoint
            var radius: CGFloat
            var dist: CGFloat
        }
        // Pass 1: match every pellet to the cell that fired it. The wire doesn't say
        // which cell fired, so pick the owner's nearest cell that sits BEHIND the
        // pellet along its flight direction. A fresh pellet is on the shooter's rim
        // (dot > 0 there), while a cell it is flying toward / landing on is ahead
        // (dot < 0). Plain nearest-cell picked that target cell during multi-cell
        // fast feeds and anchored the burst visual to the wrong cell, punching a
        // temporary hole in the pile until the offset decayed.
        var anchors: [Anchor?] = []
        anchors.reserveCapacity(added.count)
        var cellDirectionSums: [UUID: CGSize] = [:]
        for e in added {
            guard let render = ownerRender[e.ownerID] else { anchors.append(nil); continue }
            let pellet = CGPoint(x: CGFloat(e.x), y: CGFloat(e.y))
            let dir = CGSize(width: CGFloat(e.dirX), height: CGFloat(e.dirY))
            var bestID: UUID? = nil
            var bestCenter = CGPoint.zero
            var bestDist = CGFloat.greatestFiniteMagnitude
            var bestRadius: CGFloat = 0
            var bestIsBehind = false
            func consider(_ cell: PlayerCell) {
                let center = cell.position
                let toPellet = CGSize(width: pellet.x - center.x, height: pellet.y - center.y)
                let isBehind = (toPellet.width * dir.width + toPellet.height * dir.height) > 0
                let d = hypot(toPellet.width, toPellet.height)
                // A behind-cell always beats an ahead-cell; distance breaks ties.
                if (isBehind && !bestIsBehind) || (isBehind == bestIsBehind && d < bestDist) {
                    bestID = cell.id; bestCenter = center; bestRadius = cell.cachedVisualRadius
                    bestDist = d; bestIsBehind = isBehind
                }
            }
            for c in playerCells where c.ownerID == render.uuid { consider(c) }
            for c in botCells where c.ownerID == render.uuid { consider(c) }
            // Only anchor when the pellet clearly left this cell's rim; a stale or
            // teleported mirror must not visually fling pellets across the screen.
            if let id = bestID, bestIsBehind, bestDist > 0.001,
               bestDist <= bestRadius * 2 + 60 {
                anchors.append(Anchor(cellID: id, center: bestCenter,
                                      radius: bestRadius, dist: bestDist))
                var sum = cellDirectionSums[id] ?? .zero
                sum.width += CGFloat(e.dirX)
                sum.height += CGFloat(e.dirY)
                cellDirectionSums[id] = sum
            } else {
                anchors.append(nil)
            }
        }
        // Pass 2: per-cell mean aim -> per-pellet draw-only spawn offset.
        for (i, e) in added.enumerated() {
            var offset = CGSize.zero
            if let anchor = anchors[i], let sum = cellDirectionSums[anchor.cellID] {
                let sumLength = hypot(sum.width, sum.height)
                if sumLength > 0.001 {
                    let meanDir = CGSize(width: sum.width / sumLength, height: sum.height / sumLength)
                    let defaultSpot = CGPoint(x: anchor.center.x + meanDir.width * anchor.dist,
                                              y: anchor.center.y + meanDir.height * anchor.dist)
                    offset = CGSize(width: defaultSpot.x - CGFloat(e.x),
                                    height: defaultSpot.y - CGFloat(e.y))
                }
            }
            addPellet(e, spawnOffset: offset)
        }
    }

    private func removePellets(ids: [UInt32], in snap: WireSnapshot?) {
        guard !ids.isEmpty else { return }
        var targets = Set<Int>()
        for id in ids {
            if let z = pelletZIndex.removeValue(forKey: id) { targets.insert(z) }
        }
        guard !targets.isEmpty else { return }
        var i = massManager.activeMasses.count - 1
        while i >= 0 && !targets.isEmpty {
            if targets.remove(massManager.activeMasses[i].zIndex) != nil {
                noteConsumedPellet(massManager.activeMasses[i], in: snap)
                massManager.activeMasses.remove(at: i)
            }
            i -= 1
        }
        guard !targets.isEmpty else { return }
        for (key, bucket) in massManager.staticGrid {
            var b = bucket
            var changed = false
            var j = b.count - 1
            while j >= 0 && !targets.isEmpty {
                if targets.remove(b[j].zIndex) != nil {
                    noteConsumedPellet(b[j], in: snap)
                    b.remove(at: j)
                    changed = true
                }
                j -= 1
            }
            if changed {
                if b.isEmpty { massManager.staticGrid.removeValue(forKey: key) }
                else { massManager.staticGrid[key] = b }
            }
            if targets.isEmpty { break }
        }
    }

    // MARK: - Frame activation (event replay on the render timeline)

    private func activate(_ snap: WireSnapshot) {
        // food deltas
        if !snap.foodRemoved.isEmpty {
            for id in snap.foodRemoved {
                guard let p = foodPosition.removeValue(forKey: id) else { continue }
                if let eatenFood = removeFood(at: p),
                   let eater = coveringCellID(for: eatenFood.position, in: snap) {
                    newlyConsumedPickups.append(ConsumedPickupAnimation(
                        kind: .food(colorIndex: eatenFood.colorIndex),
                        position: eatenFood.position,
                        eaterCellID: eater))
                }
            }
        }
        for f in snap.foodAdded {
            let p = CGPoint(x: CGFloat(f.x), y: CGFloat(f.y))
            foodManager.add(Food(position: p, fixedColorIndex: Int(f.colorIndex)))
            foodPosition[f.id] = p
        }
        // ejected deltas
        activatePellets(snap.ejectedAdded)
        removePellets(ids: snap.ejectedRemoved, in: snap)
        // tokens
        if !snap.tokensRemoved.isEmpty {
            for id in snap.tokensRemoved {
                guard let token = tokenByID.removeValue(forKey: id) else { continue }
                if ownCellCovers(point: token.position) { tokenPickups += 1; eatTriggeredSwap = true }
                else if let eaterOwner = coveringOwnerID(for: token.position, in: snap),
                        let render = ownerRender[eaterOwner], render.wire.kind == 0 {
                    // v5 skin sync: remote player picked up a token
                    remoteEatSwapOwners.append(render.uuid)
                }
                if let eater = coveringCellID(for: token.position, in: snap) {
                    newlyConsumedPickups.append(ConsumedPickupAnimation(
                        kind: .token,
                        position: token.position,
                        eaterCellID: eater))
                }
            }
            tokens = Array(tokenByID.values)
        }
        if !snap.tokensAdded.isEmpty {
            for t in snap.tokensAdded {
                tokenByID[t.id] = Token(position: CGPoint(x: CGFloat(t.x), y: CGFloat(t.y)))
            }
            tokens = Array(tokenByID.values)
        }
        // viruses
        if snap.virusesChanged {
            wireViruses = snap.viruses
            rebuildViruses()
        }
        // eaten cells → glide animation, exactly like the offline pipeline
        for (victimID, eaterCellID) in snap.eatenCells {
            if let mirror = cellMirrors[victimID] {
                var dying = mirror
                dying.eaterID = cellMirrors[eaterCellID]?.id
                newlyEatenCells.append(dying)
                if let eaterOwner = ownerForCell(eaterCellID, in: snap) {
                    if let me = myOwnerID, eaterOwner == me {
                        eatTriggeredSwap = true
                    } else if let render = ownerRender[eaterOwner], render.wire.kind == 0 {
                        // v5 skin sync: a remote player's eat-triggered swap
                        remoteEatSwapOwners.append(render.uuid)
                    }
                }
            }
            cellMirrors.removeValue(forKey: victimID)
            lagMass.removeValue(forKey: victimID)
        }
        // leaderboard - offline label parity: skinless bots list as "Unnamed Cell"
        leaderboard = snap.leaderboard.map { entry in
            let wire = ownerRender[entry.ownerID]?.wire
            let isBot = (wire?.kind ?? 1) != 0
            let rawName = wire?.name ?? ""
            let label: String
            if isBot {
                label = (wire?.skinName ?? "").isEmpty ? "Unnamed Cell" : rawName
            } else {
                label = rawName.isEmpty ? "Unnamed Cell" : rawName
            }
            let isParty = !localPartyCode.isEmpty
                && entry.ownerID != myOwnerID
                && wire?.party == localPartyCode   // humans AND party teammate bots (kind 3)
            return RemoteLeaderboardEntry(name: label, mass: Int(entry.mass),
                                          isMe: entry.ownerID == myOwnerID, isParty: isParty)
        }
        // v5.9.5: capture our authoritative total for the score HUD.
        if let me = myOwnerID {
            myAuthoritativeMass = snap.leaderboard
                .first(where: { $0.ownerID == me })
                .map { Double($0.mass) }
        }

        frameA = snap
        frameACells = Dictionary(uniqueKeysWithValues: snap.cells.map { ($0.id, $0) })
    }

    private func ownerForCell(_ cellID: UInt32, in snap: WireSnapshot) -> UInt32? {
        if let c = snap.cells.first(where: { $0.id == cellID }) { return c.ownerID }
        return nil
    }

    /// Owner (wire ID) of the nearest server cell covering a point in the removal
    /// snapshot - attributes pellet/token pickups to a REMOTE owner for the v5
    /// level-3 skin sync. Unlike coveringCellID (which returns a render-mirror
    /// UUID for animations) this stays entirely in wire IDs and needs no mirror.
    private func coveringOwnerID(for point: CGPoint, in snap: WireSnapshot) -> UInt32? {
        var best: UInt32? = nil
        var bestDistSq = CGFloat.greatestFiniteMagnitude
        for wc in snap.cells {
            let r = OriginalGameplay.radius(forMass: CGFloat(max(wc.mass, 0)))
            let dx = CGFloat(wc.x) - point.x, dy = CGFloat(wc.y) - point.y
            let d = dx * dx + dy * dy
            if d < r * r && d < bestDistSq { bestDistSq = d; best = wc.ownerID }
        }
        return best
    }

    /// The server does not say WHICH cell consumed a pellet/token, so for the
    /// magnet-suck cosmetic we attribute the pickup to the nearest cell whose
    /// radius covers it (exactly the offline eat condition). Removals nobody
    /// covers (e.g. a virus swallowing pellets) simply skip the animation.
    ///
    /// Attribution first checks the removal snapshot's OWN cells (exact server
    /// positions/masses at eat time) so every owner on screen - other players and
    /// bots included - gets the animation even when their interpolated mirrors lag
    /// a burst of replayed events; the mirror check remains as a fallback.
    private func coveringCellID(for point: CGPoint, in snap: WireSnapshot?,
                                slack: CGFloat = 0) -> UUID? {
        if let snap = snap {
            var best: UUID? = nil
            var bestDistSq = CGFloat.greatestFiniteMagnitude
            for wc in snap.cells {
                let r = OriginalGameplay.radius(forMass: CGFloat(max(wc.mass, 0))) + slack
                let dx = CGFloat(wc.x) - point.x, dy = CGFloat(wc.y) - point.y
                let d = dx * dx + dy * dy
                if d < r * r && d < bestDistSq, let mirror = cellMirrors[wc.id] {
                    bestDistSq = d
                    best = mirror.id
                }
            }
            if best != nil { return best }
        }
        return coveringCellID(for: point, slack: slack)
    }
    
    private func coveringCellID(for point: CGPoint, slack: CGFloat = 0) -> UUID? {
        var best: UUID? = nil
        var bestDistSq = CGFloat.greatestFiniteMagnitude
        for c in playerCells {
            let r = c.cachedVisualRadius + slack
            let dx = c.position.x - point.x, dy = c.position.y - point.y
            let d = dx * dx + dy * dy
            if d < r * r && d < bestDistSq { bestDistSq = d; best = c.id }
        }
        for c in botCells {
            let r = c.cachedVisualRadius + slack
            let dx = c.position.x - point.x, dy = c.position.y - point.y
            let d = dx * dx + dy * dy
            if d < r * r && d < bestDistSq { bestDistSq = d; best = c.id }
        }
        return best
    }

    private func noteConsumedPellet(_ mass: EjectedMass, in snap: WireSnapshot?) {
        // v5.8.7: the server captures on touch (rim overlap), so the pellet can
        // be up to a pellet-radius outside the eater when its removal arrives —
        // attribute with matching slack so the magnet slide still plays.
        guard let eater = coveringCellID(for: mass.position, in: snap, slack: 25.3) else { return }
        newlyConsumedPickups.append(ConsumedPickupAnimation(
            kind: .ejected(styleID: mass.styleID),
            position: mass.position,
            eaterCellID: eater))
    }

    private func ownCellCovers(point: CGPoint) -> Bool {
        for c in playerCells {
            let r = c.cachedVisualRadius
            let dx = c.position.x - point.x, dy = c.position.y - point.y
            if dx * dx + dy * dy < r * r { return true }
        }
        return false
    }

    /// v46: reconcile local entity sets against the server's authoritative
    /// live-ID census. Removes ghosts (drawn-but-uneatable pellets/tokens/food
    /// left behind by any missed removal delta) and resurrects missing tokens.
    private func applyCensus(_ census: (serverTime: Double, tokens: [WireToken],
                                        foodIDs: [UInt32], ejectedIDs: [UInt32])) {
        // Tokens: prune ghosts AND heal missing ones (census carries full data).
        var liveTokens = Set<UInt32>()
        liveTokens.reserveCapacity(census.tokens.count)
        for t in census.tokens { liveTokens.insert(t.id) }
        var tokensChanged = false
        for id in Array(tokenByID.keys) where !liveTokens.contains(id) {
            tokenByID.removeValue(forKey: id)
            tokensChanged = true
        }
        for t in census.tokens where tokenByID[t.id] == nil {
            tokenByID[t.id] = Token(position: CGPoint(x: CGFloat(t.x), y: CGFloat(t.y)))
            tokensChanged = true
        }
        if tokensChanged { tokens = Array(tokenByID.values) }

        // Food: prune dots the server no longer has (no animation — they are
        // ghosts, nobody ate them on this timeline).
        let liveFood = Set(census.foodIDs)
        for (id, p) in Array(foodPosition) where !liveFood.contains(id) {
            foodPosition.removeValue(forKey: id)
            _ = removeFood(at: p)
        }

        // Ejected pellets: prune ghosts via the normal removal path.
        let liveEjected = Set(census.ejectedIDs)
        var ghostPellets: [UInt32] = []
        for id in pelletZIndex.keys where !liveEjected.contains(id) {
            ghostPellets.append(id)
        }
        if !ghostPellets.isEmpty { removePellets(ids: ghostPellets, in: nil) }
    }

    @discardableResult
    private func removeFood(at position: CGPoint) -> Food? {
        let key = GridKey(x: Int(position.x / foodManager.gridSize),
                          y: Int(position.y / foodManager.gridSize))
        guard var bucket = foodManager.grid[key] else { return nil }
        var bestIdx = -1
        var bestDistSq: CGFloat = 4.0     // pellets are exact; tolerate float32 rounding
        for (i, f) in bucket.enumerated() {
            let dx = f.position.x - position.x, dy = f.position.y - position.y
            let d = dx * dx + dy * dy
            if d < bestDistSq { bestDistSq = d; bestIdx = i }
        }
        guard bestIdx >= 0 else { return nil }
        let removed = bucket.remove(at: bestIdx)
        if bucket.isEmpty { foodManager.grid.removeValue(forKey: key) }
        else { foodManager.grid[key] = bucket }
        return removed
    }

    // MARK: - Per-display-frame advance

    /// Call once per display tick. Interpolates cells, replays due events and
    /// steps the local pellet/virus cosmetic simulations.
    func advance(dt: CGFloat) {
        guard let offset = clockOffset else { return }
        let renderTime = CACurrentMediaTime() + offset - interpDelay

        // activate every frame the render timeline has crossed
        while let next = frames.first, next.serverTime <= renderTime {
            frames.removeFirst()
            activate(next)
        }

        // v46 anti-ghost census: once the render timeline has crossed the
        // census moment, every delta up to it has been replayed — anything
        // we still hold that the server does not list is a ghost. Prune it.
        if let census = pendingCensus, census.serverTime <= renderTime {
            pendingCensus = nil
            applyCensus(census)
        }

        guard let a = frameA else { return }
        let b = frames.first
        var t: CGFloat = 1
        if let b = b, b.serverTime > a.serverTime {
            t = CGFloat((renderTime - a.serverTime) / (b.serverTime - a.serverTime))
            t = min(max(t, 0), 1)
        }

        // interpolate cells of frame A toward frame B
        var bCells: [UInt32: WireCell] = [:]
        if let b = b { bCells = Dictionary(uniqueKeysWithValues: b.cells.map { ($0.id, $0) }) }

        var mine: [PlayerCell] = []
        var others: [PlayerCell] = []
        let lagFactor = 1.0 - pow(1.0 - 0.15, dt * 60.0)

        for wireCell in a.cells {
            let target = bCells[wireCell.id]
            let x = target.map { CGFloat($0.x) * t + CGFloat(wireCell.x) * (1 - t) } ?? CGFloat(wireCell.x)
            let y = target.map { CGFloat($0.y) * t + CGFloat(wireCell.y) * (1 - t) } ?? CGFloat(wireCell.y)
            let mass = target.map { CGFloat($0.mass) * t + CGFloat(wireCell.mass) * (1 - t) } ?? CGFloat(wireCell.mass)

            var mirror: PlayerCell
            if let existing = cellMirrors[wireCell.id] {
                mirror = existing
            } else {
                mirror = makeMirror(for: wireCell)
                // fresh cells render at their wire state immediately — only
                // CHANGES animate (v5.8.1 font ease below)
                mirror.massFontScale = (wireCell.flags & 1 != 0) ? 0.5 : 1.0
            }
            mirror.position = CGPoint(x: x, y: y)
            mirror.mass = max(mass, 0.01)
            mirror.targetMass = mirror.mass
            mirror.massFontHalved = wireCell.flags & 1 != 0
            // v5.8.5: ratio fixed by lineage (server flag bit0) — no resets.
            mirror.massFontScale = mirror.massFontHalved ? 0.5 : 1.0
            mirror.isMerging = wireCell.flags & 2 != 0
            var lag = lagMass[wireCell.id] ?? mirror.mass
            lag += (mirror.mass - lag) * lagFactor
            lagMass[wireCell.id] = lag
            mirror.lagMass = lag
            mirror.refreshCachedRadii()
            cellMirrors[wireCell.id] = mirror

            if let me = myOwnerID, wireCell.ownerID == me { mine.append(mirror) }
            else { others.append(mirror) }
        }

        // drop mirrors for cells that vanished without an eat event (merges etc.)
        if cellMirrors.count > a.cells.count {
            let live = Set(a.cells.map { $0.id })
            for key in cellMirrors.keys where !live.contains(key) {
                cellMirrors.removeValue(forKey: key)
                lagMass.removeValue(forKey: key)
            }
        }

        playerCells = mine
        botCells = others

        let ws = OriginalGameplay.arenaSideLengthCGFloat
        // pellet flight — identical physics to offline, run locally
        massManager.update(dt: dt, worldSize: ws)
        // virus flight between snapshots (launched viruses)
        for i in viruses.indices where viruses[i].velocity != .zero {
            viruses[i].position.x += viruses[i].velocity.width * dt
            viruses[i].position.y += viruses[i].velocity.height * dt
            let decay = OriginalGameplay.impulseDecay(dt: dt)
            viruses[i].velocity.width *= decay
            viruses[i].velocity.height *= decay
            if abs(viruses[i].velocity.width) < 0.2 && abs(viruses[i].velocity.height) < 0.2 {
                viruses[i].velocity = .zero
            }
            let r = viruses[i].radius
            viruses[i].position.x = max(r, min(ws - r, viruses[i].position.x))
            viruses[i].position.y = max(r, min(ws - r, viruses[i].position.y))
        }
    }

    private func makeMirror(for wireCell: WireCell) -> PlayerCell {
        let render = ownerRender[wireCell.ownerID]
        let uuid = render?.uuid ?? {
            let u = ownerUUIDs[wireCell.ownerID] ?? UUID()
            ownerUUIDs[wireCell.ownerID] = u
            return u
        }()
        let isMe = wireCell.ownerID == myOwnerID
        return PlayerCell(
            ownerID: uuid,
            position: CGPoint(x: CGFloat(wireCell.x), y: CGFloat(wireCell.y)),
            mass: CGFloat(wireCell.mass), targetMass: CGFloat(wireCell.mass),
            color: render?.template.color ?? onlineBotColors[Int(wireCell.ownerID) % onlineBotColors.count],
            name: render?.wire.name ?? "",
            skinName: (render?.wire.skinName.isEmpty ?? true) ? nil : render?.wire.skinName,
            isBot: !isMe,
            isFeedBot: render?.wire.kind == 2,
            isRemoteHuman: !isMe && render?.wire.kind == 0   // v5 skin sync
        )
    }

    /// The view runs the (visual-only) deformation pass on its per-frame cell
    /// copies; persist the deformation rings back into the mirrors so squish
    /// state survives to the next frame exactly like the offline build.
    func persistVisualState(player: [PlayerCell], bots: [PlayerCell]) {
        guard !cellMirrors.isEmpty else { return }
        var uuidToServerID: [UUID: UInt32] = [:]
        uuidToServerID.reserveCapacity(cellMirrors.count)
        for (sid, mirror) in cellMirrors { uuidToServerID[mirror.id] = sid }
        for cell in player {
            guard let sid = uuidToServerID[cell.id] else { continue }
            cellMirrors[sid]?.skinDeformation = cell.skinDeformation
            cellMirrors[sid]?.hasActiveDeformation = cell.hasActiveDeformation
        }
        for cell in bots {
            guard let sid = uuidToServerID[cell.id] else { continue }
            cellMirrors[sid]?.skinDeformation = cell.skinDeformation
            cellMirrors[sid]?.hasActiveDeformation = cell.hasActiveDeformation
        }
    }

    // MARK: - helpers for the view

    var totalPlayerMass: CGFloat {
        var total: CGFloat = 0
        for c in playerCells { total += c.targetMass }
        return total
    }

    var playerCenter: CGPoint {
        var totalMass: CGFloat = 0
        var wx: CGFloat = 0, wy: CGFloat = 0
        for c in playerCells {
            totalMass += c.mass
            wx += c.position.x * c.mass
            wy += c.position.y * c.mass
        }
        guard totalMass > 0 else { return .zero }
        return CGPoint(x: wx / totalMass, y: wy / totalMass)
    }

    func reset() {
        pendingCensus = nil
        frames.removeAll()
        frameA = nil
        frameACells.removeAll()
        cellMirrors.removeAll()
        lagMass.removeAll()
        playerCells = []
        botCells = []
        newlyEatenCells = []
        newlyConsumedPickups = []
        foodManager.removeAll()
        massManager.clearAll()
        pelletZIndex.removeAll()
        tokenByID.removeAll()
        tokens = []
        viruses = []
        wireViruses = []
        botLevels.removeAll()
        leaderboard = []
        isDead = false
        lastError = nil
        clockOffset = nil
        interpDelay = ProtoConst.interpolationDelay
        myOwnerID = nil
        tokenPickups = 0
        ownerRender.removeAll()
        ownerUUIDs.removeAll()
        rosterOwnerIDs = []
        rosterAbsence = [:]
        teammateUUIDs = []
    }
}
