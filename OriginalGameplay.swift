import CoreGraphics
import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Values recovered from the original client's `GameConfiguration.json` and
/// `ValueMap.json`. Simulation code uses seconds; the original configuration's
/// velocity values are expressed per 20 Hz gameplay tick.
enum OriginalGameplay {
    static let arenaSideLength: Double = 11180
    static let arenaSideLengthCGFloat: CGFloat = 11180
    /// `Offline Mode - Settings`: `arenaSizeRatio = 0.5` -> `round(arenaSideLength * sqrt(0.5))` = `7905` (`0x10003f48c`).
    static let offlineArenaSizeRatio: Double = 0.5
    static let offlineArenaSideLength: CGFloat = CGFloat(Int((arenaSideLength * sqrt(offlineArenaSizeRatio)).rounded()))

    static let baseRadius: Double = 31.6227766016837
    static let minRadiusToShoot: Double = 56.56854249
    static let minRadiusToSplit: Double = 60
    static let foodBaseRadius: Double = 10
    static let shotMassBaseRadius: Double = 40
    static let shotMassBaseRadiusCGFloat: CGFloat = 40
    static let virusBaseRadius: Double = 100.01
    static let virusSplitRadius: Double = 141.421356237
    static let virusEdgeRadiusMultiplier: Double = 0.02

    static let velocityMultiplier: Double = 106.06601717
    static let inputFactorPow: Double = -0.45
    static let baseVelocityCompensation: Double = 20
    static let cellDeceleration: Double = 0.87965
    static let onSplitVelocity: Double = 100
    static let onShootFoodVelocity: Double = 100
    static let directionAngleVariation: Double = 0.2
    static let spawnFoodVelocityVariation: Double = 0.2
    static let minVelocityToMove: Double = 0.01
    /// Split child offset from the parent centre (`mitosisPositionFactor` = 20).
    static let mitosisPositionFactor: Double = 20

    static let scaleFactorForEating: Double = 0.866
    /// Cell must be this much heavier than a virus to eat it (`1 / 0.866^2`).
    static let eatMassRatio: Double = 1.0 / (scaleFactorForEating * scaleFactorForEating)
    static let scaleFactorForMergingBack: Double = 0.999
    static let overlapRatioForEating: Double = 0.5
    static let maxMagnitudeFactor: Double = 1.5
    static let percentageOfCellToSquash: CGFloat = 0.4

    // BaseArenaView camera constants (`agar.io` `0x100374bbc..0x10037579c`)
    static let cameraScaleSnapRate: CGFloat = 0.07
    static let cameraPositionSnapRate: CGFloat = 0.315
    static let zoomMultiplier: CGFloat = 1.5
    static let minZoomValue: CGFloat = 0.05

    /// Screen-point multiplier (`h / designH`) for world camera zoom:
    /// iPhone uses FixedHeight 320pt; iPad uses FixedWidth 768pt (`AppDelegate` `0x1002a714c`).
    static func arenaScreenScale(for viewportSize: CGSize, isPhoneOverride: Bool? = nil) -> CGFloat {
        let w = max(viewportSize.width, 1)
        let h = max(viewportSize.height, 1)
        #if canImport(UIKit)
        let isPhone = isPhoneOverride ?? (UIDevice.current.userInterfaceIdiom != .pad)
        #else
        let isPhone = isPhoneOverride ?? true
        #endif
        let designH: CGFloat = isPhone ? 320.0 : (768.0 * (h / w))
        return h / max(designH, 1)
    }

    static func calculateZoom(totalRadius: CGFloat,
                              cellCount: Int,
                              viewportSize: CGSize,
                              customZoomMultiplier: CGFloat = 1.0,
                              isPhoneOverride: Bool? = nil) -> CGFloat {
        let w = max(viewportSize.width, 1)
        let h = max(viewportSize.height, 1)
        #if canImport(UIKit)
        // BaseArenaView::calculateWindowHeight (`0x10037506c`): only deviceType == 0 (iPhone)
        // divides windowHeight by `(winW/winH)/zoomMultiplier`; iPad uses FixedWidth `768 * (h / w)`.
        let isPhone = isPhoneOverride ?? (UIDevice.current.userInterfaceIdiom != .pad)
        #else
        let isPhone = isPhoneOverride ?? true
        #endif
        let designH: CGFloat = isPhone ? 320.0 : (768.0 * (h / w))
        let designW = isPhone ? (designH * (w / h)) : 768.0
        let screenScale = h / max(designH, 1)
        let phoneRatio = isPhone ? ((designW / designH) / zoomMultiplier) : 1.0
        let windowHeight = designH / max(phoneRatio, 0.001)
        let rEff = max(totalRadius, CGFloat(baseRadius))
        let n = CGFloat(max(1, cellCount))
        let scaleFactor = pow(n, 0.1)
        let maxScaleFactor = pow(n, 0.32)
        let minZoom = max(minZoomValue, (0.37 * windowHeight * maxScaleFactor) / rEff)
        let q = windowHeight / (42.0 * rEff)
        let cocosZoom = min(pow(max(q, 0.0001), 0.4) * scaleFactor, minZoom)
        return cocosZoom * screenScale * customZoomMultiplier
    }

    /// `JoystickView::initWithEaseFactor:` (`0x1000e2b1c`): iPad sizes joystick from physical inch height
    /// (`1.04434"` bg, `0.5446"` stick); iPhone scales native `82x82` / `42.5x42.5` Controls sprites by `uiScale`.
    static func joystickMetrics(for viewportSize: CGSize, uiScale s: CGFloat, isPhoneOverride: Bool? = nil) -> (bgSide: CGFloat, knobSide: CGFloat, maxRadius: CGFloat) {
        #if canImport(UIKit)
        let isPhone = isPhoneOverride ?? (UIDevice.current.userInterfaceIdiom != .pad)
        #else
        let isPhone = isPhoneOverride ?? true
        #endif
        if !isPhone {
            // Standard iPad Retina density is 264 ppi / 2x = 132 pt/inch.
            let ptPerInch: CGFloat = 132.0
            let bg = CGFloat(1.04434) * ptPerInch
            let knob = CGFloat(0.5446) * ptPerInch
            let maxR = bg * 0.5 - knob * 0.25
            return (bg, knob, maxR)
        }
        let bg = 82.0 * s
        let knob = 42.5 * s
        let maxR = bg * 0.5 - knob * 0.25
        return (bg, knob, maxR)
    }

    /// Screen-normalised input distance (`0x1000b5550` + `0x10003f470`): `sqrt(500000 / aspect) / 1.5`.
    static func inputDistance(for viewportSize: CGSize) -> CGFloat {
        let w = max(viewportSize.width, 1)
        let h = max(viewportSize.height, 1)
        let aspect = max(w, h) / min(w, h)
        let normH = CGFloat(sqrt(500_000.0 / Double(aspect)))
        return normH / CGFloat(maxMagnitudeFactor)
    }

    /// Arena zoom in the normalised `normH` space used for `worldReach = inputDistance / arenaZoom`.
    static func arenaZoomForInput(totalRadius: CGFloat, cellCount: Int, viewportSize: CGSize) -> CGFloat {
        let w = max(viewportSize.width, 1)
        let h = max(viewportSize.height, 1)
        let aspect = max(w, h) / min(w, h)
        let normH = CGFloat(sqrt(500_000.0 / Double(aspect)))
        let rEff = max(totalRadius, CGFloat(baseRadius))
        let n = CGFloat(max(1, cellCount))
        let scaleFactor = pow(n, 0.1)
        let maxScaleFactor = pow(n, 0.32)
        let minZoom = max(minZoomValue, (0.37 * normH * maxScaleFactor) / rEff)
        let q = normH / (42.0 * rEff)
        return min(pow(max(q, 0.0001), 0.4) * scaleFactor, minZoom)
    }

    /// `BaseArenaView::calcPlayerCellsMassCenter` (`0x100375878`): weights by cell radius, not mass.
    static func radiusWeightedCenter(positionsAndRadii: [(CGPoint, CGFloat)]) -> CGPoint {
        var totalR: CGFloat = 0
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        for (pos, r) in positionsAndRadii {
            let w = max(r, 0.001)
            totalR += w
            sumX += pos.x * w
            sumY += pos.y * w
        }
        guard totalR > 0 else { return .zero }
        return CGPoint(x: sumX / totalR, y: sumY / totalR)
    }

    static func radius(forMass mass: Double) -> Double {
        sqrt(max(mass, 0)) * 10
    }

    static func radius(forMass mass: CGFloat) -> CGFloat {
        sqrt(max(mass, 0)) * 10
    }

    static func mass(forRadius radius: Double) -> Double {
        radius * radius / 100
    }

    static func speed(forRadius radius: Double) -> Double {
        velocityMultiplier * pow(max(radius, 0.01), inputFactorPow) * baseVelocityCompensation
    }

    static func speed(forMass mass: Double) -> Double {
        speed(forRadius: radius(forMass: mass))
    }

    static func speed(forMass mass: CGFloat) -> CGFloat {
        CGFloat(speed(forMass: Double(mass)))
    }

    static var minSplitMass: Double { mass(forRadius: minRadiusToSplit) }
    static var minEjectMass: Double { mass(forRadius: minRadiusToShoot) }
    static var ejectPelletMass: Double { mass(forRadius: shotMassBaseRadius) }
    static var virusBaseMass: Double { mass(forRadius: virusBaseRadius) }
    static var virusSplitMass: Double { mass(forRadius: virusSplitRadius) }

    static var splitImpulsePerSecond: Double { onSplitVelocity * baseVelocityCompensation }
    static var ejectImpulsePerSecond: Double { onShootFoodVelocity * baseVelocityCompensation }

    static func impulseDecay(dt: Double) -> Double {
        // Exact `agar.io` ARM64 (`0x10004c4c4`): factor = 1.0 - baseVelocityCompensation * (1.0 - cellDeceleration) * dt
        return max(0.0, 1.0 - baseVelocityCompensation * (1.0 - cellDeceleration) * dt)
    }

    static func impulseDecay(dt: CGFloat) -> CGFloat {
        CGFloat(impulseDecay(dt: Double(dt)))
    }

    /// Cocos2d `.ccbi` design point scale (`480x320` base resolution).
    static func uiScale(for size: CGSize) -> CGFloat {
        let s = min(max(size.height, 1) / 320.0, max(size.width, 1) / 480.0)
        return max(0.5, s)
    }

    static func menuBackgroundSpritePath(for size: CGSize) -> String {
        let aspect = max(size.width, 1) / max(size.height, 1)
        if aspect <= 1.48 {
            return "GeneratedAssets/images/Bundle/Background/background-ipadpro.png"
        }
        if aspect >= 1.95 {
            return "GeneratedAssets/images/Bundle/Background/backgroundSuperWide.png"
        }
        if aspect >= 1.65 {
            return "GeneratedAssets/images/Bundle/Background/backgroundWide.png"
        }
        return "GeneratedAssets/images/Bundle/Background/background.png"
    }
}

/// Crisp 9-slice `MCFramedSprite` renderer. SwiftUI `.resizable()` ignores
/// `Contents.json` `resizing` slices unless `capInsets:` is passed explicitly,
/// so we compute point insets directly from each loaded UIImage's dimensions
/// and `MCFS_*.plist` normalized margins (works cleanly on @2x and -ipadhd @3x).
struct MCFSFrame: View {
    let name: String

    static func marginFractions(for name: String) -> (top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        switch name {
        case "mcfs-divider", "mcfs-leaderboard-party-outline":
            return (0, 0, 0, 0)
        case "mcfs-leaderboard-collapsed":
            return (0.10, 0.90, 0.90, 0.10)
        case "mcfs-leaderboard-expanded":
            return (0.80, 0.40, 0.10, 0.40)
        case "mcfs-leaderboard-content-float":
            return (0.10, 0.40, 0.80, 0.40)
        case "mcfs-red-timer-frame":
            return (0.0, 0.33, 0.0, 0.65)
        case "mcfs-bar-darkcyan", "ui-bar-darkcyan":
            return (0.0, 0.40, 0.0, 0.40)
        default:
            return (0.40, 0.40, 0.40, 0.40)
        }
    }

    static func capInsets(for name: String) -> EdgeInsets {
        let f = marginFractions(for: name)
        guard f.top > 0 || f.leading > 0 || f.bottom > 0 || f.trailing > 0 else {
            return EdgeInsets()
        }
        #if canImport(UIKit)
        if let img = UIImage(named: name) {
            let w = img.size.width
            let h = img.size.height
            let vSum = f.top + f.bottom
            let hSum = f.leading + f.trailing
            let vScale = vSum > 0.96 ? (0.96 / vSum) : 1.0
            let hScale = hSum > 0.96 ? (0.96 / hSum) : 1.0
            let top = h * f.top * vScale
            let bottom = h * f.bottom * vScale
            let leading = w * f.leading * hScale
            let trailing = w * f.trailing * hScale
            return EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing)
        }
        #endif
        return EdgeInsets(top: 7, leading: 7, bottom: 7, trailing: 7)
    }

    var body: some View {
        Image(name)
            .resizable(capInsets: Self.capInsets(for: name), resizingMode: .stretch)
    }
}

enum PotionTier: String, Codable, CaseIterable {
    case common = "Common"
    case rare = "Rare"
    case exotic = "Exotic"
    case epic = "Epic"
    case legendary = "Legendary"

    var iconAsset: String {
        switch self {
        case .common: return "potion-common"
        case .rare: return "potion-rare"
        case .exotic: return "potion-exotic"
        case .epic: return "potion-epic"
        case .legendary: return "potion-legendary"
        }
    }

    var badgeColor: Color {
        switch self {
        case .common: return Color(red: 0.33, green: 0.78, blue: 0.15)
        case .rare: return Color(red: 0.0, green: 0.76, blue: 0.96)
        case .exotic: return Color(red: 0.96, green: 0.45, blue: 0.12)
        case .epic: return Color(red: 0.66, green: 0.30, blue: 0.92)
        case .legendary: return Color(red: 0.98, green: 0.72, blue: 0.06)
        }
    }

    var brewDurationSeconds: TimeInterval {
        switch self {
        case .common: return 90        // 1m 30s
        case .rare: return 300         // 5m
        case .exotic: return 600       // 10m
        case .epic: return 1200        // 20m
        case .legendary: return 1800   // 30m
        }
    }

    var rewardCoinsRange: ClosedRange<Int> {
        switch self {
        case .common: return 150...280
        case .rare: return 320...520
        case .exotic: return 550...850
        case .epic: return 900...1400
        case .legendary: return 1600...2500
        }
    }

    var rewardDNARange: ClosedRange<Int> {
        switch self {
        case .common: return 8...14
        case .rare: return 16...28
        case .exotic: return 28...44
        case .epic: return 45...75
        case .legendary: return 85...140
        }
    }

    var skinPieceCount: Int {
        switch self {
        case .common: return 20
        case .rare: return 50
        case .exotic: return 120
        case .epic: return 200
        case .legendary: return 350
        }
    }
}

struct PotionSlotState: Identifiable, Codable, Equatable {
    let id: Int
    var tier: PotionTier?
    var brewStartedAt: TimeInterval?
    var brewDuration: TimeInterval

    func isBrewing(now: TimeInterval) -> Bool {
        guard tier != nil, let start = brewStartedAt else { return false }
        return now < start + brewDuration
    }

    func isReady(now: TimeInterval) -> Bool {
        guard tier != nil, let start = brewStartedAt else { return false }
        return now >= start + brewDuration
    }

    func remainingSeconds(now: TimeInterval) -> TimeInterval {
        guard let start = brewStartedAt else { return brewDuration }
        return max(0, (start + brewDuration) - now)
    }

    func rushDNACost(now: TimeInterval) -> Int {
        let rem = remainingSeconds(now: now)
        return max(2, Int(ceil(rem / 45.0)))
    }
}

struct PotionReward: Identifiable, Equatable {
    let id = UUID()
    let tier: PotionTier
    let coins: Int
    let dna: Int
    let skinName: String
    let skinPieces: Int
}

final class PotionStore: ObservableObject {
    static let shared = PotionStore()
    private let storageKey = "macro.potionSlots.v2"

    @Published var slots: [PotionSlotState] = []
    @Published var lastAwardedSlotTier: PotionTier? = nil

    private init() {
        if let raw = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([PotionSlotState].self, from: raw),
           decoded.count == 4 {
            slots = decoded
        } else {
            let now = Date().timeIntervalSince1970
            slots = [
                PotionSlotState(id: 0, tier: .exotic, brewStartedAt: now - 700, brewDuration: PotionTier.exotic.brewDurationSeconds),
                PotionSlotState(id: 1, tier: .rare, brewStartedAt: nil, brewDuration: PotionTier.rare.brewDurationSeconds),
                PotionSlotState(id: 2, tier: .common, brewStartedAt: nil, brewDuration: PotionTier.common.brewDurationSeconds),
                PotionSlotState(id: 3, tier: nil, brewStartedAt: nil, brewDuration: 0)
            ]
            save()
        }
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(slots) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    func startBrew(slotIndex: Int, now: TimeInterval = Date().timeIntervalSince1970) {
        guard slots.indices.contains(slotIndex), let tier = slots[slotIndex].tier else { return }
        slots[slotIndex].brewStartedAt = now
        slots[slotIndex].brewDuration = tier.brewDurationSeconds
        save()
    }

    func rushWithDNA(slotIndex: Int, dna: inout Int, now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard slots.indices.contains(slotIndex), slots[slotIndex].tier != nil else { return false }
        let cost = slots[slotIndex].rushDNACost(now: now)
        guard dna >= cost else { return false }
        dna -= cost
        slots[slotIndex].brewStartedAt = now - slots[slotIndex].brewDuration
        save()
        return true
    }

    func openPotion(slotIndex: Int, coins: inout Int, dna: inout Int, now: TimeInterval = Date().timeIntervalSince1970) -> PotionReward? {
        guard slots.indices.contains(slotIndex),
              let tier = slots[slotIndex].tier,
              slots[slotIndex].isReady(now: now) else { return nil }
        let c = Int.random(in: tier.rewardCoinsRange)
        let d = Int.random(in: tier.rewardDNARange)
        coins += c
        dna += d
        let featured = (1...387).randomElement().map { String($0) } ?? "1"
        let reward = PotionReward(tier: tier, coins: c, dna: d, skinName: featured, skinPieces: tier.skinPieceCount)
        slots[slotIndex] = PotionSlotState(id: slotIndex, tier: nil, brewStartedAt: nil, brewDuration: 0)
        save()
        return reward
    }

    @discardableResult
    func awardPostMatchPotion(score: Int, survivalSeconds: Int) -> PotionTier? {
        guard score >= 25 || survivalSeconds >= 10 else {
            lastAwardedSlotTier = nil
            return nil
        }
        guard let emptyIdx = slots.firstIndex(where: { $0.tier == nil }) else {
            lastAwardedSlotTier = nil
            return nil
        }
        let tier: PotionTier
        if score >= 2500 { tier = .legendary }
        else if score >= 1200 { tier = .epic }
        else if score >= 500 { tier = .exotic }
        else if score >= 180 { tier = .rare }
        else { tier = .common }
        slots[emptyIdx] = PotionSlotState(id: emptyIdx, tier: tier, brewStartedAt: nil, brewDuration: tier.brewDurationSeconds)
        lastAwardedSlotTier = tier
        save()
        return tier
    }

    func collectSamplePotion() -> Bool {
        guard let emptyIdx = slots.firstIndex(where: { $0.tier == nil }) else { return false }
        let roll: [PotionTier] = [.common, .common, .rare, .exotic, .epic]
        let tier = roll.randomElement() ?? .common
        slots[emptyIdx] = PotionSlotState(id: emptyIdx, tier: tier, brewStartedAt: nil, brewDuration: tier.brewDurationSeconds)
        save()
        return true
    }

    func readyCount(now: TimeInterval = Date().timeIntervalSince1970) -> Int {
        slots.filter { $0.isReady(now: now) }.count
    }
}
