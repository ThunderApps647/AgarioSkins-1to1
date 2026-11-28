import XCTest

final class AgarUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
        // Orientation is applied once after launch (line 80).  Setting it here
        // too made the simulator occasionally time out before the app existed,
        // failing the whole run without capturing a single screen.
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let prefix = UIDevice.current.userInterfaceIdiom == .pad ? "iPad_" : "iPhone_"
        let raw = XCUIScreen.main.screenshot().image
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = raw.scale
        let outImage: UIImage
        if raw.size.height > raw.size.width {
            let targetSize = CGSize(width: raw.size.height, height: raw.size.width)
            outImage = UIGraphicsImageRenderer(size: targetSize, format: fmt).image { ctx in
                ctx.cgContext.translateBy(x: targetSize.width * 0.5, y: targetSize.height * 0.5)
                ctx.cgContext.rotate(by: .pi * 0.5)
                raw.draw(in: CGRect(
                    x: -raw.size.width * 0.5,
                    y: -raw.size.height * 0.5,
                    width: raw.size.width,
                    height: raw.size.height
                ))
            }
        } else {
            outImage = UIGraphicsImageRenderer(size: raw.size, format: fmt).image { _ in
                raw.draw(in: CGRect(origin: .zero, size: raw.size))
            }
        }
        let att = XCTAttachment(image: outImage)
        att.name = prefix + name
        att.lifetime = .keepAlways
        add(att)
    }

    private func attachTree(_ app: XCUIApplication, name: String) {
        let att = XCTAttachment(string: app.debugDescription)
        att.name = name
        att.lifetime = .keepAlways
        add(att)
    }

    @discardableResult
    private func waitAndTap(_ element: XCUIElement, timeout: TimeInterval = 5.0) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        return true
    }

    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 4.0) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return !element.exists
    }

    private func firstExisting(_ app: XCUIApplication, ids: [String], timeout: TimeInterval = 4.0) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for id in ids {
                let b = app.buttons[id].firstMatch
                if b.exists { return b }
                let any = app.descendants(matching: .any)[id].firstMatch
                if any.exists { return any }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        } while Date() < deadline
        return nil
    }

    func testLiveAppUIRoutingAndArenaScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeRight

        let playBtn = try XCTUnwrap(firstExisting(app, ids: ["ccbi.playButtonCallback"], timeout: 10.0), "Play button must appear on MenuMain")
        RunLoop.current.run(until: Date().addingTimeInterval(0.75))
        attachTree(app, name: "Live_01_MainMenu_Tree.txt")
        capture(app, name: "Live_01_MainMenu.png")

        // 1. Settings route + toggle
        if let settingsBtn = firstExisting(app, ids: ["ccbi.settingsButtonCallback"], timeout: 5.0) {
            waitAndTap(settingsBtn)
            let toggle = try XCTUnwrap(
                firstExisting(app, ids: ["ccbi.toggleSwipeCallback:"], timeout: 4.0) ?? {
                    waitAndTap(settingsBtn)
                    return firstExisting(app, ids: ["ccbi.toggleSwipeCallback:"], timeout: 5.0)
                }(),
                "Settings modal should open with toggles"
            )
            let backBtn = firstExisting(app, ids: ["ccbi.backButtonCallback", "ccbi._backButton"], timeout: 4.0)
            XCTAssertNotNil(backBtn, "Settings modal should expose back button")
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            capture(app, name: "Live_02_Settings.png")
            if let backBtn { waitAndTap(backBtn) }
            XCTAssertTrue(waitUntilGone(toggle, timeout: 4.0), "Closing Settings should dismiss Settings")
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        } else {
            XCTFail("Settings button missing on MenuMain")
        }

        // 2. Skins route + tabs + close
        if let skinsBtn = firstExisting(app, ids: ["ccbi.skinsButtonCallback"], timeout: 3.0) {
            waitAndTap(skinsBtn)
            let skinsMarker = firstExisting(app, ids: ["All Skins", "No Skin"], timeout: 4.0)
            XCTAssertNotNil(skinsMarker, "Skins modal should open and expose skin tabs")
            let backBtn = firstExisting(app, ids: ["ccbi.backButtonCallback", "ccbi._backButton"], timeout: 4.0)
            XCTAssertNotNil(backBtn, "Skins modal should expose back button")
            RunLoop.current.run(until: Date().addingTimeInterval(0.45))
            capture(app, name: "Live_03_Skins.png")
            if let backBtn { waitAndTap(backBtn) }
            if let skinsMarker {
                XCTAssertTrue(waitUntilGone(skinsMarker, timeout: 4.0), "Closing Skins should return to MenuMain")
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        } else {
            XCTFail("Skins button missing on MenuMain")
        }

        // 3. Shop, Quests, Potions, Leagues, Play Online, Profile routing verification.
        // Play Online is checked before the full-screen Profile card: SwiftUI can leave the
        // main menu briefly non-hit-testable while the profile overlay animates out.
        let modalRoutes: [(label: String, ids: [String], verifyIds: [String], closeIds: [String])] = [
            ("Shop", ["ccbi.shopButtonCallback"], ["ccbi.coinsButtonCallback", "Coins"], ["ccbi.backButtonCallback", "ccbi._backButton"]),
            ("Quests", ["ccbi._dailyQuestButtonNode.pressedCallback", "ccbi._dailyQuestButtonNode"], ["Milestone Chest: 0 / 3", "ccbi.backButtonCallback"], ["ccbi.backButtonCallback", "ccbi._backButton"]),
            ("Potions", ["ccbi._mysteryPotionsButtonNode.pressedCallback", "ccbi._mysteryPotionsButtonNode"], ["ccbi.helpButtonCallback", "ccbi.backButtonCallback"], ["ccbi.backButtonCallback", "ccbi._backButton"]),
            ("Leagues", ["ccbi._leaguesButtonNode.pressedCallback", "ccbi._leaguesButtonNode"], ["ccbi.myLeagueButtonCallback", "ccbi.backButtonCallback"], ["ccbi.backButtonCallback", "ccbi._backButton"]),
            ("Play Online", ["menu.playOnline"], ["online.close"], ["online.close"]),
            ("Profile", ["ccbi.profileButtonCallback"], ["ccbi.achievementsButtonCallback", "ccbi.backButtonCallback"], ["ccbi.backButtonCallback", "ccbi._backButton"])
        ]
        for route in modalRoutes {
            let trigger = try XCTUnwrap(firstExisting(app, ids: route.ids, timeout: 3.0), "\(route.label) button must exist on MenuMain")
            waitAndTap(trigger)
            let marker = try XCTUnwrap(firstExisting(app, ids: route.verifyIds, timeout: 4.0), "\(route.label) modal should open with expected content")
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            if route.label == "Potions" {
                capture(app, name: "Live_02b_Potions.png")
            }
            if let close = firstExisting(app, ids: route.closeIds, timeout: 3.5) {
                waitAndTap(close)
                XCTAssertTrue(waitUntilGone(marker, timeout: 4.0), "Closing \(route.label) should dismiss modal")
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            } else {
                XCTFail("\(route.label) modal failed to expose close/back button")
            }
        }

        // 4. Launch live Classic match -> MTKView + HUD + Edge boundary drag + Pause modal
        XCTAssertTrue(playBtn.waitForExistence(timeout: 3.0))
        waitAndTap(playBtn)

        let pauseBtn = try XCTUnwrap(firstExisting(app, ids: ["ccbi.pauseButtonCallback"], timeout: 6.0), "Pause HUD button must appear in live match")
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        capture(app, name: "Live_04_Arena_Center.png")

        // Drag virtual joystick on left-bottom quadrant toward top-left edge/corner
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.16, dy: 0.72))
        let dragTopLeft = app.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.56))
        start.press(forDuration: 0.05, thenDragTo: dragTopLeft, withVelocity: .default, thenHoldForDuration: 0.9)
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        capture(app, name: "Live_05_Arena_Edge.png")

        // Exercise HUD actions (Emoji toggle + emote pick, Leaderboard toggle, Split, Feed, Pause)
        if let emojiBtn = firstExisting(app, ids: ["ccbi.onToggle"], timeout: 2.0) {
            waitAndTap(emojiBtn)
            if let tongueBtn = firstExisting(app, ids: ["hud.emote.emoji-tongue"], timeout: 2.0) {
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                if let lbBtn = firstExisting(app, ids: ["hud.leaderboard"], timeout: 2.0) {
                    waitAndTap(lbBtn)
                    RunLoop.current.run(until: Date().addingTimeInterval(0.35))
                }
                capture(app, name: "Live_05b_Arena_Emote_and_Leaderboard.png")
                waitAndTap(tongueBtn)
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            }
        } else if let lbBtn = firstExisting(app, ids: ["hud.leaderboard"], timeout: 2.0) {
            waitAndTap(lbBtn)
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
            capture(app, name: "Live_05b_Arena_Emote_and_Leaderboard.png")
        }
        waitAndTap(pauseBtn)
        let resumeNo = firstExisting(app, ids: ["ccbi.quitCancelButtonCallback", "ccbi._noButton"], timeout: 3.0)
        XCTAssertNotNil(resumeNo, "MenuPause modal should open when Pause is tapped")
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        capture(app, name: "Live_06_Arena_HUD_and_Pause.png")
        if let resumeNo {
            waitAndTap(resumeNo)
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }

        if let splitBtn = firstExisting(app, ids: ["hud.split"], timeout: 2.0) {
            waitAndTap(splitBtn)
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
        if let feedBtn = firstExisting(app, ids: ["hud.feed"], timeout: 2.0) {
            waitAndTap(feedBtn)
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
    }
}
