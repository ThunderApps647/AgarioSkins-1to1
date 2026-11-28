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

    @State private var selectedSection: ShopTab?
    @State private var statusMessage: String = ""
    @State private var showLeftBoostInfo = false
    @State private var showRightBoostInfo = false

    init(
        coins: Binding<Int>,
        dna: Binding<Int>,
        activeStartBoost: Binding<Int>,
        initialSection: ShopTab? = nil,
        onOpenPotions: (() -> Void)? = nil,
        onOpenSkins: (() -> Void)? = nil,
        onClose: @escaping () -> Void
    ) {
        self._coins = coins
        self._dna = dna
        self._activeStartBoost = activeStartBoost
        self._selectedSection = State(initialValue: initialSection)
        self.onOpenPotions = onOpenPotions
        self.onOpenSkins = onOpenSkins
        self.onClose = onClose
    }

    private struct CurrencyTierSpec {
        let rowVar: String
        let orig: Int
        let pct: Int
        let finalAmt: Int
        let cost: Int
        let priceLabel: String
        let banner: String
    }

    private func currencyTiers(isCoins: Bool) -> [CurrencyTierSpec] {
        if isCoins {
            return [
                CurrencyTierSpec(rowVar: "_node6", orig: 25000, pct: 100, finalAmt: 50000, cost: 150, priceLabel: "150 DNA", banner: "Best"),
                CurrencyTierSpec(rowVar: "_node5", orig: 10000, pct: 80,  finalAmt: 18000, cost: 75,  priceLabel: "75 DNA",  banner: "Popular"),
                CurrencyTierSpec(rowVar: "_node4", orig: 4000,  pct: 50,  finalAmt: 6000,  cost: 40,  priceLabel: "40 DNA",  banner: "Hot"),
                CurrencyTierSpec(rowVar: "_node3", orig: 1500,  pct: 30,  finalAmt: 1950,  cost: 20,  priceLabel: "20 DNA",  banner: "+30%"),
                CurrencyTierSpec(rowVar: "_node2", orig: 500,   pct: 20,  finalAmt: 600,   cost: 10,  priceLabel: "10 DNA",  banner: ""),
                CurrencyTierSpec(rowVar: "_node",  orig: 250,   pct: 0,   finalAmt: 250,   cost: 5,   priceLabel: "5 DNA",   banner: "")
            ]
        } else {
            return [
                CurrencyTierSpec(rowVar: "_node6", orig: 500, pct: 100, finalAmt: 1000, cost: 8000, priceLabel: "8000 C", banner: "Best"),
                CurrencyTierSpec(rowVar: "_node5", orig: 200, pct: 75,  finalAmt: 350,  cost: 3500, priceLabel: "3500 C", banner: "Popular"),
                CurrencyTierSpec(rowVar: "_node4", orig: 100, pct: 50,  finalAmt: 150,  cost: 1800, priceLabel: "1800 C", banner: "Hot"),
                CurrencyTierSpec(rowVar: "_node3", orig: 40,  pct: 25,  finalAmt: 50,   cost: 600,  priceLabel: "600 C",  banner: "+25%"),
                CurrencyTierSpec(rowVar: "_node2", orig: 15,  pct: 10,  finalAmt: 17,   cost: 250,  priceLabel: "250 C",  banner: ""),
                CurrencyTierSpec(rowVar: "_node",  orig: 5,   pct: 0,   finalAmt: 5,    cost: 100,  priceLabel: "100 C",  banner: "")
            ]
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let sideInset = max(geometry.safeAreaInsets.leading, geometry.safeAreaInsets.trailing)
            let sceneW = max(1, geometry.size.width - sideInset * 2)
            let s = OriginalGameplay.uiScale(for: CGSize(width: sceneW, height: geometry.size.height))

            ZStack {
                Color.white.edgesIgnoringSafeArea(.all)

                if let section = selectedSection {
                    switch section {
                    case .coins, .dna:
                        let isCoins = (section == .coins)
                        let tiers = currencyTiers(isCoins: isCoins)
                        let backAction = {
                            withAnimation(.easeOut(duration: 0.15)) {
                                selectedSection = nil
                                statusMessage = ""
                            }
                        }
                        let labels: [String: String] = {
                            var d: [String: String] = [
                                "_titleLabel": isCoins ? "Coins" : "DNA",
                                "_coinBar._barCurrencyValue": "\(coins)",
                                "_dnaBar._barCurrencyValue": "\(dna)",
                                "_removeAdsLabel": statusMessage.isEmpty ? (isCoins ? "Tap any Coins pack to add" : "Tap any DNA pack to add") : statusMessage
                            ]
                            for t in tiers {
                                d["\(t.rowVar)._originalLabel"] = "\(t.orig)"
                                d["\(t.rowVar)._percentageLabel"] = t.pct > 0 ? "\(t.pct)%" : "Base"
                                d["\(t.rowVar)._finalLabel"] = "\(t.finalAmt)"
                                d["\(t.rowVar)._priceLabel"] = t.priceLabel
                                if !t.banner.isEmpty { d["\(t.rowVar)._bannerLabel"] = t.banner }
                            }
                            return d
                        }()
                        let vis: [String: Bool] = {
                            var d: [String: Bool] = ["_notEnoughTitleLabel": false]
                            for t in tiers {
                                d["\(t.rowVar)._coinSprite"] = isCoins
                                d["\(t.rowVar)._DNASprite"] = !isCoins
                                d["\(t.rowVar)._freeCoinsBanner"] = false
                            }
                            return d
                        }()
                        let taps: [String: () -> Void] = {
                            var d: [String: () -> Void] = [:]
                            for t in tiers {
                                d[t.rowVar] = {
                                    if isCoins {
                                        guard dna >= t.cost else { statusMessage = "Not enough DNA"; return }
                                        dna -= t.cost
                                        coins += t.finalAmt
                                        statusMessage = "Added +\(t.finalAmt) Coins!"
                                    } else {
                                        guard coins >= t.cost else { statusMessage = "Not enough Coins"; return }
                                        coins -= t.cost
                                        dna += t.finalAmt
                                        statusMessage = "Added +\(t.finalAmt) DNA!"
                                    }
                                }
                            }
                            return d
                        }()

                        CCBISceneView(
                            ccbFile: "MenuShopCurrency.ccbi",
                            context: CCBIBindingContext(
                                actions: ["backButtonCallback": backAction, "_backButton": backAction],
                                tapVarActions: taps,
                                labelOverrides: labels,
                                visibilityOverrides: vis,
                                designScaleModifier: { _ in s }
                            )
                        )
                        .frame(width: sceneW, height: geometry.size.height)

                    case .boosts, .xp:
                        let isMass = (section == .boosts)
                        let backAction = {
                            withAnimation(.easeOut(duration: 0.15)) {
                                selectedSection = nil
                                statusMessage = ""
                                showLeftBoostInfo = false
                                showRightBoostInfo = false
                            }
                        }
                        let leftGreenCost = isMass ? 150 : 120
                        let leftOrangeCost = isMass ? 300 : 250
                        let rightGreenCost = isMass ? 250 : 200
                        let rightOrangeCost = isMass ? 450 : 400
                        let boostActions: [String: () -> Void] = [
                            "backButtonCallback": backAction,
                            "_backButton": backAction,
                            "leftInfoButtonCallback": { showRightBoostInfo = false; showLeftBoostInfo.toggle() },
                            "rightInfoButtonCallback": { showLeftBoostInfo = false; showRightBoostInfo.toggle() },
                            "closeHelpButtonCallback": { showLeftBoostInfo = false; showRightBoostInfo = false },
                            "leftGreenButtonCallback": {
                                guard coins >= leftGreenCost else { statusMessage = "Not enough Coins"; return }
                                coins -= leftGreenCost
                                if isMass { activeStartBoost = 20; statusMessage = "Equipped +20 Start Mass (1h)!" }
                                else { statusMessage = "2x XP Boost activated (1h)!" }
                            },
                            "leftOrangeButtonCallback": {
                                guard coins >= leftOrangeCost else { statusMessage = "Not enough Coins"; return }
                                coins -= leftOrangeCost
                                if isMass { activeStartBoost = 20; statusMessage = "Equipped +20 Start Mass (24h)!" }
                                else { statusMessage = "2x XP Boost activated (24h)!" }
                            },
                            "rightGreenButtonCallback": {
                                guard coins >= rightGreenCost else { statusMessage = "Not enough Coins"; return }
                                coins -= rightGreenCost
                                if isMass { activeStartBoost = 40; statusMessage = "Equipped +40 Start Mass (1h)!" }
                                else { statusMessage = "3x XP Boost activated (1h)!" }
                            },
                            "rightOrangeButtonCallback": {
                                guard coins >= rightOrangeCost else { statusMessage = "Not enough Coins"; return }
                                coins -= rightOrangeCost
                                if isMass { activeStartBoost = 40; statusMessage = "Equipped +40 Start Mass (24h)!" }
                                else { statusMessage = "3x XP Boost activated (24h)!" }
                            }
                        ]
                        let boostLabels: [String: String] = [
                            "_titleLabel": isMass ? "Mass Boost" : "XP Boost",
                            "_coinBar._barCurrencyValue": "\(coins)",
                            "_dnaBar._barCurrencyValue": "\(dna)",
                            "_leftTitleLabel": isMass ? "2x Start Mass (+20)" : "2x XP Boost",
                            "_rightTitleLabel": isMass ? "3x Start Mass (+40)" : "3x XP Boost",
                            "_leftGreenPriceLabel": "\(leftGreenCost)",
                            "_leftOrangePriceLabel": "\(leftOrangeCost)",
                            "_rightGreenPriceLabel": "\(rightGreenCost)",
                            "_rightOrangePriceLabel": "\(rightOrangeCost)"
                        ]
                        let boostVis: [String: Bool] = [
                            "_leftInfo": showLeftBoostInfo,
                            "_rightInfo": showRightBoostInfo,
                            "_menuHelp": showLeftBoostInfo || showRightBoostInfo,
                            "_leftGreenUse": false, "_leftGreenUseIcon": false,
                            "_leftOrangeUse": false, "_leftOrangeUseIcon": false,
                            "_rightGreenUse": false, "_rightGreenUseIcon": false,
                            "_rightOrangeUse": false, "_rightOrangeUseIcon": false
                        ]
                        let boostSlots: [String: AnyView] = [
                            "_leftImageRoot": AnyView(Image(isMass ? "shop-mass-2x" : "shop-xp-2x").resizable().scaledToFit().frame(width: 78 * s, height: 78 * s)),
                            "_rightImageRoot": AnyView(Image(isMass ? "shop-mass-3x" : "shop-xp-3x").resizable().scaledToFit().frame(width: 78 * s, height: 78 * s))
                        ]

                        ZStack(alignment: .bottom) {
                            CCBISceneView(
                                ccbFile: "MenuShopBoosts.ccbi",
                                context: CCBIBindingContext(
                                    actions: boostActions,
                                    labelOverrides: boostLabels,
                                    visibilityOverrides: boostVis,
                                    replacingSlotViews: boostSlots,
                                    designScaleModifier: { _ in s }
                                )
                            )
                            .frame(width: sceneW, height: geometry.size.height)

                            if !statusMessage.isEmpty {
                                Text(statusMessage)
                                    .font(.custom("OpenSans-Bold", size: 12 * s))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14 * s)
                                    .padding(.vertical, 6 * s)
                                    .background(Capsule().fill(Color(hex: 0x43A81D).opacity(0.92)))
                                    .padding(.bottom, 10 * s)
                            }
                        }

                    case .potions, .skins:
                        EmptyView()
                    }
                } else {
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
                            ],
                            designScaleModifier: { _ in s }
                        )
                    )
                    .frame(width: sceneW, height: geometry.size.height)
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

// MARK: - MenuDailyQuestActive.ccbi & MenuDailyQuestCompleted.ccbi (1:1 Native Quests)
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
    @State private var showChestCompletedPopup = false

    private var claimedCount: Int {
        (q1Claimed ? 1 : 0) + (q2Claimed ? 1 : 0) + (q3Claimed ? 1 : 0)
    }

    var body: some View {
        GeometryReader { geometry in
            let s = OriginalGameplay.uiScale(for: geometry.size)
            let foodProg = min(100, offlineQuestProgress + 100 * offlineQuestStage)

            ZStack {
                Color.black.opacity(0.65).edgesIgnoringSafeArea(.all)
                    .onTapGesture { onClose() }

                if showChestCompletedPopup || (claimedCount >= 3 && !chestClaimed) {
                    let compActions: [String: () -> Void] = [
                        "acceptRewardButtonCallback": {
                            if !chestClaimed {
                                chestClaimed = true
                                coins += 500
                                dna += 25
                                showChestCompletedPopup = false
                            } else {
                                onClose()
                            }
                        }
                    ]
                    let compLabels: [String: String] = [
                        "_title": "Daily Quests",
                        "_questDescription": chestClaimed ? "Milestone Chest Claimed!" : "All 3 Daily Quests Complete!",
                        "_rewardDescription": "+500 Coins & +25 DNA",
                        "_actionButtonLabel": chestClaimed ? "Done" : "Open Chest"
                    ]
                    let compVis: [String: Bool] = [
                        "_doubleOpenQuestButton": false,
                        "_subtitleReward": chestClaimed,
                        "_subtitleComplete": !chestClaimed,
                        "_chest": !chestClaimed,
                        "_chestBottom": chestClaimed,
                        "_chestTop": chestClaimed,
                        "_rewardDescription": chestClaimed,
                        "_doubleRewardsIconNode": false
                    ]

                    CCBISceneView(
                        ccbFile: "MenuDailyQuestCompleted.ccbi",
                        context: CCBIBindingContext(
                            actions: compActions,
                            labelOverrides: compLabels,
                            visibilityOverrides: compVis,
                            designScaleModifier: { _ in s }
                        )
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    let questListSlot = AnyView(
                        VStack(spacing: 4.5 * s) {
                            compactQuestRow(
                                title: "Eat 100 food pellets",
                                progress: q1Claimed ? 100 : foodProg,
                                target: 100,
                                rewardIcon: "shop-coins-s",
                                rewardText: "+250",
                                claimed: q1Claimed,
                                scale: s
                            ) {
                                q1Claimed = true
                                coins += 250
                            }
                            compactQuestRow(
                                title: "Survive 3 minutes",
                                progress: 180,
                                target: 180,
                                rewardIcon: "shop-coins-s",
                                rewardText: "+300",
                                claimed: q2Claimed,
                                scale: s
                            ) {
                                q2Claimed = true
                                coins += 300
                            }
                            compactQuestRow(
                                title: "Split 15 times",
                                progress: 15,
                                target: 15,
                                rewardIcon: "shop-dna-s",
                                rewardText: "+25",
                                claimed: q3Claimed,
                                scale: s
                            ) {
                                q3Claimed = true
                                dna += 25
                            }
                        }
                        .frame(width: 238 * s, height: 140 * s)
                        .offset(y: 12 * s)
                    )

                    let activeActions: [String: () -> Void] = [
                        "backButtonCallback": onClose,
                        "playButtonCallback": {
                            if claimedCount >= 3 && !chestClaimed {
                                showChestCompletedPopup = true
                            } else {
                                onClose()
                            }
                        }
                    ]
                    let activeLabels: [String: String] = [
                        "_timerText": chestClaimed ? "All rewards claimed!" : "Milestone Chest: \(claimedCount) / 3"
                    ]
                    let activeVis: [String: Bool] = [
                        "_loadingAnim": false,
                        "_questDescriptionTitle": false,
                        "_questDescription": false
                    ]

                    CCBISceneView(
                        ccbFile: "MenuDailyQuestActive.ccbi",
                        context: CCBIBindingContext(
                            actions: activeActions,
                            labelOverrides: activeLabels,
                            visibilityOverrides: activeVis,
                            replacingSlotViews: ["_imageNode": questListSlot],
                            designScaleModifier: { _ in s }
                        )
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
    }

    private func compactQuestRow(title: String, progress: Int, target: Int, rewardIcon: String, rewardText: String, claimed: Bool, scale s: CGFloat, onClaim: @escaping () -> Void) -> some View {
        let ratio = min(1.0, max(0.0, CGFloat(progress) / CGFloat(max(1, target))))
        return HStack(spacing: 6 * s) {
            VStack(alignment: .leading, spacing: 2.5 * s) {
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 9.5 * s))
                    .foregroundColor(Color(hex: 0x3D4347))
                    .lineLimit(1)
                GeometryReader { geo in
                    ZStack {
                        Capsule().fill(Color(hex: 0xDCE3EC))
                        HStack(spacing: 0) {
                            Capsule().fill(Color(hex: 0x00C8F8)).frame(width: geo.size.width * ratio)
                            Spacer(minLength: 0)
                        }
                        Text("\(min(progress, target)) / \(target)")
                            .font(.custom("OpenSans-Bold", size: 8 * s))
                            .foregroundColor(Color(hex: 0x3D4347))
                    }
                }
                .frame(height: 11 * s)
            }

            HStack(spacing: 2.5 * s) {
                Image(rewardIcon).resizable().scaledToFit().frame(width: 11 * s, height: 11 * s)
                Text(rewardText).font(.custom("OpenSans-Bold", size: 9.5 * s)).foregroundColor(Color(hex: 0x3D4347))
            }
            .padding(.horizontal, 5 * s)
            .padding(.vertical, 3 * s)
            .background(MCFSFrame(name: "mcfs-white-green"))

            if claimed {
                Image("ui-quest-check").resizable().scaledToFit().frame(width: 18 * s, height: 18 * s)
            } else {
                Button(action: {
                    SoundManager.shared.play(.menuClick)
                    onClaim()
                }) {
                    Text("Claim")
                        .font(.custom("OpenSans-Bold", size: 9.5 * s))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8 * s)
                        .frame(height: 22 * s)
                }
                .buttonStyle(MCFSBevelStyle(frameAsset: "mcfs-green"))
            }
        }
        .padding(.horizontal, 7 * s)
        .padding(.vertical, 5 * s)
        .background(MCFSFrame(name: "mcfs-white"))
    }
}

// MARK: - MenuMysteryPotions.ccbi + PotionSlot.ccbi + MenuMysteryPotionMinigame_v2.ccbi
struct PotionsModalView: View {
    @Binding var coins: Int
    @Binding var dna: Int
    var onOpenShopSection: ((ShopTab) -> Void)? = nil
    let onClose: () -> Void

    @ObservedObject private var potionStore = PotionStore.shared
    @State private var nowTimestamp: TimeInterval = Date().timeIntervalSince1970
    @State private var statusBanner: String = "To win a Potion: stay in Top 40 on the leaderboard (or Top 30 in Rush)"
    @State private var activeReward: PotionReward? = nil
    @State private var showHelpModal: Bool = false

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geometry in
            let sideInset = max(geometry.safeAreaInsets.leading, geometry.safeAreaInsets.trailing)
            let s = OriginalGameplay.uiScale(for: CGSize(width: max(1, geometry.size.width - sideInset * 2), height: geometry.size.height))

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
                            "coinBarCallback": {
                                if let openShop = onOpenShopSection { openShop(.coins) } else { onClose() }
                            },
                            "DNABarCallback": {
                                if let openShop = onOpenShopSection { openShop(.dna) } else { onClose() }
                            }
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
                VStack(spacing: 0) {
                    Spacer().frame(height: 74 * s)
                    HStack(spacing: 8 * s) {
                        ForEach(potionStore.slots) { slot in
                            potionCCBICard(slot: slot, scale: s)
                                .frame(maxWidth: .infinity)
                                .frame(height: 195 * s)
                        }
                    }
                    .padding(.horizontal, max(12 * s, sideInset + 10))
                    Spacer(minLength: 20 * s)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)

                if let reward = activeReward {
                    PotionOpeningMinigameView(reward: reward, s: s, containerSize: geometry.size) {
                        withAnimation { activeReward = nil }
                    }
                    .zIndex(5)
                }

                if showHelpModal {
                    PotionsHelpOverlayView(s: s, containerSize: geometry.size, onOpenShopSection: onOpenShopSection) {
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
        let anyOtherBrewing = potionStore.slots.contains { $0.id != slot.id && $0.isBrewing(now: nowTimestamp) }
        let isStored = (tier != nil && !isReady && !isBrewing)
        let isBusy = isStored && anyOtherBrewing
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
            "_collectedNode": isStored && !isBusy,
            "_brewingNode": isBrewing,
            "_readyNode": isReady,
            "_busyNode": isBusy,
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
            "_busyNodeButtonLabel": "\(rushCost)",
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
            centerRoot: true,
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
    var onOpenShopSection: ((ShopTab) -> Void)? = nil
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
                        "mysterySkinsButtonCallback": { selectedTab = 2 },
                        "shopButtonCallback": {
                            onClose()
                            onOpenShopSection?(.coins)
                        }
                    ],
                    labelOverrides: [
                        "_classicInfoLabel": "Stay in top 5 for 60 seconds",
                        "_newUserFlowInfoLabel": "Stay in top 3 to win"
                    ],
                    visibilityOverrides: [
                        "_howToNode": selectedTab == 0,
                        "_rewardsNode": selectedTab == 1,
                        "_mysteryNode": selectedTab == 2,
                        "_newUserFlowInfoLabel": false,
                        "_probabilitiesButtonContainer": false
                    ],
                    selectedVarStates: [
                        "_howToToggleButton": selectedTab == 0,
                        "_rewardsToggleButton": selectedTab == 1,
                        "_mysteryToggleButton": selectedTab == 2
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
                            VStack(spacing: 5 * s) {
                                ForEach([PotionTier.common, .rare, .exotic, .epic, .legendary], id: \.rawValue) { t in
                                    HStack(spacing: 0) {
                                        Text(t.rawValue)
                                            .font(.custom("OpenSans-Bold", size: 10 * s))
                                            .foregroundColor(t.badgeColor)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text("x\(t.skinPieceCount)")
                                            .font(.custom("OpenSans-Bold", size: 10 * s))
                                            .foregroundColor(Color(hex: 0x3D4347))
                                            .frame(width: 72 * s, alignment: .center)
                                        Text("\(t.rewardCoinsRange.lowerBound)–\(t.rewardCoinsRange.upperBound)")
                                            .font(.custom("Lato-Regular", size: 9.5 * s))
                                            .foregroundColor(Color(hex: 0x5A5F66))
                                            .frame(width: 82 * s, alignment: .center)
                                        Text("+\(Int(t.brewDurationSeconds / 60))")
                                            .font(.custom("OpenSans-Bold", size: 10 * s))
                                            .foregroundColor(Color(hex: 0x08A9C8))
                                            .frame(width: 64 * s, alignment: .trailing)
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
    @State private var showSendGiftTab = false
    @State private var giftStatusText = ""

    var body: some View {
        GeometryReader { geometry in
            let s = OriginalGameplay.uiScale(for: geometry.size)

            if title == "Gifts" {
                let giftNodeRow = AnyView(
                    CCBISceneView(
                        ccbFile: "MenuGiftCenterNode.ccbi",
                        centerRoot: true,
                        context: CCBIBindingContext(
                            actions: [
                                "actionButtonPressed": {
                                    if !giftClaimed {
                                        coins += 500
                                        dna += 15
                                        giftClaimed = true
                                    }
                                }
                            ],
                            labelOverrides: [
                                "_usernameLabel": "Daily Login Gift",
                                "_descriptionLabel": "+500 Coins & +15 DNA",
                                "_actionLabelEnabled": "Accept"
                            ],
                            replacingSlotViews: [
                                "_playerAvatar": AnyView(
                                    Image("menu-gift-icon")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 30 * s, height: 30 * s)
                                )
                            ],
                            designScaleModifier: { _ in s }
                        )
                    )
                    .frame(width: 388 * s, height: 49 * s)
                )

                let inboxActions: [String: () -> Void] = [
                    "backButtonCallback": onClose,
                    "acceptAllButtonPressed": {
                        if !giftClaimed {
                            coins += 500
                            dna += 15
                            giftClaimed = true
                        }
                    },
                    "requestGiftsButtonPressed": {
                        withAnimation(.easeInOut(duration: 0.14)) { showSendGiftTab = true }
                    },
                    "sendGiftTabButtonCallback": {
                        giftStatusText = ""
                        withAnimation(.easeInOut(duration: 0.14)) { showSendGiftTab = true }
                    }
                ]

                let sendGiftActions: [String: () -> Void] = [
                    "backButtonCallback": onClose,
                    "inboxTabButtonCallback": {
                        giftStatusText = ""
                        withAnimation(.easeInOut(duration: 0.14)) { showSendGiftTab = false }
                    },
                    "sendCoinsButtonCallback": {
                        coins += 100
                        giftStatusText = "Sent Coins gift & earned +100 Coins!"
                    },
                    "requestGiftsButtonCallback": {
                        giftStatusText = "Gift request broadcast to friends!"
                    }
                ]

                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.65).edgesIgnoringSafeArea(.all)
                        .onTapGesture { onClose() }

                    if showSendGiftTab {
                        CCBISceneView(
                            ccbFile: "MenuGiftCenterSendGift.ccbi",
                            context: CCBIBindingContext(
                                actions: sendGiftActions,
                                labelOverrides: [
                                    "_inboxCountLabel": giftClaimed ? "0" : "1"
                                ],
                                visibilityOverrides: [
                                    "_inboxBadge": !giftClaimed,
                                    "_sendRequestMenu": true,
                                    "_noFriendsMenu": false
                                ],
                                designScaleModifier: { _ in s }
                            )
                        )
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    } else {
                        CCBISceneView(
                            ccbFile: "MenuGiftCenterInbox.ccbi",
                            context: CCBIBindingContext(
                                actions: inboxActions,
                                labelOverrides: [
                                    "_inboxCountLabel": giftClaimed ? "0" : "1"
                                ],
                                visibilityOverrides: [
                                    "_inboxBadge": !giftClaimed,
                                    "_emptyInboxNode": giftClaimed,
                                    "_tableNode": !giftClaimed,
                                    "_acceptAllButton": !giftClaimed,
                                    "_requestGiftsButton": giftClaimed,
                                    "_inviteFriendsButton": false
                                ],
                                slotViews: [
                                    "_tableNode": giftClaimed ? AnyView(EmptyView()) : giftNodeRow
                                ],
                                designScaleModifier: { _ in s }
                            )
                        )
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    }

                    if !giftStatusText.isEmpty {
                        Text(giftStatusText)
                            .font(.custom("OpenSans-Bold", size: 12 * s))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14 * s)
                            .padding(.vertical, 6 * s)
                            .background(Capsule().fill(Color(hex: 0x43A81D).opacity(0.92)))
                            .padding(.bottom, 12 * s)
                    }
                }
            } else {
                AgarModalContainer(dismissOnBackdrop: true, onClose: onClose) { triggerClose in
                    VStack(spacing: 12 * s) {
                        modalHeader(title: title, scale: s, onClose: triggerClose)
                        Image("menu-news-icon").resizable().scaledToFit().frame(width: 52 * s, height: 40 * s)
                        Text("Agar.io Mobile Build\n• 1:1 320-height CCBI UI scaling + crisp 9-slice buttons\n• Calibrated 50u grid, darker cell borders, & glide physics\n• Mystery Potions brewing + animated chest opening")
                            .font(.custom("Lato-Regular", size: 11.5 * s))
                            .foregroundColor(Color(hex: 0x5A5F66))
                            .multilineTextAlignment(.leading)
                    }
                    .padding(16 * s)
                    .frame(width: min(geometry.size.width * 0.85, 340 * s))
                    .background(MCFSFrame(name: "mcfs-white"))
                }
            }
        }
    }
}

struct ContinueGameModalView: View {
    let highScore: Int
    let tokensCollected: Int
    let survivalSeconds: Int
    let onContinue: () -> Void
    let onCloseToMenu: () -> Void

    @State private var awardedTier: PotionTier? = nil
    @State private var checkedAward = false

    var body: some View {
        GeometryReader { geometry in
            let s = OriginalGameplay.uiScale(for: geometry.size)
            let subtitle: String = {
                if let dropped = awardedTier {
                    return "Score: \(highScore) · \(dropped.rawValue) Potion!"
                }
                return "Score: \(highScore) · Continue your match?"
            }()

            ZStack {
                Color.black.opacity(0.55).edgesIgnoringSafeArea(.all)
                CCBISceneView(
                    ccbFile: "ContinueGame.ccbi",
                    centerRoot: true,
                    context: CCBIBindingContext(
                        actions: [
                            "closeButtonCallback": onCloseToMenu,
                            "continueButtonCallback": onContinue,
                            "watchVideoButtonCallback": onContinue,
                            "buyButtonCallback": onContinue
                        ],
                        labelOverrides: [
                            "_title": "Continue?",
                            "_innerFrameText": subtitle
                        ],
                        visibilityOverrides: [
                            "_buyButton": false,
                            "_watchVideoButton": false,
                            "_continueButton": true,
                            "_timerbar": false,
                            "_innerImageText": false
                        ],
                        designScaleModifier: { _ in s }
                    )
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .onAppear {
                if !checkedAward {
                    checkedAward = true
                    awardedTier = PotionStore.shared.awardPostMatchPotion(score: highScore, survivalSeconds: survivalSeconds)
                }
            }
        }
    }
}

// MARK: - MenuLeagues.ccbi + MenuLeaguesNode.ccbi (Native 1:1 Leagues)
struct LeaguesModalView: View {
    let playerName: String
    let playerLevel: Int
    let playerSkinName: String?
    let trophies: Int
    let onClose: () -> Void

    @State private var selectedTab: Int = 0
    @State private var infoBanner: String = ""

    private struct LeagueRow: Identifiable {
        let id = UUID()
        let rank: Int
        let name: String
        let level: Int
        let skinName: String?
        let trophies: Int
        let isPlayer: Bool
    }

    private var tierTitle: String {
        let lvl = LeagueBadge.clamp(playerLevel)
        if lvl >= 100 { return "Legend League" }
        if lvl >= 75 { return "Diamond League" }
        if lvl >= 50 { return "Gold League" }
        if lvl >= 25 { return "Silver League" }
        return "Bronze League"
    }

    private var standings: [LeagueRow] {
        let display = playerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Guest" : playerName
        let playerTrophies = max(trophies, playerLevel * 12)
        let pool: [(String, Int, String?, Int)] = selectedTab == 0 ? [
            ("Vortex", max(10, playerLevel + 18), "12", playerTrophies + 680),
            ("Nebula", max(8, playerLevel + 12), "42", playerTrophies + 430),
            ("Kraken", max(6, playerLevel + 7), "88", playerTrophies + 220),
            ("Titan", max(5, playerLevel + 3), "105", playerTrophies + 95),
            ("Orbit", max(3, playerLevel - 2), "210", max(10, playerTrophies - 45)),
            ("Pulse", max(2, playerLevel - 5), "77", max(10, playerTrophies - 110)),
            ("Drift", max(1, playerLevel - 9), nil, max(10, playerTrophies - 185))
        ] : (selectedTab == 1 ? [
            ("Apex", 112, "33", playerTrophies + 1240),
            ("Nova", 98, "14", playerTrophies + 890),
            ("Cobra", 81, "19", playerTrophies + 510),
            ("Zephyr", max(15, playerLevel + 4), "65", playerTrophies + 180),
            ("Blaze", max(10, playerLevel - 1), "120", max(15, playerTrophies - 30))
        ] : [
            ("Jumbo", 148, "1", playerTrophies + 4850),
            ("Sirius", 142, "7", playerTrophies + 3620),
            ("WunWun", 136, "25", playerTrophies + 2910),
            ("Typhoon", 124, "54", playerTrophies + 1740),
            ("Spectre", max(20, playerLevel + 8), "91", playerTrophies + 410)
        ])

        var combined: [(String, Int, String?, Int, Bool)] = pool.map { ($0.0, $0.1, $0.2, $0.3, false) }
        combined.append((display, playerLevel, playerSkinName, playerTrophies, true))
        combined.sort { $0.3 > $1.3 }
        return combined.enumerated().map { idx, item in
            LeagueRow(rank: idx + 1, name: item.0, level: item.1, skinName: item.2, trophies: item.3, isPlayer: item.4)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let sideInset = max(geometry.safeAreaInsets.leading, geometry.safeAreaInsets.trailing)
            let sceneW = max(1, geometry.size.width - sideInset * 2)
            let s = OriginalGameplay.uiScale(for: CGSize(width: sceneW, height: geometry.size.height))

            let tableRows = AnyView(
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 4 * s) {
                        ForEach(standings) { row in
                            CCBISceneView(
                                ccbFile: "MenuLeaguesNode.ccbi",
                                centerRoot: true,
                                context: CCBIBindingContext(
                                    labelOverrides: [
                                        "_nameLabel": row.name,
                                        "_winningsLabel": "\(row.trophies)",
                                        "_otherPositionLabel": "\(row.rank)"
                                    ],
                                    visibilityOverrides: [
                                        "_normalSlot": !row.isPlayer,
                                        "_userSlot": row.isPlayer,
                                        "_avatarNormalSlotFrame": !row.isPlayer,
                                        "_avatarUserSlotFrame": row.isPlayer,
                                        "_goldBadge": row.rank == 1,
                                        "_silverBadge": row.rank == 2,
                                        "_bronzeBadge": row.rank == 3,
                                        "_otherPositionBadge": row.rank > 3
                                    ],
                                    slotViews: [
                                        "_leagueBadgeRootNode": AnyView(
                                            Image(LeagueBadge.assetName(forLevel: row.level))
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 22 * s, height: 22 * s)
                                        )
                                    ],
                                    replacingSlotViews: [
                                        "_playerAvatar": AnyView(
                                            Group {
                                                if let sk = row.skinName {
                                                    SkinSelectorPreview(skinName: sk)
                                                        .frame(width: 30 * s, height: 30 * s)
                                                        .clipShape(Circle())
                                                } else {
                                                    Image("menu-profile-guest")
                                                        .resizable()
                                                        .scaledToFill()
                                                        .frame(width: 30 * s, height: 30 * s)
                                                        .clipShape(Circle())
                                                }
                                            }
                                        )
                                    ],
                                    designScaleModifier: { _ in s }
                                )
                            )
                            .frame(height: 39 * s)
                        }
                    }
                    .padding(.top, 38 * s)
                    .padding(.horizontal, 6 * s)
                    .padding(.bottom, 8 * s)
                }
            )

            ZStack(alignment: .bottom) {
                Color.white.edgesIgnoringSafeArea(.all)

                CCBISceneView(
                    ccbFile: "MenuLeagues.ccbi",
                    context: CCBIBindingContext(
                        actions: [
                            "backButtonCallback": onClose,
                            "_backButton": onClose,
                            "myLeagueButtonCallback": { selectedTab = 0; infoBanner = "" },
                            "countryButtonCallback": { selectedTab = 1; infoBanner = "" },
                            "worldButtonCallback": { selectedTab = 2; infoBanner = "" },
                            "helpButtonCallback": { infoBanner = "Earn trophies from Mystery Potions and matches to climb weekly League tiers." },
                            "previousLeagueResultsCallback": { infoBanner = "Last Week: Rank #\(max(1, 14 - playerLevel % 12)) · +\(max(50, playerLevel * 50)) Coins" },
                            "morePrizesCallback": { infoBanner = "Top 3 weekly finishers win 200,000 / 150,000 / 100,000 Coins!" }
                        ],
                        labelOverrides: [
                            "_leagueName": tierTitle,
                            "_leagueTimer": "4d 12h left",
                            "_firstPrizeAmountLabel": "200000",
                            "_secondPrizeAmountLabel": "150000",
                            "_thirdPrizeAmountLabel": "100000"
                        ],
                        visibilityOverrides: [
                            "_leagueTabFourButtons": false,
                            "_leagueTabThreeButtons": true,
                            "_myLeagueInfoBar": selectedTab == 0,
                            "_countryInfoBar": selectedTab == 1,
                            "_worldInfoBar": selectedTab == 2,
                            "_friendsInfoBar": false,
                            "_friendsTableArea": false,
                            "_loadingAnim": false,
                            "_pleaseWait": false,
                            "_upperDescriptionLabel": false,
                            "_middleDescriptionLabel": false,
                            "_greyBackground": true
                        ],
                        selectedVarStates: [
                            "_myLeagueButton": selectedTab == 0,
                            "_countryButton": selectedTab == 1,
                            "_worldButton": selectedTab == 2
                        ],
                        slotViews: [
                            "_leagueBadgeRootNode": AnyView(
                                Image(LeagueBadge.assetName(forLevel: playerLevel))
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 28 * s, height: 28 * s)
                            ),
                            "_tableArea": tableRows
                        ],
                        designScaleModifier: { _ in s }
                    )
                )
                .frame(width: sceneW, height: geometry.size.height)

                if !infoBanner.isEmpty {
                    Text(infoBanner)
                        .font(.custom("OpenSans-Bold", size: 11.5 * s))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14 * s)
                        .padding(.vertical, 6 * s)
                        .background(Capsule().fill(Color(hex: 0x08A9C8).opacity(0.94)))
                        .padding(.bottom, 10 * s)
                        .onTapGesture { infoBanner = "" }
                }
            }
        }
    }
}

// MARK: - MenuProfile.ccbi (Native 1:1 Player Profile & Stats)
struct ProfileModalView: View {
    let playerName: String
    let playerLevel: Int
    let playerSkinName: String?
    let coins: Int
    let dna: Int
    let trophies: Int
    let totalGames: Int
    let totalMass: Int
    let highestMass: Int
    let longestTimeSec: Int
    let totalCellsEaten: Int
    let onOpenQuests: () -> Void
    let onClose: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let sideInset = max(geometry.safeAreaInsets.leading, geometry.safeAreaInsets.trailing)
            let sceneW = max(1, geometry.size.width - sideInset * 2)
            let s = OriginalGameplay.uiScale(for: CGSize(width: sceneW, height: geometry.size.height))

            let display = playerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Guest" : playerName
            let lvl = LeagueBadge.clamp(playerLevel)
            let xpNeeded = max(100, lvl * 75)
            let xpCurr = min(xpNeeded, max(10, (totalMass + coins) % xpNeeded))
            let avgMass = totalGames > 0 ? max(10, totalMass / totalGames) : max(10, highestMass)
            let timeStr = String(format: "%dm %02ds", longestTimeSec / 60, longestTimeSec % 60)

            ZStack {
                Color.white.edgesIgnoringSafeArea(.all)

                CCBISceneView(
                    ccbFile: "MenuProfile.ccbi",
                    context: CCBIBindingContext(
                        actions: [
                            "backButtonCallback": onClose,
                            "_backButton": onClose,
                            "achievementsButtonCallback": onOpenQuests
                        ],
                        labelOverrides: [
                            "_nameLabel": display,
                            "_idLabel": "ID: AGAR-\(max(1000, coins + dna + lvl * 37))",
                            "_cashLabel": "\(coins)",
                            "_dnaLabel": "\(dna)",
                            "_levelLabel": "\(lvl)",
                            "_experiencePointsLabel": "\(xpCurr)/\(xpNeeded)",
                            "_numberOfTrophiesLabel": "\(max(trophies, lvl * 12))",
                            "_totalGamesValue": "\(totalGames)",
                            "_totalMassValue": "\(totalMass)",
                            "_averageMassValue": "\(avgMass)",
                            "_highestMassValue": "\(highestMass)",
                            "_longestTimeValue": timeStr,
                            "_totalCellsEatenValue": "\(totalCellsEaten)"
                        ],
                        visibilityOverrides: [
                            "_playGamesAchievementsButton": true
                        ],
                        slotViews: [
                            "_leagueBadgeRootNode": AnyView(
                                Image(LeagueBadge.assetName(forLevel: lvl))
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 22 * s, height: 22 * s)
                            )
                        ],
                        replacingSlotViews: [
                            "_playerAvatar": AnyView(
                                Group {
                                    if let sk = playerSkinName {
                                        SkinSelectorPreview(skinName: sk)
                                            .frame(width: 86 * s, height: 86 * s)
                                            .cornerRadius(6 * s)
                                    } else {
                                        Image("menu-profile-guest")
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 86 * s, height: 86 * s)
                                            .cornerRadius(6 * s)
                                    }
                                }
                            )
                        ],
                        designScaleModifier: { _ in s }
                    )
                )
                .frame(width: sceneW, height: geometry.size.height)
            }
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
