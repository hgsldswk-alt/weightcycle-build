import SwiftUI

struct WidgetGuide: View {
    @EnvironmentObject private var model: AppModel
    let paywall: () -> Void

    var body: some View {
        Page(title: L.t("widget.title"), subtitle: L.t("widget.preview")) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 22) {
                    SectionHeading(title: L.t("widget.quick"))
                    Label(L.t("weight.log"), systemImage: "plus.circle.fill").font(.caption.weight(.semibold))
                }.padding(13).background(Theme.blush, in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        SectionHeading(title: L.t("widget.trend"))
                        Spacer()
                        Text(L.t("widget.recent")).font(.caption).foregroundStyle(Theme.muted)
                    }
                    let recent = Trend.normalized(model.records.weights, in: model.today.add(-6)...model.today, manualOnly: false)
                    let sample = [0.6, 0.8, 0.7, 0.55, 0.63, 0.48, 0.39].enumerated().map {
                        ShapePoint(x: Double($0.offset) / 6, y: $0.element, connects: $0.offset > 0)
                    }
                    Sparkline(points: model.hasPro && !recent.isEmpty ? recent : sample).frame(height: 52)
                }.card()
            }.card()
            VStack(alignment: .leading, spacing: 8) {
                IconRow(icon: "lock.shield.fill", tone: .amber) {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeading(title: L.t("widget.private"))
                        Text(L.t("widget.privacy")).font(.subheadline).foregroundStyle(Theme.muted)
                    }
                }
                Divider().padding(.leading, 49)
                IconRow(icon: "square.grid.2x2", tone: .blue) {
                    Text(L.t("widget.steps")).font(.subheadline)
                }
            }.card()
            if !model.hasPro {
                ActionButton("paywall.title", id: "widget.pro", kind: .primary, icon: "star.fill", action: paywall)
            }
        }
    }
}
