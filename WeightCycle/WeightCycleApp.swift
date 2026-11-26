import StoreKit
import SwiftUI

enum Screen: Hashable {
    case weight(Day, UUID?), period(Day, Day?), day(Day), health
    case share(Bool, ClosedRange<Day>?), settings, history, code, widget, paywall
}

@main
@MainActor
struct WeightCycleApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(model.records.preferences.appearance == .system ? nil :
                                      model.records.preferences.appearance == .dark ? .dark : .light)
        }
    }
}

private struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    @State private var path: [Screen] = []
    @State private var pendingLog = false
    @State private var reviewAttempt = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.ready {
                    HomeView(open: open)
                } else {
                    VStack {
                        if model.problem != nil {
                            ActionButton("retry", id: "startup.retry", kind: .primary, icon: "arrow.clockwise") {
                                Task { await model.start() }
                            }.padding(.horizontal, 18)
                        } else { ProgressView() }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.paper)
                }
            }
            .navigationDestination(for: Screen.self, destination: destination)
        }
        .tint(Theme.link)
        .task {
            await model.start()
            guard model.ready else { return }
            if Launch.isTesting && Launch.arguments.contains("-paywall") { open(.paywall) }
            if pendingLog { pendingLog = false; open(.weight(model.today, nil)) }
            await model.foreground()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.foreground() } }
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in model.tick() }
        .onOpenURL { url in
            guard url.scheme == "weightcycle" else { return }
            path.removeAll()
            if url.host == "log" {
                if model.ready { open(.weight(model.today, nil)) } else { pendingLog = true }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let notice = model.notice {
                HStack {
                    Text(notice).accessibilityIdentifier("notice.message")
                    Spacer()
                    if model.canUndo {
                        Button(L.t("undo")) { Task { await model.undo() } }
                            .accessibilityIdentifier("notice.undo")
                            .disabled(model.busy)
                    }
                    Button { model.notice = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel(L.t("dismiss"))
                        .accessibilityIdentifier("notice.dismiss")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.vertical, 8).padding(.horizontal, 18)
                .background(Theme.blush)
            }
        }
        .overlay(alignment: .top) {
            if Launch.isTesting && reviewAttempt {
                Text(L.t("notice.review")).padding(5).background(Theme.surface)
                    .accessibilityIdentifier("review.requested").allowsHitTesting(false)
            }
        }
        .alert(L.t("error.title"), isPresented: Binding(get: { model.problem != nil }, set: { if !$0 { model.problem = nil } })) {
            Button(L.t("ok"), role: .cancel) { model.problem = nil }
        } message: { Text(model.problem ?? "") }
        .task(id: reviewKey) {
            guard path.isEmpty, scenePhase == .active, model.problem == nil, !model.busy, !model.healthBusy,
                  model.reviewCandidate != nil, model.records.weightLogDays.count >= 3,
                  model.records.reviewVersion != model.version else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            if await model.consumeReview(), path.isEmpty, model.problem == nil {
                if Launch.isTesting { reviewAttempt = true } else { requestReview() }
            }
        }
    }

    private var reviewKey: String {
        "\(path.count)-\(scenePhase == .active)-\(model.problem != nil)-\(model.busy)-\(model.healthBusy)-\(model.reviewCandidate?.value ?? 0)"
    }

    private func open(_ screen: Screen) { path.append(screen) }

    @ViewBuilder private func destination(_ screen: Screen) -> some View {
        switch screen {
        case .weight(let day, let id):
            WeightEditor(day: day, editing: model.records.weights.first { $0.id == id })
        case .period(let day, let band):
            PeriodEditor(day: day, bandDay: band)
        case .day(let day):
            DayView(day: day, open: open)
        case .health:
            HealthView()
        case .share(let milestone, let range):
            ShareView(milestone: milestone ? model.milestone : nil, chartWindow: range, paywall: { open(.paywall) })
        case .settings:
            SettingsView(open: open)
        case .history:
            HistoryView { open(.day($0)) }
        case .code:
            PresetView()
        case .widget:
            WidgetGuide(paywall: { open(.paywall) })
        case .paywall:
            PaywallView()
        }
    }
}

struct Page<Content: View, Trailing: View>: View {
    let title: String
    let subtitle: String?
    let trailing: Trailing
    let content: Content

    init(title: String, subtitle: String?, @ViewBuilder trailing: () -> Trailing,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title).font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)
                        if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(Theme.muted) }
                    }
                    Spacer(minLength: 0)
                    trailing
                }
                content
            }
            .frame(maxWidth: 510)
            .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 28)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(Theme.ink)
        .background(Theme.paper.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension Page where Trailing == EmptyView {
    init(title: String, subtitle: String?, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, trailing: { EmptyView() }, content: content)
    }
}

private struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var weightSize: CGFloat = 43
    @State private var chartWindow: ClosedRange<Day>?
    let open: (Screen) -> Void

    var body: some View {
        Page(title: L.t("app.title"), subtitle: nil) {
            Button { open(.settings) } label: {
                IconBadge(icon: "gearshape.fill", tone: .blue, size: 44, circular: true)
            }
            .buttonStyle(DesignButtonStyle())
            .accessibilityLabel(L.t("settings"))
            .accessibilityIdentifier("home.settings")
        } content: {
            VStack(spacing: 12) {
                overview
                PrimaryButton(title: L.t("weight.log"), id: "home.log", icon: "plus.circle.fill") {
                    open(.weight(Day(Date()), nil))
                }
            }
            shortcuts
            VStack(alignment: .leading, spacing: 12) {
                WeightChart(select: { open(.day($0)) }, paywall: { open(.paywall) }, windowChanged: { chartWindow = $0 })
                IconRow(icon: "lightbulb.fill", tone: .amber) {
                    Text(L.t("home.tip")).font(.footnote).foregroundStyle(Theme.muted)
                }
            }
            if let milestone = model.milestone {
                VStack(spacing: 8) {
                    ActionButton("milestone.open", id: "home.milestone", kind: .period, icon: "sparkles") {
                        open(.share(true, nil))
                    }
                    ActionButton("milestone.dismiss", id: "home.milestone.dismiss", icon: "xmark") {
                        Task { await model.acknowledgeMilestone(milestone.map(\.id)) }
                    }
                }
            }
            if !Launch.freePeriod && !model.hasPro {
                ActionButton("paywall.title", id: "home.pro", icon: "star.fill") { open(.paywall) }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var overview: some View {
        let unit = model.records.preferences.unit
        let entry = model.daily.max(by: { $0.key < $1.key })?.value
        let points = Trend.normalized(model.records.weights, in: model.today.add(-6)...model.today, manualOnly: false)
        return HeroCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L.t("home.latest")).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted)
                        if let entry {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text(L.number(unit.display(entry.kg)))
                                    .font(.system(size: weightSize, weight: .bold, design: .rounded))
                                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                                Text(unit.label).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("home.latestValue")
                        } else {
                            Text(L.t("home.empty")).font(.headline)
                        }
                    }
                    Spacer(minLength: 0)
                    if !dynamicTypeSize.isAccessibilitySize {
                        if points.isEmpty {
                            EmptyIllustration(icon: "scalemass.fill", tone: .rose, size: 71)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                Sparkline(points: points, color: Theme.mean).frame(height: 28)
                                Text(L.t("widget.recent")).font(.caption2.weight(.semibold)).foregroundStyle(Theme.mean)
                            }
                            .frame(width: 82)
                            .padding(8)
                            .background(Theme.sageWash, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                Divider().overlay(Theme.rose.opacity(0.18))
                cycleSummary
            }
        }
    }

    private var cycleSummary: some View {
        let estimate = CycleEstimate(starts: model.records.periods.map(\.start), today: model.today)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(L.t("home.period.estimate"), systemImage: "calendar")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.link)
                Spacer(minLength: 0)
                switch estimate {
                case let .upcoming(days, _):
                    Text(L.f(days == 1 ? "home.period.day" : "home.period.days", days))
                        .font(.system(.title3, design: .rounded).bold()).foregroundStyle(Theme.link)
                        .fixedSize(horizontal: true, vertical: false)
                case .needsHistory:
                    Text(L.t("home.period.insufficient")).font(.caption).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.trailing)
                case .passed:
                    Text(L.t("home.period.passed")).font(.caption).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.trailing)
                }
            }
            if case let .upcoming(_, progress) = estimate {
                CycleProgress(fraction: progress)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 9) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                     count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
                IconTile(title: L.t(model.openPeriod == nil ? "period.startToday" : "period.endToday"),
                         id: "home.period", icon: model.openPeriod == nil ? "drop.fill" : "checkmark.circle.fill",
                         tone: .rose) {
                    Task {
                        do { try await model.mark(Day(Date()), end: model.openPeriod != nil) }
                        catch { model.problem = error.localizedDescription }
                    }
                }.disabled(model.busy)
                IconTile(title: L.t("period.dates"), id: "home.dates", icon: "calendar.badge.plus", tone: .amber) {
                    open(.period(model.today, nil))
                }
                IconTile(title: L.t("health.title"), id: "home.health", icon: "heart.fill", tone: .sage) {
                    open(.health)
                }
                IconTile(title: L.t("share.trend"), id: "home.share", icon: "square.and.arrow.up", tone: .blue) {
                    open(.share(false, chartWindow))
                }
            }
            if let period = model.openPeriod {
                StatusPill(title: L.f("period.startedOn", period.start.short), tone: .rose)
            }
        }
    }
}

private enum CycleEstimate {
    case needsHistory, passed, upcoming(days: Int, progress: Double)

    init(starts: [Day], today: Day) {
        let recent = Array(Set(starts.filter { $0 <= today }).sorted().suffix(4))
        guard recent.count >= 3, let latest = recent.last else {
            self = .needsHistory
            return
        }
        let intervals = zip(recent.dropFirst(), recent).map { next, previous in
            next.value - previous.value
        }.sorted()
        let lower = intervals[(intervals.count - 1) / 2]
        let upper = intervals[intervals.count / 2]
        let median = lower + (upper - lower + 1) / 2
        let elapsed = today.value - latest.value
        guard elapsed <= median else {
            self = .passed
            return
        }
        self = .upcoming(days: median - elapsed, progress: Double(elapsed) / Double(median))
    }
}
