import Foundation

enum Trend {
    struct Point: Identifiable, Equatable {
        let day: Day
        let value: Double
        let segment: Int
        var id: Day { day }
    }

    static func prefers(_ lhs: WeightEntry, over rhs: WeightEntry) -> Bool {
        if (lhs.source == .correction) != (rhs.source == .correction) { return lhs.source == .correction }
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        if lhs.source != rhs.source { return lhs.source == .manual }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    static func daily(_ weights: [WeightEntry]) -> [Day: WeightEntry] {
        var result: [Day: WeightEntry] = [:]
        for weight in weights where WeightEntry.valid(weight.kg) {
            if let previous = result[weight.day], !prefers(weight, over: previous) { continue }
            result[weight.day] = weight
        }
        return result
    }

    static func average(on day: Day, daily: [Day: WeightEntry]) -> Double? {
        let values = (0...6).compactMap { daily[day.add(-$0)]?.kg }
        guard values.count >= 3 else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func trace(_ values: [(day: Day, value: Double)]) -> [Point] {
        var previous: Day?
        var segment = 0
        return values.map { day, value in
            if previous?.add(1) != day { segment += 1 }
            previous = day
            return Point(day: day, value: value, segment: segment)
        }
    }

    static func sampled(_ points: [Point], in range: ClosedRange<Day>) -> [Point] {
        let width = max(1, (range.upperBound.value - range.lowerBound.value + 1) / 150)
        guard width > 1 else { return points }
        let groups = Dictionary(grouping: points) {
            ($0.day.value - range.lowerBound.value) / width
        }
        return groups.values.flatMap { group -> [Point] in
            let sets = Dictionary(grouping: group, by: \.segment)
            return sets.values.flatMap { run -> [Point] in
                let selected = [run.first, run.last, run.min { $0.value < $1.value }, run.max { $0.value < $1.value }]
                return Array(Dictionary(grouping: selected.compactMap { $0 }, by: \.day).values.compactMap(\.first))
            }
        }.sorted { $0.day < $1.day }
    }

    static func visible(_ range: ChartRange, at day: Day, pro: Bool, earliest: Day?) -> ClosedRange<Day> {
        let floor = day.months(-3)
        switch range {
        case .week: return day.add(-6)...day
        case .month: return day.add(-29)...day
        case .all:
            return (pro ? min(day.add(-29), earliest ?? day) : floor.add(1))...day
        }
    }

    static func normalized(_ weights: [WeightEntry], in range: ClosedRange<Day>, manualOnly: Bool = true) -> [ShapePoint] {
        let values = daily(weights.filter { (!manualOnly || $0.source == .manual) && range.contains($0.day) })
            .values.sorted { $0.day < $1.day }
        guard let low = values.map(\.kg).min(), let high = values.map(\.kg).max() else { return [] }
        let width = max(1, range.upperBound.value - range.lowerBound.value)
        return values.enumerated().map { index, weight in
            ShapePoint(x: Double(weight.day.value - range.lowerBound.value) / Double(width),
                       y: high == low ? 0.5 : (weight.kg - low) / (high - low),
                       connects: index > 0 && values[index - 1].day.add(1) == weight.day)
        }
    }
}

enum Periods {
    static func save(_ period: Period, in records: inout Records, today: Day) throws {
        guard period.start <= today, period.end.map({ $0 >= period.start && $0 <= today }) ?? true else {
            throw RecordError.invalidDates
        }
        let span = period.start...period.confirmed(through: today)
        let others = records.periods.filter { $0.id != period.id }
        guard !others.contains(where: { span.overlaps($0.start...$0.confirmed(through: today)) }) else {
            throw RecordError.overlap
        }
        records.periods = others + [period]
    }

    static func mark(_ day: Day, end: Bool, in records: inout Records, today: Day) throws {
        if end {
            guard var open = records.periods.first(where: { $0.end == nil }) else {
                throw RecordError.noOpenPeriod
            }
            open.end = day
            try save(open, in: &records, today: today)
        } else {
            guard !records.periods.contains(where: { $0.end == nil }) else { throw RecordError.needsEnd }
            try save(Period(start: day), in: &records, today: today)
        }
    }

    static func bands(_ records: Records, in window: ClosedRange<Day>, today: Day) -> [PeriodBand] {
        var imported: [Day: Set<String>] = [:]
        var starts: [Day: Set<String>] = [:]
        let groups = Dictionary(grouping: records.flow, by: \.sourceID)
        for (source, samples) in groups {
            var blocked: Set<Day> = []
            var days: Set<Day> = []
            for sample in samples {
                let first = max(sample.start, window.lowerBound)
                let last = min(sample.end, window.upperBound)
                guard first <= last else { continue }
                for index in first.value...last.value {
                    if sample.hasFlow { days.insert(Day(index)) } else { blocked.insert(Day(index)) }
                }
                if sample.hasFlow && sample.starts && window.contains(sample.start) {
                    starts[sample.start, default: []].insert(source)
                }
            }
            for day in days.subtracting(blocked) { imported[day, default: []].insert(source) }
        }

        var manual: [Day: Period] = [:]
        for period in records.periods {
            if let start = period.correctedStart, let end = period.correctedEnd {
                let first = max(start, window.lowerBound)
                let last = min(end, window.upperBound)
                if first <= last {
                    for index in first.value...last.value { imported[Day(index)] = nil }
                }
            }
            let first = max(period.start, window.lowerBound)
            let last = min(period.end ?? period.start, window.upperBound)
            if first <= last {
                for index in first.value...last.value { manual[Day(index)] = period }
            }
        }

        var result: [PeriodBand] = []
        var previousSources: Set<String> = []
        for day in Set(imported.keys).union(manual.keys).sorted() {
            let sources = imported[day] ?? []
            let current = manual[day]
            if let last = result.last, last.end.add(1) == day, last.manual?.id == current?.id,
               current != nil || (!previousSources.isDisjoint(with: sources) && (starts[day] ?? []).isEmpty) {
                result[result.count - 1] = PeriodBand(start: last.start, end: day,
                                                     sources: last.sources.union(sources), manual: current)
            } else {
                result.append(PeriodBand(start: day, end: day, sources: sources, manual: current))
            }
            previousSources = sources
        }
        return result
    }

    static func milestone(_ records: Records) -> [Period]? {
        let days = Set(records.weights.filter { $0.source == .manual }.map(\.day))
        let qualified = records.periods.filter { period in
            guard let end = period.end, !period.isCorrection else { return false }
            return days.contains { (period.start...end).contains($0) }
        }.sorted { $0.start < $1.start }
        guard qualified.count >= 3, records.notifiedMilestone.isEmpty else { return nil }
        return Array(qualified.prefix(3))
    }
}
