//
//  OnlineNetClient.swift — TCP game client + LAN server discovery.
//  Add this file to the Xcode project together with MacroProtocol.swift.
//
//  NetClient: length-framed TCP over Network.framework, decoding server
//  messages on a background queue and delivering them on the main thread.
//  LANDiscovery: finds hosted macro-server games automatically by probing
//  the local /24 subnet with tiny UDP datagrams (no special entitlements;
//  iOS shows the standard Local Network permission prompt once).
//

import Foundation
import Network
import QuartzCore

// MARK: - Server messages delivered to the game

enum ServerMessage {
    case welcome(ownerID: UInt32, worldSize: Float, snapshotHz: UInt8, serverTime: Double)
    case rejected(reason: String)
    case ownerMeta([WireOwner])
    case fullState(food: [WireFood], viruses: [WireVirus], tokens: [WireToken], ejected: [WireEjected])
    case snapshot(WireSnapshot)
    case youDied
    case pong(clientTime: Double, serverTime: Double)
    /// v46 anti-ghost census: authoritative live-ID sets. Applied on the
    /// render timeline so it never races buffered removal deltas.
    case entityCensus(serverTime: Double, tokens: [WireToken],
                      foodIDs: [UInt32], ejectedIDs: [UInt32])
    case disconnected(reason: String)
}

// MARK: - Pluggable transport (v7 nearby play)
//
// NetClient's native transport is length-framed TCP. A MacroTransport swaps
// the byte pipe underneath it — nearby (MultipeerConnectivity) games reuse
// the ENTIRE online pipeline (decode → RemoteWorldModel → interpolation)
// by delivering whole payloads (no length framing) through this protocol.

protocol MacroTransport: AnyObject {
    /// Server→client payload (one whole message, no length prefix).
    var onPayload: ((Data) -> Void)? { get set }
    /// Fired once the link is ready for the hello.
    var onReady: (() -> Void)? { get set }
    /// Fired when the link dies (NOT on intentional close()).
    var onClosed: ((String) -> Void)? { get set }
    func open()
    func sendPayload(_ payload: Data)
    func close()
}

// MARK: - NetClient

final class NetClient {
    private var connection: NWConnection?
    private var transport: MacroTransport?
    private let queue = DispatchQueue(label: "macro.net")
    private var inbox = Data()
    var onMessage: ((ServerMessage) -> Void)?
    /// Fires (on the main thread) when the TCP connection reaches .ready. The hello
    /// is sent from here instead of a fixed delay after connect(): on a slow network
    /// - or while iOS shows the Local Network permission prompt - the old 0.3s timer
    /// fired before the socket existed and the identity (name/skin/level) never
    /// reached the server.
    var onReady: (() -> Void)?

    private(set) var isConnected = false

    func connect(host: String, port: UInt16) {
        disconnect()
        let conn = NWConnection(host: NWEndpoint.Host(host),
                                port: NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(rawValue: ProtoConst.defaultPort)!,
                                using: .tcp)
        connection = conn
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isConnected = true
                self?.receiveLoop()
                DispatchQueue.main.async { self?.onReady?() }
            case .failed(let error):
                self?.deliver(.disconnected(reason: error.localizedDescription))
                self?.isConnected = false
            case .cancelled:
                self?.isConnected = false
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    /// v7 nearby play: same client, different pipe. Payloads arrive whole
    /// (no TCP framing), everything downstream is byte-identical.
    func connect(transport: MacroTransport) {
        disconnect()
        self.transport = transport
        transport.onPayload = { [weak self] payload in self?.decode(payload) }
        transport.onReady = { [weak self] in
            self?.isConnected = true
            DispatchQueue.main.async { self?.onReady?() }
        }
        transport.onClosed = { [weak self] reason in
            self?.isConnected = false
            self?.deliver(.disconnected(reason: reason))
        }
        transport.open()
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        transport?.close()
        transport = nil
        inbox.removeAll()
        isConnected = false
    }

    private func deliver(_ message: ServerMessage) {
        DispatchQueue.main.async { [onMessage] in onMessage?(message) }
    }

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.inbox.append(data)
                self.drainInbox()
            }
            if isComplete || error != nil {
                self.deliver(.disconnected(reason: error?.localizedDescription ?? "server closed the connection"))
                return
            }
            self.receiveLoop()
        }
    }

    private func drainInbox() {
        while inbox.count >= 4 {
            let len = inbox.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
            guard len <= 8_000_000 else {
                deliver(.disconnected(reason: "protocol error"))
                disconnect()
                return
            }
            guard inbox.count >= 4 + Int(len) else { return }
            let payload = inbox.subdata(in: 4..<(4 + Int(len)))
            inbox.removeSubrange(0..<(4 + Int(len)))
            decode(payload)
        }
    }

    private func decode(_ payload: Data) {
        guard !payload.isEmpty else { return }
        var r = ByteReader(payload)
        guard let type = MsgType(rawValue: r.u8()) else { return }
        switch type {
        case .welcome:
            deliver(.welcome(ownerID: r.u32(), worldSize: r.f32(), snapshotHz: r.u8(), serverTime: r.f64()))
        case .rejected:
            deliver(.rejected(reason: r.str()))
        case .ownerMeta:
            var owners: [WireOwner] = []
            for _ in 0..<Int(r.u16()) { owners.append(WireOwner.decode(&r)) }
            deliver(.ownerMeta(owners))
        case .fullState:
            var food: [WireFood] = []
            let foodCount = Int(r.u32())
            food.reserveCapacity(foodCount)
            for _ in 0..<foodCount { food.append(WireFood.decode(&r)) }
            var viruses: [WireVirus] = []
            for _ in 0..<Int(r.u16()) { viruses.append(WireVirus.decode(&r)) }
            var tokens: [WireToken] = []
            for _ in 0..<Int(r.u16()) { tokens.append(WireToken.decode(&r)) }
            var ejected: [WireEjected] = []
            let ejCount = Int(r.u32())
            for _ in 0..<ejCount { ejected.append(WireEjected.decode(&r)) }
            deliver(.fullState(food: food, viruses: viruses, tokens: tokens, ejected: ejected))
        case .snapshot:
            deliver(.snapshot(WireSnapshot.decode(&r)))
        case .youDied:
            deliver(.youDied)
        case .pong:
            deliver(.pong(clientTime: r.f64(), serverTime: r.f64()))
        case .entityCensus:
            let serverTime = r.f64()
            var tokens: [WireToken] = []
            for _ in 0..<Int(r.u16()) { tokens.append(WireToken.decode(&r)) }
            var foodIDs: [UInt32] = []
            let foodCount = Int(r.u32())
            foodIDs.reserveCapacity(foodCount)
            for _ in 0..<foodCount { foodIDs.append(r.u32()) }
            var ejectedIDs: [UInt32] = []
            let ejCount = Int(r.u32())
            ejectedIDs.reserveCapacity(ejCount)
            for _ in 0..<ejCount { ejectedIDs.append(r.u32()) }
            deliver(.entityCensus(serverTime: serverTime, tokens: tokens,
                                  foodIDs: foodIDs, ejectedIDs: ejectedIDs))
        default:
            break
        }
    }

    // MARK: sends

    private func send(_ payload: Data) {
        if let transport {                        // nearby: whole payloads, no framing
            transport.sendPayload(payload)
            return
        }
        var frame = Data()
        var len = UInt32(payload.count).littleEndian
        withUnsafeBytes(of: &len) { frame.append(contentsOf: $0) }
        frame.append(payload)
        connection?.send(content: frame, completion: .contentProcessed { _ in })
    }

    func sendHello(name: String, skin: String?, level: Int, party: String = "") {
        var w = ByteWriter()
        w.u8(MsgType.hello.rawValue)
        w.u16(ProtoConst.version)
        w.str(name)
        w.str(skin ?? "")
        w.i32(Int32(level))          // -1 = no league badge
        w.str(party)                 // "" = no party (v4)
        send(w.data)
    }

    func sendInput(dragging: Bool, centerAim: Bool, joystick: CGSize, lastDirection: CGSize) {
        var w = ByteWriter()
        w.u8(MsgType.input.rawValue)
        var flags: UInt8 = 0
        if dragging { flags |= 1 }
        if centerAim { flags |= 2 }
        w.u8(flags)
        w.f32(Float(joystick.width)); w.f32(Float(joystick.height))
        w.f32(Float(lastDirection.width)); w.f32(Float(lastDirection.height))
        send(w.data)
    }

    func sendSplit() {
        var w = ByteWriter()
        w.u8(MsgType.split.rawValue)
        send(w.data)
    }

    func sendEject(times: Int) {
        var w = ByteWriter()
        w.u8(MsgType.eject.rawValue)
        w.u16(UInt16(max(1, min(times, 60))))
        send(w.data)
    }

    func sendRespawn() {
        var w = ByteWriter()
        w.u8(MsgType.respawn.rawValue)
        send(w.data)
    }

    func sendPing() {
        var w = ByteWriter()
        w.u8(MsgType.ping.rawValue)
        w.f64(CACurrentMediaTime())
        send(w.data)
    }

    func sendLeave() {
        var w = ByteWriter()
        w.u8(MsgType.leave.rawValue)
        send(w.data)
    }

    /// v5.8: mod-menu feed bots in online games — ask the server to keep
    /// `count` personal feeders alive that hunt you down and all-in split
    /// into you. 0 = off. Re-send after every respawn (owner IDs change).
    func sendFeedBots(count: Int, name: String, skin: String) {
        var w = ByteWriter()
        w.u8(MsgType.feedBots.rawValue)
        w.u8(UInt8(max(0, min(25, count))))
        w.str(name)
        w.str(skin)
        send(w.data)
    }
}

// MARK: - LAN discovery

struct DiscoveredServer: Identifiable, Equatable {
    var id: String { "\(host):\(info.port)" }
    let host: String
    let info: DiscoveryInfo
    static func == (l: DiscoveredServer, r: DiscoveredServer) -> Bool { l.id == r.id }
}

final class LANDiscovery: ObservableObject {
    @Published var servers: [DiscoveredServer] = []
    @Published var scanning = false
    private let queue = DispatchQueue(label: "macro.discovery")
    /// Consecutive scans a known server failed to answer. UDP replies get lost
    /// routinely, so a server only leaves the list after 4 silent scans instead
    /// of blinking out the first time a datagram is dropped (the old behaviour
    /// cleared the whole list at the start of every scan).
    ///
    /// v5 fix for servers "sometimes disappearing": the old scanner opened 254
    /// parallel NWConnections every 4 seconds. Under Playgrounds that burst
    /// routinely exhausted sockets, an entire scan came back empty, and three
    /// empty scans in a row dropped a perfectly healthy server from the list.
    /// The scanner now uses ONE plain UDP socket for the whole sweep (sendto ×
    /// hosts, one receive loop), fires 3 probe rounds per scan, and tolerates
    /// 4 silent scans — a listed server only vanishes after ~16s of true
    /// silence, and a running server essentially never leaves the list.
    private var missedScans: [String: Int] = [:]
    private var autoScanTimer: Timer? = nil
    /// Bumped to abandon any in-flight sweep (stopAutoScan / deinit).
    private var scanGeneration = 0

    /// Scans immediately, then keeps rescanning while the browser is on screen,
    /// so the list stays fresh and a briefly-missed server comes right back.
    func startAutoScan(interval: TimeInterval = 4.0) {
        scan()
        autoScanTimer?.invalidate()
        autoScanTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.scan()
        }
    }

    func stopAutoScan() {
        autoScanTimer?.invalidate()
        autoScanTimer = nil
        scanGeneration += 1
        scanning = false
    }

    /// Local IPv4 addresses of en0/en1/bridge interfaces.
    static func localIPv4Addresses() -> [String] {
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let flags = Int32(p.pointee.ifa_flags)
            if let sa = p.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET),
               (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    let name = String(cString: p.pointee.ifa_name)
                    if name.hasPrefix("en") || name.hasPrefix("bridge") {
                        addresses.append(String(cString: host))
                    }
                }
            }
            ptr = p.pointee.ifa_next
        }
        return addresses
    }

    func scan() {
        guard !scanning else { return }
        scanning = true
        scanGeneration += 1
        let generation = scanGeneration
        // Known servers stay listed; each scan they miss counts against them.
        for server in servers { missedScans[server.id, default: 0] += 1 }

        var candidates: Set<String> = ["127.0.0.1"]
        for address in Self.localIPv4Addresses() {
            let parts = address.split(separator: ".")
            guard parts.count == 4 else { continue }
            let prefix = parts[0...2].joined(separator: ".")
            for host in 1...254 { candidates.insert("\(prefix).\(host)") }
        }
        if let last = UserDefaults.standard.string(forKey: "macro.lastServerHost") {
            candidates.insert(last)
        }
        // Servers already on screen get probed even if they fall outside the
        // scanned /24 (e.g. a manually-entered address on another subnet).
        for server in servers { candidates.insert(server.host) }

        queue.async { [weak self] in
            self?.sweep(candidates: Array(candidates), generation: generation)
        }
    }

    /// One whole sweep on a single UDP socket: 3 probe rounds (0 / 0.5 / 1.0s),
    /// replies collected until 2.0s, then the miss counters are settled.
    private func sweep(candidates: [String], generation: Int) {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        defer { if fd >= 0 { close(fd) } }
        let finish: () -> Void = { [weak self] in
            DispatchQueue.main.async {
                guard let self, generation == self.scanGeneration else { return }
                self.scanning = false
                self.servers.removeAll { (self.missedScans[$0.id] ?? 0) >= 4 }
            }
        }
        guard fd >= 0 else { finish(); return }

        // Short receive timeout so the loop can interleave probe rounds and
        // notice cancellation without blocking.
        var tv = timeval(tv_sec: 0, tv_usec: 100_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var targets: [sockaddr_in] = []
        targets.reserveCapacity(candidates.count)
        for host in candidates {
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = ProtoConst.discoveryPort.bigEndian
            if inet_pton(AF_INET, host, &addr.sin_addr) == 1 { targets.append(addr) }
        }
        let probe = [UInt8]("\(ProtoConst.discoveryMagic)?".utf8)
        func sendRound() {
            for var addr in targets {
                _ = withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        sendto(fd, probe, probe.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }

        let started = CACurrentMediaTime()
        var roundsSent = 0
        var buffer = [UInt8](repeating: 0, count: 2048)
        while CACurrentMediaTime() - started < 2.0 {
            if generation != scanGeneration { return }   // abandoned
            let elapsed = CACurrentMediaTime() - started
            let due = min(3, Int(elapsed / 0.5) + 1)
            while roundsSent < due { sendRound(); roundsSent += 1 }

            var sender = sockaddr_in()
            var senderLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &sender) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(fd, &buffer, buffer.count, 0, $0, &senderLen)
                }
            }
            guard n > 5 else { continue }   // timeout tick or runt datagram
            let data = Data(buffer[0..<n])
            guard String(decoding: data.prefix(5), as: UTF8.self) == "\(ProtoConst.discoveryMagic)!",
                  let info = try? JSONDecoder().decode(DiscoveryInfo.self, from: data.dropFirst(5))
            else { continue }
            var hostBytes = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var senderAddr = sender.sin_addr
            guard inet_ntop(AF_INET, &senderAddr, &hostBytes, socklen_t(INET_ADDRSTRLEN)) != nil
            else { continue }
            let host = String(cString: hostBytes)
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.scanGeneration else { return }
                let server = DiscoveredServer(host: host, info: info)
                self.missedScans[server.id] = 0
                if let idx = self.servers.firstIndex(where: { $0.id == server.id }) {
                    self.servers[idx] = server        // refresh player counts etc.
                } else {
                    self.servers.append(server)
                }
            }
        }
        finish()
    }
}
