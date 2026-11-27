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

        func renderSwiftUI<V: View>(_ view: V, size: CGSize, waitSec: TimeInterval = 0.75) throws -> UIImage {
            let root = AnyView(view.frame(width: size.width, height: size.height).background(Color.white))
            if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
               let keyWin = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first {
                let host = UIHostingController(rootView: root)
                let origFrame = keyWin.frame
                keyWin.frame = CGRect(origin: .zero, size: size)
                host.view.frame = CGRect(origin: .zero, size: size)
                host.view.backgroundColor = .white
                let parentVC = keyWin.rootViewController
                if let parentVC {
                    parentVC.addChild(host)
                    parentVC.view.addSubview(host.view)
                    host.didMove(toParent: parentVC)
                } else {
                    keyWin.addSubview(host.view)
                }
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(waitSec))
                host.view.layoutIfNeeded()
                let fmt = UIGraphicsImageRendererFormat()
                fmt.scale = 2.0
                fmt.opaque = true
                let img = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
                    host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                }
                if parentVC != nil { host.willMove(toParent: nil) }
                host.view.removeFromSuperview()
                if parentVC != nil { host.removeFromParent() }
                keyWin.frame = origFrame
                if hasColorVariance(img) {
                    return img
                }
            }
            let renderer = ImageRenderer(content: root)
            renderer.scale = 2.0
            renderer.proposedSize = .init(size)
            let img = try XCTUnwrap(renderer.uiImage, "ImageRenderer returned nil")
            XCTAssertTrue(hasColorVariance(img), "Rendered snapshot must not be solid/blank")
            return img
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
                onPause: {},
                initialLeaderboardExpanded: true
            )
            EmojiWidgetHUD(isOpen: true, toggleSeqID: 1, isOnCooldown: false, onToggle: {}, onSelect: { _ in })
            ActionButtonsHUD(canSplit: true, canFeed: true, isFeedingHeld: false, feedButtonScale: 1.0, macroButtonScale: 1.0, feedHoldThreshold: 1.4, controlLayout: 2, onSplit: {}, onMacroDown: {}, onMacroUp: {}, onFeedDown: {}, onFeedUp: {})
            JoystickView(
                joystickOffset: .constant(CGSize(width: 24 * s, height: -12 * s)),
                joystickBasePosition: .constant(CGPoint(x: 180, y: 250)),
                uiScale: s
            )
        }
        try saveSnapshot(renderSwiftUI(hudView, size: phoneSize, waitSec: 0.45), name: "04_HUD_Joystick.png")

        // 5 & 6. Metal Offscreen Snapshots: Classic Arena (No Border) & Solo Boundary Overlay
        if MTLCreateSystemDefaultDevice() != nil {
            let pOwner = UUID()
            let tOwner = UUID()
            let bOwner = UUID()
            let pCellEmote = PlayerCell(ownerID: pOwner, position: CGPoint(x: 3960, y: 4000), mass: 260, targetMass: 260, color: Color(hex: 0x00A8F3), name: "Captain Idris", skinName: "Dragon")
            let pCellText = PlayerCell(ownerID: tOwner, position: CGPoint(x: 4290, y: 3980), mass: 260, targetMass: 260, color: Color(hex: 0x33D1FF), name: "Portolan", skinName: nil)
            let bCell = PlayerCell(ownerID: bOwner, position: CGPoint(x: 4530, y: 4040), mass: 160, targetMass: 160, color: Color(hex: 0xFF6B35), name: "Rival", skinName: nil, isBot: true)
            let mm = EjectedMassManager()
            mm.add(position: CGPoint(x: 4135, y: 3910), direction: CGSize(width: 1, height: 0), initialSpeed: 0, color: .cyan, ownerID: pOwner, sourceCellID: pCellEmote.id, borderColor: .blue, now: 0)

            let boxClassic = ArenaRenderBox()
            boxClassic.worldSize = OriginalGameplay.offlineArenaSideLength
            boxClassic.cameraPos = CGPoint(x: 4210, y: 4000)
            boxClassic.zoom = OriginalGameplay.calculateZoom(totalRadius: pCellEmote.cachedSolidRadius, cellCount: 1, viewportSize: phoneSize)
            boxClassic.showBoundaryOverlay = false
            boxClassic.playerCells = [pCellEmote]
            boxClassic.botCells = [pCellText, bCell]
            boxClassic.viruses = [Virus(position: CGPoint(x: 3820, y: 4120))]
            boxClassic.massManager = mm
            boxClassic.ownerLevels = [pOwner: 42, tOwner: 42]
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

    // MARK: - Pillar 2: Zero-Fallback Font Resolution

    func testAllCustomFontsResolveNonNil() throws {
        MyFont.registerFonts()
        let requiredFonts = [
            "OpenSans-Bold",
            "OpenSans-SemiboldItalic",
            "Lato-Regular",
            "Lato-Heavy",
            "Ubuntu-Bold",
            "Ubuntu-Medium",
            "UbuntuSans-SemiBold",
            "UbuntuSans-Bold",
            "HelveticaNeue-Medium"
        ]
        for fontName in requiredFonts {
            XCTAssertNotNil(UIFont(name: fontName, size: 16), "Font '\(fontName)' failed to resolve via UIFont(name:size:)")
        }
        XCTAssertEqual(MyFont.normalizedPostScriptName(for: "Fonts/Bundle/Lato-Regular.ttf"), "Lato-Regular")
        XCTAssertEqual(MyFont.normalizedPostScriptName(for: ""), "Helvetica")
        XCTAssertNotEqual(MyFont.uiFont(named: "Lato-Regular.ttf", size: 14).fontName, "OpenSans-Bold")
        XCTAssertTrue(MyFont.uiFont(named: "Lato-Regular.ttf", size: 14).fontName.contains("Lato"))
    }

    // MARK: - Pillar 4A: All 23 Disassembled CCBI Easing Curves

    func testCCBIEasingAll23Cases() throws {
        let tol = 1e-5
        // Verify boundaries and exact formulas for all 23 jump-table cases (0x100af50e8)
        XCTAssertEqual(CCBIAnimationEvaluator.ease(0.0, type: 0, opt: 0), 0.0, accuracy: tol)
        XCTAssertEqual(CCBIAnimationEvaluator.ease(0.99, type: 0, opt: 0), 0.0, accuracy: tol)
        XCTAssertEqual(CCBIAnimationEvaluator.ease(1.0, type: 0, opt: 0), 1.0, accuracy: tol)
        XCTAssertEqual(CCBIAnimationEvaluator.ease(0.35, type: 1, opt: 0), 0.35, accuracy: tol)
        XCTAssertEqual(CCBIAnimationEvaluator.ease(0.5, type: 2, opt: 3), 0.125, accuracy: tol)
        XCTAssertEqual(CCBIAnimationEvaluator.ease(0.5, type: 3, opt: 3), 0.875, accuracy: tol)
        // Case 5: CCEaseElasticIn (0x100a93610)
        let e5Expected = -pow(2.0, 10.0 * (0.7 - 1.0)) * sin(((0.7 - 1.0) - 0.3 * 0.25) * (2.0 * .pi) / 0.3)
        XCTAssertEqual(CCBIAnimationEvaluator.ease(0.7, type: 5, opt: 0.3), e5Expected, accuracy: tol)
        XCTAssertEqual(CCBIAnimationEvaluator.ease(0.0, type: 5, opt: 0.3), 0.0, accuracy: tol)
        XCTAssertEqual(CCBIAnimationEvaluator.ease(1.0, type: 5, opt: 0.3), 1.0, accuracy: tol)
        // Case 14..16: CCEaseExponentialIn/Out/InOut
        XCTAssertEqual(CCBIAnimationEvaluator.ease(0.5, type: 14, opt: 0), pow(2.0, -5.0), accuracy: tol)
        XCTAssertEqual(CCBIAnimationEvaluator.ease(0.5, type: 15, opt: 0), 1.0 - pow(2.0, -5.0), accuracy: tol)
        XCTAssertEqual(CCBIAnimationEvaluator.ease(0.25, type: 16, opt: 0), 0.5 * pow(2.0, -5.0), accuracy: tol)
        // Case 17..19: CCEasePolynomialIn/Out/InOut (0x100a93200)
        XCTAssertEqual(CCBIAnimationEvaluator.ease(0.5, type: 17, opt: 3), 0.125, accuracy: tol)
        XCTAssertEqual(CCBIAnimationEvaluator.ease(0.5, type: 18, opt: 3), 0.875, accuracy: tol)
        XCTAssertEqual(CCBIAnimationEvaluator.ease(0.25, type: 19, opt: 3), 0.0625, accuracy: tol)
        // Case 20..22: CCEaseSineIn/Out/InOut
        XCTAssertEqual(CCBIAnimationEvaluator.ease(0.5, type: 20, opt: 0), 1.0 - cos(.pi * 0.25), accuracy: tol)
        XCTAssertEqual(CCBIAnimationEvaluator.ease(0.5, type: 21, opt: 0), sin(.pi * 0.25), accuracy: tol)
        XCTAssertEqual(CCBIAnimationEvaluator.ease(0.5, type: 22, opt: 0), 0.5, accuracy: tol)
    }

    // MARK: - Pillar 4B & 4C: 300-Tick 60 Hz Touch Trajectory + Audio Spy

    private struct Golden300Tick: Decodable {
        struct Viewport: Decodable { let w: Double; let h: Double }
        struct Action: Decodable {
            let tick: Int
            let offsetX: Double
            let offsetY: Double
            let isDragging: Bool
            let stopOnRelease: Bool
            let split: Bool
            let eject: Bool
            let virusPop: Bool
            let eatCell: Bool
            let eatOwnCell: Bool
        }
        struct Frame: Decodable {
            let tick: Int
            let x: Double
            let y: Double
            let vx: Double
            let vy: Double
            let zoom: Double
            let camX: Double
            let camY: Double
            let cellCount: Int
        }
        struct AudioEventJSON: Decodable {
            let soundID: String
            let tick: Int
            let volume: Double
        }
        let dt: Double
        let viewport: Viewport
        let worldSize: Double
        let actions: [Action]
        let frames: [Frame]
        let audioEvents: [AudioEventJSON]
    }

    func test300TickTrajectoryFeelAndAudioSpy() throws {
        let testBundle = Bundle(for: AgarParityTests.self)
        let url = testBundle.url(forResource: "Agar300TickGolden", withExtension: "json", subdirectory: "Fixtures")
            ?? testBundle.url(forResource: "Agar300TickGolden", withExtension: "json")
        let resolved = try XCTUnwrap(url, "Missing Agar300TickGolden.json in test bundle")
        let golden = try JSONDecoder().decode(Golden300Tick.self, from: Data(contentsOf: resolved))

        XCTAssertEqual(golden.actions.count, 300)
        XCTAssertEqual(golden.frames.count, 300)

        struct SimCell {
            var x: CGFloat
            var y: CGFloat
            var vx: CGFloat
            var vy: CGFloat
            var mass: CGFloat
        }

        let dt = CGFloat(golden.dt)
        let vp = CGSize(width: golden.viewport.w, height: golden.viewport.h)
        let worldSize = CGFloat(golden.worldSize)
        var joy = AgarJoystickInput()
        var cells = [SimCell(x: 3950, y: 3950, vx: 0, vy: 0, mass: 160)]

        let initTotalR = cells.reduce(CGFloat(0)) { $0 + OriginalGameplay.radius(forMass: $1.mass) }
        var zoom = OriginalGameplay.calculateZoom(totalRadius: initTotalR, cellCount: cells.count, viewportSize: vp)
        var camPos = CGPoint(x: 3950, y: 3950)

        let camSmooth = 1.0 - pow(1.0 - OriginalGameplay.cameraPositionSnapRate, dt * 60.0)
        let zoomSmooth = 1.0 - pow(1.0 - OriginalGameplay.cameraScaleSnapRate, dt * 60.0)
        let stopSpeed = CGFloat(OriginalGameplay.minVelocityToMove * OriginalGameplay.baseVelocityCompensation)
        let impulseDecay = OriginalGameplay.impulseDecay(dt: dt)
        let inDist = OriginalGameplay.inputDistance(for: vp)

        SoundManager.shared.beginSpy()
        defer { _ = SoundManager.shared.endSpy() }

        for i in 0..<golden.actions.count {
            let a = golden.actions[i]
            let expected = golden.frames[i]
            let simTime = Double(a.tick) * golden.dt

            if a.isDragging {
                joy.updateTouch(offset: CGSize(width: a.offsetX, height: a.offsetY))
            } else {
                joy.step(dt: dt, isDragging: false, stopOnRelease: a.stopOnRelease)
            }

            let lnz = joy.lastNonZeroDirection
            let lnzMag = hypot(lnz.width, lnz.height)
            let aim = lnzMag > 0.001 ? CGSize(width: lnz.width / lnzMag, height: lnz.height / lnzMag) : CGSize(width: 0, height: 1)

            if a.split {
                SoundManager.shared.playBinary(.split, simTime: simTime, tick: a.tick)
                if cells.count < 16 {
                    var added: [SimCell] = []
                    for k in cells.indices {
                        if cells[k].mass >= 36 && (cells.count + added.count) < 16 {
                            let halfM = cells[k].mass * 0.5
                            cells[k].mass = halfM
                            added.append(SimCell(
                                x: cells[k].x + aim.width * CGFloat(OriginalGameplay.mitosisPositionFactor),
                                y: cells[k].y + aim.height * CGFloat(OriginalGameplay.mitosisPositionFactor),
                                vx: cells[k].vx + aim.width * CGFloat(OriginalGameplay.splitImpulsePerSecond),
                                vy: cells[k].vy + aim.height * CGFloat(OriginalGameplay.splitImpulsePerSecond),
                                mass: halfM
                            ))
                        }
                    }
                    cells.append(contentsOf: added)
                }
            }

            if a.eject {
                SoundManager.shared.playBinary(.shoot, simTime: simTime, tick: a.tick)
                if let maxIdx = cells.indices.max(by: { cells[$0].mass < cells[$1].mass }), cells[maxIdx].mass >= 36 {
                    cells[maxIdx].mass -= 16
                }
            }

            if a.eatCell {
                SoundManager.shared.playBinary(.eatCell, simTime: simTime, tick: a.tick)
                cells[0].mass += 180
            }

            if a.virusPop {
                SoundManager.shared.playBinary(.virusPop, simTime: simTime, tick: a.tick)
                if cells[0].mass >= 36 && cells.count < 16 {
                    let halfM = cells[0].mass * 0.5
                    cells[0].mass = halfM
                    cells.append(SimCell(
                        x: cells[0].x + 20,
                        y: cells[0].y,
                        vx: 0,
                        vy: CGFloat(OriginalGameplay.splitImpulsePerSecond) * 0.8,
                        mass: halfM
                    ))
                }
            }

            if a.eatOwnCell && cells.count > 1 {
                SoundManager.shared.playBinary(.eatOwnCell, simTime: simTime, tick: a.tick)
                let absorbed = cells.removeLast()
                cells[0].mass += absorbed.mass
            }

            let posAndR: [(CGPoint, CGFloat)] = cells.map {
                (CGPoint(x: $0.x, y: $0.y), OriginalGameplay.radius(forMass: $0.mass))
            }
            let flockCenter = OriginalGameplay.radiusWeightedCenter(positionsAndRadii: posAndR)
            let totalR = posAndR.reduce(CGFloat(0)) { $0 + $1.1 }
            let az = OriginalGameplay.arenaZoomForInput(
                totalRadius: max(totalR, CGFloat(OriginalGameplay.baseRadius)),
                cellCount: max(cells.count, 1),
                viewportSize: vp
            )
            let reach = inDist / max(az, 0.05)

            let axisMagSq = joy.axis.width * joy.axis.width + joy.axis.height * joy.axis.height
            let isStopped = (!a.isDragging && a.stopOnRelease) || (axisMagSq < 0.01)
            let worldCursor = CGPoint(x: flockCenter.x + joy.axis.width * reach, y: flockCenter.y + joy.axis.height * reach)

            for k in cells.indices {
                let rSolid = max(OriginalGameplay.radius(forMass: cells[k].mass), 1.0)
                let spd = OriginalGameplay.speed(forMass: cells[k].mass)
                var dx: CGFloat = 0, dy: CGFloat = 0, distT: CGFloat = 0
                if isStopped {
                    let rx = flockCenter.x - cells[k].x
                    let ry = flockCenter.y - cells[k].y
                    let dsq = rx * rx + ry * ry
                    if dsq >= 0.01 {
                        distT = sqrt(dsq)
                        dx = rx / distT
                        dy = ry / distT
                    }
                } else {
                    let rx = worldCursor.x - cells[k].x
                    let ry = worldCursor.y - cells[k].y
                    let d = hypot(rx, ry)
                    if d > 0.001 {
                        distT = d
                        dx = rx / d
                        dy = ry / d
                    }
                }
                let dmag = hypot(dx, dy)
                if dmag > 0.0001 {
                    let kk: CGFloat
                    let step: CGFloat
                    if isStopped {
                        kk = min(1.0, distT / max(rSolid, 1.0)) * dmag
                        step = min(spd * kk * dt, distT)
                    } else {
                        kk = min(1.0, (inDist * dmag) / rSolid)
                        step = spd * kk * dt
                    }
                    cells[k].x += (dx / dmag) * step
                    cells[k].y += (dy / dmag) * step
                }
                cells[k].x += cells[k].vx * dt
                cells[k].y += cells[k].vy * dt
                cells[k].vx *= impulseDecay
                cells[k].vy *= impulseDecay
                if abs(cells[k].vx) < stopSpeed && abs(cells[k].vy) < stopSpeed {
                    cells[k].vx = 0
                    cells[k].vy = 0
                }
                let clampMin = CGFloat(0.4) * rSolid
                cells[k].x = max(clampMin, min(worldSize - clampMin, cells[k].x))
                cells[k].y = max(clampMin, min(worldSize - clampMin, cells[k].y))
            }

            let postPosAndR: [(CGPoint, CGFloat)] = cells.map {
                (CGPoint(x: $0.x, y: $0.y), OriginalGameplay.radius(forMass: $0.mass))
            }
            let targetCam = OriginalGameplay.radiusWeightedCenter(positionsAndRadii: postPosAndR)
            camPos.x += (targetCam.x - camPos.x) * camSmooth
            camPos.y += (targetCam.y - camPos.y) * camSmooth
            let postTotalR = postPosAndR.reduce(CGFloat(0)) { $0 + $1.1 }
            let targetZoom = OriginalGameplay.calculateZoom(
                totalRadius: max(postTotalR, CGFloat(OriginalGameplay.baseRadius)),
                cellCount: max(cells.count, 1),
                viewportSize: vp
            )
            zoom += (targetZoom - zoom) * zoomSmooth

            let tol = 1e-5
            XCTAssertEqual(Double(cells[0].x), expected.x, accuracy: tol, "tick \(a.tick) x")
            XCTAssertEqual(Double(cells[0].y), expected.y, accuracy: tol, "tick \(a.tick) y")
            XCTAssertEqual(Double(cells[0].vx), expected.vx, accuracy: tol, "tick \(a.tick) vx")
            XCTAssertEqual(Double(cells[0].vy), expected.vy, accuracy: tol, "tick \(a.tick) vy")
            XCTAssertEqual(Double(zoom), expected.zoom, accuracy: tol, "tick \(a.tick) zoom")
            XCTAssertEqual(Double(camPos.x), expected.camX, accuracy: tol, "tick \(a.tick) camX")
            XCTAssertEqual(Double(camPos.y), expected.camY, accuracy: tol, "tick \(a.tick) camY")
            XCTAssertEqual(cells.count, expected.cellCount, "tick \(a.tick) cellCount")
        }

        let captured = SoundManager.shared.endSpy()
        let expectedAudio = golden.audioEvents.map { SoundEvent(soundID: $0.soundID, tick: $0.tick, volume: $0.volume) }
        XCTAssertEqual(captured, expectedAudio, "Spy SFX log diverged from binary expectations")
    }

    // MARK: - Pillar 4A: Multi-Frame Animation Snapshot Strips (t = 0, 50, 150, 300ms)

    @MainActor
    func testMultiFrameAnimationStrips() throws {
        MyFont.registerFonts()
        let snapDir = ProcessInfo.processInfo.environment["AGAR_SNAPSHOT_DIR"]
            ?? (NSTemporaryDirectory() as NSString).appendingPathComponent("agar_snapshots")
        try FileManager.default.createDirectory(atPath: snapDir, withIntermediateDirectories: true)

        let timesMs: [(ms: Int, sec: Double)] = [(0, 0.0), (50, 0.05), (150, 0.15), (300, 0.30)]
        let tileSize = CGSize(width: 426, height: 196)
        let s = OriginalGameplay.uiScale(for: tileSize)

        func renderTile<V: View>(_ view: V, size: CGSize) -> UIImage {
            let root = AnyView(view.frame(width: size.width, height: size.height).background(Color.white))
            let renderer = ImageRenderer(content: root)
            renderer.scale = 1.5
            renderer.proposedSize = .init(size)
            if let img = renderer.uiImage, hasColorVariance(img) { return img }
            if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
               let keyWin = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first {
                let host = UIHostingController(rootView: root)
                host.view.frame = CGRect(origin: .zero, size: size)
                host.view.backgroundColor = .white
                let parentVC = keyWin.rootViewController
                if let parentVC {
                    parentVC.addChild(host)
                    parentVC.view.addSubview(host.view)
                    host.didMove(toParent: parentVC)
                } else {
                    keyWin.addSubview(host.view)
                }
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1.5; fmt.opaque = true
                let img = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
                    host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                }
                if parentVC != nil { host.willMove(toParent: nil) }
                host.view.removeFromSuperview()
                if parentVC != nil { host.removeFromParent() }
                return img
            }
            return UIImage()
        }

        func stitchStrip(_ frames: [(label: String, img: UIImage)]) -> UIImage {
            let w = frames.reduce(CGFloat(0)) { $0 + $1.img.size.width }
            let h = frames.map { $0.img.size.height }.max() ?? 100
            let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1.0; fmt.opaque = true
            return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { _ in
                var x: CGFloat = 0
                for item in frames {
                    item.img.draw(at: CGPoint(x: x, y: 0))
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont(name: "OpenSans-Bold", size: 14) ?? UIFont.systemFont(ofSize: 14, weight: .bold),
                        .foregroundColor: UIColor.white,
                        .backgroundColor: UIColor.black.withAlphaComponent(0.65)
                    ]
                    NSString(string: item.label).draw(at: CGPoint(x: x + 8, y: 6), withAttributes: attrs)
                    x += item.img.size.width
                }
            }
        }

        var ccbiStrip: [(String, UIImage)] = []
        for t in timesMs {
            let v = ZStack {
                CCBISceneView(
                    ccbFile: "MenuMain.ccbi",
                    context: CCBIBindingContext(
                        actions: [:],
                        activeSequenceName: "enter",
                        sequencePlayID: 1,
                        designScaleModifier: { _ in s }
                    ),
                    explicitAnimTime: t.sec
                )
                CCBISceneView(
                    ccbFile: "EmojiWidget.ccbi",
                    context: CCBIBindingContext(
                        actions: [:],
                        activeSequenceName: "enter",
                        sequencePlayID: 1,
                        heightOverrides: ["_selectorArea": 70],
                        designScaleModifier: { _ in s }
                    ),
                    explicitAnimTime: t.sec
                )
            }
            ccbiStrip.append(("CCBI t=\(t.ms)ms", renderTile(v, size: tileSize)))
        }
        let strip1 = stitchStrip(ccbiStrip)
        let s1Data = try XCTUnwrap(strip1.pngData())
        try? s1Data.write(to: URL(fileURLWithPath: snapDir).appendingPathComponent("07_AnimStrip_MenuAndEmoji.png"))
        let att1 = XCTAttachment(image: strip1); att1.name = "07_AnimStrip_MenuAndEmoji.png"; att1.lifetime = .keepAlways; add(att1)
        XCTAssertTrue(hasColorVariance(strip1))

        if MTLCreateSystemDefaultDevice() != nil {
            var arenaStrip: [(String, UIImage)] = []
            for t in timesMs {
                let pOwner = UUID()
                let sec = t.sec
                let decay = OriginalGameplay.impulseDecay(dt: sec)
                let splitDist = CGFloat(OriginalGameplay.splitImpulsePerSecond) * CGFloat(sec) * (0.5 + 0.5 * CGFloat(decay))
                let cLeft = PlayerCell(ownerID: pOwner, position: CGPoint(x: 4000 - splitDist * 0.3, y: 4000), mass: 180, targetMass: 180, color: Color(hex: 0x00A8F3), name: "Idris", skinName: "Dragon")
                let cRight = PlayerCell(ownerID: pOwner, position: CGPoint(x: 4000 + splitDist, y: 4000), mass: 180, targetMass: 180, color: Color(hex: 0x00A8F3), name: "Idris", skinName: "Dragon")
                let vPop = Virus(position: CGPoint(x: 3820 - CGFloat(sec) * 600.0, y: 4040))

                let box = ArenaRenderBox()
                box.worldSize = OriginalGameplay.offlineArenaSideLength
                box.cameraPos = CGPoint(x: 4020, y: 4000)
                box.zoom = OriginalGameplay.calculateZoom(totalRadius: cLeft.cachedSolidRadius * 2, cellCount: 2, viewportSize: tileSize)
                box.showBoundaryOverlay = false
                box.playerCells = t.ms == 0 ? [PlayerCell(ownerID: pOwner, position: CGPoint(x: 4000, y: 4000), mass: 360, targetMass: 360, color: Color(hex: 0x00A8F3), name: "Idris", skinName: "Dragon")] : [cLeft, cRight]
                box.viruses = [vPop]
                let img = try XCTUnwrap(ArenaMetalCoordinator(box: box).renderOffscreenSnapshot(size: tileSize, scale: 1.5))
                arenaStrip.append(("Split/Pop t=\(t.ms)ms", img))
            }
            let strip2 = stitchStrip(arenaStrip)
            let s2Data = try XCTUnwrap(strip2.pngData())
            try? s2Data.write(to: URL(fileURLWithPath: snapDir).appendingPathComponent("08_AnimStrip_SplitAndVirusPop.png"))
            let att2 = XCTAttachment(image: strip2); att2.name = "08_AnimStrip_SplitAndVirusPop.png"; att2.lifetime = .keepAlways; add(att2)
            XCTAssertTrue(hasColorVariance(strip2))
        }
    }

    private func hasColorVariance(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage,
              let dp = cg.dataProvider,
              let data = dp.data,
              let ptr = CFDataGetBytePtr(data) else { return false }
        let bpp = cg.bitsPerPixel / 8
        let len = CFDataGetLength(data)
        guard bpp >= 4, len >= 4 else { return false }
        let r0 = ptr[0], g0 = ptr[1], b0 = ptr[2]
        var i = bpp * 8
        while i + 3 < len {
            if abs(Int(ptr[i]) - Int(r0)) > 8 || abs(Int(ptr[i + 1]) - Int(g0)) > 8 || abs(Int(ptr[i + 2]) - Int(b0)) > 8 {
                return true
            }
            i += bpp * 16
        }
        return false
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

    func testIPadScalingDecayAndJoystickMetrics() throws {
        let tol = 1e-5
        // Verify BaseArenaView fixedWidth=768 iPad zoom across 4:3 iPads (1024x768 and Pro 1366x1024)
        for vp in [CGSize(width: 1024, height: 768), CGSize(width: 1366, height: 1024)] {
            let designH = 768.0 * (vp.height / vp.width)
            let screenScale = vp.height / designH
            let r = 100.0
            let n = 4.0
            let expectedCocos = min(pow(designH / (42.0 * r), 0.4) * pow(n, 0.1), max(0.05, (0.37 * designH * pow(n, 0.32)) / r))
            let actual = Double(OriginalGameplay.calculateZoom(totalRadius: r, cellCount: Int(n), viewportSize: vp, isPhoneOverride: false))
            XCTAssertEqual(actual, Double(expectedCocos * screenScale), accuracy: tol)
        }

        // Verify iPad physical inch-height joystick metrics (JoystickView::initWithEaseFactor 0x1000e2b1c)
        let ipadJoy = OriginalGameplay.joystickMetrics(for: CGSize(width: 1024, height: 768), uiScale: 2.133, isPhoneOverride: false)
        XCTAssertEqual(Double(ipadJoy.bgSide), 1.04434 * 132.0, accuracy: tol)
        XCTAssertEqual(Double(ipadJoy.knobSide), 0.5446 * 132.0, accuracy: tol)
        XCTAssertEqual(Double(ipadJoy.maxRadius), 0.5 * 1.04434 * 132.0 - 0.25 * 0.5446 * 132.0, accuracy: tol)

        // Verify sub_10004B844 + sub_10004BFC8 linear radius decay rate
        let r = 1000.0 // mass 10000
        let t = (r - 200.0) / (1500.0 - 200.0)
        let rate = 0.99998 + (0.99922 - 0.99998) * t
        let expectedMass = 10000.0 * pow(rate, 2.0 * 50.0 * 0.02)
        let actualMass = Double(AgarPhysicsCore.applyOfflineMassDecay(mass: 10000, isPlayer: true, dt: 0.02))
        XCTAssertEqual(actualMass, expectedMass, accuracy: 1e-4)

        // Verify AppDelegate iPad FixedWidth 768 vs iPhone FixedHeight 320 UI scale & resourceScaleFactor
        XCTAssertEqual(Double(OriginalGameplay.uiScale(for: CGSize(width: 1024, height: 768), isPhoneOverride: false)), 1024.0 / 768.0, accuracy: tol)
        XCTAssertEqual(Double(OriginalGameplay.uiScale(for: CGSize(width: 852, height: 393), isPhoneOverride: true)), 393.0 / 320.0, accuracy: tol)
        XCTAssertEqual(Double(OriginalGameplay.resourceScaleFactor(isPhoneOverride: true)), 0.46875, accuracy: tol)
        XCTAssertEqual(Double(OriginalGameplay.resourceScaleFactor(isPhoneOverride: false)), 1.0, accuracy: tol)
    }

    func testVirusPopWallSplitAndAudioParity() throws {
        // 1. Recursive virus-pop mass split handles non-power-of-2 caps (e.g. 12 remaining slots)
        let pieces12 = AgarPhysicsCore.calculateVirusSplitMass(mass: 1000.0, maxSplits: 12)
        XCTAssertEqual(pieces12.count, 12)
        XCTAssertEqual(pieces12.reduce(0, +), 1000.0, accuracy: 1e-6)
        XCTAssertGreaterThanOrEqual(pieces12.last ?? 0, OriginalGameplay.minSplitMass)

        // 2. Wall split squash clamp at all 8 angles uses 0.4 * r (percentageOfCellToSquash)
        let ws = OriginalGameplay.offlineArenaSideLength
        let r: CGFloat = 120.0
        for k in 0..<8 {
            let a = CGFloat(k) * (.pi / 4.0)
            let raw = CGPoint(x: (cos(a) >= 0 ? ws : 0) + cos(a) * 100.0,
                              y: (sin(a) >= 0 ? ws : 0) + sin(a) * 100.0)
            let clamped = AgarPhysicsCore.clampSquashPosition(raw, radius: r, worldSize: ws)
            let minMargin = r * OriginalGameplay.percentageOfCellToSquash
            XCTAssertGreaterThanOrEqual(clamped.x, minMargin - 1e-4)
            XCTAssertLessThanOrEqual(clamped.x, ws - minMargin + 1e-4)
            XCTAssertGreaterThanOrEqual(clamped.y, minMargin - 1e-4)
            XCTAssertLessThanOrEqual(clamped.y, ws - minMargin + 1e-4)
        }

        // 3. Soft-body virus deformation runs and preserves deformed vertices across zoom changes
        var viruses = [Virus(position: CGPoint(x: 40, y: 4000))]
        let vis = CGRect(x: 0, y: 3600, width: 800, height: 800)
        for _ in 0..<5 {
            AgarPhysicsCore.deformViruses(viruses: &viruses, visibleWorldRect: vis, worldSize: ws, dt: 1.0 / 60.0, cocosZoom: 0.40)
        }
        let prevCount = viruses[0].deformedVertices.count
        XCTAssertGreaterThanOrEqual(prevCount, 30)
        AgarPhysicsCore.deformViruses(viruses: &viruses, visibleWorldRect: vis, worldSize: ws, dt: 1.0 / 60.0, cocosZoom: 0.55)
        XCTAssertGreaterThan(viruses[0].deformedVertices.count, prevCount)

        // 4. SoundManager binary cooldowns, volumes, and pitch jitter
        XCTAssertEqual(AgarSFX.split.binaryCooldownSec, 0.150, accuracy: 1e-6)
        XCTAssertEqual(AgarSFX.shoot.binaryCooldownSec, 0.150, accuracy: 1e-6)
        XCTAssertEqual(AgarSFX.menuClick.binaryCooldownSec, 0.200, accuracy: 1e-6)
        XCTAssertEqual(AgarSFX.eatCell.binaryCooldownSec, 0.0, accuracy: 1e-6)
        XCTAssertEqual(AgarSFX.menuClick.binaryVolume, 0.25, accuracy: 1e-6)
        XCTAssertEqual(AgarSFX.split.binaryPitchJitter, 0.05, accuracy: 1e-6)
        XCTAssertEqual(AgarSFX.virusPop.binaryPitchJitter, 0.20, accuracy: 1e-6)
    }

    func testArm64EmulatedGoldenVectors() throws {
        struct Arm64Vectors: Decodable {
            struct ZoomVec: Decodable {
                let viewportName: String
                let w: Double
                let h: Double
                let isIpad: Bool
                let totalRadius: Double
                let cellCount: Int
                let cocosZoom: Double
                let expectedSwiftZoom: Double
            }
            struct JoyVec: Decodable {
                let offsetX: Double
                let offsetY: Double
                let maxRadius: Double
                let desiredX: Double
                let desiredY: Double
            }
            struct FollowVec: Decodable {
                let joyX: Double
                let joyY: Double
                let totalRadius: Double
                let touchX: Double
                let touchY: Double
                let factor: Double
                let x: Double
                let y: Double
            }
            struct SpeedVec: Decodable {
                let mass: Double
                let radius: Double
                let speed: Double
            }
            struct DecayVec: Decodable {
                let dt: Double
                let factor: Double
            }
            let cameraZoomVectors: [ZoomVec]
            let joystickVectors: [JoyVec]
            let followJoystickVectors: [FollowVec]
            let speedVectors: [SpeedVec]
            let impulseDecayVectors: [DecayVec]
        }

        let testBundle = Bundle(for: AgarParityTests.self)
        let url = testBundle.url(forResource: "AgarArm64EmulatedVectors", withExtension: "json", subdirectory: "Fixtures")
            ?? testBundle.url(forResource: "AgarArm64EmulatedVectors", withExtension: "json")
        let resolved = try XCTUnwrap(url, "Missing AgarArm64EmulatedVectors.json in test bundle")
        let vecs = try JSONDecoder().decode(Arm64Vectors.self, from: Data(contentsOf: resolved))

        let tol = 1e-5
        for v in vecs.cameraZoomVectors {
            let zoom = Double(OriginalGameplay.calculateZoom(
                totalRadius: CGFloat(v.totalRadius),
                cellCount: v.cellCount,
                viewportSize: CGSize(width: v.w, height: v.h),
                isPhoneOverride: !v.isIpad
            ))
            XCTAssertEqual(zoom, v.expectedSwiftZoom, accuracy: tol, "ARM64 zoom \(v.viewportName) r=\(v.totalRadius) n=\(v.cellCount)")
        }

        for v in vecs.joystickVectors {
            var joy = AgarJoystickInput()
            joy.updateTouch(offset: CGSize(width: v.offsetX, height: v.offsetY), maxRadius: CGFloat(v.maxRadius))
            XCTAssertEqual(Double(joy.axis.width), v.desiredX, accuracy: tol, "ARM64 joy.x(\(v.offsetX),\(v.offsetY))")
            XCTAssertEqual(Double(joy.axis.height), v.desiredY, accuracy: tol, "ARM64 joy.y(\(v.offsetX),\(v.offsetY))")
        }

        for v in vecs.followJoystickVectors {
            let out = AgarJoystickInput.followJoystick(
                currentCenter: CGPoint(x: v.joyX, y: v.joyY),
                touchPoint: CGPoint(x: v.touchX, y: v.touchY),
                totalRadius: CGFloat(v.totalRadius),
                factor: CGFloat(v.factor)
            )
            XCTAssertEqual(Double(out.x), v.x, accuracy: tol, "ARM64 follow.x(\(v.touchX),\(v.touchY))")
            XCTAssertEqual(Double(out.y), v.y, accuracy: tol, "ARM64 follow.y(\(v.touchX),\(v.touchY))")
        }

        for v in vecs.speedVectors {
            let spd = OriginalGameplay.speed(forMass: v.mass)
            // ARM64 sub_100047320 uses 32-bit float powf -> relative accuracy 1e-5
            XCTAssertEqual(spd, v.speed, accuracy: max(tol, v.speed * 1e-5), "ARM64 speed(mass:\(v.mass))")
        }

        for v in vecs.impulseDecayVectors {
            XCTAssertEqual(OriginalGameplay.impulseDecay(dt: v.dt), v.factor, accuracy: tol, "ARM64 impulseDecay(dt:\(v.dt))")
        }
    }

    @MainActor
    func testCCBINodeCompletenessAudit() throws {
        struct ManifestNode: Decodable {
            let cls: String
            let varName: String
            let x: Double
            let y: Double
            let w: Double
            let h: Double
        }
        struct Manifest: Decodable {
            let iPhone: [String: [ManifestNode]]
            let iPad: [String: [ManifestNode]]
        }

        let testBundle = Bundle(for: AgarParityTests.self)
        let url = testBundle.url(forResource: "ccbi_node_manifest", withExtension: "json", subdirectory: "Fixtures")
            ?? testBundle.url(forResource: "ccbi_node_manifest", withExtension: "json")
        let resolved = try XCTUnwrap(url, "Missing ccbi_node_manifest.json in test bundle")
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: resolved))

        let store = CCBIAtlasStore.shared
        let screens = [
            "MenuMain", "MenuSettings", "MenuShopSkins", "PotionSlot",
            "Controls-Sides", "Score", "EmojiWidget", "PauseButton",
            "LeaderboardWidget", "MenuBattleResultPopup"
        ]

        func countVisibleCCBINodes(_ node: CCBINode) -> Int {
            if case .bool(false) = node.props["visible"] { return 0 }
            return 1 + node.children.reduce(0) { $0 + countVisibleCCBINodes($1) }
        }

        for name in screens {
            let root = try XCTUnwrap(store.loadCCBI(named: name), "Failed to load \(name).ccbi")
            let visibleCount = countVisibleCCBINodes(root)
            XCTAssertGreaterThan(visibleCount, 0, "\(name).ccbi must have visible nodes")

            let phoneNodes = try XCTUnwrap(manifest.iPhone[name], "Missing iPhone manifest for \(name)")
            let padNodes = try XCTUnwrap(manifest.iPad[name], "Missing iPad manifest for \(name)")
            XCTAssertFalse(phoneNodes.isEmpty, "\(name) iPhone manifest must not be empty")
            XCTAssertFalse(padNodes.isEmpty, "\(name) iPad manifest must not be empty")

            for n in phoneNodes {
                XCTAssertGreaterThan(n.w, 0.5, "\(name) iPhone node \(n.cls)/\(n.varName) zero width")
                XCTAssertGreaterThan(n.h, 0.5, "\(name) iPhone node \(n.cls)/\(n.varName) zero height")
            }
            for n in padNodes {
                XCTAssertGreaterThan(n.w, 0.5, "\(name) iPad node \(n.cls)/\(n.varName) zero width")
                XCTAssertGreaterThan(n.h, 0.5, "\(name) iPad node \(n.cls)/\(n.varName) zero height")
            }

            // Render CCBISceneView at both iPhone and iPad sizes and assert non-empty raster
            for (label, sz, isPad) in [("iPhone", CGSize(width: 852, height: 393), false), ("iPad", CGSize(width: 1024, height: 768), true)] {
                var ctx = CCBIBindingContext()
                ctx.designScaleModifier = { size in OriginalGameplay.uiScale(for: size, isPhoneOverride: !isPad) }
                let view = CCBISceneView(ccbFile: name, context: ctx)
                    .frame(width: sz.width, height: sz.height)
                    .background(Color.white)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 1.0
                renderer.proposedSize = .init(sz)
                let img = try XCTUnwrap(renderer.uiImage, "\(name) \(label) CCBISceneView returned nil")
                XCTAssertGreaterThan(img.size.width, 100, "\(name) \(label) width")
                XCTAssertGreaterThan(img.size.height, 100, "\(name) \(label) height")
            }
        }
    }

    @MainActor
    func testSoftBodyVertexDeformationAndMetalFrames() throws {
        let ws = OriginalGameplay.offlineArenaSideLength
        let vis = CGRect(x: 0, y: 0, width: ws, height: ws)
        let ownerA = UUID()
        let ownerB = UUID()

        // 1. Free-moving cell: radial vertices stay bounded around visualRadius
        var freeCell = PlayerCell(ownerID: ownerA, position: CGPoint(x: 2000, y: 2000), mass: 100, targetMass: 100, color: .cyan, name: "Free")
        var freeArr = [freeCell]
        for _ in 0..<6 {
            AgarPhysicsCore.deformVertices(cells: &freeArr, neighborsByOwner: true, visibleWorldRect: vis, worldSize: ws, dt: 1.0/60.0, cocosZoom: 0.5)
        }
        let freeR = freeArr[0].cachedVisualRadius
        XCTAssertGreaterThanOrEqual(freeArr[0].deformedVertices.count, 24)
        for v in freeArr[0].deformedVertices {
            let d = hypot(v.x, v.y)
            XCTAssertGreaterThan(d, freeR * 0.85)
            XCTAssertLessThan(d, freeR * 1.15)
        }

        // 2. Wall-pressing cell: left-facing vertices (cos < -0.5) squash inward
        var wallCell = PlayerCell(ownerID: ownerA, position: CGPoint(x: 40, y: 2000), mass: 100, targetMass: 100, color: .blue, name: "Wall")
        var wallArr = [wallCell]
        for _ in 0..<10 {
            AgarPhysicsCore.deformVertices(cells: &wallArr, neighborsByOwner: true, visibleWorldRect: vis, worldSize: ws, dt: 1.0/60.0, cocosZoom: 0.5)
        }
        let leftRadii = wallArr[0].deformedVertices.filter { $0.x < -wallArr[0].cachedVisualRadius * 0.5 }.map { hypot($0.x, $0.y) }
        let rightRadii = wallArr[0].deformedVertices.filter { $0.x > wallArr[0].cachedVisualRadius * 0.5 }.map { hypot($0.x, $0.y) }
        XCTAssertFalse(leftRadii.isEmpty)
        XCTAssertFalse(rightRadii.isEmpty)
        let avgLeft = leftRadii.reduce(0, +) / CGFloat(leftRadii.count)
        let avgRight = rightRadii.reduce(0, +) / CGFloat(rightRadii.count)
        XCTAssertLessThan(avgLeft, avgRight, "Wall-pressing side must squash inward relative to free side")

        // 3. Colliding sibling & enemy cells
        var sibA = PlayerCell(ownerID: ownerA, position: CGPoint(x: 3000, y: 3000), mass: 100, targetMass: 100, color: .green, name: "A")
        var sibB = PlayerCell(ownerID: ownerA, position: CGPoint(x: 3120, y: 3000), mass: 100, targetMass: 100, color: .green, name: "B")
        var enemy = PlayerCell(ownerID: ownerB, position: CGPoint(x: 2880, y: 3000), mass: 225, targetMass: 225, color: .red, name: "Enemy")
        sibA.mergeTimer = 10
        sibB.mergeTimer = 10
        var group = [sibA, sibB, enemy]
        for _ in 0..<8 {
            AgarPhysicsCore.deformVertices(cells: &group, neighborsByOwner: true, visibleWorldRect: vis, worldSize: ws, dt: 1.0/60.0, cocosZoom: 0.5)
        }
        XCTAssertGreaterThanOrEqual(group[0].deformedVertices.count, 24)
        XCTAssertGreaterThanOrEqual(group[2].deformedVertices.count, 24)

        // 4. Consecutive Metal offscreen frames: zero flicker and shrinking skin clampToEdge
        if MTLCreateSystemDefaultDevice() != nil {
            let box = ArenaRenderBox()
            box.worldSize = ws
            box.cameraPos = CGPoint(x: 3000, y: 3000)
            box.zoom = 0.5
            box.showSkins = true
            box.showMassText = true
            var skinCell = group[0]
            skinCell.skinName = "Dragon"
            box.playerCells = [skinCell]
            box.botCells = [group[2]]
            var vir = [Virus(position: CGPoint(x: 3200, y: 3100))]
            AgarPhysicsCore.deformViruses(viruses: &vir, visibleWorldRect: vis, worldSize: ws, dt: 1.0/60.0, cocosZoom: 0.5)
            box.viruses = vir

            let coord = ArenaMetalCoordinator(box: box)
            let snap1 = try XCTUnwrap(coord.renderOffscreenSnapshot(size: CGSize(width: 426, height: 196), scale: 2.0))
            let snap2 = try XCTUnwrap(coord.renderOffscreenSnapshot(size: CGSize(width: 426, height: 196), scale: 2.0))
            XCTAssertTrue(hasColorVariance(snap1))
            XCTAssertTrue(hasColorVariance(snap2))
        }
    }

    func testArenaVirusPopSelfCollisionWallSplitAndEjectParity() throws {
        let ws = OriginalGameplay.offlineArenaSideLength
        let owner = UUID()

        // 1. Virus pop split conservation & cap
        for cap in [2, 5, 12, 16] {
            let pieces = AgarPhysicsCore.calculateVirusSplitMass(mass: 1600.0, maxSplits: cap)
            XCTAssertLessThanOrEqual(pieces.count, cap)
            XCTAssertEqual(pieces.reduce(0, +), 1600.0, accuracy: 1e-6)
            for p in pieces {
                XCTAssertGreaterThanOrEqual(p, OriginalGameplay.minSplitMass)
            }
        }

        // 2. Self-collision separation pushes overlapping siblings apart when mergeTimer > 0
        var c1 = PlayerCell(ownerID: owner, position: CGPoint(x: 4000, y: 4000), mass: 100, targetMass: 100, color: .cyan, name: "1")
        var c2 = PlayerCell(ownerID: owner, position: CGPoint(x: 4020, y: 4000), mass: 100, targetMass: 100, color: .cyan, name: "2")
        c1.mergeTimer = 15
        c2.mergeTimer = 15
        var cells = [c1, c2]
        for _ in 0..<20 {
            AgarPhysicsCore.resolveSelfCollisions(cells: &cells, worldSize: ws)
        }
        let sep = hypot(cells[0].position.x - cells[1].position.x, cells[0].position.y - cells[1].position.y)
        XCTAssertGreaterThan(sep, 20.0)

        // 3. Eject pellet constants
        XCTAssertEqual(OriginalGameplay.ejectPelletMass, 16.0, accuracy: 1e-6)
        XCTAssertEqual(OriginalGameplay.ejectImpulsePerSecond, 2000.0, accuracy: 1e-6)
        XCTAssertEqual(OriginalGameplay.minEjectMass, 32.0, accuracy: 1e-6)
        XCTAssertEqual(OriginalGameplay.directionAngleVariation, 0.2, accuracy: 1e-6)
        XCTAssertEqual(OriginalGameplay.spawnFoodVelocityVariation, 0.2, accuracy: 1e-6)
    }
}
