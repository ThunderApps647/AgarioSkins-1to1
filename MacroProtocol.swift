//
//  MacroProtocol.swift — binary wire protocol shared by server and client.
//  ⚠️ This exact file is compiled into BOTH the macro-server package and the
//  iOS app (drop it into the Xcode project unchanged). Foundation-only.
//
//  Framing: [u32 little-endian payload length][payload]
//  Payload: [u8 message type][fields...]
//  Strings: u16 length + UTF-8 bytes. Floats: IEEE-754 little-endian.
//

import Foundation

public enum ProtoConst {
    public static let version: UInt16 = 4
    public static let defaultPort: UInt16 = 34567
    public static let discoveryPort: UInt16 = 34568
    public static let discoveryMagic = "MIO1"
    public static let snapshotHz: Double = 60
    /// Two 60 Hz snapshots: enough to interpolate without prediction.
    public static let interpolationDelay: Double = 2.0 / 60.0
}

public enum MsgType: UInt8 {
    // client → server
    case hello = 1
    case input = 2
    case split = 3
    case eject = 4
    case respawn = 5
    case ping = 6
    case leave = 7
    /// v5.8: mod-menu feed bots in ONLINE games — u8 count (0 = off),
    /// str name, str skin. The server keeps `count` personal feeders alive
    /// that hunt down THIS player and all-in split into them.
    case feedBots = 8
    // server → client
    case welcome = 32
    case rejected = 33
    case ownerMeta = 34
    case fullState = 35
    case snapshot = 36
    case youDied = 37
    case pong = 38
    case serverInfo = 39
    /// v5.6.7 anti-ghost census: the full live ID sets for tokens, food and
    /// ejected pellets (plus full token data — they are tiny and static).
    /// Sent every few seconds so a client that ever missed a removal delta
    /// (dropped frame, hitch, old bug) prunes its ghosts instead of drawing
    /// un-eatable entities forever. Old clients ignore the unknown type.
    case entityCensus = 40
}

// MARK: - Byte buffers

public struct ByteWriter {
    public private(set) var data = Data()
    public init() {}
    public mutating func u8(_ v: UInt8) { data.append(v) }
    public mutating func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    public mutating func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    public mutating func u64(_ v: UInt64) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    public mutating func i32(_ v: Int32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    public mutating func f32(_ v: Float) { withUnsafeBytes(of: v.bitPattern.littleEndian) { data.append(contentsOf: $0) } }
    public mutating func f64(_ v: Double) { withUnsafeBytes(of: v.bitPattern.littleEndian) { data.append(contentsOf: $0) } }
    public mutating func str(_ s: String) {
        let bytes = Array(s.utf8.prefix(Int(UInt16.max)))
        u16(UInt16(bytes.count))
        data.append(contentsOf: bytes)
    }
    public mutating func bool(_ v: Bool) { u8(v ? 1 : 0) }
}

public struct ByteReader {
    private let data: [UInt8]
    private var offset = 0
    public init(_ d: Data) { data = [UInt8](d) }
    public var remaining: Int { data.count - offset }

    public mutating func u8() -> UInt8 {
        defer { offset += 1 }
        return data[offset]
    }
    private mutating func read<T: FixedWidthInteger>(_ type: T.Type) -> T {
        var v: T = 0
        let size = MemoryLayout<T>.size
        for i in 0..<size { v |= T(truncatingIfNeeded: UInt64(data[offset + i]) << (8 * UInt64(i))) }
        offset += size
        return v
    }
    public mutating func u16() -> UInt16 { read(UInt16.self) }
    public mutating func u32() -> UInt32 { read(UInt32.self) }
    public mutating func u64() -> UInt64 { read(UInt64.self) }
    public mutating func i32() -> Int32 { read(Int32.self) }
    public mutating func f32() -> Float { Float(bitPattern: read(UInt32.self)) }
    public mutating func f64() -> Double { Double(bitPattern: read(UInt64.self)) }
    public mutating func str() -> String {
        let len = Int(u16())
        let slice = data[offset..<(offset + len)]
        offset += len
        return String(decoding: slice, as: UTF8.self)
    }
    public mutating func bool() -> Bool { u8() != 0 }
}

// MARK: - Shared wire models

public struct WireCell {
    public var id: UInt32
    public var ownerID: UInt32
    public var x: Float, y: Float
    public var mass: Float
    public var flags: UInt8            // bit0 massFontHalved, bit1 isMerging
    public init(id: UInt32, ownerID: UInt32, x: Float, y: Float, mass: Float, flags: UInt8) {
        self.id = id; self.ownerID = ownerID; self.x = x; self.y = y; self.mass = mass; self.flags = flags
    }
    public func encode(into w: inout ByteWriter) {
        w.u32(id); w.u32(ownerID); w.f32(x); w.f32(y); w.f32(mass); w.u8(flags)
    }
    public static func decode(_ r: inout ByteReader) -> WireCell {
        WireCell(id: r.u32(), ownerID: r.u32(), x: r.f32(), y: r.f32(), mass: r.f32(), flags: r.u8())
    }
}

public struct WireOwner {
    public var id: UInt32
    public var kind: UInt8             // 0 human, 1 classic bot, 2 feed bot, 3 rl bot
    public var name: String
    public var skinName: String        // "" = none
    public var colorIndex: UInt8
    public var level: Int32            // -1 = none
    public var party: String           // 6-char party code, "" = none (v4)
    public init(id: UInt32, kind: UInt8, name: String, skinName: String, colorIndex: UInt8, level: Int32,
                party: String = "") {
        self.id = id; self.kind = kind; self.name = name; self.skinName = skinName
        self.colorIndex = colorIndex; self.level = level; self.party = party
    }
    public func encode(into w: inout ByteWriter) {
        w.u32(id); w.u8(kind); w.str(name); w.str(skinName); w.u8(colorIndex); w.i32(level); w.str(party)
    }
    public static func decode(_ r: inout ByteReader) -> WireOwner {
        WireOwner(id: r.u32(), kind: r.u8(), name: r.str(), skinName: r.str(),
                  colorIndex: r.u8(), level: r.i32(), party: r.str())
    }
}

public struct WireFood {
    public var id: UInt32
    public var x: Float, y: Float
    public var colorIndex: UInt8
    public init(id: UInt32, x: Float, y: Float, colorIndex: UInt8) {
        self.id = id; self.x = x; self.y = y; self.colorIndex = colorIndex
    }
    public func encode(into w: inout ByteWriter) { w.u32(id); w.f32(x); w.f32(y); w.u8(colorIndex) }
    public static func decode(_ r: inout ByteReader) -> WireFood {
        WireFood(id: r.u32(), x: r.f32(), y: r.f32(), colorIndex: r.u8())
    }
}

public struct WireEjected {
    public var id: UInt32
    public var ownerID: UInt32
    public var x: Float, y: Float
    public var dirX: Float, dirY: Float
    public var speed: Float
    public init(id: UInt32, ownerID: UInt32, x: Float, y: Float, dirX: Float, dirY: Float, speed: Float) {
        self.id = id; self.ownerID = ownerID; self.x = x; self.y = y
        self.dirX = dirX; self.dirY = dirY; self.speed = speed
    }
    public func encode(into w: inout ByteWriter) {
        w.u32(id); w.u32(ownerID); w.f32(x); w.f32(y); w.f32(dirX); w.f32(dirY); w.f32(speed)
    }
    public static func decode(_ r: inout ByteReader) -> WireEjected {
        WireEjected(id: r.u32(), ownerID: r.u32(), x: r.f32(), y: r.f32(),
                    dirX: r.f32(), dirY: r.f32(), speed: r.f32())
    }
}

public struct WireVirus {
    public var id: UInt32
    public var x: Float, y: Float
    public var mass: Float
    public var vx: Float, vy: Float
    public init(id: UInt32, x: Float, y: Float, mass: Float, vx: Float, vy: Float) {
        self.id = id; self.x = x; self.y = y; self.mass = mass; self.vx = vx; self.vy = vy
    }
    public func encode(into w: inout ByteWriter) { w.u32(id); w.f32(x); w.f32(y); w.f32(mass); w.f32(vx); w.f32(vy) }
    public static func decode(_ r: inout ByteReader) -> WireVirus {
        WireVirus(id: r.u32(), x: r.f32(), y: r.f32(), mass: r.f32(), vx: r.f32(), vy: r.f32())
    }
}

public struct WireToken {
    public var id: UInt32
    public var x: Float, y: Float
    public init(id: UInt32, x: Float, y: Float) { self.id = id; self.x = x; self.y = y }
    public func encode(into w: inout ByteWriter) { w.u32(id); w.f32(x); w.f32(y) }
    public static func decode(_ r: inout ByteReader) -> WireToken {
        WireToken(id: r.u32(), x: r.f32(), y: r.f32())
    }
}

// MARK: - Snapshot container

public struct WireSnapshot {
    public var serverTime: Double
    public var tick: UInt64
    public var cells: [WireCell] = []
    public var viruses: [WireVirus] = []
    public var virusesChanged: Bool = false
    public var foodRemoved: [UInt32] = []
    public var foodAdded: [WireFood] = []
    public var ejectedAdded: [WireEjected] = []
    public var ejectedRemoved: [UInt32] = []
    public var tokensRemoved: [UInt32] = []
    public var tokensAdded: [WireToken] = []
    public var eatenCells: [(cellID: UInt32, eaterCellID: UInt32)] = []
    public var leaderboard: [(ownerID: UInt32, mass: Float)] = []

    public init(serverTime: Double, tick: UInt64) {
        self.serverTime = serverTime
        self.tick = tick
    }

    public func encode() -> Data {
        var w = ByteWriter()
        w.u8(MsgType.snapshot.rawValue)
        w.f64(serverTime)
        w.u64(tick)
        w.u16(UInt16(min(cells.count, Int(UInt16.max))))
        for c in cells { c.encode(into: &w) }
        w.bool(virusesChanged)
        if virusesChanged {
            w.u16(UInt16(viruses.count))
            for v in viruses { v.encode(into: &w) }
        }
        w.u16(UInt16(foodRemoved.count)); for id in foodRemoved { w.u32(id) }
        w.u16(UInt16(foodAdded.count)); for f in foodAdded { f.encode(into: &w) }
        w.u16(UInt16(ejectedAdded.count)); for e in ejectedAdded { e.encode(into: &w) }
        w.u16(UInt16(ejectedRemoved.count)); for id in ejectedRemoved { w.u32(id) }
        w.u16(UInt16(tokensRemoved.count)); for id in tokensRemoved { w.u32(id) }
        w.u16(UInt16(tokensAdded.count)); for t in tokensAdded { t.encode(into: &w) }
        w.u16(UInt16(eatenCells.count))
        for e in eatenCells { w.u32(e.cellID); w.u32(e.eaterCellID) }
        w.u8(UInt8(leaderboard.count))
        for l in leaderboard { w.u32(l.ownerID); w.f32(l.mass) }
        return w.data
    }

    public static func decode(_ r: inout ByteReader) -> WireSnapshot {
        var s = WireSnapshot(serverTime: r.f64(), tick: r.u64())
        let cellCount = Int(r.u16())
        s.cells.reserveCapacity(cellCount)
        for _ in 0..<cellCount { s.cells.append(WireCell.decode(&r)) }
        s.virusesChanged = r.bool()
        if s.virusesChanged {
            let vc = Int(r.u16())
            for _ in 0..<vc { s.viruses.append(WireVirus.decode(&r)) }
        }
        for _ in 0..<Int(r.u16()) { s.foodRemoved.append(r.u32()) }
        for _ in 0..<Int(r.u16()) { s.foodAdded.append(WireFood.decode(&r)) }
        for _ in 0..<Int(r.u16()) { s.ejectedAdded.append(WireEjected.decode(&r)) }
        for _ in 0..<Int(r.u16()) { s.ejectedRemoved.append(r.u32()) }
        for _ in 0..<Int(r.u16()) { s.tokensRemoved.append(r.u32()) }
        for _ in 0..<Int(r.u16()) { s.tokensAdded.append(WireToken.decode(&r)) }
        for _ in 0..<Int(r.u16()) { s.eatenCells.append((r.u32(), r.u32())) }
        for _ in 0..<Int(r.u8()) { s.leaderboard.append((r.u32(), r.f32())) }
        return s
    }
}

// MARK: - Discovery payload

public struct DiscoveryInfo: Codable {
    public var name: String
    public var port: UInt16
    public var players: Int
    public var bots: Int
    public var maxPlayers: Int
    public var version: UInt16
    public init(name: String, port: UInt16, players: Int, bots: Int, maxPlayers: Int, version: UInt16) {
        self.name = name; self.port = port; self.players = players
        self.bots = bots; self.maxPlayers = maxPlayers; self.version = version
    }
}
