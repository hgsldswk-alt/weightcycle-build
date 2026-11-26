import XCTest

final class FlowUITests: XCTestCase {
    private let app = XCUIApplication()
    private let timeout: TimeInterval = 15

    override func setUp() {
        continueAfterFailure = false
        executionTimeAllowance = 900
    }

    private func launch(_ options: [String] = [], lang: String = "en", code: String? = nil, reset: Bool = true) {
        if app.state != .notRunning { app.terminate() }
        let region = ["zh-Hans": "zh_CN", "zh-Hant": "zh_TW"][lang] ?? "en_US"
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(\(lang))", "-AppleLocale", region] +
            (reset ? ["-reset"] : []) + options
        app.launchEnvironment = [:]
        if let code { app.launchEnvironment["WC_TEST_CODE"] = code }
        app.launch()
    }

    private func tap(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons.matching(identifier: id).firstMatch
        reveal(button, id, scroll: !id.hasPrefix("notice."), file: file, line: line)
        XCTAssertTrue(button.wait(for: \.isEnabled, toEqual: true, timeout: timeout),
                      "\(id) is disabled", file: file, line: line)
        button.tap()
    }

    private func reveal(_ element: XCUIElement, _ name: String, scroll: Bool = true,
                        file: StaticString = #filePath, line: UInt = #line) {
        if !element.exists { _ = element.waitForExistence(timeout: timeout) }
        if scroll && !element.isHittable {
            let page = app.scrollViews.firstMatch
            for _ in 0..<4 {
                guard !element.isHittable, page.isHittable else { break }
                if element.exists && !element.frame.isEmpty && element.frame.midY < page.frame.midY {
                    page.swipeDown()
                } else {
                    page.swipeUp()
                }
            }
        }
        XCTAssertTrue(element.exists, "\(name) did not appear", file: file, line: line)
        XCTAssertTrue(element.wait(for: \.isHittable, toEqual: true, timeout: timeout),
                      "\(name) is not visible or hittable", file: file, line: line)
    }

    private func back(file: StaticString = #filePath, line: UInt = #line) {
        let button = app.navigationBars.buttons.firstMatch
        reveal(button, "Back button", scroll: false, file: file, line: line)
        button.tap()
    }

    private func enterWeight(_ value: String, atEnd: Bool = false,
                             file: StaticString = #filePath, line: UInt = #line) {
        let field = app.textFields["weight.input"]
        reveal(field, "weight.input", file: file, line: line)
        if atEnd {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        } else {
            field.tap()
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: timeout),
                      "Weight input keyboard did not appear", file: file, line: line)
        field.typeText(value)
    }

    private func tapChart(file: StaticString = #filePath, line: UInt = #line) {
        let chart = app.descendants(matching: .any).matching(identifier: "home.chart").firstMatch
        reveal(chart, "home.chart", file: file, line: line)
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.45)).tap()
        XCTAssertTrue(app.buttons["day.log"].waitForExistence(timeout: timeout), file: file, line: line)
    }

    private func waitForNotice(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let notice = app.staticTexts.matching(NSPredicate(format: "identifier == %@ AND label == %@",
                                                          "notice.message", message)).firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: timeout), "Expected notice: \(message)", file: file, line: line)
    }

    func testFreshSaveValidationUndoAndPersistence() {
        launch()
        tap("home.log")
        enterWeight("0")
        tap("weight.save")
        XCTAssertTrue(app.staticTexts["weight.error"].waitForExistence(timeout: timeout))
        XCTAssertEqual(app.textFields["weight.input"].value as? String, "0")
        enterWeight(XCUIKeyboardKey.delete.rawValue + "64.2", atEnd: true)
        tap("weight.save")
        XCTAssertTrue(app.staticTexts["notice.message"].waitForExistence(timeout: timeout))
        tap("notice.undo")
        XCTAssertTrue(app.staticTexts["No weigh-ins yet"].waitForExistence(timeout: timeout))
        tap("home.log")
        enterWeight("65")
        tap("weight.save")
        XCTAssertTrue(app.buttons["home.log"].waitForExistence(timeout: timeout))
        launch(reset: false)
        let latest = app.descendants(matching: .any).matching(identifier: "home.latestValue").firstMatch
        XCTAssertTrue(latest.waitForExistence(timeout: timeout))
        XCTAssertTrue(latest.label.contains("65"))
    }

    func testPeriodsRangeAndHistoricalDay() {
        launch(["-demo", "-expired"])
        tap("home.period")
        XCTAssertTrue(app.buttons["Period ended today"].waitForExistence(timeout: timeout))
        tap("home.period")
        XCTAssertTrue(app.buttons["Period started today"].waitForExistence(timeout: timeout))
        tap("notice.undo")
        XCTAssertTrue(app.buttons["Period ended today"].waitForExistence(timeout: timeout))
        tap("home.period")
        tap("range.all")
        XCTAssertTrue(app.staticTexts["chart.freeRange"].waitForExistence(timeout: timeout))
        tap("range.week")
        tapChart()
        XCTAssertTrue(app.staticTexts["Weigh-in details"].exists)
        back()
        tap("home.dates")
        XCTAssertTrue(app.buttons["period.save"].waitForExistence(timeout: timeout))
    }

    func testHealthIndependentResults() {
        launch(["-demo"])
        tap("home.health")
        tap("health.continue")
        XCTAssertTrue(app.staticTexts["health.result.weight"].waitForExistence(timeout: timeout))
        XCTAssertEqual(app.staticTexts["health.result.weight"].label, "12 records read")
        XCTAssertTrue(app.staticTexts["health.result.period"].waitForExistence(timeout: timeout))
        XCTAssertEqual(app.staticTexts["health.result.period"].label, "No records read yet")
    }

    func testMarkPastDateFromDayDetailAndUndo() {
        launch()
        tapChart()
        tap("day.mark")
        XCTAssertTrue(app.buttons["Mark period end"].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.buttons["day.periodEdit"].exists)
        tap("notice.undo")
        XCTAssertTrue(app.buttons["Mark period start"].waitForExistence(timeout: timeout))
    }

    func testSharePresetAndCSV() {
        let preset = #"{"unit":"lb","range":"week","average":false,"appearance":"system"}"#
        let encoded = Data(preset.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        launch(["-demo", "-pro"], code: "WC1:\(encoded)\n")
        tap("home.share")
        tap("share.image")
        XCTAssertTrue(app.staticTexts["share.requested"].waitForExistence(timeout: timeout))
        back()
        tap("home.settings")
        tap("settings.preset")
        tap("preset.apply")
        waitForNotice("Settings applied")
        tap("notice.undo")
        waitForNotice("Undone")
        tap("notice.dismiss")
        XCTAssertTrue(app.staticTexts["notice.message"].waitForNonExistence(timeout: timeout))
        back()
        tap("settings.exportCSV")
        tap("csv.save")
        waitForNotice("CSV ready")
    }

    func testReviewAfterThirdManualDayOnce() {
        launch(["-demo", "-review-demo"])
        XCTAssertFalse(app.staticTexts["review.requested"].exists)
        tap("home.log")
        enterWeight("67")
        tap("weight.save")
        XCTAssertTrue(app.staticTexts["review.requested"].waitForExistence(timeout: timeout))
        launch(["-demo", "-review-demo"], reset: false)
        tap("home.log")
        enterWeight("68")
        tap("weight.save")
        XCTAssertTrue(app.buttons["home.log"].waitForExistence(timeout: timeout))
        XCTAssertFalse(app.staticTexts["review.requested"].waitForExistence(timeout: timeout))
    }

    func testStoreScreenshots() throws {
        for lang in ["en", "zh-Hans", "zh-Hant"] {
            launch(["-demo", "-pro"], lang: lang)
            XCTAssertTrue(app.buttons["home.log"].waitForExistence(timeout: timeout))
            try shot("store-\(lang)-01-home")
            tap("home.log")
            enterWeight("65.2")
            try shot("store-\(lang)-02-log")
            back()
            tapChart()
            tap("day.periodEdit")
            XCTAssertTrue(app.buttons["period.save"].waitForExistence(timeout: timeout))
            try shot("store-\(lang)-03-period")
            back()
            back()
            tap("home.health")
            XCTAssertTrue(app.buttons["health.continue"].waitForExistence(timeout: timeout))
            try shot("store-\(lang)-04-health")
            back()
            tapChart()
            try shot("store-\(lang)-05-day")
        }
    }

    func testPaywallScreenshot() throws {
        launch(["-paywall"], lang: "zh-Hans")
        XCTAssertTrue(app.buttons["paywall.trial"].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.buttons["paywall.buy"].exists)
        XCTAssertTrue(app.buttons["paywall.restore"].exists)
        try shot("paid-01-paywall")
    }

    private func shot(_ name: String) throws {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let path = ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? ProcessInfo.processInfo.environment["TEST_RUNNER_SHOTS_DIR"] {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try screenshot.pngRepresentation.write(to: directory.appendingPathComponent(name + ".png"))
            } catch {
            }
        }
    }
}
