import CoreImage
import XCTest

final class CoreTests: XCTestCase {
    private let today = Day(iso: "2026-11-24")!

    private func weigh(_ day: Day, kg: Double, source: RecordSource = .manual, seconds: Double = 0) -> WeightEntry {
        WeightEntry(day: day, date: day.utcDate.addingTimeInterval(seconds), zoneID: "UTC", kg: kg, source: source)
    }

    func testDailyLatestTieAndCorrection() {
        XCTAssertTrue(Trend.daily([]).isEmpty)
        let old = weigh(today, kg: 50)
        let later = weigh(today, kg: 52, source: .health, seconds: 60)
        let manual = weigh(today, kg: 51, seconds: 60)
        let correction = weigh(today, kg: 53, source: .correction)
        XCTAssertEqual(Trend.daily([old])[today], old)
        XCTAssertEqual(Trend.daily([old, later])[today], later)
        XCTAssertEqual(Trend.daily([old, later, manual])[today], manual)
        XCTAssertEqual(Trend.daily([old, later, manual, correction])[today], correction)
        XCTAssertNil(Trend.daily([weigh(today, kg: .infinity)])[today])
    }

    func testAveragesCrossWindowAndKeepMissingDayIndependent() {
        let a = weigh(today.add(-6), kg: 60)
        let b = weigh(today.add(-4), kg: 66)
        let c = weigh(today.add(-1), kg: 63)
        XCTAssertNil(Trend.average(on: today, daily: Trend.daily([a, b])))
        let daily = Trend.daily([a, b, c])
        XCTAssertNil(daily[today])
        XCTAssertEqual(Trend.average(on: today, daily: daily), 63)
        XCTAssertNil(Trend.average(on: today.add(1), daily: daily))
        let trace = Trend.trace([(a.day, a.kg), (c.day, c.kg), (today, 64)])
        XCTAssertNotEqual(trace[0].segment, trace[1].segment)
        XCTAssertEqual(trace[1].segment, trace[2].segment)
    }

    func testAllRangeAndSamplingKeepExtrema() {
        XCTAssertEqual(Trend.visible(.all, at: today, pro: false, earliest: today.add(-300)).lowerBound.iso, "2026-08-25")
        XCTAssertEqual(Trend.visible(.week, at: today, pro: false, earliest: nil).lowerBound, today.add(-6))
        let first = today.add(-710)
        let values = (0...710).map { (first.add($0), $0 == 18 ? -200.0 : $0 == 20 ? 300.0 : 60.0) }
        let sampled = Trend.sampled(Trend.trace(values), in: first...today)
        XCTAssertEqual(sampled.map(\.value).min(), -200)
        XCTAssertEqual(sampled.map(\.value).max(), 300)
        XCTAssertEqual(sampled.first?.day, first)
        XCTAssertEqual(sampled.last?.day, today)
    }

    func testDatesStayPinnedAcrossDSTAndTravel() {
        let clock = ISO8601DateFormatter()
        let la = TimeZone(identifier: "America/Los_Angeles")!
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let instant = clock.date(from: "2026-03-08T07:30:00Z")!
        let day = Day(instant, zone: la)
        XCTAssertEqual(day.iso, "2026-03-07")
        XCTAssertEqual(Day(instant, zone: tokyo).iso, "2026-03-08")
        XCTAssertEqual(Day(day.add(2).localDate(zone: la), zone: la).iso, "2026-03-09")
        XCTAssertEqual(Day(iso: "2025-12-31")?.add(1).iso, "2026-01-01")
        XCTAssertNil(Day(iso: "2026-02-30"))
        let end = clock.date(from: "2026-03-09T07:00:00Z")!
        XCTAssertEqual(PeriodSample.lastDay(start: instant, end: end, zone: la).iso, "2026-03-08")
    }

    func testUnitsAndCSVKeepManualRowsOnly() throws {
        XCTAssertEqual(WeightUnit.lb.kilograms(100), 45.359237, accuracy: 0.000001)
        XCTAssertEqual(WeightUnit.lb.display(WeightUnit.lb.kilograms(123.4)), 123.4, accuracy: 0.000001)
        var records = Records()
        records.weights = [weigh(today, kg: 61.2), weigh(today, kg: 62, source: .health)]
        records.periods = [Period(start: today, end: today)]
        let csv = RecordCSV.export(records)
        let restored = try RecordCSV.imported(csv, into: Records(), today: today)
        XCTAssertEqual(restored.weights, Array(records.weights.prefix(1)))
        XCTAssertEqual(restored.periods, records.periods)
        XCTAssertEqual(try RecordCSV.imported(csv, into: restored, today: today), restored)
        XCTAssertThrowsError(try RecordCSV.imported(csv + Data("bad\r\n".utf8), into: restored, today: today))
    }

    func testImportedBandsUseStartsGapsAndExplicitNoFlow() throws {
        func sample(_ offset: Int, _ source: String = "a", starts: Bool = false, hasFlow: Bool = true) -> PeriodSample {
            let day = today.add(offset)
            return PeriodSample(id: UUID(), date: day.utcDate, endDate: day.utcDate, zoneID: "UTC", start: day,
                                end: day, sourceID: source, starts: starts, hasFlow: hasFlow)
        }
        var records = Records()
        records.flow = [sample(-7), sample(-6), sample(-5, starts: true), sample(-4), sample(-4, hasFlow: false),
                        sample(-3), sample(-3, "b"), sample(-1)]
        let window = today.add(-7)...today
        let bands = Periods.bands(records, in: window, today: today)
        XCTAssertEqual(bands.map(\.start), [-7, -5, -3, -1].map(today.add))
        XCTAssertEqual(bands.first?.end, today.add(-6))
        XCTAssertEqual(bands[2].sources, ["a", "b"])
        let correction = Period(start: today.add(-4), end: today.add(-4), correctedStart: today.add(-5), correctedEnd: today.add(-5))
        try Periods.save(correction, in: &records, today: today)
        let corrected = Periods.bands(records, in: window, today: today)
        XCTAssertFalse(corrected.contains { $0.start == today.add(-5) })
        XCTAssertTrue(corrected.contains { $0.manual?.id == correction.id })
        records.periods.removeAll()
        XCTAssertEqual(Periods.bands(records, in: window, today: today), bands)
    }

    func testManualPeriodsRejectOverlapAndFuture() throws {
        var records = Records()
        try Periods.mark(today.add(-2), end: false, in: &records, today: today)
        XCTAssertEqual(Periods.bands(records, in: today.add(-3)...today, today: today).first?.end, today.add(-2))
        XCTAssertThrowsError(try Periods.mark(today.add(-3), end: true, in: &records, today: today))
        try Periods.mark(today, end: true, in: &records, today: today)
        XCTAssertEqual(records.periods.first?.end, today)
        XCTAssertThrowsError(try Periods.save(Period(start: today.add(-1), end: today), in: &records, today: today))
        XCTAssertThrowsError(try Periods.save(Period(start: today.add(1)), in: &records, today: today))
    }

    func testIncrementalImportIsIdempotentAndOnlyDeletesExplicitIDs() {
        let manual = weigh(today, kg: 61)
        let health = weigh(today, kg: 60, source: .health)
        let correction = weigh(today, kg: 59, source: .correction)
        var records = Records()
        records.weights = [manual, correction]
        let change = HealthChange(weights: [health], anchor: Data([1]))
        records.apply(change, kind: .weight)
        records.apply(change, kind: .weight)
        XCTAssertEqual(records.weights.count, 3)
        records.apply(HealthChange(anchor: Data([2])), kind: .weight)
        XCTAssertEqual(records.weights.count, 3)
        records.apply(HealthChange(deleted: [health.id, manual.id], anchor: Data([3])), kind: .weight)
        XCTAssertEqual(Set(records.weights.map(\.id)), [manual.id, correction.id])
        XCTAssertEqual(records.anchors[.weight], Data([3]))
        XCTAssertNil(records.anchors[.period])
    }

    func testMilestoneAndShareExcludeImports() {
        var records = Records()
        for index in [30, 20, 10] {
            let first = today.add(-index)
            records.periods.append(Period(start: first, end: first.add(2)))
            records.weights.append(weigh(first, kg: 55))
        }
        records.weights.append(weigh(today, kg: 100, source: .health))
        let milestone = Periods.milestone(records)
        XCTAssertEqual(milestone?.count, 3)
        let shape = Trend.normalized(records.weights, in: today.add(-30)...today)
        XCTAssertEqual(shape.map(\.y), [0.5, 0.5, 0.5])
        records.notifiedMilestone = milestone!.map(\.id)
        XCTAssertNil(Periods.milestone(records))
    }

    func testPresetOnlyAcceptsAllowedSettings() throws {
        let prefs = Preferences(unit: .lb, range: .all, average: false, appearance: .dark)
        XCTAssertEqual(try PresetCode.decode(try PresetCode.encode(prefs)), prefs)
        XCTAssertThrowsError(try PresetCode.decode("WC2:abc"))
        func code(_ json: String) -> String {
            "WC1:" + Data(json.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        XCTAssertThrowsError(try PresetCode.decode(code(#"{"unit":"lb","range":"all","average":true,"appearance":"system","weights":[]}"#)))
        XCTAssertThrowsError(try PresetCode.decode(code(#"{"unit":"oz","range":"all","average":true,"appearance":"system"}"#)))
    }

    func testVerifiedTrialAndLifetimePurchase() {
        XCTAssertFalse(Launch.freePeriod)
        let first = today.utcDate
        let second = first.addingTimeInterval(86400)
        var entitlement = Entitlement(firstOpen: first, proStartedAt: first)
        XCTAssertFalse(entitlement.hasPro(at: first))
        entitlement.trialClaimedAt = second
        XCTAssertEqual(entitlement.trialStart, first)
        XCTAssertTrue(entitlement.hasPro(at: second))
        XCTAssertFalse(entitlement.hasPro(at: entitlement.trialEnd))
        let restored = Entitlement(firstOpen: second, proStartedAt: second, trialClaimedAt: first)
        XCTAssertEqual(restored.trialEnd, entitlement.trialEnd)
        entitlement.purchasedPro = true
        XCTAssertTrue(entitlement.hasPro(at: .distantFuture))
    }

    func testQRCodeDecodesDownloadURLWithCIDetector() throws {
        let url = DownloadCode.url(storeID: "123456789")
        XCTAssertEqual(url.absoluteString, "https://apps.apple.com/app/id123456789")
        XCTAssertEqual(DownloadCode.url(storeID: ""), DownloadCode.placeholder)
        let img = try XCTUnwrap(DownloadCode.image(for: url))
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                               options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let messages = detector.features(in: CIImage(cgImage: img)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        XCTAssertEqual(messages, [url.absoluteString])
    }
}
