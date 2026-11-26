//
//  NearbyPlay.swift — "Nearby games": host or join a multiplayer match
//  between iPads that are simply NEAR each other. No PC, no router, no
//  shared Wi-Fi network needed — Apple's MultipeerConnectivity framework
//  links the devices directly over peer-to-peer Wi-Fi (the Wi-Fi radio just
//  has to be ON; the iPads do NOT need to be on a network).
//
//  Architecture (same doctrine as PC-hosted online play):
//  - The HOST iPad runs the real authoritative server sim (NearbySim.swift,
//    the PC server's World compiled into the app) via NearbyHostCore.swift.
//  - Every player — INCLUDING the host — is a normal online client: the
//    exact same NetClient → RemoteWorldModel → snapshot-interpolation
//    pipeline used for PC servers, so visuals and feel are identical. The
//    host's own client talks to the sim through an in-process loopback;
//    guests talk over MultipeerConnectivity. One interpolated authoritative
//    timeline for everyone; no client prediction anywhere.
//
//  Requires the Local Network capability with Bonjour services
//  "_macro-io._tcp" and "_macro-io._udp" (see setup note that shipped with
//  this file). If the capability is missing, iOS silently blocks discovery —
//  both controllers surface that as a visible error instead.
//

import Foundation
import MultipeerConnectivity
import SwiftUI
import Combine

enum NearbyProto {
    /// Bonjour service type (max 15 chars, lowercase/digits/hyphen).
    static let serviceType = "macro-io"

    /// MCPeerID display names crash past 63 UTF-8 BYTES — emoji-heavy names
    /// blow the char-count check, so truncate by bytes.
    static func safePeerName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "player" }
        var name = trimmed
        while name.utf8.count > 60 { name = String(name.dropLast()) }
        return name.isEmpty ? "player" : name
    }
}

// MARK: - Loopback transport (host plays their own game in-process)

final class LoopbackTransport: MacroTransport {
    var onPayload: ((Data) -> Void)?
    var onReady: (() -> Void)?
    var onClosed: ((String) -> Void)?

    private let core: NearbyGameCore
    private var conn: NearbyConn? = nil
    private let key = "local-host"

    init(core: NearbyGameCore) {
        self.core = core
    }

    func open() {
        conn = core.register(key: key) { [weak self] payload in
            self?.onPayload?(payload)
        }
        onReady?()
    }

    func sendPayload(_ payload: Data) {
        guard let conn else { return }
        core.handlePayload(conn: conn, payload: payload)
    }

    func close() {
        onClosed = nil                       // intentional close, not an error
        core.unregister(key: key)
        conn = nil
    }
}

// MARK: - Host controller (advertise + relay peers into the core)

final class NearbyHostController: NSObject, ObservableObject {
    let gameName: String
    let core: NearbyGameCore
    private let peerID: MCPeerID
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    /// Set when iOS refuses to advertise — almost always the missing Local
    /// Network capability (see the setup note).
    @Published var startupError: String? = nil

    private let lock = NSLock()
    private var peerConns: [MCPeerID: NearbyConn] = [:]

    init(gameName: String, settings: SrvWorldSettings) {
        let cleanName = gameName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.gameName = cleanName.isEmpty ? "Nearby Game" : cleanName
        self.core = NearbyGameCore(name: self.gameName, settings: settings)
        // The peer's display name IS the game name guests see in their list.
        self.peerID = MCPeerID(displayName: NearbyProto.safePeerName(self.gameName))
        self.session = MCSession(peer: peerID, securityIdentity: nil,
                                 encryptionPreference: .required)
        self.advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: ["bots": "\(settings.botCount)",
                            "v": "\(ProtoConst.version)"],
            serviceType: NearbyProto.serviceType)
        super.init()
        session.delegate = self
        advertiser.delegate = self
    }

    func start() {
        core.start()
        advertiser.startAdvertisingPeer()
    }

    func stop() {
        advertiser.stopAdvertisingPeer()
        session.disconnect()
        core.stop()
        lock.lock(); peerConns.removeAll(); lock.unlock()
    }

    /// The host's own seat at the table.
    func makeLocalTransport() -> LoopbackTransport {
        LoopbackTransport(core: core)
    }
}

extension NearbyHostController: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)     // hello/version gate happens in-protocol
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async {
            self.startupError = "Couldn't announce the game (\(error.localizedDescription)). Check the app's Local Network capability + permission."
        }
    }
}

extension NearbyHostController: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID,
                 didChange state: MCSessionState) {
        switch state {
        case .connected:
            let key = "peer-\(ObjectIdentifier(peerID).hashValue)-\(peerID.displayName)"
            let conn = core.register(key: key) { [weak self, weak session] payload in
                guard let session, session.connectedPeers.contains(peerID) else { return }
                try? session.send(payload, toPeers: [peerID], with: .reliable)
                _ = self   // keep the controller alive in the capture
            }
            lock.lock(); peerConns[peerID] = conn; lock.unlock()
        case .notConnected:
            lock.lock()
            let conn = peerConns.removeValue(forKey: peerID)
            lock.unlock()
            if let conn { core.unregister(key: conn.key) }
        case .connecting:
            break
        @unknown default:
            break
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        lock.lock()
        let conn = peerConns[peerID]
        lock.unlock()
        guard let conn else { return }
        core.handlePayload(conn: conn, payload: data)
    }

    func session(_ session: MCSession, didReceive stream: InputStream,
                 withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - Nearby game discovery (guest side)

struct NearbyGameInfo: Identifiable {
    let id = UUID()
    let peer: MCPeerID
    let bots: Int
    let version: Int
    var name: String { peer.displayName }
}

final class NearbyBrowser: NSObject, ObservableObject {
    @Published var games: [NearbyGameInfo] = []
    @Published var startupError: String? = nil
    @Published var browsing = false

    private var myPeerID: MCPeerID
    private var browser: MCNearbyServiceBrowser? = nil

    init(playerName: String) {
        self.myPeerID = MCPeerID(displayName: NearbyProto.safePeerName(playerName))
        super.init()
    }

    func start() {
        guard browser == nil else { return }
        let b = MCNearbyServiceBrowser(peer: myPeerID, serviceType: NearbyProto.serviceType)
        b.delegate = self
        browser = b
        games.removeAll()
        b.startBrowsingForPeers()
        browsing = true
    }

    func stop() {
        browser?.stopBrowsingForPeers()
        browser = nil
        browsing = false
        games.removeAll()
    }

    /// Build the transport that joins `game`. The invite goes out RIGHT NOW —
    /// before this browser stops when the match screen replaces the menu —
    /// and the transport holds the MCNearbyServiceBrowser alive until the
    /// handshake settles. NetClient's open() then attaches to whatever state
    /// the invite has reached.
    func makeGuestTransport(for game: NearbyGameInfo) -> NearbyGuestTransport? {
        guard let browser else { return nil }
        let transport = NearbyGuestTransport(myPeerID: myPeerID, hostPeer: game.peer, browser: browser)
        transport.invite()
        return transport
    }
}

extension NearbyBrowser: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async {
            guard !self.games.contains(where: { $0.peer == peerID }) else { return }
            self.games.append(NearbyGameInfo(peer: peerID,
                                             bots: Int(info?["bots"] ?? "") ?? 0,
                                             version: Int(info?["v"] ?? "") ?? 0))
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.games.removeAll { $0.peer == peerID }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async {
            self.startupError = "Nearby search unavailable (\(error.localizedDescription)). Check the app's Local Network capability + permission."
            self.browsing = false
        }
    }
}

// MARK: - Guest transport (game traffic over the Multipeer session)

final class NearbyGuestTransport: NSObject, MacroTransport {
    var onPayload: ((Data) -> Void)?
    var onReady: (() -> Void)?
    var onClosed: ((String) -> Void)?

    private let session: MCSession
    private let hostPeer: MCPeerID
    /// STRONG on purpose: the invite must survive the menu (and its browser)
    /// being torn down when the match screen appears.
    private let browser: MCNearbyServiceBrowser
    private var everConnected = false

    /// Invite/handshake state, mutated on the main queue only, so open()
    /// (main) and delegate callbacks (hopped to main) can't race.
    private enum LinkState { case inviting, connected, failed(String) }
    private var linkState: LinkState = .inviting
    private var opened = false

    init(myPeerID: MCPeerID, hostPeer: MCPeerID, browser: MCNearbyServiceBrowser) {
        self.session = MCSession(peer: myPeerID, securityIdentity: nil,
                                 encryptionPreference: .required)
        self.hostPeer = hostPeer
        self.browser = browser
        super.init()
        session.delegate = self
    }

    /// Sent immediately when the player taps JOIN (see makeGuestTransport).
    func invite() {
        browser.invitePeer(hostPeer, to: session, withContext: nil, timeout: 20)
    }

    /// Called by NetClient once the match screen is up. The invite may have
    /// already settled — replay its outcome.
    func open() {
        opened = true
        switch linkState {
        case .connected: onReady?()
        case .failed(let reason): onClosed?(reason)
        case .inviting: break                // onReady fires on .connected
        }
    }

    func sendPayload(_ payload: Data) {
        guard session.connectedPeers.contains(hostPeer) else { return }
        try? session.send(payload, toPeers: [hostPeer], with: .reliable)
    }

    func close() {
        onClosed = nil                       // intentional close, not an error
        session.disconnect()
    }
}

extension NearbyGuestTransport: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID,
                 didChange state: MCSessionState) {
        guard peerID == hostPeer else { return }
        DispatchQueue.main.async {
            switch state {
            case .connected:
                self.everConnected = true
                self.linkState = .connected
                if self.opened { self.onReady?() }
            case .notConnected:
                let reason = self.everConnected
                    ? "Lost the connection to the host (they may have left or moved out of range)."
                    : "Couldn't reach the host. Keep both iPads unlocked and within range, then try again."
                self.linkState = .failed(reason)
                if self.opened { self.onClosed?(reason) }
            case .connecting:
                break
            @unknown default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard peerID == hostPeer else { return }
        onPayload?(data)
    }

    func session(_ session: MCSession, didReceive stream: InputStream,
                 withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - A joined/hosted nearby match, handed to OnlineGameView

struct NearbySession {
    let label: String                        // shown in the "Joining …" overlay
    let transport: MacroTransport
    let host: NearbyHostController?          // non-nil when this iPad hosts
}

// MARK: - UI: nearby card in the server browser

struct NearbyGamesCard: View {
    @ObservedObject var nearby: NearbyBrowser
    let onJoin: (NearbyGameInfo) -> Void
    let onHost: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Nearby iPads  ·  no Wi-Fi network needed")
                    .font(.custom("UbuntuSans-Bold", size: 16))
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                Button(action: onHost) {
                    Text("HOST")
                        .font(.custom("UbuntuSans-Bold", size: 14))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.green.opacity(0.85).cornerRadius(10))
                }
            }
            if let error = nearby.startupError {
                Text(error)
                    .font(.custom("UbuntuSans-Bold", size: 13))
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 6)
            }
            if nearby.games.isEmpty {
                Text(nearby.browsing
                     ? "Looking for games hosted on nearby iPads…"
                     : "Searching is off.")
                    .font(.custom("UbuntuSans-Bold", size: 14))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 8) {
                    ForEach(nearby.games) { game in
                        gameRow(game)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 340)
        .background(Color.black.opacity(0.3).cornerRadius(16))
    }

    private func gameRow(_ game: NearbyGameInfo) -> some View {
        Button(action: { onJoin(game) }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.name)
                        .font(.custom("UbuntuSans-Bold", size: 18))
                        .foregroundColor(.white)
                    Text("nearby iPad  ·  \(game.bots) bots")
                        .font(.custom("UbuntuSans-Bold", size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer()
                Text(game.version == Int(ProtoConst.version) ? "JOIN" : "v\(game.version)")
                    .font(.custom("UbuntuSans-Bold", size: 16))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background((game.version == Int(ProtoConst.version)
                                 ? Color.green.opacity(0.85)
                                 : Color.gray).cornerRadius(10))
            }
            .padding(12)
            .background(Color.black.opacity(0.35).cornerRadius(12))
        }
        .disabled(game.version != Int(ProtoConst.version))
    }
}

// MARK: - UI: host setup sheet

struct NearbyHostSetupView: View {
    let playerName: String
    let onStart: (String, SrvWorldSettings) -> Void
    let onCancel: () -> Void

    @State private var gameName: String = ""
    @State private var botCount: Double = 30
    @State private var botSkill: Double = 1.0
    @State private var randomizeBotMass = false

    private var skillLabel: String {
        if botSkill < 0.65 { return "Chill" }
        if botSkill < 0.95 { return "Normal" }
        if botSkill < 1.25 { return "Sharp" }
        return "Ruthless"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).edgesIgnoringSafeArea(.all)
            VStack(spacing: 18) {
                Text("HOST A NEARBY GAME")
                    .font(.custom("UbuntuSans-Bold", size: 24))
                    .foregroundColor(.white)
                Text("Friends nearby will see this game and can join — no Wi-Fi network needed, just keep Wi-Fi & Bluetooth switched on.")
                    .font(.custom("UbuntuSans-Bold", size: 13))
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .frame(width: 300)

                TextField(defaultName, text: $gameName)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(Color.white.opacity(0.9).cornerRadius(8))
                    .frame(width: 280)

                VStack(spacing: 4) {
                    Text("Bots: \(Int(botCount))")
                        .font(.custom("UbuntuSans-Bold", size: 16))
                        .foregroundColor(.white)
                    Slider(value: $botCount, in: 0...60, step: 5)
                        .frame(width: 280)
                }

                VStack(spacing: 4) {
                    Text("Bot skill: \(skillLabel)")
                        .font(.custom("UbuntuSans-Bold", size: 16))
                        .foregroundColor(.white)
                    Slider(value: $botSkill, in: 0.4...1.6)
                        .frame(width: 280)
                }

                Toggle(isOn: $randomizeBotMass) {
                    Text("Randomize bot start mass")
                        .font(.custom("UbuntuSans-Bold", size: 16))
                        .foregroundColor(.white)
                }
                .frame(width: 280)

                HStack(spacing: 14) {
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.custom("UbuntuSans-Bold", size: 18))
                            .foregroundColor(.white)
                            .padding(.horizontal, 26).padding(.vertical, 12)
                            .background(Color.gray.opacity(0.7).cornerRadius(14))
                    }
                    Button(action: startGame) {
                        Text("START HOSTING")
                            .font(.custom("UbuntuSans-Bold", size: 18))
                            .foregroundColor(.white)
                            .padding(.horizontal, 26).padding(.vertical, 12)
                            .background(Color.green.opacity(0.85).cornerRadius(14))
                    }
                }
            }
            .padding(28)
            .background(Color(white: 0.12).cornerRadius(20))
        }
    }

    private var defaultName: String {
        let trimmed = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Nearby Game" : "\(trimmed)'s Game"
    }

    private func startGame() {
        var settings = SrvWorldSettings()
        settings.botCount = Int(botCount)
        settings.botSkill = botSkill
        settings.randomizeBotStartMass = randomizeBotMass
        let name = gameName.trimmingCharacters(in: .whitespacesAndNewlines)
        onStart(name.isEmpty ? defaultName : name, settings)
    }
}
