//
//  NearbyHostCore.swift — the authoritative game host that runs ON THE iPAD
//  for "Host Nearby Game". A transport-agnostic port of the PC server's
//  GameServer (Networking.swift): same 60Hz simulation tick, same wire
//  protocol (MacroProtocol.swift), same join/input/split/eject/respawn/
//  feed-bot handling — but peers deliver whole payloads (no TCP framing).
//  MultipeerConnectivity glue and UI live in NearbyPlay.swift; this file is
//  pure Foundation so the logic is testable anywhere.
//

import Foundation

/// One connected player (a Multipeer peer, or the host's own loopback).
/// Mirrors the PC server's ClientConnection minus the socket.
final class NearbyConn {
    let key: String                       // peer identity (loopback = "local")
    let sendPayload: (Data) -> Void       // whole payload, no length prefix
    var ownerID: UInt32? = nil
    var name: String = ""
    var skin: String = ""
    var level: Int? = nil
    var party: String = ""
    var feedBotCount: Int = 0             // v5.8 sticky mod-menu feeders
    var feedBotName: String = "Feeder"
    var feedBotSkin: String = ""
    var closed = false

    init(key: String, sendPayload: @escaping (Data) -> Void) {
        self.key = key
        self.sendPayload = sendPayload
    }
}

/// The nearby game host. All world access happens on `queue` (same
/// single-queue discipline as the PC server's game.tick queue).
final class NearbyGameCore {
    let world: SrvWorld
    let serverName: String
    let queue = DispatchQueue(label: "nearby.tick")
    private var tickTimer: DispatchSourceTimer?
    private var connections: [String: NearbyConn] = [:]
    private var snapshotAccumulator = 0.0
    private var metaAccumulator = 0.0
    private var censusAccumulator = 0.0
    private var running = false
    /// MCSession tops out at 8 peers (host + 7 guests) — enforce the same.
    let maxPlayers = 8
    /// Nearby snapshots go out at 30Hz (vs 60 on LAN): half the radio
    /// bandwidth, and the client's interpolation delay auto-adapts because
    /// the welcome message carries this rate.
    static let snapshotHz: Double = 30

    var humanCount: Int {
        connections.values.filter { $0.ownerID != nil }.count
    }

    init(name: String, settings: SrvWorldSettings) {
        self.serverName = name
        self.world = SrvWorld(settings: settings)
    }

    // MARK: lifecycle

    func start() {
        guard !running else { return }
        running = true
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1.0 / 60.0)
        var lastTick = Date()
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let now = Date()
            let dt = min(max(now.timeIntervalSince(lastTick), 0.001), 0.1)
            lastTick = now
            self.tickWorld(dt: dt)
        }
        timer.resume()
        tickTimer = timer
    }

    func stop() {
        running = false
        tickTimer?.cancel()
        tickTimer = nil
        queue.async { self.connections.removeAll() }
    }

    /// Register a player link. `key` must be unique per peer.
    /// Returns the connection; feed every payload from that peer into
    /// `handlePayload(conn:payload:)`.
    @discardableResult
    func register(key: String, sendPayload: @escaping (Data) -> Void) -> NearbyConn {
        let conn = NearbyConn(key: key, sendPayload: sendPayload)
        queue.async { self.connections[key] = conn }
        return conn
    }

    /// Peer vanished (Multipeer .notConnected / loopback teardown) — same
    /// cleanup as the PC server's onClose.
    func unregister(key: String) {
        queue.async {
            guard let conn = self.connections.removeValue(forKey: key) else { return }
            conn.closed = true
            if let oid = conn.ownerID {
                self.world.setPersonalFeeders(for: oid, count: 0, name: "", skin: nil)
                self.world.cells.removeAll { $0.ownerID == oid }
                self.world.inputs.removeValue(forKey: oid)
                if let owner = self.world.owners[oid], owner.diedAt == nil {
                    owner.diedAt = self.world.time      // off the roster immediately
                }
                self.ownersDirty = true
            }
        }
    }

    func handlePayload(conn: NearbyConn, payload: Data) {
        queue.async { self.handleMessage(conn, payload) }
    }

    // MARK: tick

    private func tickWorld(dt: Double) {
        world.step(dt: dt)
        collectEvents(world.drainEvents())

        snapshotAccumulator += dt
        metaAccumulator += dt
        censusAccumulator += dt

        if snapshotAccumulator >= 1.0 / Self.snapshotHz {
            snapshotAccumulator = 0
            broadcastSnapshot()
        }
        if metaAccumulator >= 1.0 {
            metaAccumulator = 0
            broadcastOwnerMeta()
        }
        if censusAccumulator >= 4.0 {
            censusAccumulator = 0
            broadcastEntityCensus()
        }
    }

    // MARK: event accumulation between snapshots (same as PC server)

    private var pendingFoodRemoved: [UInt32] = []
    private var pendingFoodAdded: [WireFood] = []
    private var pendingEjectedAdded: [WireEjected] = []
    private var pendingEjectedRemoved: [UInt32] = []
    private var pendingTokensRemoved: [UInt32] = []
    private var pendingTokensAdded: [WireToken] = []
    private var pendingEaten: [(UInt32, UInt32)] = []
    private var virusesDirty = true
    private var deadOwnerIDs: [UInt32] = []
    private var ownersDirty = true

    private func collectEvents(_ events: [SrvSimEvent]) {
        for event in events {
            switch event {
            case .foodRemoved(let ids): pendingFoodRemoved.append(contentsOf: ids)
            case .foodAdded(let food):
                pendingFoodAdded.append(contentsOf: food.map {
                    WireFood(id: $0.id, x: Float($0.position.x), y: Float($0.position.y), colorIndex: $0.colorIndex)
                })
            case .ejectedAdded(let pellets):
                pendingEjectedAdded.append(contentsOf: pellets.map {
                    WireEjected(id: $0.id, ownerID: $0.ownerID,
                                x: Float($0.position.x), y: Float($0.position.y),
                                dirX: Float($0.direction.x), dirY: Float($0.direction.y),
                                speed: Float($0.currentSpeed))
                })
            case .ejectedRemoved(let ids): pendingEjectedRemoved.append(contentsOf: ids)
            case .tokensRemoved(let ids): pendingTokensRemoved.append(contentsOf: ids)
            case .tokensAdded(let tokens):
                pendingTokensAdded.append(contentsOf: tokens.map {
                    WireToken(id: $0.id, x: Float($0.position.x), y: Float($0.position.y))
                })
            case .virusesChanged: virusesDirty = true
            case .cellEaten(let cellID, let eaterCellID): pendingEaten.append((cellID, eaterCellID))
            case .ownerDied(let ownerID):
                deadOwnerIDs.append(ownerID)
                ownersDirty = true
            case .ownerJoined: ownersDirty = true
            }
        }
    }

    // MARK: broadcasts (verbatim ports of the PC server's)

    private func broadcastSnapshot() {
        var snap = WireSnapshot(serverTime: world.time, tick: world.tick)
        snap.cells = world.cells.map {
            var flags: UInt8 = 0
            if $0.massFontHalved { flags |= 1 }
            if $0.isMerging { flags |= 2 }
            return WireCell(id: $0.id, ownerID: $0.ownerID,
                            x: Float($0.position.x), y: Float($0.position.y),
                            mass: Float($0.mass), flags: flags)
        }
        snap.virusesChanged = virusesDirty
        if virusesDirty {
            snap.viruses = world.viruses.map {
                WireVirus(id: $0.id, x: Float($0.position.x), y: Float($0.position.y),
                          mass: Float($0.mass), vx: Float($0.velocity.x), vy: Float($0.velocity.y))
            }
            virusesDirty = false
        }
        snap.foodRemoved = pendingFoodRemoved; pendingFoodRemoved = []
        snap.foodAdded = pendingFoodAdded; pendingFoodAdded = []
        snap.ejectedAdded = pendingEjectedAdded; pendingEjectedAdded = []
        snap.ejectedRemoved = pendingEjectedRemoved; pendingEjectedRemoved = []
        snap.tokensRemoved = pendingTokensRemoved; pendingTokensRemoved = []
        snap.tokensAdded = pendingTokensAdded; pendingTokensAdded = []
        snap.eatenCells = pendingEaten; pendingEaten = []

        // full ranked leaderboard (v5.2 semantics), capped at 255
        var totals: [UInt32: Double] = [:]
        for c in world.cells { totals[c.ownerID, default: 0] += c.targetMass }
        let ranked = totals.sorted { $0.value > $1.value }
        snap.leaderboard = ranked.prefix(255).map { ($0.key, Float($0.value)) }

        let payload = snap.encode()
        let dead = deadOwnerIDs; deadOwnerIDs = []
        for conn in connections.values where conn.ownerID != nil {
            conn.sendPayload(payload)
            if let oid = conn.ownerID, dead.contains(oid) {
                var w = ByteWriter()
                w.u8(MsgType.youDied.rawValue)
                conn.sendPayload(w.data)
                world.setPersonalFeeders(for: oid, count: 0, name: "", skin: nil)
                conn.ownerID = nil
            }
        }
        if ownersDirty { broadcastOwnerMeta(); ownersDirty = false }
        connections = connections.filter { !$0.value.closed }
    }

    private func ownerMetaPayload() -> Data {
        var w = ByteWriter()
        w.u8(MsgType.ownerMeta.rawValue)
        let owners = world.owners.values.filter { $0.diedAt == nil }
        w.u16(UInt16(owners.count))
        for o in owners {
            let kind: UInt8
            switch o.kind {
            case .human: kind = 0
            case .classicBot: kind = 1
            case .feedBot: kind = 2
            case .rlBot: kind = 3
            }
            WireOwner(id: o.id, kind: kind, name: o.name, skinName: o.skinName ?? "",
                      colorIndex: UInt8(o.colorIndex), level: Int32(o.level ?? -1),
                      party: o.party)
                .encode(into: &w)
        }
        return w.data
    }

    private func broadcastOwnerMeta() {
        let payload = ownerMetaPayload()
        for conn in connections.values where conn.ownerID != nil { conn.sendPayload(payload) }
    }

    private func fullStatePayload() -> Data {
        var w = ByteWriter()
        w.u8(MsgType.fullState.rawValue)
        var foods: [WireFood] = []
        for bucket in world.foodGrid.grid.values {
            for f in bucket {
                foods.append(WireFood(id: f.id, x: Float(f.position.x), y: Float(f.position.y), colorIndex: f.colorIndex))
            }
        }
        w.u32(UInt32(foods.count))
        for f in foods { f.encode(into: &w) }
        w.u16(UInt16(world.viruses.count))
        for v in world.viruses {
            WireVirus(id: v.id, x: Float(v.position.x), y: Float(v.position.y),
                      mass: Float(v.mass), vx: Float(v.velocity.x), vy: Float(v.velocity.y)).encode(into: &w)
        }
        w.u16(UInt16(world.tokens.count))
        for t in world.tokens {
            WireToken(id: t.id, x: Float(t.position.x), y: Float(t.position.y)).encode(into: &w)
        }
        var pellets: [WireEjected] = []
        for m in world.activeEjected {
            pellets.append(WireEjected(id: m.id, ownerID: m.ownerID, x: Float(m.position.x), y: Float(m.position.y),
                                       dirX: Float(m.direction.x), dirY: Float(m.direction.y), speed: Float(m.currentSpeed)))
        }
        for bucket in world.staticEjectedGrid.values {
            for m in bucket {
                pellets.append(WireEjected(id: m.id, ownerID: m.ownerID, x: Float(m.position.x), y: Float(m.position.y),
                                           dirX: 0, dirY: 0, speed: 0))
            }
        }
        w.u32(UInt32(pellets.count))
        for p in pellets { p.encode(into: &w) }
        return w.data
    }

    /// v5.6.7 anti-ghost census — authoritative live-ID sets so a client that
    /// missed a removal delta self-heals. Sent to everyone, including dead
    /// players on the respawn screen.
    private func broadcastEntityCensus() {
        var w = ByteWriter()
        w.u8(MsgType.entityCensus.rawValue)
        w.f64(world.time)
        w.u16(UInt16(min(world.tokens.count, 65535)))
        for t in world.tokens {
            WireToken(id: t.id, x: Float(t.position.x), y: Float(t.position.y)).encode(into: &w)
        }
        var foodIDs: [UInt32] = []
        for bucket in world.foodGrid.grid.values {
            for f in bucket { foodIDs.append(f.id) }
        }
        w.u32(UInt32(foodIDs.count))
        for id in foodIDs { w.u32(id) }
        var ejectedIDs: [UInt32] = []
        for m in world.activeEjected { ejectedIDs.append(m.id) }
        for bucket in world.staticEjectedGrid.values {
            for m in bucket { ejectedIDs.append(m.id) }
        }
        w.u32(UInt32(ejectedIDs.count))
        for id in ejectedIDs { w.u32(id) }
        let payload = w.data
        for conn in connections.values { conn.sendPayload(payload) }
    }

    // MARK: message handling (verbatim port of the PC server's)

    static func sanitizedPartyCode(_ raw: String) -> String {
        let cleaned = raw.uppercased().unicodeScalars.filter {
            ("A"..."Z").contains(Character($0)) || ("0"..."9").contains(Character($0))
        }
        let code = String(String.UnicodeScalarView(cleaned))
        return code.count == 6 ? code : ""
    }

    private func welcomePayload(ownerID: UInt32) -> Data {
        var w = ByteWriter()
        w.u8(MsgType.welcome.rawValue)
        w.u32(ownerID)
        w.f32(Float(SrvRules.worldSize))
        w.u8(UInt8(Self.snapshotHz))
        w.f64(world.time)
        return w.data
    }

    private func handleMessage(_ conn: NearbyConn, _ payload: Data) {
        guard !payload.isEmpty else { return }
        var r = ByteReader(payload)
        guard let type = MsgType(rawValue: r.u8()) else { return }

        switch type {
        case .hello:
            let version = r.u16()
            let name = String(r.str().prefix(24))
            let skin = r.str()
            let level: Int? = {
                guard r.remaining >= 4 else { return nil }
                let raw = Int(r.i32())
                return (1...150).contains(raw) ? raw : nil
            }()
            let party: String = {
                guard r.remaining >= 2 else { return "" }
                return Self.sanitizedPartyCode(r.str())
            }()
            guard version == ProtoConst.version else {
                var w = ByteWriter()
                w.u8(MsgType.rejected.rawValue)
                w.str("Version mismatch: host v\(ProtoConst.version), you v\(version). Update the app on both iPads.")
                conn.sendPayload(w.data)
                return
            }
            guard humanCount < maxPlayers else {
                var w = ByteWriter()
                w.u8(MsgType.rejected.rawValue)
                w.str("Game is full (\(maxPlayers) players).")
                conn.sendPayload(w.data)
                return
            }
            conn.name = name
            conn.skin = skin
            conn.level = level
            conn.party = party
            let owner = world.spawnHuman(name: name, skinName: skin.isEmpty ? nil : skin, level: level,
                                         party: party)
            conn.ownerID = owner.id
            conn.sendPayload(welcomePayload(ownerID: owner.id))
            conn.sendPayload(ownerMetaPayload())
            conn.sendPayload(fullStatePayload())
            if conn.feedBotCount > 0 {   // v5.8 sticky feeder squad
                world.setPersonalFeeders(for: owner.id, count: conn.feedBotCount,
                                         name: conn.feedBotName,
                                         skin: conn.feedBotSkin.isEmpty ? nil : conn.feedBotSkin)
            }

        case .input:
            guard let oid = conn.ownerID else { return }
            let flags = r.u8()
            var input = world.inputs[oid] ?? SrvPlayerInput()
            let wasDragging = input.joystickDragging
            input.joystickDragging = flags & 1 != 0
            input.centerAim = flags & 2 != 0
            input.joystick = SrvVec2(x: Double(r.f32()), y: Double(r.f32()))
            input.lastDirection = SrvVec2(x: Double(r.f32()), y: Double(r.f32()))
            if input.joystickDragging {
                input.anchor = nil
            } else if wasDragging {
                input.anchor = world.ownerCentre(oid)      // release → anchor at flock centre
            }
            world.inputs[oid] = input

        case .split:
            guard let oid = conn.ownerID else { return }
            world.requestSplit(ownerID: oid)

        case .eject:
            guard let oid = conn.ownerID else { return }
            let times = Int(r.u16())
            world.requestEject(ownerID: oid, times: times)

        case .respawn:
            guard conn.ownerID == nil else { return }
            let owner = world.spawnHuman(name: conn.name, skinName: conn.skin.isEmpty ? nil : conn.skin,
                                         level: conn.level, party: conn.party)
            conn.ownerID = owner.id
            conn.sendPayload(welcomePayload(ownerID: owner.id))
            conn.sendPayload(ownerMetaPayload())
            conn.sendPayload(fullStatePayload())
            if conn.feedBotCount > 0 {   // v5.8 sticky feeder squad
                world.setPersonalFeeders(for: owner.id, count: conn.feedBotCount,
                                         name: conn.feedBotName,
                                         skin: conn.feedBotSkin.isEmpty ? nil : conn.feedBotSkin)
            }

        case .ping:
            let clientTime = r.f64()
            var w = ByteWriter()
            w.u8(MsgType.pong.rawValue)
            w.f64(clientTime)
            w.f64(world.time)
            conn.sendPayload(w.data)

        case .leave:
            if let oid = conn.ownerID {
                world.setPersonalFeeders(for: oid, count: 0, name: "", skin: nil)
                world.cells.removeAll { $0.ownerID == oid }
                world.inputs.removeValue(forKey: oid)
                conn.ownerID = nil
            }

        case .feedBots:
            // v5.8 mod-menu feed bots — identical to the PC server.
            let count = Int(r.u8())
            let fname = String(r.str().prefix(24))
            let fskin = r.str()
            conn.feedBotCount = max(0, min(25, count))
            conn.feedBotName = fname.isEmpty ? "Feeder" : fname
            conn.feedBotSkin = fskin
            if let oid = conn.ownerID {
                world.setPersonalFeeders(for: oid, count: conn.feedBotCount,
                                         name: conn.feedBotName,
                                         skin: conn.feedBotSkin.isEmpty ? nil : conn.feedBotSkin)
            }

        default:
            break
        }
    }
}
