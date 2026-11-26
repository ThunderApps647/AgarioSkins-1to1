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
                modalHeader(title: "Shop", onClose: triggerClose)

                HStack(spacing: 12) {
                    currencyPill(icon: "ui-coin-icon", value: coins)
                    currencyPill(icon: "ui-dna-icon", value: dna)
                    Spacer()
                }

                // MenuShop.ccbi 3-tab segmented bar: Boosts / Coins / DNA
                HStack(spacing: 8) {
                    ForEach(ShopTab.allCases, id: \.self) { tab in
                        Button(action: {
                            SoundManager.shared.play(.menuClick)
                            withAnimation(.easeOut(duration: 0.16)) { selectedTab = tab }
                        }) {
                            Text(tab.rawValue)
                                .font(.custom("UbuntuSans-Bold", size: 14))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background(
                                    AgarBevelButtonStyle(
                                        fill: selectedTab == tab ? Color(hex: 0x00C8F8) : Color(hex: 0x264166),
                                        bevel: selectedTab == tab ? Color(hex: 0x0095BA) : Color(hex: 0x162842),
                                        cornerRadius: 10
                                    )
                                )
                        }
                    }
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.custom("UbuntuSans-Bold", size: 13))
                        .foregroundColor(Color(hex: 0x54D62C))
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
                            shopTile(icon: "ui-shop-mass2x", title: "2x Mass Boost", subtitle: "Double mass gain", cost: 250, costIsDNA: false) {
                                statusMessage = "2x Mass Boost activated!"
                            }
                            shopTile(icon: "ui-shop-mass3x", title: "3x Mass Boost", subtitle: "Triple mass gain", cost: 25, costIsDNA: true) {
                                statusMessage = "3x Mass Boost activated!"
                            }
                            shopTile(icon: "ui-shop-xp2x", title: "2x XP Boost", subtitle: "Double XP gain", cost: 200, costIsDNA: false) {
                                statusMessage = "2x XP Boost activated!"
                            }
                            shopTile(icon: "ui-shop-xp3x", title: "3x XP Boost", subtitle: "Triple XP gain", cost: 20, costIsDNA: true) {
                                statusMessage = "3x XP Boost activated!"
                            }
                        case .coins:
                            shopTile(icon: "ui-coin-icon", title: "Coin Pouch", subtitle: "+500 Coins", cost: 10, costIsDNA: true, iconScale: 0.9) {
                                coins += 500
                                statusMessage = "Added +500 Coins!"
                            }
                            shopTile(icon: "ui-coin-icon", title: "Coin Stack", subtitle: "+1,500 Coins", cost: 25, costIsDNA: true, iconScale: 1.05) {
                                coins += 1500
                                statusMessage = "Added +1,500 Coins!"
                            }
                            shopTile(icon: "ui-coin-icon", title: "Coin Chest", subtitle: "+4,000 Coins", cost: 60, costIsDNA: true, iconScale: 1.2) {
                                coins += 4000
                                statusMessage = "Added +4,000 Coins!"
                            }
                        case .dna:
                            shopTile(icon: "ui-dna-icon", title: "DNA Vial", subtitle: "+15 DNA", cost: 250, costIsDNA: false, iconScale: 0.9) {
                                dna += 15
                                statusMessage = "Added +15 DNA!"
                            }
                            shopTile(icon: "ui-dna-icon", title: "DNA Flask", subtitle: "+40 DNA", cost: 600, costIsDNA: false, iconScale: 1.05) {
                                dna += 40
                                statusMessage = "Added +40 DNA!"
                            }
                            shopTile(icon: "ui-dna-icon", title: "DNA Crate", subtitle: "+100 DNA", cost: 1400, costIsDNA: false, iconScale: 1.2) {
                                dna += 100
                                statusMessage = "Added +100 DNA!"
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 310)
            }
            .padding(20)
            .frame(maxWidth: 560)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(hex: 0x1A2E4C))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.18), lineWidth: 2))
            )
            .shadow(radius: 20)
        }
    }

    private func shopTile(icon: String, title: String, subtitle: String, cost: Int, costIsDNA: Bool, iconScale: CGFloat = 1.0, onBuy: @escaping () -> Void) -> some View {
        let canAfford = costIsDNA ? dna >= cost : coins >= cost
        return VStack(spacing: 8) {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 48)
                .scaleEffect(iconScale)
                .padding(.top, 6)

            Text(title)
                .font(.custom("UbuntuSans-Bold", size: 13))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(1)

            Text(subtitle)
                .font(.custom("UbuntuSans-Bold", size: 11))
                .foregroundColor(Color(hex: 0xFFE38A))
                .multilineTextAlignment(.center)
                .lineLimit(1)

            Button(action: {
                guard canAfford else { statusMessage = "Not enough \(costIsDNA ? "DNA" : "Coins")"; return }
                SoundManager.shared.play(.menuClick)
                if costIsDNA { dna -= cost } else { coins -= cost }
                onBuy()
            }) {
                HStack(spacing: 4) {
                    Image(costIsDNA ? "ui-dna-icon" : "ui-coin-icon").resizable().scaledToFit().frame(width: 15, height: 15)
                    Text("\(cost)").font(.custom("UbuntuSans-Bold", size: 13)).foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 32)
            }
            .buttonStyle(
                AgarBevelPressStyle(
                    fill: canAfford ? Color(hex: 0x54C826) : Color(hex: 0xF57C00),
                    bevel: canAfford ? Color(hex: 0x398E17) : Color(hex: 0xB55500),
                    cornerRadius: 9
                )
            )
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: 0x102138))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.14), lineWidth: 1.5))
        )
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
            VStack(spacing: 14) {
                modalHeader(title: "Daily Quests", onClose: triggerClose)

                // MenuQuestTracker.ccbi Milestone Chest Header
                HStack(spacing: 12) {
                    Image("ui-quest-chest")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Daily Milestone Chest")
                                .font(.custom("UbuntuSans-Bold", size: 15))
                                .foregroundColor(.white)
                            Spacer()
                            Text("\(claimedCount) / 3")
                                .font(.custom("UbuntuSans-Bold", size: 13))
                                .foregroundColor(Color(hex: 0xFFE38A))
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.black.opacity(0.45))
                                Capsule()
                                    .fill(Color(hex: 0x54C826))
                                    .frame(width: geo.size.width * CGFloat(claimedCount) / 3.0)
                                    .animation(.easeOut(duration: 0.25), value: claimedCount)
                            }
                        }
                        .frame(height: 12)
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
                                .font(.custom("UbuntuSans-Bold", size: 12))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                        }
                        .disabled(claimedCount < 3)
                        .opacity(claimedCount >= 3 ? 1.0 : 0.55)
                        .buttonStyle(
                            AgarBevelPressStyle(
                                fill: Color(hex: 0x54C826),
                                bevel: Color(hex: 0x398E17),
                                cornerRadius: 9
                            )
                        )
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: 0x102138))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.cyan.opacity(0.28), lineWidth: 1.5))
                )

                // Side Quest Tiles
                VStack(spacing: 10) {
                    let foodProg = min(100, offlineQuestProgress + 100 * offlineQuestStage)
                    sideQuestTile(
                        title: "Eat 100 food pellets",
                        progress: q1Claimed ? 100 : foodProg,
                        target: 100,
                        rewardIcon: "ui-coin-icon",
                        rewardText: "+250",
                        claimed: q1Claimed
                    ) {
                        q1Claimed = true; coins += 250
                    }

                    sideQuestTile(
                        title: "Survive 3 minutes",
                        progress: q2Claimed ? 180 : 180,
                        target: 180,
                        rewardIcon: "ui-coin-icon",
                        rewardText: "+300",
                        claimed: q2Claimed
                    ) {
                        q2Claimed = true; coins += 300
                    }

                    sideQuestTile(
                        title: "Split 15 times",
                        progress: q3Claimed ? 15 : 15,
                        target: 15,
                        rewardIcon: "ui-dna-icon",
                        rewardText: "+25",
                        claimed: q3Claimed
                    ) {
                        q3Claimed = true; dna += 25
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 520)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(hex: 0x1A2E4C))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.18), lineWidth: 2))
            )
            .shadow(radius: 20)
        }
    }

    private func sideQuestTile(title: String, progress: Int, target: Int, rewardIcon: String, rewardText: String, claimed: Bool, onClaim: @escaping () -> Void) -> some View {
        let ratio = min(1.0, max(0.0, CGFloat(progress) / CGFloat(max(1, target))))
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.custom("UbuntuSans-Bold", size: 14)).foregroundColor(.white)

                GeometryReader { geo in
                    ZStack {
                        Capsule().fill(Color.black.opacity(0.45))
                        HStack(spacing: 0) {
                            Capsule()
                                .fill(Color(hex: 0x00C8F8))
                                .frame(width: geo.size.width * ratio)
                            Spacer(minLength: 0)
                        }
                        Text("\(min(progress, target)) / \(target)")
                            .font(.custom("UbuntuSans-Bold", size: 11))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 1)
                    }
                }
                .frame(height: 18)
            }

            HStack(spacing: 4) {
                Image(rewardIcon).resizable().scaledToFit().frame(width: 16, height: 16)
                Text(rewardText).font(.custom("UbuntuSans-Bold", size: 13)).foregroundColor(Color(hex: 0xFFE38A))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.black.opacity(0.32)))

            if claimed {
                Image("ui-quest-check").resizable().scaledToFit().frame(width: 28, height: 28)
            } else {
                Button(action: {
                    SoundManager.shared.play(.menuClick)
                    onClaim()
                }) {
                    Text("Claim")
                        .font(.custom("UbuntuSans-Bold", size: 13))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                }
                .buttonStyle(AgarBevelPressStyle(fill: Color(hex: 0x54C826), bevel: Color(hex: 0x398E17), cornerRadius: 9))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: 0x102138))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 1.5))
        )
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
                modalHeader(title: "Mystery Potions", onClose: triggerClose)

                HStack(spacing: 12) {
                    currencyPill(icon: "ui-coin-icon", value: coins)
                    currencyPill(icon: "ui-dna-icon", value: dna)
                    Spacer()
                }

                Text(lastReward)
                    .font(.custom("UbuntuSans-Bold", size: 13))
                    .foregroundColor(Color(hex: 0xFFE38A))
                    .multilineTextAlignment(.center)

                // PotionSlot.ccbi: 4 circular stone pedestals side-by-side
                HStack(spacing: 10) {
                    ForEach(0..<specs.count, id: \.self) { idx in
                        potionPedestalSlot(index: idx, spec: specs[idx])
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 560)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(hex: 0x1A2E4C))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.18), lineWidth: 2))
            )
            .shadow(radius: 20)
        }
    }

    private func potionPedestalSlot(index: Int, spec: PotionSlotSpec) -> some View {
        let isReady = slotReady[index]
        return VStack(spacing: 8) {
            Text(spec.tier)
                .font(.custom("UbuntuSans-Bold", size: 12))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(spec.accentColor.opacity(0.85)))

            // Bottle standing on layered circular stone pedestal
            ZStack(alignment: .bottom) {
                Ellipse()
                    .fill(Color(hex: 0x263242))
                    .frame(width: 92, height: 28)
                    .overlay(Ellipse().stroke(Color(hex: 0x5B6E85), lineWidth: 2))
                    .shadow(color: .black.opacity(0.55), radius: 4, x: 0, y: 3)
                Ellipse()
                    .fill(Color(hex: 0x415266))
                    .frame(width: 72, height: 18)
                    .offset(y: -5)
                Image(spec.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 76)
                    .offset(y: -12)
            }
            .frame(height: 92)

            Text(isReady ? "Ready!" : "Brewing \(spec.brewLabel)")
                .font(.custom("UbuntuSans-Bold", size: 11))
                .foregroundColor(isReady ? Color(hex: 0x54D62C) : .white.opacity(0.75))

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
                        Image("ui-dna-icon").resizable().scaledToFit().frame(width: 14, height: 14)
                        Text("Rush \(spec.rushDNACost)")
                            .font(.custom("UbuntuSans-Bold", size: 12))
                            .foregroundColor(.white)
                    } else {
                        Text("Open")
                            .font(.custom("UbuntuSans-Bold", size: 13))
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 34)
            }
            .buttonStyle(
                AgarBevelPressStyle(
                    fill: isReady ? Color(hex: 0x54C826) : Color(hex: 0x00C8F8),
                    bevel: isReady ? Color(hex: 0x398E17) : Color(hex: 0x0095BA),
                    cornerRadius: 9
                )
            )
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(hex: 0x102138))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(spec.accentColor.opacity(0.35), lineWidth: 1.5))
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
                    Image("ui-gift-icon").resizable().scaledToFit().frame(width: 64, height: 64)
                    Text(giftClaimed ? "Daily gift claimed!" : "Daily Login Gift: +500 Coins & +15 DNA")
                        .font(.custom("UbuntuSans-Bold", size: 15))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    if !giftClaimed {
                        Button(action: {
                            SoundManager.shared.play(.menuClick)
                            coins += 500
                            dna += 15
                            giftClaimed = true
                        }) {
                            Text("Claim Gift").font(.custom("UbuntuSans-Bold", size: 17)).foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background(AgarBevelButtonStyle(fill: Color(hex: 0x54C826), bevel: Color(hex: 0x398E17), cornerRadius: 10))
                        }
                    }
                } else {
                    Image("ui-news-icon").resizable().scaledToFit().frame(width: 64, height: 48)
                    Text("Agar.io Mobile Build\n• Calibrated 60/120Hz physics + IPA adapted decay & 4/3 eat ratio\n• Original SFX, emotes, minimap & match results")
                        .font(.custom("UbuntuSans-Bold", size: 13))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.leading)
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
}

struct MatchResultsModalView: View {
    let highScore: Int
    let tokensCollected: Int
    let survivalSeconds: Int
    let onPlayAgain: () -> Void
    let onMainMenu: () -> Void

    var body: some View {
        AgarModalContainer(dismissOnBackdrop: false, onClose: onMainMenu) { _ in
            VStack(spacing: 16) {
                Text("Game Over")
                    .font(.custom("UbuntuSans-Bold", size: 32))
                    .foregroundColor(.white)

                VStack(spacing: 10) {
                    statRow(label: "Highest Mass", value: "\(highScore)")
                    statRow(label: "Tokens Collected", value: "\(tokensCollected)")
                    statRow(label: "Time Alive", value: String(format: "%d:%02d", survivalSeconds / 60, survivalSeconds % 60))
                }
                .padding(14)
                .background(Color.black.opacity(0.28).cornerRadius(12))

                HStack(spacing: 12) {
                    Button(action: {
                        SoundManager.shared.play(.menuClick)
                        onMainMenu()
                    }) {
                        Text("Menu")
                            .font(.custom("UbuntuSans-Bold", size: 18))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(AgarBevelButtonStyle(fill: Color(hex: 0xF57C00), bevel: Color(hex: 0xB55500), cornerRadius: 12))
                    }
                    Button(action: {
                        SoundManager.shared.play(.menuClick)
                        onPlayAgain()
                    }) {
                        Text("Play Again")
                            .font(.custom("UbuntuSans-Bold", size: 18))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(AgarBevelButtonStyle(fill: Color(hex: 0x54C826), bevel: Color(hex: 0x398E17), cornerRadius: 12))
                    }
                }
            }
            .padding(22)
            .frame(width: 340)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(hex: 0x1A2E4C))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.18), lineWidth: 2))
            )
            .shadow(radius: 24)
        }
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.custom("UbuntuSans-Bold", size: 15)).foregroundColor(.white.opacity(0.75))
            Spacer()
            Text(value).font(.custom("UbuntuSans-Bold", size: 17)).foregroundColor(Color(hex: 0xFFE38A))
        }
    }
}

private func modalHeader(title: String, onClose: @escaping () -> Void) -> some View {
    HStack {
        Spacer()
        Text(title).font(.custom("UbuntuSans-Bold", size: 26)).foregroundColor(.white)
        Spacer()
        Button(action: {
            SoundManager.shared.play(.menuClick)
            onClose()
        }) {
            Image("ui-close-btn").resizable().scaledToFit().frame(width: 28, height: 28)
        }
    }
}

private func currencyPill(icon: String, value: Int) -> some View {
    HStack(spacing: 6) {
        Image(icon).resizable().scaledToFit().frame(width: 20, height: 20)
        Text("\(value)")
            .font(.custom("UbuntuSans-Bold", size: 14))
            .foregroundColor(.white)
            .contentTransition(.numericText())
            .animation(.easeOut(duration: 0.25), value: value)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x0E233A)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cyan.opacity(0.35), lineWidth: 1)))
}
