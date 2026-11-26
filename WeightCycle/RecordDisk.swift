import Foundation

actor RecordDisk {
    private let testing = Launch.isTesting
    private var loaded: Records?
    private var file: URL?

    func open() throws -> Records {
        if let loaded { return loaded }
        var directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true)
            .appendingPathComponent(testing ? "UITesting" : "PrivateRecords", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        let url = directory.appendingPathComponent("records.json")
        let fresh = testing && Launch.arguments.contains("-reset")
        let records: Records
        if fresh {
            records = Launch.arguments.contains("-demo") ? Self.demo() : Records()
            try persist(records, at: url)
        } else if FileManager.default.fileExists(atPath: url.path) {
            records = try JSONDecoder().decode(Records.self, from: Data(contentsOf: url))
        } else {
            records = Records()
            try persist(records, at: url)
        }
        file = url
        loaded = records
        return records
    }

    func update(_ change: @Sendable (inout Records) throws -> Void) throws -> Records {
        guard var next = loaded, let file else { throw RecordError.storage }
        try change(&next)
        if next != loaded {
            try persist(next, at: file)
            loaded = next
        }
        return next
    }

    func importCSV(_ url: URL, today: Day) throws -> Records {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let attributes = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = attributes.fileSize, size <= 16_000_000 else { throw RecordError.invalidFile }
        let data = try Data(contentsOf: url)
        return try update { records in records = try RecordCSV.imported(data, into: records, today: today) }
    }

    func exportCSV() throws -> Data { RecordCSV.export(try open()) }

    func widget(pro: Bool, expiry: Date, day: Day) throws {
        guard !testing, let loaded else { return }
        let points = Trend.normalized(loaded.weights, in: day.add(-6)...day, manualOnly: false)
        let snapshot = pro ? WidgetSnapshot(points: points, expiresAt: expiry) : nil
        try WidgetSnapshot.write(snapshot)
    }

    private func persist(_ records: Records, at url: URL) throws {
        try JSONEncoder().encode(records).write(to: url, options: [.atomic, .completeFileProtection])
    }

    private static func demo() -> Records {
        var records = Records()
        let today = Day(Date())
        let pattern = [65.8, 66.1, 66.4, 66.7, 66.1, 65.9, 65.6, 65.8, 65.5, 65.5]
        for i in 0..<100 where ![8, 19, 35, 53].contains(i) {
            let day = today.add(i - 99)
            let date = day.localDate()
            let source: RecordSource = i % 4 == 0 && i != 99 ? .health : .manual
            records.weights.append(WeightEntry(day: day, date: date, zoneID: TimeZone.current.identifier,
                                               kg: pattern[i % 10] - Double(i) * 0.015, source: source))
        }
        for offset in [-76, -53, -29, -7] {
            records.periods.append(Period(start: today.add(offset), end: today.add(offset + 4)))
        }
        records.notifiedMilestone = Array(records.periods.prefix(3).map(\.id))
        if Launch.arguments.contains("-review-demo") {
            records.weightLogDays = [today.add(-2), today.add(-1)]
        }
        return records
    }
}
