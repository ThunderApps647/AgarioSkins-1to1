import XCTest

final class AgarUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .landscapeRight
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let shot = XCUIScreen.main.screenshot()
        let att = XCTAttachment(screenshot: shot)
        att.name = name
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
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        return true
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
        if let settingsBtn = firstExisting(app, ids: ["ccbi.settingsButtonCallback"], timeout: 3.0) {
            waitAndTap(settingsBtn)
            let backBtn = firstExisting(app, ids: ["ccbi.backButtonCallback", "ccbi._backButton"], timeout: 4.0)
            XCTAssertNotNil(backBtn, "Settings modal should expose back button")
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            if let toggle = firstExisting(app, ids: ["ccbi.toggleSwipeCallback:"], timeout: 2.0) {
                toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
                RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            }
            capture(app, name: "Live_02_Settings.png")
            if let backBtn { waitAndTap(backBtn) }
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        } else {
            XCTFail("Settings button missing on MenuMain")
        }

        // 2. Skins route + tabs + close
        if let skinsBtn = firstExisting(app, ids: ["ccbi.skinsButtonCallback"], timeout: 3.0) {
            waitAndTap(skinsBtn)
            let backBtn = firstExisting(app, ids: ["ccbi.backButtonCallback", "ccbi._backButton"], timeout: 4.0)
            XCTAssertNotNil(backBtn, "Skins modal should open and expose back button")
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            capture(app, name: "Live_03_Skins.png")
            if let backBtn { waitAndTap(backBtn) }
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        } else {
            XCTFail("Skins button missing on MenuMain")
        }

        // 3. Shop, Quests, Potions, Leagues, Profile, Play Online routing verification
        let modalRoutes: [(label: String, ids: [String], closeIds: [String])] = [
            ("Shop", ["ccbi.shopButtonCallback"], ["ccbi.backButtonCallback", "ccbi._backButton"]),
            ("Quests", ["ccbi._dailyQuestButtonNode.pressedCallback", "ccbi._dailyQuestButtonNode"], ["ccbi.backButtonCallback", "ccbi.playButtonCallback"]),
            ("Potions", ["ccbi._mysteryPotionsButtonNode.pressedCallback", "ccbi._mysteryPotionsButtonNode"], ["ccbi.backButtonCallback"]),
            ("Leagues", ["ccbi._leaguesButtonNode.pressedCallback", "ccbi._leaguesButtonNode"], ["ccbi.backButtonCallback", "ccbi._backButton"]),
            ("Profile", ["ccbi.profileButtonCallback"], ["ccbi.backButtonCallback", "ccbi._backButton"]),
            ("Play Online", ["menu.playOnline"], ["online.close"])
        ]
        for route in modalRoutes {
            if let trigger = firstExisting(app, ids: route.ids, timeout: 2.5) {
                waitAndTap(trigger)
                RunLoop.current.run(until: Date().addingTimeInterval(0.35))
                if let close = firstExisting(app, ids: route.closeIds, timeout: 3.5) {
                    waitAndTap(close)
                    RunLoop.current.run(until: Date().addingTimeInterval(0.35))
                } else {
                    XCTFail("\(route.label) modal failed to expose close/back button")
                }
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
        start.press(forDuration: 0.05, thenDragTo: dragTopLeft)
        RunLoop.current.run(until: Date().addingTimeInterval(0.45))
        capture(app, name: "Live_05_Arena_Edge.png")

        // Exercise HUD actions (Emoji toggle, Leaderboard toggle, Split, Feed, Pause)
        if let emojiBtn = firstExisting(app, ids: ["ccbi.onToggle"], timeout: 2.0) {
            waitAndTap(emojiBtn)
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        if let lbBtn = firstExisting(app, ids: ["hud.leaderboard"], timeout: 2.0) {
            waitAndTap(lbBtn)
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

        waitAndTap(pauseBtn)
        let resumeNo = firstExisting(app, ids: ["ccbi.quitCancelButtonCallback", "ccbi._noButton"], timeout: 3.0)
        XCTAssertNotNil(resumeNo, "MenuPause modal should open when Pause is tapped")
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        capture(app, name: "Live_06_Arena_HUD_and_Pause.png")
        if let resumeNo { waitAndTap(resumeNo) }
    }
}
