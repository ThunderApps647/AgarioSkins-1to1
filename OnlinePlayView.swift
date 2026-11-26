//
//  OnlinePlayView.swift — PLAY ONLINE: server browser + networked match screen.
//
//  The match screen is a faithful twin of the offline ContentView game branch:
//  the SAME GameWorldView renderer, SAME HUD components (TopBarHUD,
//  ActionButtonsHUD, JoystickView, PlayerArrow, LeavePopupModal, mod menu),
//  SAME camera/zoom/deformation/eaten-cell maths — but the world state comes
//  from RemoteWorldModel (server-authoritative, snapshot-interpolated)
//  instead of the local simulation. Offline play is completely untouched.
//

import SwiftUI
import Combine
import QuartzCore

// MARK: - Entry

struct OnlinePlayView: View {
    // Bindings, not values: fullScreenCover can capture a stale copy of the menu
    // state; bindings read the live source of truth when the session starts, so
    // the name/skin/level typed in the menu always reach the server.
    @Binding var playerName: String
    @Binding var selectedSkinName: String?
    @Binding var showPlayerLevel: Bool
    @Binding var playerLevel: Int
    @Environment(\.dismiss) private var dismiss

    @State private var joinedServer: DiscoveredServer? = nil
    @State private var manualTarget: (host: String, port: UInt16)? = nil
    /// v7: a hosted or joined nearby (MultipeerConnectivity) match.
    @State private var nearbySession: NearbySession? = nil

    var body: some View {
        if let session = nearbySession {
            OnlineGameView(host: session.label, port: 0,
                           playerName: playerName, selectedSkinName: selectedSkinName,
                           showPlayerLevel: showPlayerLevel, playerLevel: playerLevel,
                           onExit: {
                               nearbySession?.host?.stop()
                               nearbySession = nil
                           },
                           nearbySession: session)
        } else if let target = manualTarget {
            OnlineGameView(host: target.host, port: target.port,
                           playerName: playerName, selectedSkinName: selectedSkinName,
                           showPlayerLevel: showPlayerLevel, playerLevel: playerLevel,
                           onExit: { manualTarget = nil; joinedServer = nil })
        } else if let server = joinedServer {
            OnlineGameView(host: server.host, port: server.info.port,
                           playerName: playerName, selectedSkinName: selectedSkinName,
                           showPlayerLevel: showPlayerLevel, playerLevel: playerLevel,
                           onExit: { joinedServer = nil })
        } else {
            ServerBrowserView(playerName: playerName,
                              onJoin: { server in joinedServer = server },
                              onJoinManual: { host, port in manualTarget = (host, port) },
                              onJoinNearby: { session in nearbySession = session },
                              onBack: { dismiss() })
        }
    }
}

// MARK: - Server browser (styled like the main menu)

struct ServerBrowserView: View {
    let playerName: String
    let onJoin: (DiscoveredServer) -> Void
    let onJoinManual: (String, UInt16) -> Void
    /// v7: hand a ready nearby session (hosted or joined) to OnlinePlayView.
    let onJoinNearby: (NearbySession) -> Void
    let onBack: () -> Void

    @StateObject private var discovery = LANDiscovery()
    @StateObject private var nearby: NearbyBrowser
    @State private var showHostSetup = false
    @State private var manualAddress: String = UserDefaults.standard.string(forKey: "macro.lastServerHost") ?? ""
    @AppStorage("macro.partyCode") private var partyCode: String = ""

    init(playerName: String,
         onJoin: @escaping (DiscoveredServer) -> Void,
         onJoinManual: @escaping (String, UInt16) -> Void,
         onJoinNearby: @escaping (NearbySession) -> Void,
         onBack: @escaping () -> Void) {
        self.playerName = playerName
        self.onJoin = onJoin
        self.onJoinManual = onJoinManual
        self.onJoinNearby = onJoinNearby
        self.onBack = onBack
        _nearby = StateObject(wrappedValue: NearbyBrowser(playerName: playerName))
    }

    // Body split into helper views so the Swift type-checker stays fast.
    var body: some View {
        ZStack {
            Image("background-ipadpro-hd").resizable().scaledToFill().edgesIgnoringSafeArea(.all)

            VStack(spacing: 18) {
                Image("title").resizable().scaledToFit().frame(width: 260).padding(.top, 60)

                Text("PLAY ONLINE")
                    .font(.custom("UbuntuSans-Bold", size: 28))
                    .foregroundColor(.white).shadow(radius: 5)

                if !partyCode.isEmpty {
                    Text("Party \(partyCode) - party members who join the same server play together")
                        .font(.custom("UbuntuSans-Bold", size: 13))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.orange.opacity(0.55).cornerRadius(10))
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        serverListCard
                        NearbyGamesCard(nearby: nearby,
                                        onJoin: { joinNearby($0) },
                                        onHost: { showHostSetup = true })
                        manualJoinCard
                    }
                }

                Spacer()

                Button(action: onBack) {
                    Text("Back")
                        .font(.title3).fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 36).padding(.vertical, 12)
                        .background(Color.black.opacity(0.45)).cornerRadius(18)
                }
                .padding(.bottom, 40)
            }

            if showHostSetup {
                NearbyHostSetupView(playerName: playerName,
                                    onStart: { name, settings in
                                        showHostSetup = false
                                        startHosting(name: name, settings: settings)
                                    },
                                    onCancel: { showHostSetup = false })
                    .zIndex(500)
            }
        }
        .onAppear { discovery.startAutoScan(); nearby.start() }
        .onDisappear { discovery.stopAutoScan(); nearby.stop() }
    }

    // MARK: nearby (MultipeerConnectivity) flows

    private func joinNearby(_ game: NearbyGameInfo) {
        guard let transport = nearby.makeGuestTransport(for: game) else { return }
        onJoinNearby(NearbySession(label: game.name, transport: transport, host: nil))
    }

    private func startHosting(name: String, settings: SrvWorldSettings) {
        nearby.stop()      // a host doesn't browse; frees the radio for the session
        let host = NearbyHostController(gameName: name, settings: settings)
        host.start()
        onJoinNearby(NearbySession(label: name,
                                   transport: host.makeLocalTransport(),
                                   host: host))
    }

    private var serverListCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text(discovery.scanning && discovery.servers.isEmpty ? "Searching your network…" : "Servers on your network")
                    .font(.custom("UbuntuSans-Bold", size: 16))
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                Button(action: { discovery.scan() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.blue.clipShape(Circle()))
                }
            }
            if discovery.servers.isEmpty {
                Text(discovery.scanning ? "…" : "No servers found yet.\nStart one on your computer:  swift run macro-server")
                    .font(.custom("UbuntuSans-Bold", size: 14))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 22)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(discovery.servers) { server in
                            serverRow(server)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .padding(16)
        .frame(width: 340)
        .background(Color.black.opacity(0.3).cornerRadius(16))
    }

    private func serverRow(_ server: DiscoveredServer) -> some View {
        Button(action: {
            UserDefaults.standard.set(server.host, forKey: "macro.lastServerHost")
            onJoin(server)
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.info.name)
                        .font(.custom("UbuntuSans-Bold", size: 18))
                        .foregroundColor(.white)
                    Text("\(server.host)  ·  \(server.info.players)/\(server.info.maxPlayers) players  ·  \(server.info.bots) bots")
                        .font(.custom("UbuntuSans-Bold", size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer()
                Text("JOIN")
                    .font(.custom("UbuntuSans-Bold", size: 16))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(Color.blue.cornerRadius(10))
            }
            .padding(12)
            .background(Color.black.opacity(0.35).cornerRadius(12))
        }
    }

    private var manualJoinCard: some View {
        VStack(spacing: 8) {
            Text("Or join by address")
                .font(.custom("UbuntuSans-Bold", size: 14))
                .foregroundColor(.white.opacity(0.8))
            HStack {
                TextField("192.168.1.20:34567", text: $manualAddress)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(10)
                    .background(Color.white.opacity(0.85).cornerRadius(8))
                    .frame(width: 210)
                Button(action: joinManual) {
                    Text("JOIN")
                        .font(.custom("UbuntuSans-Bold", size: 16))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Color.blue.cornerRadius(10))
                }
            }
        }
        .padding(14)
        .frame(width: 340)
        .background(Color.black.opacity(0.3).cornerRadius(16))
    }

    private func joinManual() {
        let trimmed = manualAddress.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var host = trimmed
        var port = ProtoConst.defaultPort
        if let idx = trimmed.lastIndex(of: ":"), let p = UInt16(trimmed[trimmed.index(after: idx)...]) {
            host = String(trimmed[..<idx])
            port = p
        }
        UserDefaults.standard.set(host, forKey: "macro.lastServerHost")
        onJoinManual(host, port)
    }
}

// MARK: - Online match screen

struct OnlineGameView: View {
    let host: String
    let port: UInt16
    let playerName: String
    let selectedSkinName: String?
    let showPlayerLevel: Bool
    let playerLevel: Int
    let onExit: () -> Void
    /// v7: when set, this match runs over a nearby (MultipeerConnectivity)
    /// link instead of TCP — everything else is byte-identical.
    var nearbySession: NearbySession? = nil

    // net + world
    @State private var net = NetClient()
    @State private var world = RemoteWorldModel()
    @State private var connectionPhase: ConnectionPhase = .connecting
    @State private var errorText: String? = nil

    enum ConnectionPhase { case connecting, playing, dead }

    // render state fed to the ORIGINAL GameWorldView
    @State private var playerCells: [PlayerCell] = []
    @State private var botCells: [PlayerCell] = []
    @State private var animatingEatenCells: [PlayerCell] = []
    /// Food/ejected-mass/token pickups mid magnet-suck into their eater (cosmetic).
    @State private var consumeAnimations: [ConsumedPickupAnimation] = []
    @State private var viruses: [Virus] = []
    @State private var tokens: [Token] = []
    @State private var botLevels: [UUID: Int] = [:]
    /// Dark mode: keeps the safe-area backdrop in step with the inverted grid.
    @AppStorage("macro.darkModeGrid") private var darkModeGrid: Bool = false

    // camera (identical maths to offline)
    @State private var smoothedTotalMass: CGFloat = 1300
    @State private var smoothedPlayerPosition: CGPoint = .zero
    @State private var cameraJumpOffset: CGSize = .zero
    @State private var lastCameraTargetPos: CGPoint? = nil
    @State private var lastCameraCellCount: Int = 0
    @State private var zoomLevel: CGFloat = 1.0
    @State private var visibleWorldRect: CGRect = .zero

    // controls (identical to offline)
    @State private var joystickOffset = CGSize.zero
    @State private var joystickBasePosition: CGPoint? = nil
    @State private var joystickIsDragging = false
    @State private var lastJoystickDirection = CGSize.zero
    @State private var centerAimUntilCursorMoves = true
    @State private var isFeedingHeld = false
    @State private var feedHoldStartTime: Date? = nil
    private let feedHoldThreshold: TimeInterval = 1.4
    private let spamFeedInterval: TimeInterval = 0.076
    @State private var lastSpamFeedTime: TimeInterval = 0
    @State private var feedButtonScale: CGFloat = 1.0
    @State private var isMacroHeld = false
    @State private var macroButtonScale: CGFloat = 1.0
    @State private var lastMacroFeedTime: TimeInterval = 0
    @State private var macroInterval: TimeInterval = 0.02
    @State private var macroBullets: Int = 15
    @State private var macroPressBudget: Double = 0
    @State private var ejectControlSession: UInt = 0
    @State private var inputSendAccumulator: CGFloat = 0

    // HUD
    @State private var highScore: Int = 0
    @State private var tokenCount: Int = 0
    @State private var fps: Int = 60
    @State private var frameCount: Int = 0
    @State private var lastFpsCheckTime: TimeInterval = 0
    @State private var showFPS = false
    @State private var lastFrameTimestamp: CFTimeInterval = 0
    @State private var pingAccumulator: CGFloat = 0

    // popups / menus
    @State private var isLeavePopupPresented = false
    @State private var leavePopupMounted = false
    @State private var showModMenu = false
    @State private var modMenuIconOffset: CGSize = .zero
    @State private var lastModMenuIconOffset: CGSize = .zero
    @State private var modMenuPanelOffset: CGSize = .zero
    @State private var lastModMenuPanelOffset: CGSize = .zero
    @State private var zoomSliderValue: Double = 1.0
    @State private var showGrid = true
    @State private var showSkins = true
    // mod-menu placeholders (host-controlled online; kept for identical panel UI)
    @State private var allowPlayerTeaming = true
    @State private var botSkill: Double = 1.0
    @State private var randomizeBotStartMass = false
    @State private var spawnFeedBots = false
    @State private var feedBotName = "Feeder"
    @State private var feedBotSkinID = ""

    // dual-skin swap (same phases as offline)
    @State private var dualSkinSwapPhase: DualSkinSwapPhase = .idle
    @State private var dualSkinSwapPhaseEndsAt: TimeInterval = 0
    @State private var dualSkinSwapStartedAt: TimeInterval = 0
    // v5 skin sync: dual-skin swap state per REMOTE human owner. Same
    // idle -> showing -> cooldown machine as the local player, driven by
    // server eat events, so everyone sees everyone's level-3 skins react.
    @State private var remoteSwapPhase: [UUID: DualSkinSwapPhase] = [:]
    @State private var remoteSwapEndsAt: [UUID: TimeInterval] = [:]
    @State private var remoteSwapStartedAt: [UUID: TimeInterval] = [:]

    @StateObject private var displayLink = DisplayLinkDriver()

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

    /// Leaderboard HUD rows from the server's snapshot leaderboard. Names come off the
    /// wire (empty -> "Unnamed Cell"); the own entry lists the player's nickname
    /// ("You" only when blank; gold row).
    /// If the server's list doesn't include us, the rank shown is the best estimate:
    /// one past every listed entry that outweighs us.
    /// v5.9.3: the own leaderboard row shows the actual nickname; "You" stays
    /// only as the blank-name fallback.
    private var myLeaderboardName: String {
        let trimmed = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "You" : trimmed
    }

    private func computeLeaderboardRows() -> [LeaderboardHUDRow] {
        var entries = world.leaderboard
        entries.sort { $0.mass > $1.mass }
        // Party = you + everyone sharing your party code, exactly like the offline
        // pact: party rows carry the team pfp, and party members outside the top 5
        // fill up to 3 extra spots below the 5th row (in rank order).
        let partyActive = !world.teammateUUIDs.isEmpty
        func inParty(_ entry: RemoteLeaderboardEntry) -> Bool {
            partyActive && (entry.isMe || entry.isParty)
        }
        var rows: [LeaderboardHUDRow] = []
        for (index, entry) in entries.prefix(5).enumerated() {
            rows.append(LeaderboardHUDRow(rank: index + 1,
                                          name: entry.isMe ? myLeaderboardName : entry.name,
                                          isPlayer: entry.isMe,
                                          isPartyMember: inParty(entry)))
        }
        var extraSpots = 0
        for (index, entry) in entries.enumerated() where index >= 5 && extraSpots < 3 {
            guard entry.isMe || (partyActive && entry.isParty) else { continue }
            rows.append(LeaderboardHUDRow(rank: index + 1,
                                          name: entry.isMe ? myLeaderboardName : entry.name,
                                          isPlayer: entry.isMe,
                                          isPartyMember: inParty(entry)))
            extraSpots += 1
        }
        if !entries.contains(where: { $0.isMe }), !playerCells.isEmpty {
            let myMass = Int(totalPlayerMass)
            let ahead = entries.filter { $0.mass > myMass }.count
            rows.append(LeaderboardHUDRow(rank: ahead + 1, name: myLeaderboardName, isPlayer: true,
                                          isPartyMember: partyActive))
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

    private var renderedOwnerLevels: [UUID: Int] {
        var levels = botLevels
        if showPlayerLevel, let mine = playerCells.first?.ownerID {
            levels[mine] = LeagueBadge.clamp(playerLevel)
        }
        return levels
    }

    // NOTE: the body is deliberately split into small helper views/functions.
    // A single flat ZStack expression of this size makes the Swift type-checker
    // give up ("unable to type-check this expression in reasonable time").
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(hex: darkModeGrid ? 0x000000 : 0xFFFFFF).edgesIgnoringSafeArea(.all)
                worldLayer(geometry: geometry)
                if connectionPhase == .playing && !isLeavePopupPresented {
                    touchLayer(geometry: geometry)
                }
                // The top bar stays MOUNTED (just hidden) while the leave popup is
                // up: unmounting it would reset the leaderboard panel's expansion
                // state, collapsing it after tapping "No".
                if connectionPhase == .playing {
                    topHUD
                        .opacity(isLeavePopupPresented ? 0 : 1)
                        .allowsHitTesting(!isLeavePopupPresented)
                }
                if connectionPhase == .playing && !isLeavePopupPresented {
                    actionButtons
                    modMenuIcon(geometry: geometry)
                    if showModMenu { modMenuPanel(geometry: geometry) }
                }
                if connectionPhase == .playing && leavePopupMounted {
                    LeavePopupModal(
                        onNo: { resumeFromLeavePopup() },
                        onNoExitComplete: { leavePopupMounted = false },
                        onYes: { leaveMatch() }
                    )
                    .zIndex(1000)
                }
                if connectionPhase == .connecting {
                    connectingOverlay.zIndex(2000)
                }
                if connectionPhase == .dead {
                    deathOverlay.zIndex(2000)
                }
            }
            .edgesIgnoringSafeArea(.all)
            .statusBar(hidden: true)
            .onAppear { startSession() }
            // v5.8: mod-menu feed bots now work ONLINE — the toggle asks the
            // server for a personal squad that hunts you down and all-ins.
            .onChange(of: spawnFeedBots) { on in
                net.sendFeedBots(count: on ? 15 : 0, name: feedBotName, skin: feedBotSkinID)
            }
            .onChange(of: feedBotName) { newName in
                if spawnFeedBots {
                    net.sendFeedBots(count: 15, name: newName, skin: feedBotSkinID)
                }
            }
            .onChange(of: feedBotSkinID) { newSkin in
                if spawnFeedBots {
                    net.sendFeedBots(count: 15, name: feedBotName, skin: newSkin)
                }
            }
            .onDisappear {
                displayLink.stop()
                net.sendLeave()
                net.disconnect()
            }
            .onReceive(displayLink.frames) { timestamp in
                gameTick(timestamp: timestamp, screenSize: geometry.size)
            }
        }
        .edgesIgnoringSafeArea(.all)
    }

    // MARK: body pieces (split to keep the type-checker fast)

    private func worldLayer(geometry: GeometryProxy) -> some View {
        GameWorldView(
            screenSize: CGSize(width: geometry.size.width,
                               height: geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom),
            smoothedPlayerPosition: $smoothedPlayerPosition,
            zoomLevel: $zoomLevel,
            playerCells: $playerCells,
            botCells: $botCells,
            animatingEatenCells: $animatingEatenCells,
            tokens: tokens,
            foodManager: world.foodManager,
            massManager: world.massManager,
            viruses: viruses,
            showGrid: showGrid,
            showSkins: showSkins,
            teammateOwnerID: nil,
            teammateOwnerIDs: world.teammateUUIDs,
            localPlayerInParty: !world.localPartyCode.isEmpty,
            dualSkinSwapShowingSince: dualSkinSwapPhase == .showing ? dualSkinSwapStartedAt : nil,
            dualSkinSwapShowingSinceByOwner: remoteSwapShowingByOwner(),
            ownerLevels: renderedOwnerLevels,
            consumeAnimations: consumeAnimations
        )
        .offset(y: -(geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom) / 2)
        .zIndex(0)
    }

    private func aimDragGesture(geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if centerAimUntilCursorMoves { centerAimUntilCursorMoves = false }
                if !joystickIsDragging {
                    joystickBasePosition = value.startLocation
                    joystickIsDragging = true
                }
                let dragVector = value.translation
                let distance = sqrt(dragVector.width * dragVector.width + dragVector.height * dragVector.height)
                let maxDistance: CGFloat = 130 / 2
                if distance > maxDistance {
                    let ratio = maxDistance / distance
                    joystickOffset = CGSize(width: dragVector.width * ratio, height: dragVector.height * ratio)
                } else {
                    joystickOffset = dragVector
                }
                lastJoystickDirection = joystickOffset
                sendInputNow()
            }
            .onEnded { value in
                joystickIsDragging = false
                joystickBasePosition = nil
                let isTap = value.translation.width.magnitude < 5 && value.translation.height.magnitude < 5
                if isTap {
                    let playerScreenCenter = CGPoint(x: geometry.size.width / 2,
                                                     y: (geometry.size.height + geometry.safeAreaInsets.top - geometry.safeAreaInsets.bottom) / 2)
                    lastJoystickDirection = CGSize(width: value.startLocation.x - playerScreenCenter.x,
                                                   height: value.startLocation.y - playerScreenCenter.y)
                }
                joystickOffset = .zero
                sendInputNow()
            }
    }

    @ViewBuilder
    private func touchLayer(geometry: GeometryProxy) -> some View {
        Color.clear.contentShape(Rectangle())
            .gesture(aimDragGesture(geometry: geometry))

        if lastJoystickDirection != .zero {
            PlayerArrow(geometry: geometry, joystickIsDragging: joystickIsDragging,
                        joystickOffset: joystickOffset, lastJoystickDirection: lastJoystickDirection,
                        playerCells: playerCells, playerCenter: playerCenter, zoomLevel: $zoomLevel)
        }
        if joystickIsDragging {
            JoystickView(joystickOffset: $joystickOffset, joystickBasePosition: $joystickBasePosition)
        }
    }

    private var topHUD: some View {
        TopBarHUD(score: highScore,
                  tokenCount: tokenCount,
                  fps: fps,
                  showFPS: showFPS,
                  friendCount: world.teammateUUIDs.count,
                  inParty: !world.localPartyCode.isEmpty,
                  leaderboardRows: computeLeaderboardRows(),
                  onPause: { pause() })
        .equatable()
        .zIndex(1)
    }

    private var actionButtons: some View {
        ActionButtonsHUD(canSplit: canSplit(),
                         canFeed: canFeed(),
                         isFeedingHeld: isFeedingHeld,
                         feedButtonScale: feedButtonScale,
                         macroButtonScale: macroButtonScale,
                         feedHoldThreshold: feedHoldThreshold,
                         onSplit: { if canSplit() { net.sendSplit() } },
                         onMacroDown: handleMacroDown,
                         onMacroUp: handleMacroUp,
                         onFeedDown: handleFeedDown,
                         onFeedUp: handleFeedUp)
        .equatable()
        .id(ejectControlSession)
        .zIndex(1)
    }

    private func handleMacroDown() {
        if !isMacroHeld {
            isMacroHeld = true
            // Seed one burst, then drain it over display frames. This keeps
            // the same bullets/second as offline macro settings without
            // presenting each whole burst as one network-visible clump.
            macroPressBudget = 1
            lastMacroFeedTime = CACurrentMediaTime()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { macroButtonScale = 1.15 }
        }
    }

    private func handleMacroUp() {
        isMacroHeld = false
        macroPressBudget = 0
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { macroButtonScale = 1.0 }
    }

    private func handleFeedDown() {
        if !isFeedingHeld {
            isFeedingHeld = true
            feedHoldStartTime = Date()
        }
    }

    private func handleFeedUp() {
        let holdDuration = feedHoldStartTime.map { Date().timeIntervalSince($0) } ?? 0
        let isTap = holdDuration < feedHoldThreshold
        isFeedingHeld = false
        feedHoldStartTime = nil
        if isTap, canFeed() { net.sendEject(times: 1) }
    }

    private func modMenuIcon(geometry: GeometryProxy) -> some View {
        Image("mod-menu-btn")
            .resizable().scaledToFit().frame(width: 50, height: 50)
            .contentShape(Rectangle())
            .offset(modMenuIconOffset)
            .position(x: geometry.size.width - 50, y: 150)
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { val in
                        modMenuIconOffset = CGSize(width: lastModMenuIconOffset.width + val.translation.width,
                                                   height: lastModMenuIconOffset.height + val.translation.height)
                    }
                    .onEnded { _ in lastModMenuIconOffset = modMenuIconOffset }
            )
            .onTapGesture { withAnimation(.easeInOut(duration: 0.5)) { showModMenu.toggle() } }
            .zIndex(99)
    }

    private func modMenuPanel(geometry: GeometryProxy) -> some View {
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
            onClose: { withAnimation(.easeInOut(duration: 0.5)) { showModMenu = false } },
            onHeaderDragChanged: { translation in
                modMenuPanelOffset = CGSize(width: lastModMenuPanelOffset.width + translation.width,
                                            height: lastModMenuPanelOffset.height + translation.height)
            },
            onHeaderDragEnded: { lastModMenuPanelOffset = modMenuPanelOffset }
        )
        .offset(modMenuPanelOffset)
        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        .zIndex(100)
        .transition(.opacity)
    }

    // MARK: overlays

    private var connectingOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).edgesIgnoringSafeArea(.all)
            VStack(spacing: 16) {
                if let error = errorText {
                    Text("Couldn't join")
                        .font(.custom("UbuntuSans-Bold", size: 24)).foregroundColor(.white)
                    Text(error)
                        .font(.custom("UbuntuSans-Bold", size: 15))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                    Button(action: { onExit() }) {
                        Text("Back")
                            .font(.custom("UbuntuSans-Bold", size: 18)).foregroundColor(.white)
                            .padding(.horizontal, 30).padding(.vertical, 12)
                            .background(Color.blue.cornerRadius(14))
                    }
                } else {
                    ProgressView().scaleEffect(1.4).tint(.white)
                    Text("Joining \(host)…")
                        .font(.custom("UbuntuSans-Bold", size: 18)).foregroundColor(.white)
                }
            }
            .padding(30)
            .background(Color(white: 0.12).cornerRadius(20))
        }
    }

    private var deathOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).edgesIgnoringSafeArea(.all)
            VStack(spacing: 18) {
                Text("You were eaten!")
                    .font(.custom("UbuntuSans-Bold", size: 26)).foregroundColor(.white)
                Text("Score: \(highScore)")
                    .font(.custom("UbuntuSans-Bold", size: 18)).foregroundColor(.white.opacity(0.85))
                HStack(spacing: 14) {
                    Button(action: {
                        connectionPhase = .connecting
                        net.sendRespawn()
                    }) {
                        Text("Respawn")
                            .font(.custom("UbuntuSans-Bold", size: 18)).foregroundColor(.white)
                            .padding(.horizontal, 28).padding(.vertical, 12)
                            .background(Color.blue.cornerRadius(14))
                    }
                    Button(action: { leaveMatch() }) {
                        Text("Leave")
                            .font(.custom("UbuntuSans-Bold", size: 18)).foregroundColor(.white)
                            .padding(.horizontal, 28).padding(.vertical, 12)
                            .background(Color.red.opacity(0.85).cornerRadius(14))
                    }
                }
            }
            .padding(30)
            .background(Color(white: 0.12).cornerRadius(20))
        }
    }

    // MARK: session

    private func startSession() {
        TextSpriteCache.shared.warmUp()
        world.reset()
        consumeAnimations.removeAll()
        centerAimUntilCursorMoves = true
        connectionPhase = .connecting
        errorText = nil
        net.onMessage = { message in
            switch message {
            case .welcome:
                world.handle(message)
                connectionPhase = .connecting     // waiting for first snapshot
                highScore = 0
                // v5.8: feeder squads are per-life server-side (owner IDs
                // change on respawn) — re-request ours on every welcome.
                if spawnFeedBots {
                    net.sendFeedBots(count: 15, name: feedBotName, skin: feedBotSkinID)
                }
            case .rejected(let reason):
                errorText = reason
            case .disconnected(let reason):
                if connectionPhase != .dead { errorText = reason }
                connectionPhase = .connecting
            case .youDied:
                world.handle(message)
                connectionPhase = .dead
            default:
                world.handle(message)
            }
        }
        let party = sanitizedPartyCode(UserDefaults.standard.string(forKey: "macro.partyCode") ?? "")
        world.localPartyCode = party
        // Hello goes out the moment the socket is actually READY (not a fixed timer):
        // this is what carries name/skin/level/party to the server, and it used to be
        // lost when connecting took longer than 0.3s (e.g. the Local Network prompt).
        net.onReady = {
            net.sendHello(name: playerName, skin: selectedSkinName,
                          level: showPlayerLevel ? LeagueBadge.clamp(playerLevel) : -1,
                          party: party)
        }
        if let session = nearbySession {
            net.connect(transport: session.transport)   // nearby: Multipeer/loopback pipe
        } else {
            net.connect(host: host, port: port)
        }
        lastFrameTimestamp = 0
        displayLink.start()
    }

    private func leaveMatch() {
        net.sendLeave()
        net.disconnect()
        displayLink.stop()
        onExit()
    }

    private func pause() {
        guard connectionPhase == .playing, !isLeavePopupPresented else { return }
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
        sendInputNow()
    }

    private func resumeFromLeavePopup() {
        guard isLeavePopupPresented else { return }
        centerAimUntilCursorMoves = true
        lastJoystickDirection = .zero
        joystickIsDragging = false
        joystickOffset = .zero
        joystickBasePosition = nil
        ejectControlSession &+= 1
        isLeavePopupPresented = false
        sendInputNow()
    }

    private func canSplit() -> Bool {
        guard playerCells.count < 16 else { return false }
        return playerCells.contains(where: { $0.targetMass >= 40 })
    }

    private func canFeed() -> Bool {
        return playerCells.contains(where: { $0.targetMass >= 32 }) &&
        (centerAimUntilCursorMoves || lastJoystickDirection != .zero)
    }

    private func sendInputNow() {
        net.sendInput(dragging: joystickIsDragging,
                      centerAim: centerAimUntilCursorMoves,
                      joystick: joystickOffset,
                      lastDirection: lastJoystickDirection)
    }

    // MARK: - GAME TICK (render-side only; the server owns the simulation)

    private func gameTick(timestamp: CFTimeInterval, screenSize: CGSize) {
        let currentTime = CACurrentMediaTime()
        if showFPS {
            if lastFpsCheckTime == 0 { lastFpsCheckTime = currentTime; frameCount = 0 }
            frameCount += 1
            if currentTime - lastFpsCheckTime >= 1.0 {
                fps = frameCount; frameCount = 0; lastFpsCheckTime = currentTime
            }
        } else if frameCount != 0 || lastFpsCheckTime != 0 {
            frameCount = 0; lastFpsCheckTime = 0
        }

        var deltaTime: CGFloat = 1.0 / 60.0
        if lastFrameTimestamp > 0 {
            deltaTime = CGFloat(min(max(timestamp - lastFrameTimestamp, 0.0005), 0.05))
        }
        lastFrameTimestamp = timestamp

        updateDualSkinSwap(now: currentTime)
        updateRemoteSwaps(now: currentTime)

        // 1. advance the interpolated remote world
        world.advance(dt: deltaTime)
        playerCells = world.playerCells
        botCells = world.botCells
        viruses = world.viruses
        tokens = world.tokens
        botLevels = world.botLevels
        if !world.newlyEatenCells.isEmpty {
            animatingEatenCells.append(contentsOf: world.newlyEatenCells)
            world.newlyEatenCells.removeAll()
        }
        if !world.newlyConsumedPickups.isEmpty {
            consumeAnimations.append(contentsOf: world.newlyConsumedPickups)
            world.newlyConsumedPickups.removeAll()
        }
        if world.eatTriggeredSwap {
            world.eatTriggeredSwap = false
            triggerDualSkinSwap(now: currentTime)
        }
        if !world.remoteEatSwapOwners.isEmpty {
            for owner in world.remoteEatSwapOwners { triggerRemoteSwap(owner: owner, now: currentTime) }
            world.remoteEatSwapOwners.removeAll()
        }
        tokenCount = world.tokenPickups

        if connectionPhase == .connecting && !playerCells.isEmpty && errorText == nil {
            connectionPhase = .playing
            smoothedPlayerPosition = playerCenter
            smoothedTotalMass = totalPlayerMass
            cameraJumpOffset = .zero
            lastCameraTargetPos = nil
            lastCameraCellCount = playerCells.count
            zoomLevel = 1.0
        }
        guard connectionPhase == .playing else { return }

        // v5.9.5: score uses the server's AUTHORITATIVE total (leaderboard
        // sums targetMass) — summing rendered cell masses counted the split
        // parent's ease-down AND the new half at once, inflating the
        // high-water score by up to ~1.5x per split (online-only bug).
        let currTotalPlayerMass = CGFloat(world.myAuthoritativeMass ?? Double(totalPlayerMass))
        if currTotalPlayerMass > CGFloat(highScore) { highScore = Int(currTotalPlayerMass) }

        // 2. visual-only passes (identical maths to offline)
        updateVisibleObjects(screenSize: screenSize)
        updateCellDeformation(dt: deltaTime)
        world.persistVisualState(player: playerCells, bots: botCells)
        updateEatenCellsAnimation(dt: deltaTime)

        // 3. camera — exact copy of the offline behaviour
        let targetPos = playerCenter
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

        // 4. feed / macro cadence → network
        if !canFeed() {
            if isFeedingHeld { isFeedingHeld = false }
            if isMacroHeld { isMacroHeld = false }
            if feedHoldStartTime != nil { feedHoldStartTime = nil }
            if feedButtonScale != 1.0 || macroButtonScale != 1.0 {
                withAnimation { feedButtonScale = 1.0; macroButtonScale = 1.0 }
            }
        } else {
            if isFeedingHeld, let start = feedHoldStartTime,
               Date().timeIntervalSince(start) >= feedHoldThreshold {
                if feedButtonScale != 1.15 { withAnimation { feedButtonScale = 1.15 } }
                if currentTime - lastSpamFeedTime >= spamFeedInterval {
                    net.sendEject(times: 1)
                    lastSpamFeedTime = currentTime
                }
            } else if !isFeedingHeld, feedButtonScale != 1.0 {
                withAnimation { feedButtonScale = 1.0 }
            }
            if isMacroHeld {
                // Offline semantics are macroBullets every macroInterval.
                // Convert that to a continuous press rate and emit once per
                // display frame, preserving throughput but avoiding 15/30+
                // pellet snapshot clumps.
                let rate = Double(macroBullets) / max(macroInterval, 0.005)
                macroPressBudget += rate * Double(deltaTime)
                let due = min(60, Int(macroPressBudget))
                if due > 0 {
                    net.sendEject(times: due)
                    macroPressBudget -= Double(due)
                    lastMacroFeedTime = currentTime
                }
            }
        }

        // 5. input stream at 60Hz + keepalive ping
        inputSendAccumulator += deltaTime
        if inputSendAccumulator >= 1.0 / 60.0 {
            inputSendAccumulator = 0
            sendInputNow()
        }
        pingAccumulator += deltaTime
        if pingAccumulator >= 2.0 {
            pingAccumulator = 0
            net.sendPing()
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
        let targetZoom = ((baseZoom / spreadFactor) / cellCountFactor) * customZoomMultiplier
        let zoomSmooth = getLerpFactor(base: 0.06, dt: dt)
        zoomLevel += (targetZoom - zoomLevel) * zoomSmooth
    }

    private func updateVisibleObjects(screenSize: CGSize) {
        let cameraOffsetX = -smoothedPlayerPosition.x * zoomLevel + screenSize.width / 2
        let cameraOffsetY = -smoothedPlayerPosition.y * zoomLevel + screenSize.height / 2
        visibleWorldRect = CGRect(
            origin: CGPoint(x: (0 - cameraOffsetX) / zoomLevel, y: (0 - cameraOffsetY) / zoomLevel),
            size: CGSize(width: screenSize.width / zoomLevel, height: screenSize.height / zoomLevel)
        ).insetBy(dx: -400, dy: -400)
    }

    private func triggerDualSkinSwap(now: TimeInterval) {
        guard DualSkinCatalog.shared.isDual(selectedSkinName) else { return }
        guard dualSkinSwapPhase == .idle else { return }
        dualSkinSwapPhase = .showing
        dualSkinSwapStartedAt = now
        dualSkinSwapPhaseEndsAt = now + DualSkin.altShowDuration
    }

    // v5 skin sync: remote humans' eat-swap machines (idle -> showing -> cooldown).
    private func triggerRemoteSwap(owner: UUID, now: TimeInterval) {
        guard remoteSwapPhase[owner, default: .idle] == .idle else { return }
        remoteSwapPhase[owner] = .showing
        remoteSwapStartedAt[owner] = now
        remoteSwapEndsAt[owner] = now + DualSkin.altShowDuration
    }

    private func updateRemoteSwaps(now: TimeInterval) {
        guard !remoteSwapPhase.isEmpty else { return }
        for (owner, phase) in remoteSwapPhase {
            switch phase {
            case .idle:
                // prune stale entries (owner left / long idle)
                if now - (remoteSwapStartedAt[owner] ?? now) > 30 {
                    remoteSwapPhase[owner] = nil
                    remoteSwapStartedAt[owner] = nil
                    remoteSwapEndsAt[owner] = nil
                }
            case .showing:
                if now >= remoteSwapEndsAt[owner, default: 0] {
                    remoteSwapPhase[owner] = .cooldown
                    remoteSwapEndsAt[owner] = now + DualSkin.retriggerDelay
                }
            case .cooldown:
                if now >= remoteSwapEndsAt[owner, default: 0] {
                    remoteSwapPhase[owner] = .idle
                }
            }
        }
    }

    private func remoteSwapShowingByOwner() -> [UUID: TimeInterval] {
        var map: [UUID: TimeInterval] = [:]
        for (owner, phase) in remoteSwapPhase where phase == .showing {
            map[owner] = remoteSwapStartedAt[owner]
        }
        return map
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

    private func updateEatenCellsAnimation(dt: CGFloat) {
        // The pickup magnet-suck shares the eaten-cell glide factor exactly.
        updateConsumedPickupAnimations(&consumeAnimations,
                                       playerCells: playerCells,
                                       botCells: botCells,
                                       glideSpeedFactor: getLerpFactor(base: 0.18, dt: dt),
                                       dt: dt)
        guard !animatingEatenCells.isEmpty else { return }
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
                let dx = tPos.x - animatingEatenCells[i].position.x
                let dy = tPos.y - animatingEatenCells[i].position.y
                let distanceSq = dx * dx + dy * dy
                if distanceSq < (targetRad * targetRad * 0.64) || distanceSq < 100.0 || animatingEatenCells[i].mass < 1.0 {
                    animatingEatenCells.swapAt(i, animatingEatenCells.count - 1)
                    animatingEatenCells.removeLast()
                } else {
                    animatingEatenCells[i].position.x += dx * glideSpeedFactor
                    animatingEatenCells[i].position.y += dy * glideSpeedFactor
                    animatingEatenCells[i].mass *= (1.0 - glideSpeedFactor)
                    animatingEatenCells[i].lagMass *= (1.0 - glideSpeedFactor)
                    animatingEatenCells[i].refreshCachedRadii()
                }
            } else {
                animatingEatenCells.swapAt(i, animatingEatenCells.count - 1)
                animatingEatenCells.removeLast()
            }
            i -= 1
        }
    }

    /// Exact copy of the offline deformation pass, applied to the interpolated
    /// remote cells (squish against pellets and arena walls — visual only).
    private func updateCellDeformation(dt: CGFloat) {
        let worldSize: CGFloat = 11000
        let visRect = visibleWorldRect
        let relax = 1.0 - pow(0.05, dt)

        func lerpValue(start: CGFloat, end: CGFloat, t: CGFloat) -> CGFloat {
            return start + (end - start) * t
        }

        func processDeformation(cells: inout [PlayerCell]) {
            let count = cells.count
            guard count > 0 else { return }
            let targetVertexCount = max(20, 128 / max(1, count))
            let trig = TrigCache.get(count: targetVertexCount)
            var objectBuf = [CGFloat](repeating: 0, count: targetVertexCount)
            var smoothBuf = [CGFloat](repeating: 0, count: targetVertexCount)
            var tmpBuf = [CGFloat](repeating: 0, count: targetVertexCount)
            let zeroBuf = [CGFloat](repeating: 0, count: targetVertexCount)

            for i in cells.indices {
                let pos = cells[i].position
                let visualRadius = cells[i].cachedSolidRadius

                if cells[i].skinDeformation.count != targetVertexCount {
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

                if !onScreen || (!complexIndentations && !nearWall) {
                    guard cells[i].hasActiveDeformation else { continue }
                    var stillActive = false
                    for v in 0..<targetVertexCount {
                        let d = cells[i].skinDeformation[v]
                        let relaxed = d > 0.01 ? lerpValue(start: d, end: 0.0, t: relax) : 0
                        cells[i].skinDeformation[v] = relaxed
                        if relaxed > 0.01 { stillActive = true }
                    }
                    cells[i].hasActiveDeformation = stillActive
                    continue
                }

                let maxCompression = visualRadius * 3.0
                for v in 0..<targetVertexCount {
                    cells[i].skinDeformation[v] = lerpValue(start: cells[i].skinDeformation[v], end: 0.0, t: relax)
                }

                var nearbyMass: [EjectedMass] = []
                if complexIndentations {
                    let searchRadius = visualRadius + 100
                    let searchRect = CGRect(x: pos.x - searchRadius, y: pos.y - searchRadius,
                                            width: searchRadius * 2, height: searchRadius * 2)
                    nearbyMass = world.massManager.getLimitedVisibleMassesArray(in: searchRect, limit: 12)
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

        processDeformation(cells: &playerCells)
        processDeformation(cells: &botCells)
    }
}
