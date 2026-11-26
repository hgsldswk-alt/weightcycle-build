import Charts
import SwiftUI

struct WeightChart: View {
    @EnvironmentObject private var model: AppModel
    @State private var windowEnd: Day?
    @State private var zoomSpan: Int?
    @State private var focusedDay: Day?
    let select: (Day) -> Void
    let paywall: () -> Void
    let windowChanged: (ClosedRange<Day>) -> Void

    private var range: ChartRange { model.records.preferences.range }
    private var unit: WeightUnit { model.records.preferences.unit }
    private var earliest: Day? {
        [model.records.weights.map(\.day).min(), model.records.periods.map(\.start).min(),
         model.records.flow.map(\.start).min()].compactMap { $0 }.min()
    }
    private var floor: Day { model.hasPro ? min(earliest ?? model.today, model.today.add(-29)) : model.today.months(-3).add(1) }
    private var window: ClosedRange<Day> {
        let end = min(model.today, max(floor, windowEnd ?? model.today))
        if range == .all && zoomSpan == nil {
            return Trend.visible(.all, at: model.today, pro: model.hasPro, earliest: earliest)
        }
        let span = range == .week ? 7 : range == .month ? 30 : (zoomSpan ?? 30)
        return max(floor, end.add(1 - span))...end
    }
    private var showAverage: Bool { model.hasPro && model.records.preferences.average }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(ChartRange.allCases, id: \.self) { item in
                    Button {
                        windowEnd = nil
                        zoomSpan = nil
                        focusedDay = nil
                        Task {
                            var settings = model.records.preferences
                            settings.range = item
                            do { try await model.preferences(settings) }
                            catch { model.problem = error.localizedDescription }
                        }
                    } label: {
                        Text(item.label).font(.subheadline.weight(.semibold))
                            .foregroundStyle(item == range ? Theme.link : Theme.muted)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(item == range ? Theme.surface : .clear, in: RoundedRectangle(cornerRadius: 11))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("range." + item.rawValue)
                    .accessibilityAddTraits(item == range ? .isSelected : [])
                    .disabled(model.busy)
                }
            }
            .padding(3).background(Theme.blush, in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        chartHeading
                        Spacer(minLength: 0)
                        chartDateRange
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        chartHeading
                        chartDateRange
                    }
                }
                plot
                HStack(spacing: 8) {
                    legend(.weight, "chart.weighIns")
                    legend(.period, "chart.period")
                    Spacer(minLength: 0)
                    Button {
                        guard model.hasPro else { paywall(); return }
                        Task {
                            var settings = model.records.preferences
                            settings.average.toggle()
                            do { try await model.preferences(settings) }
                            catch { model.problem = error.localizedDescription }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            legend(.average, "chart.average")
                            Image(systemName: model.hasPro ? (showAverage ? "checkmark.circle.fill" : "circle") : "lock")
                                .font(.caption2).foregroundStyle(Theme.link).accessibilityHidden(true)
                        }.frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("chart.average")
                    .accessibilityValue(L.t(showAverage ? "on" : "off"))
                }
                if range == .all && !model.hasPro {
                    Text(L.t("chart.freeRange")).font(.caption.weight(.semibold)).foregroundStyle(Theme.amberInk)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Theme.amberWash, in: Capsule())
                        .accessibilityIdentifier("chart.freeRange")
                }
                if range != .all || model.hasPro {
                    HStack {
                        nudge("chevron.left", title: "chart.earlier", id: "chart.earlier") { page(-1) }
                            .disabled(window.lowerBound <= floor && !(range == .all && zoomSpan == nil))
                        if range == .all && model.hasPro {
                            Button(L.t(zoomSpan == nil ? "chart.zoom" : "chart.resetZoom")) {
                                zoom(zoomSpan == nil ? 2 : 0)
                            }.font(.caption.weight(.semibold)).accessibilityIdentifier("chart.zoom")
                        }
                        Spacer()
                        nudge("chevron.right", title: "chart.later", id: "chart.later") { page(1) }
                            .disabled(window.upperBound >= model.today)
                    }
                }
            }
            .card(12)
        }
        .onChange(of: model.hasPro) { _, enabled in
            if !enabled { zoomSpan = nil; windowEnd = nil; focusedDay = nil }
        }
        .onChange(of: window, initial: true) { _, range in windowChanged(range) }
    }

    private var chartHeading: some View {
        HStack(spacing: 7) {
            IconBadge(icon: "chart.xyaxis.line", tone: .sage, size: 26, circular: true)
                .accessibilityHidden(true)
            SectionHeading(title: L.t("chart.title"))
        }
    }

    private var chartDateRange: some View {
        Text(L.f("chart.range", window.lowerBound.short, window.upperBound.short))
            .font(.caption).foregroundStyle(Theme.muted)
            .accessibilityIdentifier("chart.range")
    }

    private enum Legend { case weight, period, average }
    private func legend(_ style: Legend, _ label: String) -> some View {
        HStack(spacing: 4) {
            switch style {
            case .weight: Capsule().fill(Theme.sage).frame(width: 13, height: 3)
            case .period: RoundedRectangle(cornerRadius: 2).fill(Theme.rose.opacity(0.32))
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.rose))
                    .frame(width: 13, height: 8)
            case .average: Rectangle().stroke(Theme.mean, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .frame(width: 13, height: 1)
            }
            Text(L.t(label)).font(.caption2)
        }.foregroundStyle(Theme.muted)
    }

    private func nudge(_ icon: String, title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            IconBadge(icon: icon, tone: .rose, size: 30, circular: true)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(DesignButtonStyle())
        .accessibilityLabel(L.t(title)).accessibilityIdentifier(id)
    }

    private func page(_ direction: Int) {
        if range == .all && zoomSpan == nil {
            guard model.hasPro else { return }
            zoomSpan = 30
        }
        let length = range == .week ? 7 : range == .month ? 30 : (zoomSpan ?? 30)
        windowEnd = min(model.today, max(min(model.today, floor.add(length - 1)), (windowEnd ?? model.today).add(length * direction)))
        focusedDay = nil
    }

    private func zoom(_ magnification: Double) {
        guard range == .all && model.hasPro else { return }
        let count = model.today.value - floor.value + 1
        if magnification <= 0 { zoomSpan = nil; windowEnd = nil; return }
        let scale = max(0.25, min(4, magnification))
        let next = min(count, max(7, Int(Double(zoomSpan ?? count) / scale)))
        if next == count { zoomSpan = nil; windowEnd = nil }
        else { zoomSpan = next }
        focusedDay = nil
    }

    private var plot: some View {
        let daily = model.daily
        let window = self.window
        let rawValues = daily.values.filter { window.contains($0.day) }.sorted { $0.day < $1.day }
        let weighIns = Trend.sampled(Trend.trace(rawValues.map { ($0.day, unit.display($0.kg)) }), in: window)
        let means = showAverage ? averagePoints(window, daily: daily) : []
        let bounds = Periods.bands(model.records, in: window, today: model.today)
        let axis = (weighIns + means).map(\.value)
        let minimum = axis.min() ?? (unit == .kg ? 50 : 110)
        let maximum = axis.max() ?? (unit == .kg ? 70 : 150)
        let pad = max((maximum - minimum) * 0.12, 0.4)
        let y = (minimum - pad)...(maximum + pad)
        let x = (Double(window.lowerBound.value) - 0.5)...(Double(window.upperBound.value) + 0.5)
        return Chart {
            ForEach(bounds) { band in
                RectangleMark(xStart: .value("x", Double(band.start.value) - 0.5),
                              xEnd: .value("x", Double(band.end.value) + 0.5),
                              yStart: .value("y", y.lowerBound), yEnd: .value("y", y.upperBound))
                    .foregroundStyle(Theme.rose.opacity(0.24))
                RuleMark(x: .value("x", Double(band.start.value) - 0.5))
                    .foregroundStyle(Theme.rose.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1))
                RuleMark(x: .value("x", Double(band.end.value) + 0.5))
                    .foregroundStyle(Theme.rose.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1))
            }
            ForEach(means) { point in
                LineMark(x: .value("x", Double(point.day.value)), y: .value("y", point.value),
                         series: .value("series", "mean-\(point.segment)"))
                    .foregroundStyle(Theme.mean).lineStyle(StrokeStyle(lineWidth: 1.4, dash: [3, 4]))
            }
            ForEach(weighIns) { point in
                LineMark(x: .value("x", Double(point.day.value)), y: .value("y", point.value),
                         series: .value("series", "weight-\(point.segment)"))
                    .foregroundStyle(Theme.sage).lineStyle(StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                PointMark(x: .value("x", Double(point.day.value)), y: .value("y", point.value))
                    .foregroundStyle(Theme.mean).symbolSize(15)
            }
        }
        .chartXScale(domain: x).chartYScale(domain: y)
        .chartXAxis {
            let distance = window.upperBound.value - window.lowerBound.value
            let ticks = Set([0, distance / 3, 2 * distance / 3, distance])
            AxisMarks(values: ticks.sorted().map { Double(window.lowerBound.value + $0) }) { mark in
                AxisValueLabel {
                    if let value = mark.as(Double.self) { Text(Day(Int(value)).short).font(.caption2) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { mark in
                AxisGridLine().foregroundStyle(Theme.boundary)
                AxisValueLabel {
                    if let value = mark.as(Double.self) {
                        Text(value.formatted(.number.precision(.fractionLength(0...1)))).font(.caption2)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { tap in
                        guard let frame = proxy.plotFrame else { return }
                        let area = geometry[frame]
                        guard area.contains(tap.location),
                              let value: Double = proxy.value(atX: tap.location.x - area.minX) else { return }
                        let day = min(window.upperBound, max(window.lowerBound, Day(Int(value.rounded()))))
                        focusedDay = day
                        select(day)
                    })
                    .simultaneousGesture(DragGesture(minimumDistance: 28).onEnded { drag in
                        guard abs(drag.translation.width) > abs(drag.translation.height),
                              range != .all || model.hasPro else { return }
                        page(drag.translation.width > 0 ? -1 : 1)
                    })
                    .simultaneousGesture(MagnifyGesture().onEnded { zoom($0.magnification) })
            }
        }
        .frame(height: 166)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("home.chart")
        .accessibilityLabel(L.t("chart.title"))
        .accessibilityValue(dayAccessibility(focusedDay ?? window.upperBound, daily: daily, bands: bounds))
        .accessibilityAdjustableAction { direction in
            let current = focusedDay ?? window.upperBound
            switch direction {
            case .increment: focusedDay = min(window.upperBound, current.add(1))
            case .decrement: focusedDay = max(window.lowerBound, current.add(-1))
            @unknown default: break
            }
        }
        .accessibilityAction(named: Text(L.t("day.open"))) { select(focusedDay ?? window.upperBound) }
    }

    private func dayAccessibility(_ day: Day, daily: [Day: WeightEntry], bands: [PeriodBand]) -> String {
        let reading = daily[day].map { unit.text($0.kg) } ?? L.t("day.empty")
        let period = bands.contains { ($0.start...$0.end).contains(day) }
        return L.f("chart.spoken", day.full, reading, L.t(period ? "day.inPeriod" : "day.noPeriod"))
    }

    private func averagePoints(_ window: ClosedRange<Day>, daily: [Day: WeightEntry]) -> [Trend.Point] {
        var dates: Set<Day> = []
        for day in daily.keys where day >= window.lowerBound.add(-6) && day <= window.upperBound {
            for offset in 0...6 where window.contains(day.add(offset)) { dates.insert(day.add(offset)) }
        }
        let values = dates.sorted().compactMap { day in
            Trend.average(on: day, daily: daily).map { (day, unit.display($0)) }
        }
        return Trend.sampled(Trend.trace(values), in: window)
    }
}
