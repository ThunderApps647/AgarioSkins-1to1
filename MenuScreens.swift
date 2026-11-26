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
    case boosts = "Boosts"
    case coins = "Coins"
    case dna = "DNA"
}

struct MCFSBevelStyle: ButtonStyle {
    let frameAsset: String
    var showShadow: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? 1.5 : 0)
            .background(
                ZStack {
                    if showShadow {
                        MCFSFrame(name: "mcfs-shadow")
                            .offset(y: configuration.isPressed ? 1.0 : 2.5)
                    }
                    MCFSFrame(name: frameAsset)
                }
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

// MARK: - MenuShop.ccbi (Full-Screen 1:1)
struct ShopModalView: View {
    @Binding var coins: Int
    @Binding var dna: Int
    @Binding var activeStartBoost: Int
    let onClose: () -> Void

    @State private var selectedTab: ShopTab = .boosts
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
                    genericFullHeader(title: "Shop", coins: coins, dna: dna, scale: s, onClose: onClose)

                    // MenuShop.ccbi 3-tab segmented bar
                    HStack(spacing: 8 * s) {
                        ForEach(ShopTab.allCases, id: \.self) { tab in
                            let selected = selectedTab == tab
                            Button(action: {
                                SoundManager.shared.play(.menuClick)
                                withAnimation(.easeOut(duration: 0.16)) { selectedTab = tab }
                            }) {
                                Text(tab.rawValue)
                                    .font(.custom("OpenSans-Bold", size: 13 * s))
                                    .foregroundColor(selected ? .white : Color(hex: 0x5A5F66))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 30 * s)
                            }
                            .buttonStyle(MCFSBevelStyle(frameAsset: selected ? "mcfs-light-blue" : "mcfs-white-grey-tab", showShadow: selected))
                        }
                    }
                    .padding(.horizontal, 14 * s)
                    .padding(.vertical, 8 * s)
                    .background(Color(hex: 0xF2F5F8))

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.custom("OpenSans-Bold", size: 12 * s))
                            .foregroundColor(Color(hex: 0x43A81D))
                            .padding(.vertical, 4 * s)
                            .frame(maxWidth: .infinity)
                            .background(Color(hex: 0xF2F5F8))
                    }

                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 10 * s) {
                            switch selectedTab {
                            case .boosts:
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

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geometry in
            let s = max(1.0, min(OriginalGameplay.uiScale(for: geometry.size), geometry.size.width / 460.0))

            ZStack {
                Color(hex: 0xF7F9FB).edgesIgnoringSafeArea(.all)

                VStack(spacing: 0) {
                    genericFullHeader(title: "Mystery Potions", coins: coins, dna: dna, scale: s, onClose: onClose)

                    VStack(spacing: 10 * s) {
                        Text(statusBanner)
                            .font(.custom("Lato-Regular", size: 12 * s))
                            .foregroundColor(Color(hex: 0x5A5F66))
                            .multilineTextAlignment(.center)
                            .padding(.top, 6 * s)

                        // PotionSlot.ccbi: 4 vertical slot pedestals
                        HStack(spacing: 8 * s) {
                            ForEach(potionStore.slots) { slot in
                                potionPedestalCard(slot: slot, scale: s)
                            }
                        }
                        .padding(.horizontal, 12 * s)
                        .padding(.bottom, 12 * s)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(MCFSFrame(name: "mcfs-gray"))
                }
                .frame(width: geometry.size.width, height: geometry.size.height)

                if let reward = activeReward {
                    PotionOpeningMinigameView(reward: reward, s: s, containerSize: geometry.size) {
                        withAnimation { activeReward = nil }
                    }
                    .zIndex(5)
                }
            }
            .onReceive(ticker) { date in
                nowTimestamp = date.timeIntervalSince1970
            }
        }
    }

    private func potionPedestalCard(slot: PotionSlotState, scale s: CGFloat) -> some View {
        let tier = slot.tier
        let isReady = slot.isReady(now: nowTimestamp)
        let isBrewing = slot.isBrewing(now: nowTimestamp)
        let slotSprite = isReady ? "potion-slot-orange" : (tier != nil ? "potion-slot-blue" : "potion-slot-grey")

        return VStack(spacing: 6 * s) {
            if let tier = tier {
                Text(tier.rawValue)
                    .font(.custom("OpenSans-Bold", size: 10.5 * s))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8 * s)
                    .padding(.vertical, 2 * s)
                    .background(Capsule().fill(tier.badgeColor))

                ZStack {
                    Image(slotSprite)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 82 * s)
                    Image(tier.iconAsset)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50 * s, height: 66 * s)
                        .offset(y: -6 * s)
                }
                .frame(height: 86 * s)

                if isReady {
                    Text("Ready to Open!")
                        .font(.custom("OpenSans-Bold", size: 10.5 * s))
                        .foregroundColor(Color(hex: 0x43A81D))
                } else if isBrewing {
                    let rem = Int(ceil(slot.remainingSeconds(now: nowTimestamp)))
                    let progress = min(1.0, max(0.05, 1.0 - (slot.remainingSeconds(now: nowTimestamp) / max(1, slot.brewDuration))))
                    VStack(spacing: 3 * s) {
                        HStack(spacing: 3 * s) {
                            Image("potion-clock-grey").resizable().scaledToFit().frame(width: 11 * s, height: 11 * s)
                            Text(String(format: "%02d:%02d", rem / 60, rem % 60))
                                .font(.custom("OpenSans-Bold", size: 10.5 * s))
                                .foregroundColor(Color(hex: 0x5A5F66))
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Image("potion-progressbar-bg").resizable()
                                Image("potion-progressbar-blue")
                                    .resizable()
                                    .frame(width: max(4 * s, geo.size.width * progress))
                            }
                        }
                        .frame(height: 7 * s)
                        .padding(.horizontal, 6 * s)
                    }
                } else {
                    HStack(spacing: 3 * s) {
                        Image("potion-clock-grey").resizable().scaledToFit().frame(width: 11 * s, height: 11 * s)
                        Text("\(Int(tier.brewDurationSeconds / 60))m \(Int(tier.brewDurationSeconds) % 60)s")
                            .font(.custom("Lato-Regular", size: 10 * s))
                            .foregroundColor(Color(hex: 0x6E767E))
                    }
                }

                Spacer(minLength: 2 * s)

                if isReady {
                    Button(action: {
                        SoundManager.shared.play(.menuClick)
                        if let reward = potionStore.openPotion(slotIndex: slot.id, coins: &coins, dna: &dna, now: nowTimestamp) {
                            statusBanner = "Opened \(reward.tier.rawValue) Potion: +\(reward.coins) Coins & +\(reward.dna) DNA!"
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                                activeReward = reward
                            }
                        }
                    }) {
                        Text("Open")
                            .font(.custom("OpenSans-Bold", size: 12 * s))
                            .foregroundColor(.white)
                            .shadow(color: Color.black.opacity(0.35), radius: 0, x: 0, y: 1)
                            .frame(maxWidth: .infinity)
                            .frame(height: 29 * s)
                    }
                    .buttonStyle(MCFSBevelStyle(frameAsset: "mcfs-green"))
                } else if isBrewing {
                    let rushCost = slot.rushDNACost(now: nowTimestamp)
                    Button(action: {
                        SoundManager.shared.play(.menuClick)
                        if potionStore.rushWithDNA(slotIndex: slot.id, dna: &dna, now: nowTimestamp),
                           let reward = potionStore.openPotion(slotIndex: slot.id, coins: &coins, dna: &dna, now: nowTimestamp) {
                            statusBanner = "Rushed \(reward.tier.rawValue) Potion: +\(reward.coins) Coins & +\(reward.dna) DNA!"
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                                activeReward = reward
                            }
                        } else {
                            statusBanner = "Need \(rushCost) DNA to rush!"
                        }
                    }) {
                        HStack(spacing: 4 * s) {
                            Image("shop-dna-s").resizable().scaledToFit().frame(width: 13 * s, height: 13 * s)
                            Text("Rush \(rushCost)")
                                .font(.custom("OpenSans-Bold", size: 11 * s))
                                .foregroundColor(.white)
                                .shadow(color: Color.black.opacity(0.35), radius: 0, x: 0, y: 1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 29 * s)
                    }
                    .buttonStyle(MCFSBevelStyle(frameAsset: dna >= rushCost ? "mcfs-green" : "mcfs-orange"))
                } else {
                    Button(action: {
                        SoundManager.shared.play(.menuClick)
                        potionStore.startBrew(slotIndex: slot.id, now: nowTimestamp)
                        statusBanner = "Brewing \(tier.rawValue) Potion!"
                    }) {
                        Text("Brew")
                            .font(.custom("OpenSans-Bold", size: 12 * s))
                            .foregroundColor(.white)
                            .shadow(color: Color.black.opacity(0.35), radius: 0, x: 0, y: 1)
                            .frame(maxWidth: .infinity)
                            .frame(height: 29 * s)
                    }
                    .buttonStyle(MCFSBevelStyle(frameAsset: "mcfs-light-blue"))
                }
            } else {
                Text("Empty Slot")
                    .font(.custom("OpenSans-Bold", size: 10 * s))
                    .foregroundColor(Color(hex: 0x7A828C))
                    .padding(.horizontal, 6 * s)
                    .padding(.vertical, 2 * s)
                    .background(Capsule().fill(Color(hex: 0xE2E7EE)))

                Image("potion-slot-grey")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 82 * s)

                Text("Play matches or claim below")
                    .font(.custom("Lato-Regular", size: 9.5 * s))
                    .foregroundColor(Color(hex: 0x8A939E))
                    .multilineTextAlignment(.center)

                Spacer(minLength: 2 * s)

                Button(action: {
                    SoundManager.shared.play(.menuClick)
                    if potionStore.collectSamplePotion() {
                        statusBanner = "Found a Mystery Potion! Tap Brew to start."
                    }
                }) {
                    Text("Find Potion")
                        .font(.custom("OpenSans-Bold", size: 10.5 * s))
                        .foregroundColor(.white)
                        .shadow(color: Color.black.opacity(0.35), radius: 0, x: 0, y: 1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 29 * s)
                }
                .buttonStyle(MCFSBevelStyle(frameAsset: "mcfs-green"))
            }
        }
        .padding(8 * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MCFSFrame(name: "mcfs-white"))
    }
}

/// MenuMysteryPotionMinigame_v2.ccbi — Two-column animated potion reward reveal
private struct PotionOpeningMinigameView: View {
    let reward: PotionReward
    let s: CGFloat
    let containerSize: CGSize
    let onCollect: () -> Void

    @State private var revealed = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).edgesIgnoringSafeArea(.all)

            VStack(spacing: 10 * s) {
                HStack {
                    Text("\(reward.tier.rawValue) Mystery Potion")
                        .font(.custom("OpenSans-Bold", size: 18 * s))
                        .foregroundColor(Color(hex: 0x3D4347))
                    Spacer()
                    Button(action: {
                        SoundManager.shared.play(.menuClick)
                        onCollect()
                    }) {
                        Image("menu-exit-btn").resizable().scaledToFit().frame(width: 24 * s, height: 24 * s)
                    }
                }

                Image("mcfs-divider").resizable().frame(height: max(1.5, 2 * s))

                // Two-column CCBI layout: Left (pellets + bottle) | Right (Coins, DNA, Skin Pieces)
                HStack(spacing: 12 * s) {
                    ZStack {
                        Image("potion-pellets-open")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 120 * s, height: 120 * s)
                            .rotationEffect(.degrees(revealed ? 12 : -18))
                            .scaleEffect(revealed ? 1.08 : 0.72)
                        Image(reward.tier.iconAsset)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 74 * s, height: 94 * s)
                            .scaleEffect(revealed ? 1.05 : 0.6)
                    }
                    .frame(width: 126 * s, height: 136 * s)
                    .background(MCFSFrame(name: "mcfs-light-grey"))

                    VStack(spacing: 8 * s) {
                        HStack(spacing: 8 * s) {
                            rewardBox(icon: "shop-coins-s", title: "+\(reward.coins)", subtitle: "Coins", scale: s)
                            rewardBox(icon: "shop-dna-s", title: "+\(reward.dna)", subtitle: "DNA", scale: s)
                        }

                        HStack(spacing: 8 * s) {
                            SkinSelectorPreview(skinName: reward.skinName)
                                .frame(width: 34 * s, height: 34 * s)
                            VStack(alignment: .leading, spacing: 1 * s) {
                                Text("Skin #\(reward.skinName)")
                                    .font(.custom("OpenSans-Bold", size: 11 * s))
                                    .foregroundColor(Color(hex: 0x3D4347))
                                HStack(spacing: 3 * s) {
                                    Image("potion-skinpiece").resizable().scaledToFit().frame(width: 12 * s, height: 12 * s)
                                    Text("+\(reward.skinPieces) Pieces")
                                        .font(.custom("Lato-Regular", size: 10 * s))
                                        .foregroundColor(Color(hex: 0x43A81D))
                                }
                            }
                            Spacer()
                        }
                        .padding(7 * s)
                        .background(MCFSFrame(name: "mcfs-white"))

                        Button(action: {
                            SoundManager.shared.play(.menuClick)
                            onCollect()
                        }) {
                            Text("Collect Rewards")
                                .font(.custom("OpenSans-Bold", size: 13 * s))
                                .foregroundColor(.white)
                                .shadow(color: Color.black.opacity(0.35), radius: 0, x: 0, y: 1)
                                .frame(maxWidth: .infinity)
                                .frame(height: 32 * s)
                        }
                        .buttonStyle(MCFSBevelStyle(frameAsset: "mcfs-green"))
                    }
                    .padding(10 * s)
                    .background(MCFSFrame(name: "mcfs-light-grey"))
                }
            }
            .padding(14 * s)
            .frame(width: min(containerSize.width * 0.9, 430 * s))
            .background(MCFSFrame(name: "mcfs-white"))
            .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
        }
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.65)) {
                revealed = true
            }
        }
    }

    private func rewardBox(icon: String, title: String, subtitle: String, scale s: CGFloat) -> some View {
        HStack(spacing: 6 * s) {
            Image(icon).resizable().scaledToFit().frame(width: 22 * s, height: 22 * s)
            VStack(alignment: .leading, spacing: 1 * s) {
                Text(title).font(.custom("OpenSans-Bold", size: 12 * s)).foregroundColor(Color(hex: 0x3D4347))
                Text(subtitle).font(.custom("Lato-Regular", size: 9.5 * s)).foregroundColor(Color(hex: 0x6E767E))
            }
            Spacer(minLength: 0)
        }
        .padding(7 * s)
        .frame(maxWidth: .infinity)
        .background(MCFSFrame(name: "mcfs-white"))
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
    VStack(spacing: 0) {
        HStack(spacing: 8 * s) {
            Button(action: {
                SoundManager.shared.play(.menuClick)
                onClose()
            }) {
                Image("menu-back-btn").resizable().scaledToFit().frame(width: 28 * s, height: 28 * s)
            }
            Text(title)
                .font(.custom("OpenSans-Bold", size: 19 * s))
                .foregroundColor(Color(hex: 0x5A5F66))
            Spacer()
            currencyPill(icon: "menu-coin-icon", value: coins, scale: s)
            currencyPill(icon: "menu-dna-icon", value: dna, scale: s)
        }
        .padding(.horizontal, 14 * s)
        .padding(.vertical, 8 * s)
        .background(Color.white)
        Image("mcfs-divider").resizable().frame(height: max(1.5, 2 * s))
    }
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
