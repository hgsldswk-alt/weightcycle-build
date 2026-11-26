import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectingFile = false
    @State private var exporting = false
    @State private var document: CSVDocument?
    @State private var confirmExport = false
    let open: (Screen) -> Void

    var body: some View {
        Page(title: L.t("settings"), subtitle: nil) {
            preferences
            VStack(alignment: .leading, spacing: 8) {
                SectionHeading(title: L.t("settings.section.records"))
                VStack(spacing: 5) {
                    IconRowButton(title: "history.title", id: "settings.history", icon: "clock.arrow.circlepath", tone: .blue) {
                        open(.history)
                    }
                    Divider().padding(.leading, 49)
                    IconRowButton(title: "health.title", id: "settings.health", icon: "heart.fill", tone: .sage) {
                        open(.health)
                    }
                }.card(12)
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionHeading(title: L.t("settings.section.transfer"))
                VStack(spacing: 5) {
                    IconRowButton(title: "preset.import", id: "settings.preset", icon: "clipboard", tone: .amber) {
                        open(.code)
                    }
                    Divider().padding(.leading, 49)
                    IconRowButton(title: "preset.copy", id: "settings.copy", icon: "doc.on.doc",
                                  tone: .amber, accessory: nil) {
                        copyPreset(model)
                    }
                    Divider().padding(.leading, 49)
                    IconRowButton(title: "csv.import", id: "settings.importCSV", icon: "tray.and.arrow.down", tone: .sage) {
                        selectingFile = true
                    }
                    Divider().padding(.leading, 49)
                    IconRowButton(title: "csv.export", id: "settings.exportCSV", icon: "tray.and.arrow.up", tone: .blue) {
                        if model.hasPro { confirmExport = true } else { open(.paywall) }
                    }
                    if confirmExport {
                        VStack(alignment: .leading, spacing: 9) {
                            Text(L.t("csv.fields")).font(.footnote).foregroundStyle(Theme.muted)
                            ActionButton("csv.saveFile", id: "csv.save", kind: .primary, icon: "arrow.down.doc") {
                                Task {
                                    do {
                                        document = CSVDocument(data: try await model.exportCSV())
                                        if Launch.isTesting { model.inform("notice.exportReady"); document = nil }
                                        else { exporting = true }
                                    } catch { model.problem = error.localizedDescription }
                                }
                            }
                        }
                        .padding(10)
                        .background(Theme.blueWash, in: RoundedRectangle(cornerRadius: 12))
                    }
                }.card(12)
            }
            VStack(spacing: 5) {
                IconRowButton(title: "widget.title", id: "settings.widget", icon: "square.grid.2x2", tone: .blue) {
                    open(.widget)
                }
                if !Launch.freePeriod {
                    Divider().padding(.leading, 49)
                    IconRowButton(title: "paywall.title", id: "settings.pro", icon: "star.fill", tone: .amber) {
                        open(.paywall)
                    }
                    Divider().padding(.leading, 49)
                    IconRowButton(title: "paywall.restore", id: "settings.restore", icon: "arrow.clockwise",
                                  tone: .rose, accessory: nil) {
                        Task { await model.restore() }
                    }.disabled(model.purchaseBusy)
                }
            }.card(12)
        }
        .fileImporter(isPresented: $selectingFile, allowedContentTypes: [.commaSeparatedText]) { result in
            do {
                let url = try result.get()
                Task { await model.importCSV(url) }
            } catch { model.problem = L.t("error.invalidFile") }
        }
        .fileExporter(isPresented: $exporting, document: document,
                      contentType: .commaSeparatedText, defaultFilename: "WeightCycle") { result in
            document = nil
            switch result {
            case .success: model.inform("notice.exported")
            case .failure: model.problem = L.t("error.storage")
            }
        }
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: L.t("settings.section.preferences"))
            VStack(alignment: .leading, spacing: 8) {
                IconRow(icon: "scalemass.fill", tone: .sage) {
                    Text(L.t("settings.unit")).font(.subheadline.weight(.semibold))
                }
                Picker(L.t("settings.unit"), selection: Binding(get: { model.records.preferences.unit }, set: { unit in
                    var next = model.records.preferences
                    next.unit = unit
                    apply(next)
                })) {
                    ForEach(WeightUnit.allCases, id: \.self) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("settings.unit")
                Divider().padding(.leading, 49)
                Picker(selection: Binding(get: { model.records.preferences.appearance }, set: { appearance in
                    var next = model.records.preferences
                    next.appearance = appearance
                    apply(next)
                })) {
                    ForEach(Appearance.allCases, id: \.self) { Text($0.label).tag($0) }
                } label: {
                    IconRow(icon: "circle.lefthalf.filled", tone: .amber) { Text(L.t("settings.appearance")) }
                }
                .accessibilityIdentifier("settings.appearance")
            }.card(12).disabled(model.busy)
        }
    }

    private func apply(_ next: Preferences) {
        Task {
            do { try await model.preferences(next) }
            catch { model.problem = error.localizedDescription }
        }
    }
}

private struct CSVDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText]
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw RecordError.invalidFile }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var day = Date()
    let open: (Day) -> Void

    var body: some View {
        Page(title: L.t("history.title"), subtitle: L.t("history.subtitle")) {
            let recent = Set(model.records.weights.map(\.day) + model.records.periods.map(\.start) + model.records.flow.filter(\.hasFlow).map(\.start))
            let daily = model.daily
            VStack(spacing: 10) {
                if recent.isEmpty {
                    VStack(spacing: 7) {
                        EmptyIllustration(icon: "clock.arrow.circlepath", tone: .blue)
                        Text(L.t("history.empty")).font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .card()
                }
                DatePicker(selection: $day, in: ...max(model.today.localDate(), day), displayedComponents: .date) {
                    IconRow(icon: "calendar", tone: .blue) { Text(L.t("date")) }
                }.accessibilityIdentifier("history.date").card(12)
                ActionButton("day.open", id: "history.open", kind: .primary, icon: "calendar") { open(Day(day)) }
            }
            VStack(spacing: 6) {
                ForEach(Array(recent.sorted(by: >).prefix(14))) { date in
                    Button { open(date) } label: {
                        IconRow(icon: daily[date] == nil ? "drop.fill" : "scalemass.fill",
                                tone: daily[date] == nil ? .rose : .sage) {
                            Text(date.full).font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            if let weight = daily[date] {
                                StatusPill(title: model.records.preferences.unit.text(weight.kg), tone: .sage)
                                    .monospacedDigit()
                            }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted).accessibilityHidden(true)
                        }.card(9)
                    }
                    .buttonStyle(DesignButtonStyle())
                    .accessibilityIdentifier("history.day." + date.iso)
                }
            }
        }
    }
}

@MainActor
func copyPreset(_ model: AppModel) {
    do {
        UIPasteboard.general.string = try PresetCode.encode(model.records.preferences)
        model.inform("notice.copied")
    } catch { model.problem = L.t("error.invalidCode") }
}

struct PresetView: View {
    @EnvironmentObject private var model: AppModel
    @State private var issue: String?

    var body: some View {
        Page(title: L.t("preset.import"), subtitle: nil) {
            HeroCard {
                IconRow(icon: "clipboard", tone: .amber) {
                    Text(L.t("preset.help")).font(.subheadline).foregroundStyle(Theme.muted)
                }
            }
            if let issue { Text(issue).foregroundStyle(Theme.link).accessibilityIdentifier("preset.error") }
            ActionButton("preset.paste", id: "preset.apply", kind: .primary, icon: "clipboard") {
                Task {
                    do {
                        let code = Launch.isTesting ? ProcessInfo.processInfo.environment["WC_TEST_CODE"] : UIPasteboard.general.string
                        let next = try PresetCode.decode(code ?? "")
                        try await model.preferences(next, imported: true)
                        issue = nil
                    } catch { issue = error.localizedDescription }
                }
            }.disabled(model.busy)
        }
    }
}

struct PaywallView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Page(title: L.t("paywall.title"), subtitle: L.t("paywall.intro")) {
            VStack(alignment: .leading, spacing: 4) {
                IconRow(icon: "clock.arrow.circlepath", tone: .blue) { Text(L.t("paywall.history")) }
                IconRow(icon: "chart.xyaxis.line", tone: .sage) { Text(L.t("chart.average")) }
                IconRow(icon: "tray.and.arrow.up", tone: .amber) { Text(L.t("csv.export")) }
                IconRow(icon: "square.and.arrow.up", tone: .rose) { Text(L.t("paywall.share")) }
                IconRow(icon: "square.grid.2x2", tone: .blue) { Text(L.t("widget.title")) }
            }.card(12)
            VStack(alignment: .leading, spacing: 10) {
                Text(L.t("paywall.terms")).font(.footnote).foregroundStyle(Theme.muted)
                if model.entitlement?.purchasedPro == true {
                    IconRow(icon: "checkmark.seal.fill", tone: .sage) {
                        StatusPill(title: L.t("paywall.owned"), tone: .sage)
                    }.card(12)
                } else {
                    if let entitlement = model.entitlement, entitlement.trialClaimedAt != nil, entitlement.hasPro(at: model.clock) {
                        IconRow(icon: "clock.fill", tone: .sage) {
                            StatusPill(title: L.f("paywall.ends", Day(entitlement.trialEnd).full), tone: .sage)
                        }.card(12)
                    } else if model.entitlement?.trialClaimedAt == nil,
                              model.entitlement.map({ model.clock < $0.trialEnd }) ?? true,
                              !(Launch.isTesting && Launch.arguments.contains("-expired")) {
                        ActionButton("paywall.trial", id: "paywall.trial", kind: .primary, icon: "gift.fill") {
                            Task { await model.purchase(Launch.trialID) }
                        }.disabled(model.purchaseBusy)
                    } else {
                        IconRow(icon: "clock.fill", tone: .amber) {
                            Text(L.t("paywall.expired")).font(.subheadline).foregroundStyle(Theme.muted)
                        }.card(12)
                    }
                    ActionButton("paywall.buy", id: "paywall.buy", kind: .primary, icon: "star.fill") {
                        Task { await model.purchase(Launch.proID) }
                    }.disabled(model.purchaseBusy)
                    let price = model.products[Launch.proID]?.displayPrice ?? (Launch.isTesting ? L.t("paywall.testPrice") : nil)
                    Text(price.map { L.f("paywall.price", $0) } ?? L.t("paywall.priceUnavailable"))
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                ActionButton("paywall.restore", id: "paywall.restore", icon: "arrow.clockwise") { Task { await model.restore() } }
                    .disabled(model.purchaseBusy)
                if model.purchaseBusy { ProgressView() }
            }
        }
        .task { await model.loadProducts() }
    }
}
