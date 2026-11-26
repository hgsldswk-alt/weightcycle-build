import SwiftUI
import UIKit

struct ShareView: View {
    @EnvironmentObject private var model: AppModel
    @State private var datesOpen = false
    @State private var first: Date?
    @State private var last: Date?
    @State private var alternate = false
    @State private var qr: CGImage?
    @State private var share: SharePayload?
    @State private var requested = false
    @State private var snapshot: [Period]?
    let milestone: [Period]?
    let chartWindow: ClosedRange<Day>?
    let paywall: () -> Void

    private var appStoreURL: URL {
        DownloadCode.url(storeID: Bundle.main.object(forInfoDictionaryKey: "APP_STORE_ID") as? String ?? "")
    }
    private var goal: Period? { (snapshot ?? milestone)?.last }
    private var defaultRange: ClosedRange<Day> {
        if let goal, let end = goal.end { return goal.start...end }
        if let chartWindow, model.hasPro || chartWindow.lowerBound > model.today.months(-3) { return chartWindow }
        return Trend.visible(model.records.preferences.range, at: model.today, pro: model.hasPro,
                             earliest: model.records.weights.filter { $0.source == .manual }.map(\.day).min())
    }
    private var selectedRange: ClosedRange<Day> {
        if model.hasPro, first != nil || last != nil {
            let start = first.map { Day($0) } ?? defaultRange.lowerBound
            let end = last.map { Day($0) } ?? defaultRange.upperBound
            if start <= end { return start...end }
        }
        return defaultRange
    }
    private var validDates: Bool {
        let start = first.map { Day($0) } ?? defaultRange.lowerBound
        let end = last.map { Day($0) } ?? defaultRange.upperBound
        return !model.hasPro || start <= end
    }
    private var plotted: [ShapePoint] { Trend.normalized(model.records.weights, in: selectedRange) }
    private var title: String {
        if let goal, let end = goal.end, selectedRange == (goal.start...end), !plotted.isEmpty {
            return L.f("share.cycle", 3)
        }
        let ordered = model.records.periods.filter { !$0.isCorrection && $0.end != nil }.sorted { $0.start < $1.start }
        let matches = ordered.enumerated().filter { _, period in
            guard let end = period.end else { return false }
            return selectedRange.contains(period.start) && selectedRange.contains(end)
                && model.records.weights.contains { $0.source == .manual && (period.start...end).contains($0.day) }
        }
        if matches.count == 1, let match = matches.first { return L.f("share.cycle", match.offset + 1) }
        return L.t("share.trend")
    }
    private var art: ShareArt {
        ShareArt(title: title, points: plotted.isEmpty ? Self.example : plotted, qr: qr,
                 alternate: model.hasPro && alternate)
    }

    var body: some View {
        Page(title: L.t("share.title"), subtitle: L.t("share.subtitle")) {
            VStack(alignment: .leading, spacing: 9) {
                art.aspectRatio(4 / 5, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                    .shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("share.preview")
                if plotted.isEmpty { Text(L.t("share.example")).font(.caption).foregroundStyle(Theme.muted) }
                Text(L.t(appStoreURL == DownloadCode.placeholder ? "share.placeholder" : "share.privacy"))
                    .font(.caption).foregroundStyle(Theme.muted)
                if requested { Text(L.t("notice.share")).accessibilityIdentifier("share.requested") }
            }
            VStack(spacing: 9) {
                ActionButton("share.image", id: "share.image", kind: .primary, icon: "square.and.arrow.up") {
                    makeShare()
                }
                .disabled(qr == nil || !validDates)
                HStack(spacing: 8) {
                    ActionButton("share.style", id: "share.style", icon: "paintpalette") {
                        if model.hasPro { alternate.toggle() } else { paywall() }
                    }
                    ActionButton("share.range", id: "share.range", icon: "calendar") {
                        if model.hasPro { datesOpen.toggle() } else { paywall() }
                    }
                }
            }
            if datesOpen && model.hasPro {
                VStack(alignment: .leading, spacing: 10) {
                    DatePicker(selection: selection($first, defaultRange.lowerBound),
                               in: ...model.today.localDate(), displayedComponents: .date) {
                        IconRow(icon: "calendar.badge.plus", tone: .rose) { Text(L.t("period.start")) }
                    }.accessibilityIdentifier("share.start")
                    Divider().padding(.leading, 49)
                    DatePicker(selection: selection($last, defaultRange.upperBound),
                               in: ...model.today.localDate(), displayedComponents: .date) {
                        IconRow(icon: "calendar.badge.checkmark", tone: .blue) { Text(L.t("period.end")) }
                    }.accessibilityIdentifier("share.end")
                    if !validDates { Text(L.t("error.invalidDates")).font(.caption).foregroundStyle(Theme.link) }
                }.card()
            }
            VStack(spacing: 5) {
                IconRowButton(title: "share.copyTags", id: "share.tags", icon: "number", tone: .blue, accessory: nil) {
                    UIPasteboard.general.string = L.t("share.tags")
                    model.inform("notice.copied")
                }
                Divider().padding(.leading, 49)
                IconRowButton(title: "preset.copy", id: "share.copyPreset", icon: "doc.on.doc", tone: .amber, accessory: nil) {
                    copyPreset(model)
                }
            }.card(12)
        }
        .task {
            let url = appStoreURL
            qr = await Task.detached { DownloadCode.image(for: url) }.value
        }
        .onAppear { if snapshot == nil { snapshot = milestone } }
        .sheet(item: $share) { item in
            ShareController(image: item.image)
                .presentationDetents([.medium, .large])
        }
    }

    private func selection(_ date: Binding<Date?>, _ day: Day) -> Binding<Date> {
        Binding(get: { date.wrappedValue ?? day.localDate() }, set: { date.wrappedValue = $0 })
    }

    @MainActor private func makeShare() {
        let renderer = ImageRenderer(content: art.frame(width: 360, height: 450))
        renderer.scale = 3
        renderer.isOpaque = true
        guard let image = renderer.uiImage else { model.problem = L.t("error.storage"); return }
        if Launch.isTesting { requested = true } else { share = SharePayload(image: image) }
        if let ids = (snapshot ?? milestone)?.map(\.id) {
            Task { await model.acknowledgeMilestone(ids) }
        }
    }

    private static let example = [0.50, 0.62, 0.83, 0.70, 0.51, 0.43, 0.31].enumerated().map { index, height in
        ShapePoint(x: Double(index) / 6, y: height, connects: index > 0)
    }
}

private struct ShareArt: View {
    let title: String
    let points: [ShapePoint]
    let qr: CGImage?
    let alternate: Bool
    private let evergreen = Color(red: 0.23, green: 0.37, blue: 0.30)
    private let paleRose = Color(red: 0.97, green: 0.89, blue: 0.90)
    private let ivory = Color(red: 1, green: 0.98, blue: 0.95)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                Text(title).font(.system(size: 36, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.62).lineLimit(2)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                EmptyIllustration(icon: "chart.xyaxis.line", tone: alternate ? .sage : .rose, size: 82)
                    .environment(\.colorScheme, .light)
            }
            Spacer(minLength: 0)
            Sparkline(points: points, color: alternate ? ivory : evergreen)
                .frame(height: 95)
                .padding(.vertical, 18).padding(.horizontal, 14)
                .background(Color.white.opacity(alternate ? 0.13 : 0.75), in: RoundedRectangle(cornerRadius: 16))
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 12) {
                Text(L.t("share.tags")).font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                if let qr {
                    Image(decorative: qr, scale: 1).interpolation(.none).resizable()
                        .frame(width: 76, height: 76)
                        .padding(5)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .foregroundStyle(alternate ? ivory : Theme.fixedInk)
        .background {
            LinearGradient(colors: alternate ? [evergreen, Color(red: 0.15, green: 0.27, blue: 0.23)] : [paleRose, ivory],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(
                LinearGradient(colors: [Theme.rose, Theme.rose.opacity(0.36), Theme.sage],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 2
            ).allowsHitTesting(false)
        }
    }
}

private struct SharePayload: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct ShareController: UIViewControllerRepresentable {
    let image: UIImage
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
