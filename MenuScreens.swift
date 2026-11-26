//
//  MenuScreens.swift — Clean Agar.io mobile modals (Shop, Quests, Potions,
//  Gifts/News, Match Results) using extracted IPA icons and crisp 3D bevels.
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
        withAnimation(.easeIn(duration: 0.15)) {
            appeared = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
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
                .scaleEffect(appeared ? 1.0 : 0.85)
                .opacity(appeared ? 1.0 : 0.0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.78)) {
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
            .offset(y: configuration.isPressed ? 2.0 : 0)
            .background(
                ZStack {
                    if showShadow {
                        Image("mcfs-shadow").resizable().offset(y: configuration.isPressed ? 1.5 : 3.5)
                    }
                    Image(frameAsset).resizable()
                }
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

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
        AgarModalContainer(dismissOnBackdrop: true, onClose: onClose) { triggerClose in
            VStack(spacing: 12) {
                genericModalHeader(title: "Shop", coins: coins, dna: dna, onClose: triggerClose)

                // MenuShop.ccbi 3-tab segmented bar: mcfs-light-blue (selected) / mcfs-white-grey-tab
                HStack(spacing: 8) {
                    ForEach(ShopTab.allCases, id: \.self) { tab in
                        let selected = selectedTab == tab
                        Button(action: {
                            SoundManager.shared.play(.menuClick)
                            withAnimation(.easeOut(duration: 0.16)) { selectedTab = tab }
                        }) {
                            Text(tab.rawValue)
                                .font(.custom("OpenSans-Bold", size: 14))
                                .foregroundColor(selected ? .white : Color(hex: 0x5A5F66))
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                        }
                        .buttonStyle(MCFSBevelStyle(frameAsset: selected ? "mcfs-light-blue" : "mcfs-white-grey-tab", showShadow: selected))
                    }
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.custom("OpenSans-Bold", size: 13))
                        .foregroundColor(Color(hex: 0x43A81D))
                }

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        switch selectedTab {
                        case .boosts:
                            shopTile(icon: "ui-mass-20", title: "+20 Start Mass", subtitle: "Start match bigger", cost: 150, costIsDNA: false) {
                                activeStartBoost = 20
                                statusMessage = "Equipped +20 Start Mass!"
                            }
                            shopTile(icon: "ui-mass-40", title: "+40 Start Mass", subtitle: "Start match huge", cost: 300, costIsDNA: false) {
                                activeStartBoost = 40
                                statusMessage = "Equipped +40 Start Mass!"
                            }
                            shopTile(icon: "shop-mass-2x", title: "2x Mass Boost", subtitle: "Double mass gain", cost: 250, costIsDNA: false) {
                                statusMessage = "2x Mass Boost activated!"
                            }
                            shopTile(icon: "shop-mass-3x", title: "3x Mass Boost", subtitle: "Triple mass gain", cost: 25, costIsDNA: true) {
                                statusMessage = "3x Mass Boost activated!"
                            }
                            shopTile(icon: "shop-xp-2x", title: "2x XP Boost", subtitle: "Double XP gain", cost: 200, costIsDNA: false) {
                                statusMessage = "2x XP Boost activated!"
                            }
                            shopTile(icon: "shop-xp-3x", title: "3x XP Boost", subtitle: "Triple XP gain", cost: 20, costIsDNA: true) {
                                statusMessage = "3x XP Boost activated!"
                            }
                        case .coins:
                            shopTile(icon: "shop-coins", title: "Coin Pouch", subtitle: "+500 Coins", cost: 10, costIsDNA: true, iconScale: 0.9) {
                                coins += 500
                                statusMessage = "Added +500 Coins!"
                            }
                            shopTile(icon: "shop-coins", title: "Coin Stack", subtitle: "+1,500 Coins", cost: 25, costIsDNA: true, iconScale: 1.05) {
                                coins += 1500
                                statusMessage = "Added +1,500 Coins!"
                            }
                            shopTile(icon: "shop-coins", title: "Coin Chest", subtitle: "+4,000 Coins", cost: 60, costIsDNA: true, iconScale: 1.15) {
                                coins += 4000
                                statusMessage = "Added +4,000 Coins!"
                            }
                        case .dna:
                            shopTile(icon: "shop-dna", title: "DNA Vial", subtitle: "+15 DNA", cost: 250, costIsDNA: false, iconScale: 0.9) {
                                dna += 15
                                statusMessage = "Added +15 DNA!"
                            }
                            shopTile(icon: "shop-dna", title: "DNA Flask", subtitle: "+40 DNA", cost: 600, costIsDNA: false, iconScale: 1.05) {
                                dna += 40
                                statusMessage = "Added +40 DNA!"
                            }
                            shopTile(icon: "shop-dna", title: "DNA Crate", subtitle: "+100 DNA", cost: 1400, costIsDNA: false, iconScale: 1.15) {
                                dna += 100
                                statusMessage = "Added +100 DNA!"
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 310)
            }
            .padding(18)
            .frame(maxWidth: 600)
            .padding(.horizontal, 14)
            .background(Image("mcfs-white").resizable())
            .shadow(radius: 20)
        }
    }

    private func shopTile(icon: String, title: String, subtitle: String, cost: Int, costIsDNA: Bool, iconScale: CGFloat = 1.0, onBuy: @escaping () -> Void) -> some View {
        let canAfford = costIsDNA ? dna >= cost : coins >= cost
        return VStack(spacing: 7) {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 46)
                .scaleEffect(iconScale)
                .padding(.top, 4)

            Text(title)
                .font(.custom("OpenSans-Bold", size: 13))
                .foregroundColor(Color(hex: 0x3D4347))
                .multilineTextAlignment(.center)
                .lineLimit(1)

            Text(subtitle)
                .font(.custom("Lato-Regular", size: 11))
                .foregroundColor(Color(hex: 0x6E767E))
                .multilineTextAlignment(.center)
                .lineLimit(1)

            Button(action: {
                guard canAfford else { statusMessage = "Not enough \(costIsDNA ? "DNA" : "Coins")"; return }
                SoundManager.shared.play(.menuClick)
                if costIsDNA { dna -= cost } else { coins -= cost }
                onBuy()
            }) {
                HStack(spacing: 4) {
                    Image(costIsDNA ? "menu-dna-icon" : "menu-coin-icon").resizable().scaledToFit().frame(width: 15, height: 15)
                    Text("\(cost)")
                        .font(.custom("OpenSans-Bold", size: 13))
                        .foregroundColor(.white)
                        .shadow(color: Color.black.opacity(0.35), radius: 0, x: 0, y: 1)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 32)
            }
            .buttonStyle(MCFSBevelStyle(frameAsset: canAfford ? "mcfs-green" : "mcfs-orange"))
        }
        .padding(10)
        .background(Image("mcfs-light-grey").resizable())
    }
}

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
        AgarModalContainer(dismissOnBackdrop: true, onClose: onClose) { triggerClose in
            VStack(spacing: 12) {
                genericModalHeader(title: "Daily Quests", coins: coins, dna: dna, onClose: triggerClose)

                // MenuQuestTracker.ccbi Milestone Chest Header
                HStack(spacing: 12) {
                    Image("quest-chest")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 58, height: 58)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Daily Milestone Chest")
                                .font(.custom("OpenSans-Bold", size: 15))
                                .foregroundColor(Color(hex: 0x3D4347))
                            Spacer()
                            Text("\(claimedCount) / 3")
                                .font(.custom("OpenSans-Bold", size: 13))
                                .foregroundColor(Color(hex: 0x5A5F66))
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Image("mcfs-hud-xp-box").resizable()
                                Image("mcfs-hud-xp")
                                    .resizable()
                                    .frame(width: max(0, geo.size.width * CGFloat(claimedCount) / 3.0))
                                    .animation(.easeOut(duration: 0.25), value: claimedCount)
                            }
                        }
                        .frame(height: 14)
                    }

                    if chestClaimed {
                        Image("ui-quest-check").resizable().scaledToFit().frame(width: 30, height: 30)
                    } else {
                        Button(action: {
                            guard claimedCount >= 3 else { return }
                            SoundManager.shared.play(.menuClick)
                            chestClaimed = true
                            coins += 500
                            dna += 25
                        }) {
                            Text("Claim Chest")
                                .font(.custom("OpenSans-Bold", size: 12))
                                .foregroundColor(.white)
                                .shadow(color: Color.black.opacity(0.35), radius: 0, x: 0, y: 1)
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                        }
                        .disabled(claimedCount < 3)
                        .opacity(claimedCount >= 3 ? 1.0 : 0.55)
                        .buttonStyle(MCFSBevelStyle(frameAsset: "mcfs-green"))
                    }
                }
                .padding(12)
                .background(Image("mcfs-light-grey").resizable())

                VStack(spacing: 8) {
                    let foodProg = min(100, offlineQuestProgress + 100 * offlineQuestStage)
                    sideQuestTile(
                        title: "Eat 100 food pellets",
                        progress: q1Claimed ? 100 : foodProg,
                        target: 100,
                        rewardIcon: "menu-coin-icon",
                        rewardText: "+250",
                        claimed: q1Claimed
                    ) {
                        q1Claimed = true; coins += 250
                    }

                    sideQuestTile(
                        title: "Survive 3 minutes",
                        progress: q2Claimed ? 180 : 180,
                        target: 180,
                        rewardIcon: "menu-coin-icon",
                        rewardText: "+300",
                        claimed: q2Claimed
                    ) {
                        q2Claimed = true; coins += 300
                    }

                    sideQuestTile(
                        title: "Split 15 times",
                        progress: q3Claimed ? 15 : 15,
                        target: 15,
                        rewardIcon: "menu-dna-icon",
                        rewardText: "+25",
                        claimed: q3Claimed
                    ) {
                        q3Claimed = true; dna += 25
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: 540)
            .padding(.horizontal, 14)
            .background(Image("mcfs-white").resizable())
            .shadow(radius: 20)
        }
    }

    private func sideQuestTile(title: String, progress: Int, target: Int, rewardIcon: String, rewardText: String, claimed: Bool, onClaim: @escaping () -> Void) -> some View {
        let ratio = min(1.0, max(0.0, CGFloat(progress) / CGFloat(max(1, target))))
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.custom("OpenSans-Bold", size: 14)).foregroundColor(Color(hex: 0x3D4347))

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
                            .font(.custom("OpenSans-Bold", size: 11))
                            .foregroundColor(Color(hex: 0x3D4347))
                    }
                }
                .frame(height: 18)
            }

            HStack(spacing: 4) {
                Image(rewardIcon).resizable().scaledToFit().frame(width: 16, height: 16)
                Text(rewardText).font(.custom("OpenSans-Bold", size: 13)).foregroundColor(Color(hex: 0x3D4347))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Image("mcfs-white-green").resizable())

            if claimed {
                Image("ui-quest-check").resizable().scaledToFit().frame(width: 28, height: 28)
            } else {
                Button(action: {
                    SoundManager.shared.play(.menuClick)
                    onClaim()
                }) {
                    Text("Claim")
                        .font(.custom("OpenSans-Bold", size: 13))
                        .foregroundColor(.white)
                        .shadow(color: Color.black.opacity(0.35), radius: 0, x: 0, y: 1)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                }
                .buttonStyle(MCFSBevelStyle(frameAsset: "mcfs-green"))
            }
        }
        .padding(10)
        .background(Image("mcfs-white-grey-tab").resizable())
    }
}

struct PotionsModalView: View {
    @Binding var coins: Int
    @Binding var dna: Int
    let onClose: () -> Void

    @State private var lastReward: String = "Open ready potions or rush brewing slots with DNA"
    @State private var slotReady: [Bool] = [true, false, false, false]

    private struct PotionSlotSpec {
        let tier: String
        let icon: String
        let rewardCoins: Int
        let rewardDNA: Int
        let brewLabel: String
        let rushDNACost: Int
        let accentColor: Color
    }

    private let specs: [PotionSlotSpec] = [
        PotionSlotSpec(tier: "Common", icon: "ui-potion-common", rewardCoins: 150, rewardDNA: 5, brewLabel: "Ready!", rushDNACost: 2, accentColor: Color(hex: 0x54C826)),
        PotionSlotSpec(tier: "Rare", icon: "ui-potion-rare", rewardCoins: 300, rewardDNA: 12, brewLabel: "02:45", rushDNACost: 5, accentColor: Color(hex: 0x00C8F8)),
        PotionSlotSpec(tier: "Epic", icon: "ui-potion-epic", rewardCoins: 600, rewardDNA: 25, brewLabel: "05:30", rushDNACost: 10, accentColor: Color(hex: 0xA44DFF)),
        PotionSlotSpec(tier: "Exotic", icon: "ui-potion-exotic", rewardCoins: 1200, rewardDNA: 50, brewLabel: "11:00", rushDNACost: 15, accentColor: Color(hex: 0xFFB300))
    ]

    var body: some View {
        AgarModalContainer(dismissOnBackdrop: true, onClose: onClose) { triggerClose in
            VStack(spacing: 14) {
                HStack {
                    Button(action: {
                        SoundManager.shared.play(.menuClick)
                        triggerClose()
                    }) {
                        Image("menu-back-btn").resizable().scaledToFit().frame(width: 30, height: 30)
                    }
                    Text("Mystery Potions").font(.custom("OpenSans-Bold", size: 22)).foregroundColor(.white)
                    Spacer()
                    currencyPill(icon: "menu-coin-icon", value: coins)
                    currencyPill(icon: "menu-dna-icon", value: dna)
                }

                Text(lastReward)
                    .font(.custom("Lato-Regular", size: 13))
                    .foregroundColor(Color(hex: 0xFFE38A))
                    .multilineTextAlignment(.center)

                // PotionSlot.ccbi: 4 pedestal cards using real potion-slot-* & potion-* sprites
                HStack(spacing: 10) {
                    ForEach(0..<specs.count, id: \.self) { idx in
                        potionPedestalSlot(index: idx, spec: specs[idx])
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: 580)
            .padding(.horizontal, 14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(Color(hex: 0x152741))
                    Image("mcfs-dark-blue").resizable().opacity(0.28)
                    RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.18), lineWidth: 2)
                }
            )
            .shadow(radius: 20)
        }
    }

    private func potionPedestalSlot(index: Int, spec: PotionSlotSpec) -> some View {
        let isReady = slotReady[index]
        let slotSprite = isReady ? "potion-slot-orange" : "potion-slot-blue"
        let bottleSprite: String = {
            switch index {
            case 0: return "potion-common"
            case 1: return "potion-rare"
            case 2: return "potion-epic"
            default: return "potion-legendary"
            }
        }()
        return VStack(spacing: 8) {
            Text(spec.tier)
                .font(.custom("OpenSans-Bold", size: 12))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(spec.accentColor.opacity(0.88)))

            ZStack {
                Image(slotSprite)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 92)
                Image(bottleSprite)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 58, height: 74)
                    .offset(y: -8)
            }
            .frame(height: 96)

            HStack(spacing: 4) {
                if !isReady {
                    Image("potion-clock-grey").resizable().scaledToFit().frame(width: 13, height: 13)
                }
                Text(isReady ? "Ready!" : spec.brewLabel)
                    .font(.custom("Lato-Regular", size: 11))
                    .foregroundColor(isReady ? Color(hex: 0x54D62C) : .white.opacity(0.85))
            }

            Button(action: {
                if isReady {
                    SoundManager.shared.play(.menuClick)
                    coins += spec.rewardCoins
                    dna += spec.rewardDNA
                    lastReward = "Opened \(spec.tier) Potion: +\(spec.rewardCoins) Coins, +\(spec.rewardDNA) DNA!"
                    slotReady[index] = false
                } else if dna >= spec.rushDNACost {
                    SoundManager.shared.play(.menuClick)
                    dna -= spec.rushDNACost
                    coins += spec.rewardCoins
                    dna += spec.rewardDNA
                    lastReward = "Rushed \(spec.tier) Potion: +\(spec.rewardCoins) Coins, +\(spec.rewardDNA) DNA!"
                } else {
                    lastReward = "Need \(spec.rushDNACost) DNA to rush \(spec.tier)!"
                }
            }) {
                HStack(spacing: 4) {
                    if !isReady {
                        Image("menu-dna-icon").resizable().scaledToFit().frame(width: 14, height: 14)
                        Text("Rush \(spec.rushDNACost)")
                            .font(.custom("OpenSans-Bold", size: 12))
                            .foregroundColor(.white)
                            .shadow(color: Color.black.opacity(0.35), radius: 0, x: 0, y: 1)
                    } else {
                        Text("Open")
                            .font(.custom("OpenSans-Bold", size: 13))
                            .foregroundColor(.white)
                            .shadow(color: Color.black.opacity(0.35), radius: 0, x: 0, y: 1)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 34)
            }
            .buttonStyle(MCFSBevelStyle(frameAsset: isReady ? "mcfs-green" : "mcfs-light-blue"))
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: 0x102138))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(spec.accentColor.opacity(0.38), lineWidth: 1.5))
        )
    }
}

struct GiftsNewsModalView: View {
    let title: String
    @Binding var coins: Int
    @Binding var dna: Int
    let onClose: () -> Void
    @State private var giftClaimed = false

    var body: some View {
        AgarModalContainer(dismissOnBackdrop: true, onClose: onClose) { triggerClose in
            VStack(spacing: 14) {
                modalHeader(title: title, onClose: triggerClose)
                if title == "Gifts" {
                    Image("menu-gift-icon").resizable().scaledToFit().frame(width: 64, height: 64)
                    Text(giftClaimed ? "Daily gift claimed!" : "Daily Login Gift: +500 Coins & +15 DNA")
                        .font(.custom("OpenSans-Bold", size: 15))
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
                                .font(.custom("OpenSans-Bold", size: 17))
                                .foregroundColor(.white)
                                .shadow(color: Color.black.opacity(0.35), radius: 0, x: 0, y: 1)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                        .buttonStyle(MCFSBevelStyle(frameAsset: "mcfs-green"))
                    }
                } else {
                    Image("menu-news-icon").resizable().scaledToFit().frame(width: 64, height: 48)
                    Text("Agar.io Mobile Build\n• Calibrated 60/120Hz physics + IPA adapted decay & 4/3 eat ratio\n• Original SFX, emotes, minimap & match results")
                        .font(.custom("Lato-Regular", size: 13))
                        .foregroundColor(Color(hex: 0x5A5F66))
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(18)
            .frame(width: 340)
            .background(Image("mcfs-white").resizable())
            .shadow(radius: 20)
        }
    }
}

struct MatchResultsModalView: View {
    let highScore: Int
    let tokensCollected: Int
    let survivalSeconds: Int
    let onPlayAgain: () -> Void
    let onMainMenu: () -> Void

    var body: some View {
        AgarModalContainer(dismissOnBackdrop: false, onClose: onMainMenu) { _ in
            VStack(spacing: 14) {
                Text("Game Over")
                    .font(.custom("OpenSans-Bold", size: 28))
                    .foregroundColor(Color(hex: 0x4A4F55))
                Image("mcfs-divider").resizable().frame(height: 2)

                VStack(spacing: 8) {
                    statRow(label: "Highest Mass", value: "\(highScore)")
                    statRow(label: "Tokens Collected", value: "\(tokensCollected)")
                    statRow(label: "Time Alive", value: String(format: "%d:%02d", survivalSeconds / 60, survivalSeconds % 60))
                }
                .padding(12)
                .background(Image("mcfs-light-grey").resizable())

                HStack(spacing: 12) {
                    Button(action: {
                        SoundManager.shared.play(.menuClick)
                        onMainMenu()
                    }) {
                        Text("Menu")
                            .font(.custom("OpenSans-Bold", size: 17))
                            .foregroundColor(.white)
                            .shadow(color: Color.black.opacity(0.35), radius: 0, x: 0, y: 1)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                    }
                    .buttonStyle(MCFSBevelStyle(frameAsset: "mcfs-orange"))
                    Button(action: {
                        SoundManager.shared.play(.menuClick)
                        onPlayAgain()
                    }) {
                        Text("Play Again")
                            .font(.custom("OpenSans-Bold", size: 17))
                            .foregroundColor(.white)
                            .shadow(color: Color.black.opacity(0.35), radius: 0, x: 0, y: 1)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                    }
                    .buttonStyle(MCFSBevelStyle(frameAsset: "mcfs-green"))
                }
            }
            .padding(20)
            .frame(width: 344)
            .background(Image("mcfs-white").resizable())
            .shadow(radius: 24)
        }
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.custom("Lato-Regular", size: 15)).foregroundColor(Color(hex: 0x5A5F66))
            Spacer()
            Text(value).font(.custom("OpenSans-Bold", size: 17)).foregroundColor(Color(hex: 0xE57200))
        }
    }
}

private func genericModalHeader(title: String, coins: Int, dna: Int, onClose: @escaping () -> Void) -> some View {
    VStack(spacing: 8) {
        HStack(spacing: 8) {
            Button(action: {
                SoundManager.shared.play(.menuClick)
                onClose()
            }) {
                Image("menu-back-btn").resizable().scaledToFit().frame(width: 30, height: 30)
            }
            Text(title).font(.custom("OpenSans-Bold", size: 20)).foregroundColor(Color(hex: 0x5A5F66))
            Spacer()
            currencyPill(icon: "menu-coin-icon", value: coins)
            currencyPill(icon: "menu-dna-icon", value: dna)
        }
        Image("mcfs-divider").resizable().frame(height: 2)
    }
}

private func modalHeader(title: String, onClose: @escaping () -> Void) -> some View {
    VStack(spacing: 8) {
        HStack {
            Button(action: {
                SoundManager.shared.play(.menuClick)
                onClose()
            }) {
                Image("menu-back-btn").resizable().scaledToFit().frame(width: 30, height: 30)
            }
            Spacer()
            Text(title).font(.custom("OpenSans-Bold", size: 22)).foregroundColor(Color(hex: 0x5A5F66))
            Spacer()
            Color.clear.frame(width: 30, height: 30)
        }
        Image("mcfs-divider").resizable().frame(height: 2)
    }
}

private func currencyPill(icon: String, value: Int) -> some View {
    HStack(spacing: 5) {
        Image(icon).resizable().scaledToFit().frame(width: 18, height: 18)
        Text("\(value)")
            .font(.custom("OpenSans-Bold", size: 13))
            .foregroundColor(Color(hex: 0x3D4347))
            .contentTransition(.numericText())
            .animation(.easeOut(duration: 0.25), value: value)
        Image("menu-plus-box").resizable().scaledToFit().frame(width: 15, height: 15)
    }
    .padding(.horizontal, 8)
    .frame(height: 28)
    .background(Image("mcfs-white-green").resizable())
}
