//
//  MenuScreens.swift — IPA-matched Shop, Quests, Potions, Boosts, Gifts/News,
//  and Match Results screens using extracted agarskins.ipa sprites.
//

import SwiftUI

private let modalCapInsets = EdgeInsets(top: 24, leading: 23, bottom: 24, trailing: 23)

struct ShopModalView: View {
    @Binding var coins: Int
    @Binding var dna: Int
    @Binding var activeStartBoost: Int
    let onClose: () -> Void

    @State private var statusMessage: String = ""

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).edgesIgnoringSafeArea(.all).onTapGesture(perform: onClose)
            VStack(spacing: 14) {
                modalHeader(title: "Shop", onClose: onClose)

                HStack(spacing: 12) {
                    currencyPill(icon: "ui-coin-icon", value: coins)
                    currencyPill(icon: "ui-dna-icon", value: dna)
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.custom("UbuntuSans-Bold", size: 13))
                        .foregroundColor(.green)
                }

                ScrollView {
                    VStack(spacing: 10) {
                        shopRow(icon: "ui-mass-20", title: "+20 Start Mass Boost", subtitle: "Next match starts with +20 mass", cost: 150, isDNA: false) {
                            activeStartBoost = 20
                            statusMessage = "Equipped +20 Start Mass!"
                        }
                        shopRow(icon: "ui-mass-40", title: "+40 Start Mass Boost", subtitle: "Next match starts with +40 mass", cost: 300, isDNA: false) {
                            activeStartBoost = 40
                            statusMessage = "Equipped +40 Start Mass!"
                        }
                        shopRow(icon: "ui-shop-mass2x", title: "2x Mass Boost", subtitle: "Double mass gain for 1 match", cost: 250, isDNA: false) {
                            statusMessage = "2x Mass Boost activated!"
                        }
                        shopRow(icon: "ui-shop-mass3x", title: "3x Mass Boost", subtitle: "Triple mass gain for 1 match", cost: 25, isDNA: true) {
                            statusMessage = "3x Mass Boost activated!"
                        }
                        shopRow(icon: "ui-shop-xp2x", title: "2x XP Boost", subtitle: "Double XP gain for 1 match", cost: 200, isDNA: false) {
                            statusMessage = "2x XP Boost activated!"
                        }
                        shopRow(icon: "ui-shop-xp3x", title: "3x XP Boost", subtitle: "Triple XP gain for 1 match", cost: 20, isDNA: true) {
                            statusMessage = "3x XP Boost activated!"
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 330)
            }
            .padding(20)
            .frame(width: 360)
            .background(Image("ui-btn-darkblue").resizable(capInsets: modalCapInsets, resizingMode: .stretch))
            .shadow(radius: 20)
        }
    }

    private func shopRow(icon: String, title: String, subtitle: String, cost: Int, isDNA: Bool, onBuy: @escaping () -> Void) -> some View {
        let canAfford = isDNA ? dna >= cost : coins >= cost
        return HStack(spacing: 12) {
            Image(icon).resizable().scaledToFit().frame(width: 50, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.custom("UbuntuSans-Bold", size: 15)).foregroundColor(.white)
                Text(subtitle).font(.custom("UbuntuSans-Bold", size: 11)).foregroundColor(.white.opacity(0.7))
            }
            Spacer()
            Button(action: {
                guard canAfford else { statusMessage = "Not enough \(isDNA ? "DNA" : "Coins")"; return }
                SoundManager.shared.play(.menuClick)
                if isDNA { dna -= cost } else { coins -= cost }
                onBuy()
            }) {
                HStack(spacing: 4) {
                    Image(isDNA ? "ui-dna-icon" : "ui-coin-icon").resizable().scaledToFit().frame(width: 16, height: 16)
                    Text("\(cost)").font(.custom("UbuntuSans-Bold", size: 13)).foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Image(canAfford ? "ui-btn-green" : "ui-btn-orange")
                        .resizable(capInsets: modalCapInsets, resizingMode: .stretch)
                )
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.28).cornerRadius(10))
    }
}

struct QuestsModalView: View {
    @Binding var coins: Int
    @Binding var dna: Int
    let onClose: () -> Void

    @AppStorage("macro.quest1Claimed") private var q1Claimed: Bool = false
    @AppStorage("macro.quest2Claimed") private var q2Claimed: Bool = false
    @AppStorage("macro.quest3Claimed") private var q3Claimed: Bool = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).edgesIgnoringSafeArea(.all).onTapGesture(perform: onClose)
            VStack(spacing: 14) {
                modalHeader(title: "Daily Quests", onClose: onClose)
                Image("ui-quest-chest").resizable().scaledToFit().frame(height: 68)

                VStack(spacing: 10) {
                    questRow(title: "Play a Classic Match", reward: "+250 Coins", claimed: q1Claimed) {
                        q1Claimed = true; coins += 250
                    }
                    questRow(title: "Split 5 Times in One Game", reward: "+300 Coins", claimed: q2Claimed) {
                        q2Claimed = true; coins += 300
                    }
                    questRow(title: "Reach 500 Mass", reward: "+25 DNA", claimed: q3Claimed) {
                        q3Claimed = true; dna += 25
                    }
                }
            }
            .padding(20)
            .frame(width: 350)
            .background(Image("ui-btn-darkblue").resizable(capInsets: modalCapInsets, resizingMode: .stretch))
            .shadow(radius: 20)
        }
    }

    private func questRow(title: String, reward: String, claimed: Bool, onClaim: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.custom("UbuntuSans-Bold", size: 14)).foregroundColor(.white)
                Text(reward).font(.custom("UbuntuSans-Bold", size: 12)).foregroundColor(Color(hex: 0xFFE38A))
            }
            Spacer()
            if claimed {
                Image("ui-quest-check").resizable().scaledToFit().frame(width: 26, height: 26)
            } else {
                Button(action: {
                    SoundManager.shared.play(.menuClick)
                    onClaim()
                }) {
                    Text("Claim").font(.custom("UbuntuSans-Bold", size: 13)).foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Image("ui-btn-green").resizable(capInsets: modalCapInsets, resizingMode: .stretch))
                }
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.28).cornerRadius(10))
    }
}

struct PotionsModalView: View {
    @Binding var coins: Int
    @Binding var dna: Int
    let onClose: () -> Void

    @State private var lastReward: String = "Tap any potion to brew & open"

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).edgesIgnoringSafeArea(.all).onTapGesture(perform: onClose)
            VStack(spacing: 14) {
                modalHeader(title: "Potions", onClose: onClose)
                Text(lastReward)
                    .font(.custom("UbuntuSans-Bold", size: 13))
                    .foregroundColor(Color(hex: 0xFFE38A))
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    potionSlot("ui-potion-common", name: "Common", rewardCoins: 120, rewardDNA: 5)
                    potionSlot("ui-potion-rare", name: "Rare", rewardCoins: 250, rewardDNA: 10)
                    potionSlot("ui-potion-epic", name: "Epic", rewardCoins: 500, rewardDNA: 20)
                }
                HStack(spacing: 10) {
                    potionSlot("ui-potion-exotic", name: "Exotic", rewardCoins: 750, rewardDNA: 35)
                    potionSlot("ui-potion-legendary", name: "Legendary", rewardCoins: 1200, rewardDNA: 60)
                }
            }
            .padding(20)
            .frame(width: 350)
            .background(Image("ui-btn-darkblue").resizable(capInsets: modalCapInsets, resizingMode: .stretch))
            .shadow(radius: 20)
        }
    }

    private func potionSlot(_ icon: String, name: String, rewardCoins: Int, rewardDNA: Int) -> some View {
        Button(action: {
            SoundManager.shared.play(.menuClick)
            coins += rewardCoins
            dna += rewardDNA
            lastReward = "Opened \(name) Potion: +\(rewardCoins) Coins, +\(rewardDNA) DNA!"
        }) {
            VStack(spacing: 4) {
                Image(icon).resizable().scaledToFit().frame(width: 48, height: 64)
                Text(name).font(.custom("UbuntuSans-Bold", size: 11)).foregroundColor(.white)
            }
            .frame(width: 90, height: 96)
            .background(Color.black.opacity(0.28).cornerRadius(10))
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
        ZStack {
            Color.black.opacity(0.72).edgesIgnoringSafeArea(.all).onTapGesture(perform: onClose)
            VStack(spacing: 14) {
                modalHeader(title: title, onClose: onClose)
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
                                .background(Image("ui-btn-green").resizable(capInsets: modalCapInsets, resizingMode: .stretch))
                        }
                    }
                } else {
                    Image("ui-news-icon").resizable().scaledToFit().frame(width: 64, height: 48)
                    Text("Agar.io Mobile 1:1 Build\n• Authentic 11180×11180 arena & sqrt(mass)×10 physics\n• Adapted decay, 4/3 eat ratio & viewport camera zoom\n• Original SFX, emotes, minimap & 9-slice UI")
                        .font(.custom("UbuntuSans-Bold", size: 13))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(20)
            .frame(width: 340)
            .background(Image("ui-btn-darkblue").resizable(capInsets: modalCapInsets, resizingMode: .stretch))
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
        ZStack {
            Color.black.opacity(0.68).edgesIgnoringSafeArea(.all)
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
                .background(Color.black.opacity(0.3).cornerRadius(12))

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
                            .background(Image("ui-btn-orange").resizable(capInsets: modalCapInsets, resizingMode: .stretch))
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
                            .background(Image("ui-btn-classic").resizable(capInsets: modalCapInsets, resizingMode: .stretch))
                    }
                }
            }
            .padding(22)
            .frame(width: 340)
            .background(Image("ui-btn-darkblue").resizable(capInsets: modalCapInsets, resizingMode: .stretch))
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
        Text("\(value)").font(.custom("UbuntuSans-Bold", size: 14)).foregroundColor(.white)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(Image("ui-bar-darkcyan").resizable(capInsets: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10), resizingMode: .stretch))
}
