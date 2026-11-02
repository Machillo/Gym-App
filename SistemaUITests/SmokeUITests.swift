import XCTest

/// Onboarding → itinerario y rutina → registrar la misión de hoy → el XP sube.
@MainActor
final class SmokeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testOnboardingLogSessionAndXPIncreases() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitesting"]
        app.launch()

        let name = app.textFields["onboarding.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText("Jugador UI")
        app.buttons["onboarding.next"].tap()

        let routineName = app.textFields["onboarding.routineName"]
        XCTAssertTrue(routineName.waitForExistence(timeout: 5))
        app.buttons["onboarding.add.strength"].tap()
        app.buttons["onboarding.routineNext"].tap()

        let finish = app.buttons["onboarding.finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()

        let totalXP = app.staticTexts["status.totalXP"]
        XCTAssertTrue(totalXP.waitForExistence(timeout: 10))
        XCTAssertEqual(xpValue(totalXP.label), 0)

        let logButton = app.buttons["status.logMission"]
        XCTAssertTrue(logButton.waitForExistence(timeout: 5))
        logButton.tap()

        let save = app.buttons["log.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        // Si aparece un anuncio del Sistema, se descarta tocándolo.
        let announcement = app.otherElements["announcement"]
        if announcement.waitForExistence(timeout: 2) { announcement.tap() }

        XCTAssertTrue(app.staticTexts["status.missionDone"].waitForExistence(timeout: 10))
        let after = xpValue(app.staticTexts["status.totalXP"].label)
        XCTAssertGreaterThan(after, 0, "El XP debería subir después de registrar la sesión")
    }

    private func xpValue(_ label: String) -> Int {
        Int(label.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? -1
    }
}
