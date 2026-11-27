import XCTest
import SwiftUI
import UIKit
import Metal
@testable import AgarioApp

// MARK: - Golden Vector Codable Models

private struct GoldenVectors: Decodable {
    struct Metadata: Decodable {
        let constants: [String: Double]
    }
    struct MassSpeedMerge: Decodable {
        let mass: Double
        let radius: Double
        let speed: Double
        let mergeTimerSec: Double
    }
    struct SplitAndEject: Decodable {
        let mass: Double
        let radius: Double
        let canSplit: Bool
        let canEject: Bool
        let splitChildMass: Double
        let splitChildRadius: Double
        let splitImpulsePerSec: Double
        let ejectImpulsePerSec: Double
        let ejectPelletMass: Double
    }
    struct VirusVec: Decodable {
        let cellMass: Double
        let cellCount: Int
        let canPopVirus: Bool
        let popMinMass: Double
        let virusSplitMass: Double
    }
    struct EatOverlapVec: Decodable {
        let eaterMass: Double
        let victimMass: Double
        let dist: Double
        let expectedEat: Bool
    }
    struct ImpulseDecayVec: Decodable {
        let dt: Double
        let factor: Double
    }
    struct JoystickVec: Decodable {
        let offsetX: Double
        let offsetY: Double
        let maxRadius: Double
        let expectedScale: Double
        let expectedStopped: Bool
    }
    struct CameraZoomVec: Decodable {
        let viewportName: String
        let w: Double
        let h: Double
        let totalRadius: Double
        let cellCount: Int
        let expectedZoom: Double
        let expectedInputDist: Double
        let expectedWorldReach: Double
    }

    let metadata: Metadata
    let massSpeedMergeVectors: [MassSpeedMerge]
    let splitAndEjectVectors: [SplitAndEject]
    let virusVectors: [VirusVec]
    let eatOverlapVectors: [EatOverlapVec]
    let impulseDecayVectors: [ImpulseDecayVec]
    let joystickVectors: [JoystickVec]
    let cameraZoomVectors: [CameraZoomVec]
}

final class AgarParityTests: XCTestCase {

    private func loadGoldenVectors() throws -> GoldenVectors {
        let testBundle = Bundle(for: AgarParityTests.self)
        let url = testBundle.url(forResource: "AgarGoldenVectors", withExtension: "json", subdirectory: "Fixtures")
            ?? testBundle.url(forResource: "AgarGoldenVectors", withExtension: "json")
        let resolved = try XCTUnwrap(url, "Missing AgarGoldenVectors.json in test bundle")
        let data = try Data(contentsOf: resolved)
        return try JSONDecoder().decode(GoldenVectors.self, from: data)
    }

    func testGoldenVectorsPhysicsAndCameraParity() throws {
        let gv = try loadGoldenVectors()
        let tol = 1e-5
        let c = gv.metadata.constants

        XCTAssertEqual(OriginalGameplay.arenaSideLength, c["arenaSideLength"]!, accuracy: tol)
        XCTAssertEqual(Double(OriginalGameplay.offlineArenaSideLength), c["offlineArenaSideLength"]!, accuracy: tol)
        XCTAssertEqual(OriginalGameplay.baseRadius, c["baseRadius"]!, accuracy: tol)
        XCTAssertEqual(OriginalGameplay.minRadiusToShoot, c["minRadiusToShoot"]!, accuracy: tol)
        XCTAssertEqual(OriginalGameplay.minRadiusToSplit, c["minRadiusToSplit"]!, accuracy: tol)
        XCTAssertEqual(OriginalGameplay.shotMassBaseRadius, c["shotMassBaseRadius"]!, accuracy: tol)
        XCTAssertEqual(OriginalGameplay.virusBaseRadius, c["virusBaseRadius"]!, accuracy: tol)
        XCTAssertEqual(OriginalGameplay.virusSplitRadius, c["virusSplitRadius"]!, accuracy: tol)
        XCTAssertEqual(OriginalGameplay.velocityMultiplier, c["velocityMultiplier"]!, accuracy: tol)
        XCTAssertEqual(OriginalGameplay.inputFactorPow, c["inputFactorPow"]!, accuracy: tol)
        XCTAssertEqual(OriginalGameplay.baseVelocityCompensation, c["baseVelocityCompensation"]!, accuracy: tol)
        XCTAssertEqual(OriginalGameplay.cellDeceleration, c["cellDeceleration"]!, accuracy: tol)
        XCTAssertEqual(OriginalGameplay.onSplitVelocity, c["onSplitVelocity"]!, accuracy: tol)
        XCTAssertEqual(OriginalGameplay.onShootFoodVelocity, c["onShootFoodVelocity"]!, accuracy: tol)
        XCTAssertEqual(OriginalGameplay.mitosisPositionFactor, c["mitosisPositionFactor"]!, accuracy: tol)
        XCTAssertEqual(OriginalGameplay.scaleFactorForEating, c["scaleFactorForEating"]!, accuracy: tol)
        XCTAssertEqual(OriginalGameplay.eatMassRatio, c["eatMassRatio"]!, accuracy: tol)
        XCTAssertEqual(OriginalGameplay.overlapRatioForEating, c["overlapRatioForEating"]!, accuracy: tol)
        XCTAssertEqual(Double(OriginalGameplay.percentageOfCellToSquash), c["percentageOfCellToSquash"]!, accuracy: tol)
        XCTAssertEqual(Double(OriginalGameplay.zoomMultiplier), c["zoomMultiplier"]!, accuracy: tol)
        XCTAssertEqual(Double(OriginalGameplay.cameraPositionSnapRate), c["cameraPositionSnapRate"]!, accuracy: tol)
        XCTAssertEqual(Double(OriginalGameplay.cameraScaleSnapRate), c["cameraScaleSnapRate"]!, accuracy: tol)

        for v in gv.massSpeedMergeVectors {
            XCTAssertEqual(OriginalGameplay.radius(forMass: v.mass), v.radius, accuracy: tol, "radius(mass:\(v.mass))")
            XCTAssertEqual(OriginalGameplay.speed(forMass: v.mass), v.speed, accuracy: tol, "speed(mass:\(v.mass))")
            XCTAssertEqual(AgarPhysicsCore.mergeDuration(forNewCellMass: CGFloat(v.mass)), v.mergeTimerSec, accuracy: tol, "mergeTimer(mass:\(v.mass))")
        }

        for v in gv.splitAndEjectVectors {
            XCTAssertEqual(v.mass >= OriginalGameplay.minSplitMass, v.canSplit, "canSplit(mass:\(v.mass))")
            XCTAssertEqual(v.mass >= OriginalGameplay.minEjectMass - 1e-6, v.canEject, "canEject(mass:\(v.mass))")
            XCTAssertEqual(OriginalGameplay.radius(forMass: v.splitChildMass), v.splitChildRadius, accuracy: tol, "splitChildRadius(mass:\(v.mass))")
            XCTAssertEqual(OriginalGameplay.splitImpulsePerSecond, v.splitImpulsePerSec, accuracy: tol)
            XCTAssertEqual(OriginalGameplay.ejectImpulsePerSecond, v.ejectImpulsePerSec, accuracy: tol)
            XCTAssertEqual(OriginalGameplay.ejectPelletMass, v.ejectPelletMass, accuracy: tol)
        }

        for v in gv.virusVectors {
            let popMin = OriginalGameplay.virusBaseMass * OriginalGameplay.eatMassRatio
            XCTAssertEqual(popMin, v.popMinMass, accuracy: tol)
            XCTAssertEqual(OriginalGameplay.virusSplitMass, v.virusSplitMass, accuracy: tol)
            XCTAssertEqual(v.cellMass >= popMin, v.canPopVirus)
        }

        for v in gv.eatOverlapVectors {
            let rEater = CGFloat(OriginalGameplay.radius(forMass: v.eaterMass))
            let canEat = AgarPhysicsCore.canEat(
                eaterMass: CGFloat(v.eaterMass),
                eaterRadius: rEater,
                victimMass: CGFloat(v.victimMass),
                dx: CGFloat(v.dist),
                dy: 0
            )
            XCTAssertEqual(canEat, v.expectedEat, "eat(\(v.eaterMass) vs \(v.victimMass) @ \(v.dist))")
        }

        for v in gv.impulseDecayVectors {
            XCTAssertEqual(OriginalGameplay.impulseDecay(dt: v.dt), v.factor, accuracy: tol, "impulseDecay(dt:\(v.dt))")
        }

        for v in gv.joystickVectors {
            var joy = AgarJoystickInput()
            joy.updateTouch(offset: CGSize(width: v.offsetX, height: v.offsetY), maxRadius: CGFloat(v.maxRadius))
            XCTAssertEqual(Double(joy.scale), v.expectedScale, accuracy: tol, "joy.scale(\(v.offsetX))")
            let magSq = joy.axis.width * joy.axis.width + joy.axis.height * joy.axis.height
            XCTAssertEqual(magSq < 0.01, v.expectedStopped, "joy.stopped(\(v.offsetX))")
        }

        for v in gv.cameraZoomVectors {
            let vp = CGSize(width: v.w, height: v.h)
            let zoom = Double(OriginalGameplay.calculateZoom(totalRadius: CGFloat(v.totalRadius), cellCount: v.cellCount, viewportSize: vp))
            let reach = AgarPhysicsCore.worldCursorReach(
                cells: [PlayerCell(ownerID: UUID(), position: .zero, mass: CGFloat((v.totalRadius * v.totalRadius) / 100.0), targetMass: CGFloat((v.totalRadius * v.totalRadius) / 100.0), color: .cyan, name: "P")],
                viewportSize: vp
            )
            // Adjust for exact totalRadius when cellCount > 1
            let inputDist = Double(OriginalGameplay.inputDistance(for: vp))
            let arenaZ = Double(OriginalGameplay.arenaZoomForInput(totalRadius: CGFloat(v.totalRadius), cellCount: v.cellCount, viewportSize: vp))
            XCTAssertEqual(zoom, v.expectedZoom, accuracy: tol, "\(v.viewportName) r=\(v.totalRadius) n=\(v.cellCount)")
            XCTAssertEqual(inputDist, v.expectedInputDist, accuracy: tol)
            XCTAssertEqual(inputDist / max(arenaZ, 0.05), v.expectedWorldReach, accuracy: tol)
            XCTAssertGreaterThan(reach.worldReach, 0)
        }
    }

    @MainActor
    func testSimulatorVisualSnapshots() throws {
        MyFont.registerFonts()
        let snapDir = ProcessInfo.processInfo.environment["AGAR_SNAPSHOT_DIR"]
            ?? (NSTemporaryDirectory() as NSString).appendingPathComponent("agar_snapshots")
        try FileManager.default.createDirectory(atPath: snapDir, withIntermediateDirectories: true)

        let phoneSize = CGSize(width: 852, height: 393)
        let s = OriginalGameplay.uiScale(for: phoneSize)

        @discardableResult
        func saveSnapshot(_ image: UIImage, name: String) throws -> UIImage {
            let png = try XCTUnwrap(image.pngData(), "PNG encoding failed for \(name)")
            let outURL = URL(fileURLWithPath: snapDir).appendingPathComponent(name)
            try? png.write(to: outURL)
            let att = XCTAttachment(image: image)
            att.name = name
            att.lifetime = .keepAlways
            add(att)
            XCTAssertGreaterThan(png.count, 2000, "\(name) PNG unexpectedly tiny")
            return image
        }

        func renderSwiftUI<V: View>(_ view: V, size: CGSize) throws -> UIImage {
            let wrapped = view
                .frame(width: size.width, height: size.height)
                .background(Color.white)
            let renderer = ImageRenderer(content: wrapped)
            renderer.scale = 2.0
            renderer.proposedSize = .init(size)
            return try XCTUnwrap(renderer.uiImage, "ImageRenderer returned nil")
        }

        // 1. MenuMain
        let menuView = MainMenu(
            isPlaying: .constant(false),
            zoomLevel: .constant(1.0),
            selectedSkinName: .constant("Dragon"),
            playerName: .constant("Captain Idris"),
            showPlayerLevel: .constant(true),
            playerLevel: .constant(28),
            playerStartMass: .constant(50),
            botStartMass: .constant(50),
            randomizeBotStartMass: .constant(true),
            targetBotCount: .constant(55),
            feedBotCount: .constant(0),
            botSkill: .constant(1.0),
            lastMatchStats: MatchSummaryStats(highestMass: 1840, foodEaten: 412, cellsEaten: 9, timeAliveSec: 268, leaderboardTimeSec: 112, topPosition: 2),
            onPlayOnline: {}
        )
        try saveSnapshot(renderSwiftUI(menuView, size: phoneSize), name: "01_MenuMain.png")

        // 2. Settings
        try saveSnapshot(renderSwiftUI(menuView.settingsModalOverlay(scale: s, sideInset: 48, containerSize: phoneSize), size: phoneSize), name: "02_Settings.png")

        // 3. Skins Selector
        try saveSnapshot(renderSwiftUI(menuView.skinsModalOverlay(scale: s, containerSize: phoneSize), size: phoneSize), name: "03_Skins.png")

        // 4. HUD + Expanded Leaderboard + Controls + Open Emotes + Joystick (at 50/255 composite opacity)
        let hudView = ZStack {
            Color(hex: 0xF5FAFF)
            TopBarHUD(
                score: 123456,
                tokenCount: 42,
                fps: 60,
                showFPS: true,
                friendCount: 1,
                inParty: true,
                leaderboardRows: [
                    LeaderboardHUDRow(rank: 1, name: "Bot_Alpha", isPlayer: false),
                    LeaderboardHUDRow(rank: 2, name: "Bot_Beta", isPlayer: false, isPartyMember: true),
                    LeaderboardHUDRow(rank: 3, name: "Bot_Gamma", isPlayer: false),
                    LeaderboardHUDRow(rank: 4, name: "Bot_Delta", isPlayer: false),
                    LeaderboardHUDRow(rank: 5, name: "Bot_Epsilon", isPlayer: false),
                    LeaderboardHUDRow(rank: 10, name: "Captain Idris", isPlayer: true)
                ],
                onPause: {}
            )
            EmojiWidgetHUD(isOpen: true, toggleSeqID: 1, isOnCooldown: false, onToggle: {}, onSelect: { _ in })
            ActionButtonsHUD(canSplit: true, canFeed: true, isFeedingHeld: false, feedButtonScale: 1.0, macroButtonScale: 1.0, feedHoldThreshold: 1.4, controlLayout: 2, onSplit: {}, onMacroDown: {}, onMacroUp: {}, onFeedDown: {}, onFeedUp: {})
            JoystickView(
                joystickOffset: .constant(CGSize(width: 24 * s, height: -12 * s)),
                joystickBasePosition: .constant(CGPoint(x: 180, y: 250)),
                uiScale: s
            )
        }
        try saveSnapshot(renderSwiftUI(hudView, size: phoneSize), name: "04_HUD_Joystick.png")

        // 5 & 6. Metal Offscreen Snapshots: Classic Arena (No Border) & Solo Boundary Overlay
        if MTLCreateSystemDefaultDevice() != nil {
            let pOwner = UUID()
            let bOwner = UUID()
            let pCell = PlayerCell(ownerID: pOwner, position: CGPoint(x: 4000, y: 4000), mass: 260, targetMass: 260, color: Color(hex: 0x00A8F3), name: "Captain Idris", skinName: "Dragon")
            let bCell = PlayerCell(ownerID: bOwner, position: CGPoint(x: 4320, y: 4030), mass: 160, targetMass: 160, color: Color(hex: 0xFF6B35), name: "Rival", skinName: nil, isBot: true)
            let mm = EjectedMassManager()
            mm.add(position: CGPoint(x: 4160, y: 3960), direction: CGSize(width: 1, height: 0), initialSpeed: 0, color: .cyan, ownerID: pOwner, sourceCellID: pCell.id, borderColor: .blue, now: 0)

            let boxClassic = ArenaRenderBox()
            boxClassic.worldSize = OriginalGameplay.offlineArenaSideLength
            boxClassic.cameraPos = CGPoint(x: 4100, y: 4000)
            boxClassic.zoom = OriginalGameplay.calculateZoom(totalRadius: pCell.cachedSolidRadius, cellCount: 1, viewportSize: phoneSize)
            boxClassic.showBoundaryOverlay = false
            boxClassic.playerCells = [pCell]
            boxClassic.botCells = [bCell]
            boxClassic.viruses = [Virus(position: CGPoint(x: 3820, y: 4120))]
            boxClassic.massManager = mm
            boxClassic.ownerLevels = [pOwner: 42]
            boxClassic.activeEmoteAsset = "emoji-tongue"
            boxClassic.activeEmoteStartedAt = 0
            boxClassic.activeEmoteExpiresAt = 1000

            let coordClassic = ArenaMetalCoordinator(box: boxClassic)
            let classicImg = try XCTUnwrap(coordClassic.renderOffscreenSnapshot(size: phoneSize, scale: 2.0))
            try saveSnapshot(classicImg, name: "05_Arena_Classic_CellsEmoteVirus.png")

            // Assert Classic camera near world edge (0,0) shows zero boundary red pixels
            let boxClassicEdge = ArenaRenderBox()
            boxClassicEdge.worldSize = OriginalGameplay.offlineArenaSideLength
            boxClassicEdge.cameraPos = CGPoint(x: 20, y: 20)
            boxClassicEdge.zoom = 0.65
            boxClassicEdge.showBoundaryOverlay = false
            let edgeClassicImg = try XCTUnwrap(ArenaMetalCoordinator(box: boxClassicEdge).renderOffscreenSnapshot(size: phoneSize, scale: 2.0))
            XCTAssertFalse(hasRedBoundaryPixels(edgeClassicImg), "Classic arena must not render red boundary wall")

            // 6. Solo Arena Boundary Overlay (showBoundaryOverlay = true)
            let boxSolo = ArenaRenderBox()
            boxSolo.worldSize = OriginalGameplay.offlineArenaSideLength
            boxSolo.cameraPos = CGPoint(x: 40, y: 40)
            boxSolo.zoom = 0.65
            boxSolo.showBoundaryOverlay = true
            let soloImg = try XCTUnwrap(ArenaMetalCoordinator(box: boxSolo).renderOffscreenSnapshot(size: phoneSize, scale: 2.0))
            try saveSnapshot(soloImg, name: "06_Arena_Solo_Boundary.png")
            XCTAssertTrue(hasRedBoundaryPixels(soloImg), "Solo arena boundary overlay should render crimson border")
        }
    }

    private func hasRedBoundaryPixels(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage,
              let dp = cg.dataProvider,
              let data = dp.data,
              let ptr = CFDataGetBytePtr(data) else { return false }
        let bpp = cg.bitsPerPixel / 8
        let len = CFDataGetLength(data)
        var hits = 0
        var i = 0
        while i + 3 < len {
            let r = Int(ptr[i])
            let g = Int(ptr[i + 1])
            let b = Int(ptr[i + 2])
            if r > 170 && g < 80 && b < 100 {
                hits += 1
                if hits > 40 { return true }
            }
            i += bpp * 4
        }
        return false
    }
}
