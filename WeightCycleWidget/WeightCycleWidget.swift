import SwiftUI
import WidgetKit

private struct WeightTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

private struct WeightProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeightTimelineEntry {
        WeightTimelineEntry(date: .now, snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeightTimelineEntry) -> Void) {
        completion(WeightTimelineEntry(date: .now, snapshot: nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeightTimelineEntry>) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let now = Date()
            let snapshot = WidgetSnapshot.load().flatMap { $0.expiresAt > now ? $0 : nil }
            var entries = [WeightTimelineEntry(date: now, snapshot: snapshot)]
            if let snapshot {
                entries.append(WeightTimelineEntry(date: snapshot.expiresAt, snapshot: nil))
            }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(6 * 3600))))
        }
    }
}

private struct WeightWidgetContent: View {
    @Environment(\.widgetFamily) private var family
    let entry: WeightTimelineEntry
    private let quickLog = URL(string: "weightcycle://log")!
    private let trend = URL(string: "weightcycle://trend")!

    var body: some View {
        Group {
            if family == .systemSmall, entry.snapshot != nil {
                VStack(alignment: .leading) {
                    Text(L.t("widget.quick")).font(.headline)
                    Spacer()
                    Label(L.t("weight.log"), systemImage: "plus.circle.fill").font(.subheadline.weight(.semibold))
                }
                .widgetURL(quickLog)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(L.t("widget.trend")).font(.headline)
                        Spacer()
                        if entry.snapshot != nil {
                            Link(destination: quickLog) {
                                Image(systemName: "plus.circle.fill").font(.title3)
                            }.accessibilityLabel(L.t("weight.log"))
                        }
                    }
                    if let snapshot = entry.snapshot, !snapshot.points.isEmpty {
                        Sparkline(points: snapshot.points).privacySensitive()
                        Text(L.t("widget.recent")).font(.caption).foregroundStyle(Theme.muted)
                    } else {
                        Spacer()
                        Text(L.t("widget.neutral")).font(.subheadline).foregroundStyle(Theme.muted)
                        Spacer()
                    }
                }
                .widgetURL(trend)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .foregroundStyle(Theme.ink)
        .containerBackground(for: .widget) { Theme.paper }
    }
}

@main
struct WeightCycleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeightCycleWidget", provider: WeightProvider()) { entry in
            WeightWidgetContent(entry: entry)
        }
        .configurationDisplayName(L.t("widget.title"))
        .description(L.t("widget.description"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
