import SwiftUI

struct WeightEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var keyboard: Bool
    @State private var date: Date
    @State private var zone: TimeZone
    @State private var text = ""
    @State private var unit: WeightUnit = .kg
    @State private var issue: String?
    let day: Day
    let editing: WeightEntry?

    init(day: Day, editing: WeightEntry?) {
        self.day = day
        self.editing = editing
        let zone = TimeZone.current
        _zone = State(initialValue: zone)
        _date = State(initialValue: day.localDate(zone: zone))
    }

    var body: some View {
        Page(title: L.t(editing == nil ? "weight.log" : "weight.edit"), subtitle: day.full) {
            VStack(alignment: .leading, spacing: 12) {
                DatePicker(selection: $date,
                           in: ...max(Day(Date(), zone: zone).localDate(zone: zone), date), displayedComponents: .date) {
                    IconRow(icon: "calendar", tone: .blue) { Text(L.t("date")) }
                }
                .environment(\.timeZone, zone).environment(\.calendar, Day.calendar(zone))
                .accessibilityIdentifier("weight.date")
                HStack(spacing: 10) {
                    IconBadge(icon: "scalemass.fill", tone: .sage).accessibilityHidden(true)
                    TextField(L.t("weight.placeholder"), text: $text)
                        .font(.system(.largeTitle, design: .rounded).bold().monospacedDigit())
                        .keyboardType(.decimalPad)
                        .focused($keyboard)
                        .accessibilityIdentifier("weight.input")
                    StatusPill(title: unit.label, tone: .sage)
                }
                .padding(12)
                .background(Theme.sageWash.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
                HStack(spacing: 7) {
                    ForEach(WeightUnit.allCases, id: \.self) { choice in
                        ActionButton("unit." + choice.rawValue, id: "weight.unit." + choice.rawValue,
                                     kind: unit == choice ? .period : .normal) {
                            if let value = parsed {
                                text = L.number(choice.display(unit.kilograms(value)), digits: 4)
                            }
                            unit = choice
                        }
                    }
                }
            }.card()
            if let issue { Text(issue).foregroundStyle(Theme.link).accessibilityIdentifier("weight.error") }
            ActionButton("save", id: "weight.save", kind: .primary) {
                Task { await save() }
            }.disabled(model.busy)
            if let editing, editing.source == .correction {
                ActionButton("weight.restoreOriginal", id: "weight.restore", icon: "arrow.uturn.backward") {
                    Task {
                        do { try await model.removeWeightCorrection(editing); dismiss() }
                        catch { issue = L.t("error.storage") }
                    }
                }.disabled(model.busy)
            }
        }
        .task {
            unit = model.records.preferences.unit
            if let editing { text = L.number(unit.display(editing.kg), digits: 4) }
            keyboard = true
        }
    }

    private var parsed: Double? {
        let separator = Locale.current.decimalSeparator ?? "."
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: separator, with: ".")
        var ascii = ""
        for character in input {
            if character == "." { ascii.append(character) }
            else if let digit = character.wholeNumberValue, (0...9).contains(digit) { ascii += String(digit) }
            else { return nil }
        }
        return Double(ascii)
    }

    private func save() async {
        guard let parsed else { issue = L.t("error.invalidWeight"); return }
        do {
            let value = editing.flatMap { text == L.number(unit.display($0.kg), digits: 4) ? unit.display($0.kg) : nil } ?? parsed
            try await model.saveWeight(value: value, unit: unit, day: Day(date, zone: zone), zone: zone, editing: editing)
            keyboard = false
            dismiss()
        } catch { issue = (error as? RecordError)?.localizedDescription ?? L.t("error.storage") }
    }
}

struct PeriodEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date
    @State private var ongoing = false
    @State private var issue: String?
    @State private var existing: Period?
    @State private var original: PeriodBand?
    let day: Day
    let bandDay: Day?

    init(day: Day, bandDay: Day?) {
        self.day = day
        self.bandDay = bandDay
        _start = State(initialValue: day.localDate())
        _end = State(initialValue: day.localDate())
    }

    var body: some View {
        Page(title: L.t("period.dates"), subtitle: nil) {
            if let period = model.openPeriod {
                HeroCard {
                    VStack(alignment: .leading, spacing: 8) {
                        IconRow(icon: "drop.fill", tone: .rose) {
                            VStack(alignment: .leading, spacing: 4) {
                                StatusPill(title: L.t("period.ongoing"), tone: .rose)
                                Text(L.f("period.startedOn", period.start.full)).font(.subheadline)
                            }
                        }
                        if existing?.id != period.id {
                            ActionButton("period.editCurrent", id: "period.editCurrent", icon: "pencil") {
                                existing = period
                                original = nil
                                start = period.start.localDate()
                                end = model.today.localDate()
                                ongoing = true
                                issue = nil
                            }
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                DatePicker(selection: $start, in: ...max(model.today.localDate(), start), displayedComponents: .date) {
                    IconRow(icon: "calendar.badge.plus", tone: .rose) { Text(L.t("period.start")) }
                }.accessibilityIdentifier("period.start")
                Divider().padding(.leading, 49)
                Toggle(isOn: $ongoing) {
                    IconRow(icon: "drop.fill", tone: .amber) { Text(L.t("period.ongoing")) }
                }.accessibilityIdentifier("period.ongoing")
                if !ongoing {
                    Divider().padding(.leading, 49)
                    DatePicker(selection: $end, in: ...max(model.today.localDate(), end), displayedComponents: .date) {
                        IconRow(icon: "calendar.badge.checkmark", tone: .blue) { Text(L.t("period.end")) }
                    }.accessibilityIdentifier("period.end")
                }
            }.card()
            VStack(alignment: .leading, spacing: 10) {
                let first = Day(start)
                let last = ongoing ? first : Day(end)
                IconRow(icon: "calendar", tone: .rose) {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeading(title: L.t("preview"))
                        Text(L.f("chart.range", first.full, last.full)).font(.subheadline).foregroundStyle(Theme.link)
                    }
                }
                HStack {
                    ForEach(-1..<6) { i in
                        let date = first.add(i)
                        let active = date >= first && date <= last
                        Text(Day.utc.component(.day, from: date.utcDate).formatted())
                            .font(.system(.caption, design: .rounded).bold()).frame(maxWidth: .infinity, minHeight: 32)
                            .foregroundStyle(active ? Theme.link : Theme.muted)
                            .background(active ? Theme.blush : Theme.paper, in: RoundedRectangle(cornerRadius: 7))
                    }
                }.accessibilityHidden(true)
            }.card()
            if let issue { Text(issue).foregroundStyle(Theme.link).accessibilityIdentifier("period.error") }
            ActionButton("period.save", id: "period.save", kind: .primary) {
                Task {
                    var period = existing ?? Period(start: Day(start))
                    period.start = Day(start)
                    period.end = ongoing ? nil : Day(end)
                    if let original, original.manual == nil {
                        period.correctedStart = original.start
                        period.correctedEnd = original.end
                    }
                    do { try await model.savePeriod(period); dismiss() }
                    catch { issue = (error as? RecordError)?.localizedDescription ?? L.t("error.storage") }
                }
            }.disabled(model.busy)
            if let existing, existing.isCorrection {
                ActionButton("period.restoreOriginal", id: "period.restore", icon: "arrow.uturn.backward") {
                    Task {
                        do { try await model.removeCorrection(existing); dismiss() }
                        catch { issue = L.t("error.storage") }
                    }
                }.disabled(model.busy)
            }
        }
        .task {
            if let bandDay {
                original = model.band(on: bandDay)
                existing = original?.manual
            }
            start = (existing?.start ?? original?.start ?? day).localDate()
            end = (existing?.end ?? original?.end ?? day).localDate()
            ongoing = existing.map { $0.end == nil } ?? false
        }
    }
}

extension AppModel {
    func band(on day: Day) -> PeriodBand? {
        let first = min(day, records.flow.map(\.start).min() ?? day, records.periods.map(\.start).min() ?? day)
        return Periods.bands(records, in: first...max(day, today), today: today)
            .first { ($0.start...$0.end).contains(day) }
    }
}

struct DayView: View {
    @EnvironmentObject private var model: AppModel
    let day: Day
    let open: (Screen) -> Void

    var body: some View {
        Page(title: day.full, subtitle: L.t("day.title")) {
            let measurements = model.records.measurements(on: day)
            let band = model.band(on: day)
            VStack(spacing: 10) {
                if measurements.isEmpty {
                    VStack(spacing: 7) {
                        EmptyIllustration(icon: "scalemass.fill", tone: .sage)
                        Text(L.t("day.empty")).font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .card()
                } else {
                    ForEach(measurements) { reading in
                        VStack(alignment: .leading, spacing: 8) {
                            IconRow(icon: "scalemass.fill", tone: .sage) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.records.preferences.unit.text(reading.kg))
                                        .font(.system(.title, design: .rounded).bold().monospacedDigit())
                                    Text(L.f("day.reading", reading.source.label, reading.localTime))
                                        .font(.subheadline).foregroundStyle(Theme.muted)
                                    if let sourceID = reading.sourceID {
                                        Text(sourceID).font(.caption).foregroundStyle(Theme.muted).textSelection(.enabled)
                                    }
                                }
                            }
                            ActionButton("edit", id: "day.editWeight", icon: "pencil") {
                                open(.weight(day, reading.id))
                            }
                        }.card()
                    }
                }
                ActionButton("weight.log", id: "day.log", kind: .primary, icon: "plus.circle.fill") {
                    open(.weight(day, nil))
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                IconRow(icon: "drop.fill", tone: .rose) {
                    VStack(alignment: .leading, spacing: 5) {
                        SectionHeading(title: L.t("chart.period"))
                        StatusPill(title: periodText(band), tone: band == nil ? .blue : .rose)
                        if let band, !band.sources.isEmpty {
                            Text(band.sources.sorted().joined(separator: " · "))
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                }
                if model.hasPro, let mean = Trend.average(on: day, daily: model.daily) {
                    Divider().padding(.leading, 49)
                    IconRow(icon: "chart.xyaxis.line", tone: .sage) {
                        LabeledContent(L.t("chart.average"), value: model.records.preferences.unit.text(mean))
                            .font(.subheadline)
                    }
                }
            }.card()
            VStack(spacing: 9) {
                if band != nil {
                    ActionButton("period.edit", id: "day.periodEdit", kind: .period, icon: "calendar") {
                        open(.period(day, day))
                    }
                }
                if model.openPeriod == nil || day >= model.openPeriod!.start {
                    ActionButton(model.openPeriod == nil ? "period.markStart" : "period.markEnd",
                                 id: "day.mark", kind: .period, icon: "drop.fill") {
                        Task {
                            do { try await model.mark(day, end: model.openPeriod != nil) }
                            catch { model.problem = error.localizedDescription }
                        }
                    }.disabled(model.busy)
                }
                if band == nil {
                    ActionButton("period.dates", id: "day.dates", icon: "calendar.badge.plus") {
                        open(.period(day, nil))
                    }
                }
            }
        }
    }

    private func periodText(_ band: PeriodBand?) -> String {
        guard let band else { return L.t("day.noPeriod") }
        let first = band.manual?.start ?? band.start
        let last = band.manual?.end ?? band.end
        return L.f("day.periodLine", day.value - first.value + 1, first.short, last.short)
    }
}
