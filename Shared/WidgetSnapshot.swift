import SwiftUI

struct ShapePoint: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let connects: Bool
}

struct Sparkline: View {
    let points: [ShapePoint]
    var color = Theme.mean

    var body: some View {
        Canvas { context, size in
            var line = Path()
            for point in points {
                let position = CGPoint(x: 4 + CGFloat(point.x) * max(0, size.width - 8),
                                       y: 4 + CGFloat(1 - point.y) * max(0, size.height - 8))
                if point.connects { line.addLine(to: position) } else { line.move(to: position) }
                context.fill(Path(ellipseIn: CGRect(x: position.x - 2, y: position.y - 2, width: 4, height: 4)), with: .color(color))
            }
            context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

struct WidgetSnapshot: Codable, Sendable {
    static let group = "group.com.hgsldswk.weightcycle"
    let points: [ShapePoint]
    let expiresAt: Date

    private static func file(create: Bool) throws -> URL? {
        guard var directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("PrivateWidget", isDirectory: true) else { return nil }
        if create {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.protectionKey: FileProtectionType.complete])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
        }
        return directory.appendingPathComponent("trend.json")
    }

    static func load() -> WidgetSnapshot? {
        guard let url = try? file(create: false), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    static func write(_ snapshot: Self?) throws {
        guard let url = try file(create: snapshot != nil) else { return }
        if let snapshot {
            try JSONEncoder().encode(snapshot).write(to: url, options: [.atomic, .completeFileProtection])
        } else if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
