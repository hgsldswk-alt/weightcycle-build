import Foundation

enum PresetCode {
    static func encode(_ preferences: Preferences) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(preferences)
        return "WC1:" + data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ text: String) throws -> Preferences {
        let code = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.hasPrefix("WC1:") else {
            throw code.hasPrefix("WC") ? RecordError.codeVersion : RecordError.invalidCode
        }
        let payload = String(code.dropFirst(4))
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        guard !payload.isEmpty, payload.count <= 512, payload.unicodeScalars.allSatisfy(allowed.contains) else {
            throw RecordError.invalidCode
        }
        var base64 = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let fields = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(fields.keys) == ["unit", "range", "average", "appearance"],
              let preferences = try? JSONDecoder().decode(Preferences.self, from: data) else {
            throw RecordError.invalidCode
        }
        return preferences
    }
}

enum RecordCSV {
    static let header = "type,id,date,end_date,time_utc,time_zone,weight_kg"

    static func export(_ records: Records) -> Data {
        let clock = ISO8601DateFormatter()
        clock.formatOptions.insert(.withFractionalSeconds)
        var rows = [header]
        for w in records.weights.filter({ $0.source == .manual }).sorted(by: { $0.date < $1.date }) {
            rows.append(["weight", w.id.uuidString, w.day.iso, "", clock.string(from: w.date), w.zoneID, String(w.kg)].joined(separator: ","))
        }
        for p in records.periods.filter({ !$0.isCorrection }).sorted(by: { $0.start < $1.start }) {
            rows.append(["period", p.id.uuidString, p.start.iso, p.end?.iso ?? "", "", "", ""].joined(separator: ","))
        }
        return Data((rows.joined(separator: "\r\n") + "\r\n").utf8)
    }

    static func imported(_ data: Data, into records: Records, today: Day) throws -> Records {
        guard data.count <= 16_000_000, let raw = String(data: data, encoding: .utf8) else {
            throw RecordError.invalidFile
        }
        let content = raw.hasPrefix("\u{FEFF}") ? String(raw.dropFirst()) : raw
        let rows = content.split(whereSeparator: \.isNewline)
        guard rows.first.map(String.init) == header else { throw RecordError.invalidFile }
        let clock = ISO8601DateFormatter()
        clock.formatOptions.insert(.withFractionalSeconds)
        let standardClock = ISO8601DateFormatter()
        var next = records
        var seen = Set(records.weights.map(\.id) + records.periods.map(\.id))
        for row in rows.dropFirst() {
            let values = row.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard values.count == 7, let id = UUID(uuidString: values[1]),
                  let day = Day(iso: values[2]), day <= today else { throw RecordError.invalidFile }
            switch values[0] {
            case "weight":
                guard values[3].isEmpty, let date = clock.date(from: values[4]) ?? standardClock.date(from: values[4]),
                      let zone = TimeZone(identifier: values[5]), Day(date, zone: zone) == day,
                      let kg = Double(values[6]), WeightEntry.valid(kg) else { throw RecordError.invalidFile }
                if seen.insert(id).inserted {
                    next.weights.append(WeightEntry(id: id, day: day, date: date, zoneID: values[5], kg: kg))
                }
            case "period":
                let end = Day(iso: values[3])
                guard values[3].isEmpty || end != nil, values[4...6].allSatisfy(\.isEmpty) else {
                    throw RecordError.invalidFile
                }
                if seen.insert(id).inserted {
                    try Periods.save(Period(id: id, start: day, end: end), in: &next, today: today)
                }
            default: throw RecordError.invalidFile
            }
        }
        return next
    }
}
