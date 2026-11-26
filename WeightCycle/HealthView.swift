import SwiftUI

struct HealthView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var kinds = Set(HealthKind.allCases)
    @State private var clearKind: HealthKind?

    var body: some View {
        Page(title: L.t("health.title"), subtitle: L.t("health.subtitle")) {
            HeroCard {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L.t("health.headline")).font(.title2.bold())
                        Text(L.t("health.intro")).font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                    if !dynamicTypeSize.isAccessibilitySize {
                        EmptyIllustration(icon: "heart.fill", tone: .rose, size: 70)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(HealthKind.allCases, id: \.self) { kind in
                    row(kind)
                    if kind == .weight { Divider().padding(.leading, 49) }
                }
            }.card()
            IconRow(icon: "lock.shield.fill", tone: .amber) {
                VStack(alignment: .leading, spacing: 5) {
                    SectionHeading(title: L.t("health.readOnly"))
                    Text(L.t("health.privacy")).font(.footnote).foregroundStyle(Theme.muted)
                }
            }.card()
            if model.healthBusy { ProgressView() }
            ActionButton("health.continue", id: "health.continue", kind: .primary, icon: "heart.fill") {
                Task { await model.authorize(kinds) }
            }.disabled(kinds.isEmpty || model.healthBusy || model.busy)
            if !model.records.enabled.isEmpty {
                ActionButton("retry", id: "health.retry", icon: "arrow.clockwise") {
                    Task { await model.syncHealth(model.records.enabled) }
                }.disabled(model.healthBusy || model.busy)
            }
        }
        .confirmationDialog(L.t("health.clearConfirm"), isPresented: Binding(get: { clearKind != nil }, set: { if !$0 { clearKind = nil } }),
                            titleVisibility: .visible, presenting: clearKind) { kind in
            Button(L.t("health.clear"), role: .destructive) { manage(kind, clear: true) }
        }
    }

    private func row(_ kind: HealthKind) -> some View {
        let active = model.records.enabled.contains(kind)
        let existing = kind == .weight ? model.records.weights.filter { $0.source == .health }.count : model.records.flow.filter(\.hasFlow).count
        let count = model.healthResults[kind] ?? existing
        let tone: AccentTone = kind == .weight ? .sage : .rose
        let actionsLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 7)) : AnyLayout(HStackLayout(spacing: 7))
        return VStack(alignment: .leading, spacing: 7) {
            Toggle(isOn: Binding(get: { kinds.contains(kind) }, set: { enabled in
                if enabled { kinds.insert(kind) } else { kinds.remove(kind) }
            })) {
                IconRow(icon: kind == .weight ? "scalemass.fill" : "drop.fill", tone: tone) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(kind.label).font(.subheadline.weight(.semibold))
                        Text(L.t("health.description." + kind.rawValue)).font(.caption).foregroundStyle(Theme.muted)
                    }
                }
            }.accessibilityIdentifier("health.select." + kind.rawValue)
            if model.healthFailures.contains(kind) {
                StatusPill(title: L.t("health.readError"), tone: .amber)
                    .accessibilityIdentifier("health.result." + kind.rawValue)
                    .padding(.leading, 49)
            } else if model.healthResults[kind] != nil || active || existing > 0 {
                StatusPill(title: count > 0 ? L.f("health.count", count) : L.t("health.empty"),
                           tone: count > 0 ? tone : .blue)
                    .accessibilityIdentifier("health.result." + kind.rawValue)
                    .padding(.leading, 49)
            }
            if active || count > 0 {
                actionsLayout {
                    if active {
                        ActionButton("health.pause", id: "health.pause." + kind.rawValue, icon: "pause") {
                            manage(kind, clear: false)
                        }
                    }
                    ActionButton("health.clear", id: "health.clear." + kind.rawValue, icon: "trash") {
                        clearKind = kind
                    }
                }
                .disabled(model.healthBusy || model.busy)
            }
        }
    }

    private func manage(_ kind: HealthKind, clear: Bool) {
        Task {
            do { try await model.manageHealth(kind, clear: clear) }
            catch { model.problem = L.t("error.storage") }
        }
    }
}
