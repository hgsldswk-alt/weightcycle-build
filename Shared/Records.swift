import Foundation

struct Day: Codable, Hashable, Comparable, Identifiable, Sendable {
    let value: Int
    var id: Int { value }
    init(_ value: Int) { self.value = value }

    static var utc: Calendar { calendar(TimeZone(secondsFromGMT: 0)!) }
    static func calendar(_ zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    init(_ date: Date, zone: TimeZone = .current) {
        let parts = Self.calendar(zone).dateComponents([.year, .month, .day], from: date)
        let midnight = Self.utc.date(from: parts)!
        value = Int(midnight.timeIntervalSince1970 / 86_400)
    }

    var utcDate: Date { Date(timeIntervalSince1970: Double(value) * 86_400) }
    func localDate(zone: TimeZone = .current) -> Date {
        var parts = Self.utc.dateComponents([.year, .month, .day], from: utcDate)
        parts.hour = 12
        return Self.calendar(zone).date(from: parts)!
    }

    func add(_ days: Int) -> Day { Day(value + days) }
    func months(_ months: Int) -> Day {
        Day(Self.utc.date(byAdding: .month, value: months, to: utcDate)!, zone: Self.utc.timeZone)
    }

    static func < (lhs: Day, rhs: Day) -> Bool { lhs.value < rhs.value }
    var iso: String {
        let parts = Self.utc.dateComponents([.year, .month, .day], from: utcDate)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    init?(iso: String) {
        let fields = iso.split(separator: "-").compactMap { Int($0) }
        guard fields.count == 3, (1...9999).contains(fields[0]),
              let date = Self.utc.date(from: DateComponents(year: fields[0], month: fields[1], day: fields[2])) else { return nil }
        self.init(date, zone: Self.utc.timeZone)
        guard self.iso == iso else { return nil }
    }

    var short: String { utcDate.formatted(.dateTime.month(.abbreviated).day().timeZoneUTC) }
    var full: String { utcDate.formatted(.dateTime.year().month(.abbreviated).day().timeZoneUTC) }
}

private extension Date.FormatStyle {
    var timeZoneUTC: Self {
        var style = self
        style.timeZone = Day.utc.timeZone
        style.calendar = Day.utc
        return style
    }
}

enum WeightUnit: String, Codable, CaseIterable, Sendable {
    case kg, lb
    func display(_ kg: Double) -> Double { self == .kg ? kg : kg / 0.45359237 }
    func kilograms(_ value: Double) -> Double { self == .kg ? value : value * 0.45359237 }
    var label: String { L.t("unit." + rawValue) }
    func text(_ kg: Double) -> String { L.f("weight.value", L.number(display(kg)), label) }
}

enum ChartRange: String, Codable, CaseIterable, Sendable {
    case week, month, all
    var label: String { L.t("range." + rawValue) }
}

enum Appearance: String, Codable, CaseIterable, Sendable {
    case system, light, dark
    var label: String { L.t("appearance." + rawValue) }
}

struct Preferences: Codable, Equatable, Sendable {
    var unit: WeightUnit = Locale.current.measurementSystem == .us ? .lb : .kg
    var range: ChartRange = .month
    var average = true
    var appearance: Appearance = .system
}

enum RecordSource: String, Codable, Sendable {
    case manual, health, correction
    var label: String { L.t("source." + rawValue) }
}

struct WeightEntry: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    let day: Day
    let date: Date
    let zoneID: String
    let kg: Double
    var source: RecordSource = .manual
    var sourceID: String? = nil
    var original: UUID? = nil

    var localTime: String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = TimeZone(identifier: zoneID) ?? .current
        return date.formatted(style)
    }
    static func valid(_ kg: Double) -> Bool { kg.isFinite && kg > 0 && kg <= 1500 }
}

struct PeriodSample: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let date: Date
    let endDate: Date
    let zoneID: String
    let start: Day
    let end: Day
    let sourceID: String
    let starts: Bool
    let hasFlow: Bool

    static func lastDay(start: Date, end: Date, zone: TimeZone) -> Day {
        guard end > start else { return Day(start, zone: zone) }
        let calendar = Day.calendar(zone)
        if calendar.startOfDay(for: end) == end {
            return Day(calendar.date(byAdding: .day, value: -1, to: end)!, zone: zone)
        }
        return Day(end, zone: zone)
    }
}

struct Period: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var start: Day
    var end: Day?
    var correctedStart: Day? = nil
    var correctedEnd: Day? = nil

    func confirmed(through today: Day) -> Day { max(start, end ?? today) }
    var isCorrection: Bool { correctedStart != nil }
}

struct PeriodBand: Equatable, Identifiable, Sendable {
    let start: Day
    var end: Day
    let sources: Set<String>
    let manual: Period?
    var id: Day { start }
}

enum HealthKind: String, Codable, CaseIterable, Sendable {
    case weight, period
    var label: String { L.t("health." + rawValue) }
}

struct Records: Codable, Equatable, Sendable {
    var weights: [WeightEntry] = []
    var flow: [PeriodSample] = []
    var periods: [Period] = []
    var preferences = Preferences()
    var anchors: [HealthKind: Data] = [:]
    var enabled: Set<HealthKind> = []
    var notifiedMilestone: [UUID] = []
    var reviewVersion: String?
    var weightLogDays: Set<Day> = []

    func measurements(on day: Day) -> [WeightEntry] {
        weights.filter { $0.day == day && WeightEntry.valid($0.kg) }.sorted { Trend.prefers($0, over: $1) }
    }

    mutating func apply(_ change: HealthChange, kind: HealthKind) {
        let removed = Set(change.deleted)
        switch kind {
        case .weight:
            var indexed = Dictionary(uniqueKeysWithValues: weights.map { ($0.id, $0) })
            for id in removed where indexed[id]?.source == .health { indexed[id] = nil }
            for weight in change.weights where !removed.contains(weight.id) && indexed[weight.id] == nil {
                indexed[weight.id] = weight
            }
            weights = Array(indexed.values)
        case .period:
            var indexed = Dictionary(uniqueKeysWithValues: flow.map { ($0.id, $0) })
            for id in removed { indexed[id] = nil }
            for sample in change.flow where !removed.contains(sample.id) && indexed[sample.id] == nil {
                indexed[sample.id] = sample
            }
            flow = Array(indexed.values)
        }
        anchors[kind] = change.anchor
    }
}

struct HealthChange: Sendable {
    var weights: [WeightEntry] = []
    var flow: [PeriodSample] = []
    var deleted: [UUID] = []
    var anchor: Data
}

enum RecordError: String, Error, LocalizedError {
    case invalidWeight, invalidDates, overlap, noOpenPeriod, needsEnd, invalidFile, invalidCode, codeVersion, storage, unavailable, product, pending, verification
    var errorDescription: String? { L.t("error." + rawValue) }
}
