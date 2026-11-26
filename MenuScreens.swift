//
//  MenuScreens.swift — Authentic 1:1 Agar.io mobile modals (Shop, Quests,
//  Potions + Potion Opening Minigame, Gifts/News, Match Results) using
//  Cocos2d design scaling, explicit 9-slice MCFSFrame cap-insets, and real assets.
//

import SwiftUI

struct AgarBevelButtonStyle: View {
    let fill: Color
    let bevel: Color
    var cornerRadius: CGFloat = 12
    var isPressed: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(bevel)
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(fill)
                .padding(.bottom, isPressed ? 1 : 4)
                .offset(y: isPressed ? 3 : 0)
        }
    }
}

struct AgarBevelPressStyle: ButtonStyle {
    let fill: Color
    let bevel: Color
    var cornerRadius: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? 2.5 : 0)
            .background(AgarBevelButtonStyle(fill: fill, bevel: bevel, cornerRadius: cornerRadius, isPressed: configuration.isPressed))
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct AgarModalContainer<Content: View>: View {
    let dismissOnBackdrop: Bool
    let onClose: () -> Void
    @ViewBuilder let content: (_ triggerClose: @escaping () -> Void) -> Content

    @State private var appeared = false

    private func triggerClose() {
        withAnimation(.easeIn(duration: 0.14)) {
            appeared = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            onClose()
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(appeared ? 0.65 : 0.0)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    if dismissOnBackdrop { triggerClose() }
                }
            content(triggerClose)
                .scaleEffect(appeared ? 1.0 : 0.92)
                .opacity(appeared ? 1.0 : 0.0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                appeared = true
            }
        }
    }
}

enum ShopTab: String, CaseIterable {
    case coins = "Coins"
    case dna = "DNA"
    case potions = "Potions"
    case skins = "Skins"
    case boosts = "Mass"
    case xp = "XP"
}

struct MCFSBevelStyle: ButtonStyle {
    let frameAsset: String
    var showShadow: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? 1.5 : 0)
            .background(
                ZStack(alignment: .bottom) {
                    if showShadow {
                        MCFSFrame(name: "mcfs-shadow")
                            .frame(height: 24)
                            .offset(y: configuration.isPressed ? 1.0 : 3.0)
                    }
                    MCFSFrame(name: frameAsset)
                }
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

// MARK: - MenuShop.ccbi (6-Category Hub + Detail Grids, Full-Screen 1:1)
struct ShopModalView: View {
    @Binding var coins: Int
    @Binding var dna: Int
    @Binding var activeStartBoost: Int
    var onOpenPotions: (() -> Void)? = nil
    var onOpenSkins: (() -> Void)? = nil
    let onClose: () -> Void

    @State private var selectedSection: ShopTab? = nil
    @State private var statusMessage: String = ""

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        GeometryReader { geometry in
            let s = max(1.0, min(OriginalGameplay.uiScale(for: geometry.size), geometry.size.width / 460.0))

            ZStack {
                Color.white.edgesIgnoringSafeArea(.all)

                VStack(spacing: 0) {
                    genericFullHeader(
                        title: selectedSection == nil ? "Shop" : (selectedSection == .xp || selectedSection == .boosts ? "Boosts" : selectedSection!.rawValue),
                        coins: coins,
                        dna: dna,
                        scale: s
                    ) {
                        if selectedSection != nil {
                            withAnimation(.easeOut(duration: 0.15)) {
                                selectedSection = nil
                                statusMessage = ""
                            }
                        } else {
                            onClose()
                        }
                    }

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.custom("OpenSans-Bold", size: 12 * s))
                            .foregroundColor(Color(hex: 0x43A81D))
                            .padding(.vertical, 5 * s)
                            .frame(maxWidth: .infinity)
                            .background(Color(hex: 0xF2F5F8))
                    }

                    if let section = selectedSection {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 10 * s) {
                                switch section {
                                case .boosts, .xp:
                                    shopTile(icon: "ui-mass-20", title: "+20 Start Mass", subtitle: "Start match bigger", cost: 150, costIsDNA: false, scale: s) {
                                        activeStartBoost = 20
                                        statusMessage = "Equipped +20 Start Mass!"
                                    }
                                    shopTile(icon: "ui-mass-40", title: "+40 Start Mass", subtitle: "Start match huge", cost: 300, costIsDNA: false, scale: s) {
                                        activeStartBoost = 40
                                        statusMessage = "Equipped +40 Start Mass!"
                                    }
                                    shopTile(icon: "shop-mass-2x", title: "2x Mass Boost", subtitle: "Double mass gain", cost: 250, costIsDNA: false, scale: s) {
                                        statusMessage = "2x Mass Boost activated!"
                                    }
                                    shopTile(icon: "shop-mass-3x", title: "3x Mass Boost", subtitle: "Triple mass gain", cost: 25, costIsDNA: true, scale: s) {
                                        statusMessage = "3x Mass Boost activated!"
                                    }
                                    shopTile(icon: "shop-xp-2x", title: "2x XP Boost", subtitle: "Double XP gain", cost: 200, costIsDNA: false, scale: s) {
                                        statusMessage = "2x XP Boost activated!"
                                    }
                                    shopTile(icon: "shop-xp-3x", title: "3x XP Boost", subtitle: "Triple XP gain", cost: 20, costIsDNA: true, scale: s) {
                                        statusMessage = "3x XP Boost activated!"
                                    }
                                case .coins:
                                    shopTile(icon: "shop-coins", title: "Coin Pouch", subtitle: "+500 Coins", cost: 10, costIsDNA: true, iconScale: 0.9, scale: s) {
                                        coins += 500
                                        statusMessage = "Added +500 Coins!"
                                    }
                                    shopTile(icon: "shop-coins", title: "Coin Stack", subtitle: "+1,500 Coins", cost: 25, costIsDNA: true, iconScale: 1.05, scale: s) {
                                        coins += 1500
                                        statusMessage = "Added +1,500 Coins!"
                                    }
                                    shopTile(icon: "shop-coins", title: "Coin Chest", subtitle: "+4,000 Coins", cost: 60, costIsDNA: true, iconScale: 1.15, scale: s) {
                                        coins += 4000
                                        statusMessage = "Added +4,000 Coins!"
                                    }
                                case .dna:
                                    shopTile(icon: "shop-dna", title: "DNA Vial", subtitle: "+15 DNA", cost: 250, costIsDNA: false, iconScale: 0.9, scale: s) {
                                        dna += 15
                                        statusMessage = "Added +15 DNA!"
                                    }
                                    shopTile(icon: "shop-dna", title: "DNA Flask", subtitle: "+40 DNA", cost: 600, costIsDNA: false, iconScale: 1.05, scale: s) {
                                        dna += 40
                                        statusMessage = "Added +40 DNA!"
                                    }
                                    shopTile(icon: "shop-dna", title: "DNA Crate", subtitle: "+100 DNA", cost: 1400, costIsDNA: false, iconScale: 1.15, scale: s) {
                                        dna += 100
                                        statusMessage = "Added +100 DNA!"
                                    }
                                case .potions, .skins:
                                    EmptyView()
                                }
                            }
                            .padding(14 * s)
                        }
                        .background(MCFSFrame(name: "mcfs-gray"))
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)

                if selectedSection == nil {
                    CCBISceneView(
                        ccbFile: "MenuShop.ccbi",
                        context: CCBIBindingContext(
                            actions: [
                                "backButtonCallback": onClose,
                                "_backButton": onClose,
                                "coinsButtonCallback": { withAnimation(.easeOut(duration: 0.15)) { selectedSection = .coins } },
                                "_coinsShop": { withAnimation(.easeOut(duration: 0.15)) { selectedSection = .coins } },
                                "dnaButtonCallback": { withAnimation(.easeOut(duration: 0.15)) { selectedSection = .dna } },
                                "_dnaShop": { withAnimation(.easeOut(duration: 0.15)) { selectedSection = .dna } },
                                "potionsButtonCallback": {
                                    if let onOpenPotions = onOpenPotions { onOpenPotions() }
                                    else { onClose() }
                                },
                                "_potionsShop": {
                                    if let onOpenPotions = onOpenPotions { onOpenPotions() }
                                    else { onClose() }
                                },
                                "skinsButtonCallback": {
                                    if let onOpenSkins = onOpenSkins { onOpenSkins() }
                                    else { onClose() }
                                },
                                "_skinsShop": {
                                    if let onOpenSkins = onOpenSkins { onOpenSkins() }
                                    else { onClose() }
                                },
                                "massButtonCallback": { withAnimation(.easeOut(duration: 0.15)) { selectedSection = .boosts } },
                                "_massShop": { withAnimation(.easeOut(duration: 0.15)) { selectedSection = .boosts } },
                                "xpButtonCallback": { withAnimation(.easeOut(duration: 0.15)) { selectedSection = .xp } },
                                "_xpShop": { withAnimation(.easeOut(duration: 0.15)) { selectedSection = .xp } }
                            ],
                            labelOverrides: [
                                "_coinBar._barCurrencyValue": "\(coins)",
                                "_dnaBar._barCurrencyValue": "\(dna)"
                            ],
                            visibilityOverrides: [
                                "_vipSubscriptionButton": false,
                                "_coinsRedBadge": false,
                                "_dnaRedBadge": false,
                                "_potionsRedBadge": false,
                                "_skinsRedBadge": false,
                                "_massRedBadge": false,
                                "_xpRedBadge": false
                            ]
                        )
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
    }

    private func shopCategoryCard(icon: String, title: String, accent: Color, scale s: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: {
            SoundManager.shared.play(.menuClick)
            action()
        }) {
            VStack(spacing: 6 * s) {
                Image(icon)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 52 * s)
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 13.5 * s))
                    .foregroundColor(Color(hex: 0x3D4347))
                    .padding(.horizontal, 10 * s)
                    .padding(.vertical, 2.5 * s)
                    .background(Capsule().fill(accent.opacity(0.14)))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 94 * s)
            .background(
                ZStack(alignment: .bottom) {
                    MCFSFrame(name: "mcfs-shadow")
                        .frame(height: 22 * s)
                        .offset(y: 3 * s)
                    MCFSFrame(name: "mcfs-white")
                }
            )
        }
    }

    private func shopTile(icon: String, title: String, subtitle: String, cost: Int, costIsDNA: Bool, iconScale: CGFloat = 1.0, scale s: CGFloat, onBuy: @escaping () -> Void) -> some View {
        let canAfford = costIsDNA ? dna >= cost : coins >= cost
        return VStack(spacing: 6 * s) {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 46 * s, height: 38 * s)
                .scaleEffect(iconScale)
                .padding(.top, 4 * s)

            Text(title)
                .font(.custom("OpenSans-Bold", size: 11.5 * s))
                .foregroundColor(Color(hex: 0x3D4347))
                .multilineTextAlignment(.center)
                .lineLimit(1)

            Text(subtitle)
                .font(.custom("Lato-Regular", size: 10 * s))
                .foregroundColor(Color(hex: 0x6E767E))
                .multilineTextAlignment(.center)
                .lineLimit(1)

            Button(action: {
                guard canAfford else { statusMessage = "Not enough \(costIsDNA ? "DNA" : "Coins")"; return }
                SoundManager.shared.play(.menuClick)
                if costIsDNA { dna -= cost } else { coins -= cost }
                onBuy()
            }) {
                HStack(spacing: 4 * s) {
                    Image(costIsDNA ? "shop-dna-s" : "shop-coins-s").resizable().scaledToFit().frame(width: 14 * s, height: 14 * s)
                    Text("\(cost)")
                        .font(.custom("OpenSans-Bold", size: 11.5 * s))
                        .foregroundColor(.white)
                        .shadow(color: Color.black.opacity(0.35), radius: 0, x: 0, y: 1)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 27 * s)
            }
            .buttonStyle(MCFSBevelStyle(frameAsset: canAfford ? "mcfs-green" : "mcfs-orange"))
        }
        .padding(8 * s)
        .background(MCFSFrame(name: "mcfs-white"))
    }
}

// MARK: - MenuQuestTracker.ccbi (Full-Screen 1:1)
struct QuestsModalView: View {
    @Binding var coins: Int
    @Binding var dna: Int
    let onClose: () -> Void

    @AppStorage("macro.quest1Claimed") private var q1Claimed: Bool = false
    @AppStorage("macro.quest2Claimed") private var q2Claimed: Bool = false
    @AppStorage("macro.quest3Claimed") private var q3Claimed: Bool = false
    @AppStorage("macro.questChestClaimed") private var chestClaimed: Bool = false
    @AppStorage("macro.offlineQuestStage") private var offlineQuestStage: Int = 0
    @AppStorage("macro.offlineQuestProgress") private var offlineQuestProgress: Int = 0

    private var claimedCount: Int {
        (q1Claimed ? 1 : 0) + (q2Claimed ? 1 : 0) + (q3Claimed ? 1 : 0)
    }

    var body: some View {
        GeometryReader { geometry in
            let s = max(1.0, min(OriginalGameplay.uiScale(for: geometry.size), geometry.size.width / 460.0))

            ZStack {
                Color(hex: 0xF2F5F8).edgesIgnoringSafeArea(.all)

                VStack(spacing: 0) {
                    genericFullHeader(title: "Daily Quests", coins: coins, dna: dna, scale: s, onClose: onClose)

                    ScrollView {
                        VStack(spacing: 10 * s) {
                            // MenuQuestTracker.ccbi Milestone Chest Banner with BG_MicroWorld
                            HStack(spacing: 12 * s) {
                                Image("quest-chest")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 50 * s, height: 50 * s)

                                VStack(alignment: .leading, spacing: 5 * s) {
                                    HStack {
                                        Text("Daily Milestone Chest")
                                            .font(.custom("OpenSans-Bold", size: 13.5 * s))
                                            .foregroundColor(.white)
                                            .shadow(color: .black.opacity(0.45), radius: 0, x: 0, y: 1)
                                        Spacer()
                                        Text("\(claimedCount) / 3")
                                            .font(.custom("OpenSans-Bold", size: 12 * s))
                                            .foregroundColor(.white)
                                    }

                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            MCFSFrame(name: "mcfs-hud-xp-box")
                                            MCFSFrame(name: "mcfs-hud-xp")
                                                .frame(width: max(0, geo.size.width * CGFloat(claimedCount) / 3.0))
                                                .animation(.easeOut(duration: 0.25), value: claimedCount)
                                        }
                                    }
                                    .frame(height: 12 * s)
                                }

                                if chestClaimed {
                                    Image("ui-quest-check").resizable().scaledToFit().frame(width: 26 * s, height: 26 * s)
                                } else {
                                    Button(action: {
                                        guard claimedCount >= 3 else { return }
                                        SoundManager.shared.play(.menuClick)
                                        chestClaimed = true
                                        coins += 500
                                        dna += 25
                                    }) {
                                        Text("Claim Chest")
                                            .font(.custom("OpenSans-Bold", size: 11 * s))
                                            .foregroundColor(.white)
                                            .shadow(color: Color.black.opacity(0.35), radius: 0, x: 0, y: 1)
                                            .padding(.horizontal, 12 * s)
                                            .frame(height: 30 * s)
                                    }
                                    .disabled(claimedCount < 3)
                                    .opacity(claimedCount >= 3 ? 1.0 : 0.55)
                                    .buttonStyle(MCFSBevelStyle(frameAsset: "mcfs-green"))
                                }
                            }
                            .padding(12 * s)
                            .background(
                                ZStack {
                                    Image("quest-microworld-bg")
                                        .resizable()
                                        .scaledToFill()
                                        .clipped()
                                    Color(hex: 0x0A2540).opacity(0.35)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 8 * s))
                            )

                            let foodProg = min(100, offlineQuestProgress + 100 * offlineQuestStage)
                            sideQuestTile(
                                title: "Eat 100 food pellets",
                                progress: q1Claimed ? 100 : foodProg,
                                target: 100,
                                rewardIcon: "shop-coins-s",
                                rewardText: "+250",
                                claimed: q1Claimed,
                                scale: s
                            ) {
                                q1Claimed = true; coins += 250
                            }

                            sideQuestTile(
                                title: "Survive 3 minutes",
                                progress: q2Claimed ? 180 : 180,
                                target: 180,
                                rewardIcon: "shop-coins-s",
                                rewardText: "+300",
                                claimed: q2Claimed,
                                scale: s
                            ) {
                                q2Claimed = true; coins += 300
                            }

                            sideQuestTile(
                                title: "Split 15 times",
                                progress: q3Claimed ? 15 : 15,
                                target: 15,
                                rewardIcon: "shop-dna-s",
                                rewardText: "+25",
                                claimed: q3Claimed,
                                scale: s
                            ) {
                                q3Claimed = true; dna += 25
                            }
                        }
                        .padding(14 * s)
                    }
                    .background(MCFSFrame(name: "mcfs-gray"))
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }

    private func sideQuestTile(title: String, progress: Int, target: Int, rewardIcon: String, rewardText: String, claimed: Bool, scale s: CGFloat, onClaim: @escaping () -> Void) -> some View {
        let ratio = min(1.0, max(0.0, CGFloat(progress) / CGFloat(max(1, target))))
        return HStack(spacing: 10 * s) {
            VStack(alignment: .leading, spacing: 5 * s) {
                Text(title).font(.custom("OpenSans-Bold", size: 12.5 * s)).foregroundColor(Color(hex: 0x3D4347))

                GeometryReader { geo in
                    ZStack {
                        Capsule().fill(Color(hex: 0xDCE3EC))
                        HStack(spacing: 0) {
                            Capsule()
                                .fill(Color(hex: 0x00C8F8))
                                .frame(width: geo.size.width * ratio)
                            Spacer(minLength: 0)
                        }
                        Text("\(min(progress, target)) / \(target)")
                            .font(.custom("OpenSans-Bold", size: 10 * s))
                            .foregroundColor(Color(hex: 0x3D4347))
                    }
                }
                .frame(height: 15 * s)
            }

            HStack(spacing: 4 * s) {
                Image(rewardIcon).resizable().scaledToFit().frame(width: 14 * s, height: 14 * s)
                Text(rewardText).font(.custom("OpenSans-Bold", size: 11.5 * s)).foregroundColor(Color(hex: 0x3D4347))
            }
            .padding(.horizontal, 8 * s)
            .padding(.vertical, 4 * s)
            .background(MCFSFrame(name: "mcfs-white-green"))

            if claimed {
                Image("ui-quest-check").resizable().scaledToFit().frame(width: 24 * s, height: 24 * s)
            } else {
                Button(action: {
                    SoundManager.shared.play(.menuClick)
                    onClaim()
                }) {
                    Text("Claim")
                        .font(.custom("OpenSans-Bold", size: 11.5 * s))
                        .foregroundColor(.white)
                        .shadow(color: Color.black.opacity(0.35), radius: 0, x: 0, y: 1)
                        .padding(.horizontal, 12 * s)
                        .frame(height: 28 * s)
                }
                .buttonStyle(MCFSBevelStyle(frameAsset: "mcfs-green"))
            }
        }
        .padding(9 * s)
        .background(MCFSFrame(name: "mcfs-white"))
    }
}

// MARK: - MenuMysteryPotions.ccbi + PotionSlot.ccbi + MenuMysteryPotionMinigame_v2.ccbi
struct PotionsModalView: View {
    @Binding var coins: Int
    @Binding var dna: Int
    let onClose: () -> Void

    @ObservedObject private var potionStore = PotionStore.shared
    @State private var nowTimestamp: TimeInterval = Date().timeIntervalSince1970
    @State private var statusBanner: String = "Brew Mystery Potions to unlock Coins, DNA & Skin Pieces!"
    @State private var activeReward: PotionReward? = nil
    @State private var showHelpModal: Bool = false

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geometry in
            let s = max(0.75, geometry.size.height / 320.0)
            let sideInset = max(geometry.safeAreaInsets.leading, geometry.safeAreaInsets.trailing)

            ZStack {
                Color.white.edgesIgnoringSafeArea(.all)

                // Exact MenuMysteryPotions.ccbi header, currency bars, help button, subtitle, footer
                CCBISceneView(
                    ccbFile: "MenuMysteryPotions.ccbi",
                    context: CCBIBindingContext(
                        actions: [
                            "backButtonCallback": onClose,
                            "helpButtonCallback": {
                                withAnimation(.easeInOut(duration: 0.16)) { showHelpModal = true }
                            },
                            "coinBarCallback": {},
                            "DNABarCallback": {}
                        ],
                        labelOverrides: [
                            "_coinBar._barCurrencyValue": "\(coins)",
                            "_dnaBar._barCurrencyValue": "\(dna)",
                            "_subtitleLabel": statusBanner
                        ]
                    )
                )
                .padding(.horizontal, sideInset)

                // PotionSlot.ccbi 4 pedestal slots centered in MenuMysteryPotions body band (y=74..294 of 320)
                HStack(spacing: 8 * s) {
                    ForEach(potionStore.slots) { slot in
                        potionCCBICard(slot: slot, scale: s)
                    }
                }
                .padding(.horizontal, max(12 * s, sideInset + 10))
                .padding(.top, 74 * s)
                .padding(.bottom, 26 * s)
                .frame(width: geometry.size.width, height: geometry.size.height)

                if let reward = activeReward {
                    PotionOpeningMinigameView(reward: reward, s: s, containerSize: geometry.size) {
                        withAnimation { activeReward = nil }
                    }
                    .zIndex(5)
                }

                if showHelpModal {
                    PotionsHelpOverlayView(s: s, containerSize: geometry.size) {
                        withAnimation(.easeInOut(duration: 0.15)) { showHelpModal = false }
                    }
                    .zIndex(6)
                }
            }
            .onReceive(ticker) { date in
                nowTimestamp = date.timeIntervalSince1970
            }
        }
    }

    private func potionCCBICard(slot: PotionSlotState, scale s: CGFloat) -> some View {
        let tier = slot.tier
        let isReady = slot.isReady(now: nowTimestamp)
        let isBrewing = slot.isBrewing(now: nowTimestamp)
        let isStored = (tier != nil && !isReady && !isBrewing)
        let isEmpty = (tier == nil)
        let rem = Int(ceil(slot.remainingSeconds(now: nowTimestamp)))
        let rushCost = slot.rushDNACost(now: nowTimestamp)

        let timerString: String = {
            if isBrewing { return String(format: "%02d:%02d", rem / 60, rem % 60) }
            if let t = tier { return "\(Int(t.brewDurationSeconds / 60))m" }
            return ""
        }()

        let vis: [String: Bool] = [
            "_emptyNode": isEmpty,
            "_collectedNode": isStored,
            "_brewingNode": isBrewing,
            "_readyNode": isReady,
            "_busyNode": false,
            "_ftueBackgroundNode": false,
            "_accelerateBrewingButton": false,
            "_doubleOpenReadyButton": false,
            "_hoursNode": (tier != nil && !isReady),
            "_potionTypeLabel": (tier != nil)
        ]

        let labels: [String: String] = [
            "_headerTimerLabel": timerString,
            "_brewingTimer": timerString,
            "_brewingNodeButtonLabel": "\(rushCost)",
            "_potionTypeLabel": tier?.rawValue ?? ""
        ]

        let slots: [String: AnyView] = tier != nil ? [
            "_potionParentNode": AnyView(
                Image(tier!.iconAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56 * s, height: 70 * s)
            )
        ] : [:]

        let actions: [String: () -> Void] = [
            "getMoreButtonCallback": {
                if potionStore.collectSamplePotion() {
                    statusBanner = "Found a Mystery Potion! Tap Brew to start."
                }
            },
            "startButtonCallback": {
                potionStore.startBrew(slotIndex: slot.id, now: nowTimestamp)
                if let t = tier { statusBanner = "Brewing \(t.rawValue) Potion!" }
            },
            "openNowButtonCallback": {
                if potionStore.rushWithDNA(slotIndex: slot.id, dna: &dna, now: nowTimestamp),
                   let reward = potionStore.openPotion(slotIndex: slot.id, coins: &coins, dna: &dna, now: nowTimestamp) {
                    statusBanner = "Rushed \(reward.tier.rawValue) Potion: +\(reward.coins) Coins & +\(reward.dna) DNA!"
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                        activeReward = reward
                    }
                } else {
                    statusBanner = "Need \(rushCost) DNA to open immediately!"
                }
            },
            "openButtonCallback": {
                if let reward = potionStore.openPotion(slotIndex: slot.id, coins: &coins, dna: &dna, now: nowTimestamp) {
                    statusBanner = "Opened \(reward.tier.rawValue) Potion: +\(reward.coins) Coins & +\(reward.dna) DNA!"
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                        activeReward = reward
                    }
                }
            }
        ]

        return CCBISceneView(
            ccbFile: "PotionSlot.ccbi",
            context: CCBIBindingContext(
                actions: actions,
                labelOverrides: labels,
                visibilityOverrides: vis,
                slotViews: slots,
                designScaleModifier: { _ in s }
            )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PotionsHelpOverlayView: View {
    let s: CGFloat
    let containerSize: CGSize
    let onClose: () -> Void

    @State private var selectedTab: Int = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).edgesIgnoringSafeArea(.all).onTapGesture { onClose() }

            CCBISceneView(
                ccbFile: "MenuPotionsHelpSection.ccbi",
                context: CCBIBindingContext(
                    actions: [
                        "backButtonCallback": onClose,
                        "howToGetPotionsButtonCallback": { selectedTab = 0 },
                        "rewardsButtonCallback": { selectedTab = 1 },
                        "mysterySkinsButtonCallback": { selectedTab = 2 }
                    ],
                    visibilityOverrides: [
                        "_howToNode": selectedTab == 0,
                        "_rewardsNode": selectedTab == 1,
                        "_mysteryNode": selectedTab == 2,
                        "_probabilitiesButtonContainer": false
                    ],
                    slotViews: [
                        "_potionAlignmentNode": AnyView(
                            HStack(spacing: 8 * s) {
                                ForEach([PotionTier.common, .rare, .epic, .exotic, .legendary], id: \.rawValue) { t in
                                    Image(t.iconAsset).resizable().scaledToFit().frame(height: 34 * s)
                                }
                            }
                        ),
                        "_skinUnlock": AnyView(
                            HStack(spacing: 6 * s) {
                                SkinSelectorPreview(skinName: "42").frame(width: 44 * s, height: 44 * s)
                                Image("potion-skinpiece").resizable().scaledToFit().frame(height: 22 * s)
                            }
                        ),
                        "_skinUpgrade": AnyView(
                            HStack(spacing: 6 * s) {
                                SkinSelectorPreview(skinName: "88").frame(width: 44 * s, height: 44 * s)
                                Image("potion-arrow-up-green").resizable().scaledToFit().frame(height: 22 * s)
                            }
                        ),
                        "_tableContainer": AnyView(
                            VStack(spacing: 4 * s) {
                                ForEach([PotionTier.common, .rare, .exotic, .epic, .legendary], id: \.rawValue) { t in
                                    HStack {
                                        Text(t.rawValue).font(.custom("OpenSans-Bold", size: 10.5 * s)).foregroundColor(t.badgeColor)
                                        Spacer()
                                        Text("\(Int(t.brewDurationSeconds / 60))m").font(.custom("Lato-Regular", size: 10 * s)).foregroundColor(Color(hex: 0x5A5F66))
                                    }
                                    .padding(.horizontal, 10 * s)
                                }
                            }
                        )
                    ]
                )
            )
            .frame(width: containerSize.width, height: containerSize.height)
        }
    }
}

/// MenuMysteryPotionMinigame_v2.ccbi — Native CCBI step-by-step potion reward reveal
private struct PotionOpeningMinigameView: View {
    let reward: PotionReward
    let s: CGFloat
    let containerSize: CGSize
    let onCollect: () -> Void

    @State private var revealStage: Int = 0

    private func advanceReveal() {
        SoundManager.shared.play(.menuClick)
        if revealStage < 3 {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.7)) {
                revealStage += 1
            }
        } else {
            onCollect()
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).edgesIgnoringSafeArea(.all)

            CCBISceneView(
                ccbFile: "MenuMysteryPotionMinigame_v2.ccbi",
                context: CCBIBindingContext(
                    actions: [
                        "backButtonCallback": onCollect,
                        "checkSkinsButtonCallback": advanceReveal,
                        "skipToNextReward": advanceReveal
                    ],
                    labelOverrides: [
                        "_potionTypeText": "\(reward.tier.rawValue) Potion",
                        "_rewardsNumberText": "\(revealStage == 0 ? 3 : max(0, 3 - revealStage))",
                        "_coinsText": "+\(reward.coins)",
                        "_dnaText": "+\(reward.dna)",
                        "_skinsText": "+\(reward.skinPieces)",
                        "_numberOfPiecesWonText": "+\(reward.skinPieces) Pieces",
                        "_checkSkinsButtonText": revealStage == 0 ? "Tap to Open!" : (revealStage < 3 ? "Next (\(revealStage)/3)" : "Collect")
                    ],
                    visibilityOverrides: [
                        "_facebookButton": false,
                        "_twitterButton": false,
                        "_genericRewardedNode": false,
                        "_battleSkinsNode": false,
                        "_seasonSkinsNode": false,
                        "_boostNode": false,
                        "_boostNode2": false,
                        "_trophiesNode": false,
                        "_seasonTokensNode": false,
                        "_extraRewardVideoNode": false,
                        "_coinsNode": revealStage >= 1,
                        "_dnaNode": revealStage >= 2,
                        "_skinsNode": revealStage >= 3,
                        "_skinRewardedNode": revealStage >= 3,
                        "_specialSkinsText": false
                    ],
                    slotViews: [
                        "_visualPotion": AnyView(
                            Image(reward.tier.iconAsset)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 78 * s, height: 96 * s)
                                .scaleEffect(revealStage > 0 ? 1.08 : 0.92)
                        ),
                        "_coinsImageNode": AnyView(Image("shop-coins-s").resizable().scaledToFit().frame(width: 24 * s, height: 24 * s)),
                        "_dnaImageNode": AnyView(Image("shop-dna-s").resizable().scaledToFit().frame(width: 24 * s, height: 24 * s)),
                        "_normalSkinImageNode": AnyView(SkinSelectorPreview(skinName: reward.skinName).frame(width: 28 * s, height: 28 * s)),
                        "_rewardedSkinImageNode": AnyView(SkinSelectorPreview(skinName: reward.skinName).frame(width: 58 * s, height: 58 * s))
                    ]
                )
            )
            .frame(width: containerSize.width, height: containerSize.height)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                if revealStage == 0 {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) { revealStage = 1 }
                }
            }
        }
    }
}

struct GiftsNewsModalView: View {
    let title: String
    @Binding var coins: Int
    @Binding var dna: Int
    let onClose: () -> Void
    @State private var giftClaimed = false

    var body: some View {
        GeometryReader { geometry in
            let s = max(1.0, min(OriginalGameplay.uiScale(for: geometry.size), geometry.size.width / 460.0))

            AgarModalContainer(dismissOnBackdrop: true, onClose: onClose) { triggerClose in
                VStack(spacing: 12 * s) {
                    modalHeader(title: title, scale: s, onClose: triggerClose)
                    if title == "Gifts" {
                        Image("menu-gift-icon").resizable().scaledToFit().frame(width: 52 * s, height: 52 * s)
                        Text(giftClaimed ? "Daily gift claimed!" : "Daily Login Gift: +500 Coins & +15 DNA")
                            .font(.custom("OpenSans-Bold", size: 13.5 * s))
                            .foregroundColor(Color(hex: 0x3D4347))
                            .multilineTextAlignment(.center)
                        if !giftClaimed {
                            Button(action: {
                                SoundManager.shared.play(.menuClick)
                                coins += 500
                                dna += 15
                                giftClaimed = true
                            }) {
                                Text("Claim Gift")
                                    .font(.custom("OpenSans-Bold", size: 14 * s))
                                    .foregroundColor(.white)
                                    .shadow(color: Color.black.opacity(0.35), radius: 0, x: 0, y: 1)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36 * s)
                            }
                            .buttonStyle(MCFSBevelStyle(frameAsset: "mcfs-green"))
                        }
                    } else {
                        Image("menu-news-icon").resizable().scaledToFit().frame(width: 52 * s, height: 40 * s)
                        Text("Agar.io Mobile Build\n• 1:1 320-height CCBI UI scaling + crisp 9-slice buttons\n• Calibrated 50u grid, darker cell borders, & glide physics\n• Mystery Potions brewing + animated chest opening")
                            .font(.custom("Lato-Regular", size: 11.5 * s))
                            .foregroundColor(Color(hex: 0x5A5F66))
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding(16 * s)
                .frame(width: min(geometry.size.width * 0.85, 340 * s))
                .background(MCFSFrame(name: "mcfs-white"))
                .shadow(radius: 20)
            }
        }
    }
}

struct MatchResultsModalView: View {
    let highScore: Int
    let tokensCollected: Int
    let survivalSeconds: Int
    let onPlayAgain: () -> Void
    let onMainMenu: () -> Void

    @State private var awardedTier: PotionTier? = nil
    @State private var checkedAward = false

    var body: some View {
        GeometryReader { geometry in
            let s = max(1.0, min(OriginalGameplay.uiScale(for: geometry.size), geometry.size.width / 460.0))

            AgarModalContainer(dismissOnBackdrop: false, onClose: onMainMenu) { _ in
                VStack(spacing: 10 * s) {
                    Text("Game Over")
                        .font(.custom("OpenSans-Bold", size: 22 * s))
                        .foregroundColor(Color(hex: 0x4A4F55))
                    Image("mcfs-divider").resizable().frame(height: max(1.5, 2 * s))

                    VStack(spacing: 7 * s) {
                        statRow(label: "Highest Mass", value: "\(highScore)", scale: s)
                        statRow(label: "Tokens Collected", value: "\(tokensCollected)", scale: s)
                        statRow(label: "Time Alive", value: String(format: "%d:%02d", survivalSeconds / 60, survivalSeconds % 60), scale: s)
                    }
                    .padding(10 * s)
                    .background(MCFSFrame(name: "mcfs-light-grey"))

                    if let dropped = awardedTier {
                        HStack(spacing: 8 * s) {
                            Image(dropped.iconAsset).resizable().scaledToFit().frame(width: 26 * s, height: 32 * s)
                            VStack(alignment: .leading, spacing: 1 * s) {
                                Text("\(dropped.rawValue) Mystery Potion Earned!")
                                    .font(.custom("OpenSans-Bold", size: 11.5 * s))
                                    .foregroundColor(Color(hex: 0x3D4347))
                                Text("Open Menu → Potions to brew it.")
                                    .font(.custom("Lato-Regular", size: 10 * s))
                                    .foregroundColor(Color(hex: 0x43A81D))
                            }
                            Spacer()
                        }
                        .padding(8 * s)
                        .background(MCFSFrame(name: "mcfs-white-green"))
                    }

                    HStack(spacing: 10 * s) {
                        Button(action: {
                            SoundManager.shared.play(.menuClick)
                            onMainMenu()
                        }) {
                            Text("Menu")
                                .font(.custom("OpenSans-Bold", size: 14 * s))
                                .foregroundColor(.white)
                                .shadow(color: Color.black.opacity(0.35), radius: 0, x: 0, y: 1)
                                .frame(maxWidth: .infinity)
                                .frame(height: 38 * s)
                        }
                        .buttonStyle(MCFSBevelStyle(frameAsset: "mcfs-orange"))
                        Button(action: {
                            SoundManager.shared.play(.menuClick)
                            onPlayAgain()
                        }) {
                            Text("Play Again")
                                .font(.custom("OpenSans-Bold", size: 14 * s))
                                .foregroundColor(.white)
                                .shadow(color: Color.black.opacity(0.35), radius: 0, x: 0, y: 1)
                                .frame(maxWidth: .infinity)
                                .frame(height: 38 * s)
                        }
                        .buttonStyle(MCFSBevelStyle(frameAsset: "mcfs-green"))
                    }
                }
                .padding(16 * s)
                .frame(width: min(geometry.size.width * 0.88, 340 * s))
                .background(MCFSFrame(name: "mcfs-white"))
                .shadow(radius: 24)
            }
            .onAppear {
                if !checkedAward {
                    checkedAward = true
                    awardedTier = PotionStore.shared.awardPostMatchPotion(score: highScore, survivalSeconds: survivalSeconds)
                }
            }
        }
    }

    private func statRow(label: String, value: String, scale s: CGFloat) -> some View {
        HStack {
            Text(label).font(.custom("Lato-Regular", size: 12.5 * s)).foregroundColor(Color(hex: 0x5A5F66))
            Spacer()
            Text(value).font(.custom("OpenSans-Bold", size: 14 * s)).foregroundColor(Color(hex: 0xE57200))
        }
    }
}

// MARK: - Shared Headers (GenericHeader.ccbi)
private func genericFullHeader(title: String, coins: Int, dna: Int, scale s: CGFloat, onClose: @escaping () -> Void) -> some View {
    ZStack {
        CCBISceneView(
            ccbFile: "GenericHeader.ccbi",
            context: CCBIBindingContext(
                actions: [
                    "backButtonCallback": onClose,
                    "_backButton": onClose
                ],
                designScaleModifier: { _ in s }
            )
        )
        .frame(height: 40 * s)

        HStack(spacing: 8 * s) {
            Spacer().frame(width: 44 * s)
            Text(title)
                .font(.custom("OpenSans-Bold", size: 19 * s))
                .foregroundColor(Color(hex: 0x5A5F66))
            Spacer()
            currencyPill(icon: "menu-coin-icon", value: coins, scale: s)
            currencyPill(icon: "menu-dna-icon", value: dna, scale: s)
        }
        .padding(.horizontal, 14 * s)
    }
    .frame(height: 40 * s)
    .background(Color.white)
}

private func modalHeader(title: String, scale s: CGFloat, onClose: @escaping () -> Void) -> some View {
    VStack(spacing: 6 * s) {
        HStack {
            Button(action: {
                SoundManager.shared.play(.menuClick)
                onClose()
            }) {
                Image("menu-back-btn").resizable().scaledToFit().frame(width: 26 * s, height: 26 * s)
            }
            Spacer()
            Text(title).font(.custom("OpenSans-Bold", size: 18 * s)).foregroundColor(Color(hex: 0x5A5F66))
            Spacer()
            Color.clear.frame(width: 26 * s, height: 26 * s)
        }
        Image("mcfs-divider").resizable().frame(height: max(1.5, 2 * s))
    }
}

private func currencyPill(icon: String, value: Int, scale s: CGFloat) -> some View {
    HStack(spacing: 4 * s) {
        Image(icon).resizable().scaledToFit().frame(width: 15 * s, height: 15 * s)
        Text("\(value)")
            .font(.custom("OpenSans-Bold", size: 11.5 * s))
            .foregroundColor(Color(hex: 0x3D4347))
            .contentTransition(.numericText())
            .animation(.easeOut(duration: 0.25), value: value)
        Image("menu-plus-box").resizable().scaledToFit().frame(width: 13 * s, height: 13 * s)
    }
    .padding(.horizontal, 7 * s)
    .frame(height: 24 * s)
    .background(MCFSFrame(name: "mcfs-white-green"))
}
