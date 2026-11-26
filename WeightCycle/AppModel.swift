import Foundation
import SwiftUI
import StoreKit
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var records = Records()
    @Published private(set) var ready = false
    @Published private(set) var busy = false
    @Published private(set) var healthBusy = false
    @Published private(set) var healthResults: [HealthKind: Int] = [:]
    @Published private(set) var healthFailures: Set<HealthKind> = []
    @Published private(set) var entitlement: Entitlement?
    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var purchaseBusy = false
    @Published private(set) var today = Day(Date())
    @Published var notice: String?
    @Published var problem: String?
    @Published var reviewCandidate: Day?
    @Published private(set) var clock = Date()

    private let disk = RecordDisk()
    private let purchases = PurchaseDisk()
    private let health = HealthReader()
    private var undoChange: (@Sendable (inout Records) throws -> Void)?
    private var expiryTask: Task<Void, Never>?
    private var listener: Task<Void, Never>?
    private var productsLoading = false

    var hasPro: Bool {
        if Launch.isTesting {
            return Launch.arguments.contains("-pro") && !Launch.arguments.contains("-expired")
        }
        return entitlement?.hasPro(at: clock) ?? Launch.freePeriod
    }
    var daily: [Day: WeightEntry] { Trend.daily(records.weights) }
    var openPeriod: Period? { records.periods.first { $0.end == nil } }
    var milestone: [Period]? { Periods.milestone(records) }
    var canUndo: Bool { undoChange != nil }
    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }

    func start() async {
        guard !ready, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            records = try await disk.open()
            ready = true
            tick()
        } catch {
            problem = L.t("error.storage")
            return
        }
        guard !Launch.isTesting, !Launch.freePeriod else { return }
        Task { await loadPurchases() }
        listener = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard let self else { return }
                if case let .verified(transaction) = result {
                    do {
                        try await self.accept(transaction)
                        await transaction.finish()
                    } catch {
                        self.problem = L.t("error.storage")
                    }
                }
            }
        }
    }

    func tick() {
        let wasPro = hasPro
        let oldDay = today
        clock = Date()
        today = Day(clock)
        if oldDay != today || wasPro != hasPro { refreshWidget() }
    }

    func foreground() async {
        tick()
        guard ready, !Launch.isTesting else { return }
        if !records.enabled.isEmpty { await syncHealth(records.enabled) }
        refreshWidget()
    }

    @discardableResult
    func update(_ block: @escaping @Sendable (inout Records) throws -> Void,
                undo: (@Sendable (inout Records) throws -> Void)? = nil,
                message: String? = nil) async throws -> Bool {
        guard ready, !busy else { throw RecordError.storage }
        busy = true
        defer { busy = false }
        records = try await disk.update(block)
        if let message {
            undoChange = undo
            notice = message
        }
        refreshWidget()
        return true
    }

    func undo() async {
        guard let undoChange else { return }
        do {
            try await update(undoChange, message: L.t("notice.undone"))
            reviewCandidate = nil
        } catch { problem = error.localizedDescription }
    }

    func inform(_ key: String) {
        undoChange = nil
        notice = L.t(key)
    }

    func saveWeight(value: Double, unit: WeightUnit, day: Day, zone: TimeZone, editing: WeightEntry?) async throws {
        let kg = unit.kilograms(value)
        guard WeightEntry.valid(kg) else { throw RecordError.invalidWeight }
        let now = Date()
        guard day <= Day(now, zone: zone) else { throw RecordError.invalidDates }
        let old = editing?.source == .health
            ? records.weights.first { $0.original == editing?.id } : editing
        let timestamp = editing?.day == day ? editing!.date : (day == Day(now, zone: zone) ? now : day.localDate(zone: zone))
        let zoneID = editing?.day == day ? editing!.zoneID : zone.identifier
        let source: RecordSource = editing?.source == .health || editing?.source == .correction ? .correction : .manual
        let previousDesignations = source == .correction
            ? records.weights.filter { $0.day == day && $0.source == .correction } : []
        let superseded = Set(previousDesignations.map(\.id) + [old?.id].compactMap { $0 })
        let entry = WeightEntry(id: old?.id ?? UUID(), day: day, date: timestamp, zoneID: zoneID,
                                kg: kg, source: source, sourceID: editing?.sourceID,
                                original: editing?.source == .health ? editing?.id : editing?.original)
        let isNew = editing == nil
        let alreadyRecorded = records.weightLogDays.contains(day)
        try await update({ records in
            records.weights.removeAll { superseded.contains($0.id) }
            records.weights.append(entry)
            if isNew { records.weightLogDays.insert(day) }
        }, undo: { records in
            records.weights.removeAll { $0.id == entry.id }
            records.weights.append(contentsOf: previousDesignations)
            if let old, !previousDesignations.contains(where: { $0.id == old.id }) { records.weights.append(old) }
            if isNew && !alreadyRecorded { records.weightLogDays.remove(day) }
        }, message: L.t("notice.saved"))
        if isNew && !alreadyRecorded { reviewCandidate = day }
    }

    func removeWeightCorrection(_ correction: WeightEntry) async throws {
        guard correction.source == .correction else { return }
        try await update({ $0.weights.removeAll { $0.id == correction.id } },
                         undo: { $0.weights.append(correction) }, message: L.t("notice.saved"))
    }

    func savePeriod(_ period: Period) async throws {
        let old = records.periods.first { $0.id == period.id }
        let today = self.today
        try await update({ try Periods.save(period, in: &$0, today: today) }, undo: { records in
            records.periods.removeAll { $0.id == period.id }
            if let old { records.periods.append(old) }
        }, message: L.t("notice.saved"))
    }

    func mark(_ day: Day, end: Bool) async throws {
        let old = records.periods
        let today = self.today
        try await update({ try Periods.mark(day, end: end, in: &$0, today: today) },
                         undo: { $0.periods = old }, message: L.t("notice.saved"))
    }

    func removeCorrection(_ period: Period) async throws {
        try await update({ $0.periods.removeAll { $0.id == period.id } },
                         undo: { $0.periods.append(period) }, message: L.t("notice.saved"))
    }

    func preferences(_ preferences: Preferences, imported: Bool = false) async throws {
        let previous = records.preferences
        try await update({ $0.preferences = preferences }, undo: { $0.preferences = previous },
                         message: imported ? L.t("notice.preset") : nil)
    }

    func acknowledgeMilestone(_ ids: [UUID]) async {
        do { try await update { $0.notifiedMilestone = ids } }
        catch { problem = error.localizedDescription }
    }

    func consumeReview() async -> Bool {
        let version = self.version
        guard reviewCandidate != nil, records.weightLogDays.count >= 3, records.reviewVersion != version,
              !busy else { return false }
        do {
            try await update { $0.reviewVersion = version }
            reviewCandidate = nil
            return true
        } catch { return false }
    }

    func importCSV(_ url: URL) async {
        guard ready, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            records = try await disk.importCSV(url, today: today)
            undoChange = nil
            notice = L.t("notice.imported")
            refreshWidget()
        } catch { problem = error is RecordError ? error.localizedDescription : L.t("error.invalidFile") }
    }

    func exportCSV() async throws -> Data {
        guard hasPro else { throw RecordError.product }
        return try await disk.exportCSV()
    }

    func authorize(_ kinds: Set<HealthKind>) async {
        guard !healthBusy, !kinds.isEmpty else { return }
        healthBusy = true
        defer { healthBusy = false }
        do {
            if !Launch.isTesting { try await health.authorize(kinds) }
            try await update { $0.enabled.formUnion(kinds) }
            await readHealth(kinds)
        } catch { problem = L.t("error.unavailable") }
    }

    func syncHealth(_ kinds: Set<HealthKind>) async {
        guard !healthBusy, !kinds.isEmpty else { return }
        healthBusy = true
        defer { healthBusy = false }
        await readHealth(kinds)
    }

    private func readHealth(_ kinds: Set<HealthKind>) async {
        for kind in HealthKind.allCases where kinds.contains(kind) {
            do {
                if Launch.isTesting {
                    healthResults[kind] = kind == .weight && Launch.arguments.contains("-demo") ? 12 : 0
                } else {
                    let change = try await health.changes(kind, since: records.anchors[kind])
                    guard records.enabled.contains(kind) else { continue }
                    try await update { $0.apply(change, kind: kind) }
                    healthResults[kind] = kind == .weight
                        ? records.weights.filter { $0.source == .health }.count : records.flow.filter(\.hasFlow).count
                }
                healthFailures.remove(kind)
            } catch { healthFailures.insert(kind) }
        }
    }

    func manageHealth(_ kind: HealthKind, clear: Bool) async throws {
        guard !healthBusy else { return }
        try await update { records in
            records.enabled.remove(kind)
            if clear {
                records.anchors[kind] = nil
                if kind == .weight { records.weights.removeAll { $0.source == .health } }
                else { records.flow.removeAll() }
            }
        }
        healthFailures.remove(kind)
        if clear { healthResults[kind] = 0 }
    }

    func loadProducts() async {
        guard !Launch.isTesting, !Launch.freePeriod, !productsLoading else { return }
        productsLoading = true
        defer { productsLoading = false }
        do {
            let available = try await Product.products(for: [Launch.proID, Launch.trialID])
            products = Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0) })
        } catch {
            if products.isEmpty { products = [:] }
        }
    }

    private func loadPurchases() async {
        do {
            if entitlement == nil { entitlement = try await purchases.load() }
            for await result in StoreKit.Transaction.currentEntitlements {
                if case let .verified(transaction) = result { try await accept(transaction) }
            }
            scheduleExpiry()
        } catch { problem = L.t("error.storage") }
    }

    private func accept(_ transaction: StoreKit.Transaction) async throws {
        guard transaction.productID == Launch.proID || transaction.productID == Launch.trialID else { return }
        entitlement = try await purchases.apply(product: transaction.productID,
                                                 original: transaction.originalPurchaseDate,
                                                 revoked: transaction.revocationDate != nil)
        tick()
        scheduleExpiry()
    }

    func purchase(_ id: String) async {
        guard !purchaseBusy else { return }
        purchaseBusy = true
        defer { purchaseBusy = false }
        do {
            if products[id] == nil { await loadProducts() }
            guard let product = products[id] else { throw RecordError.product }
            switch try await product.purchase() {
            case .success(let result):
                guard case let .verified(transaction) = result else { throw RecordError.verification }
                try await accept(transaction)
                await transaction.finish()
                inform("notice.purchase")
            case .pending: throw RecordError.pending
            case .userCancelled: break
            @unknown default: throw RecordError.product
            }
        } catch { problem = (error as? RecordError)?.localizedDescription ?? L.t("error.product") }
    }

    func restore() async {
        guard !purchaseBusy, !Launch.isTesting else { return }
        purchaseBusy = true
        defer { purchaseBusy = false }
        do {
            try await AppStore.sync()
            var found = false
            for await result in StoreKit.Transaction.currentEntitlements {
                if case let .verified(transaction) = result,
                   [Launch.proID, Launch.trialID].contains(transaction.productID) {
                    try await accept(transaction)
                    found = true
                }
            }
            inform(found ? "notice.restored" : "notice.noPurchase")
        } catch { problem = L.t("error.product") }
    }

    private func scheduleExpiry() {
        expiryTask?.cancel()
        refreshWidget()
        guard let entitlement, !entitlement.purchasedPro, hasPro else { return }
        let seconds = max(0, entitlement.trialEnd.timeIntervalSinceNow)
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.tick()
        }
    }

    private func refreshWidget() {
        guard !Launch.isTesting else { return }
        let enabled = hasPro
        let entitlementEnd = entitlement?.purchasedPro == true || Launch.freePeriod
            ? Date.distantFuture : entitlement?.trialEnd ?? clock
        let calendar = Day.calendar(.current)
        let nextDay = calendar.dateInterval(of: .day, for: clock)?.end ?? clock.addingTimeInterval(6 * 3600)
        let expiry = min(entitlementEnd, nextDay)
        let day = today
        Task {
            do {
                try await disk.widget(pro: enabled, expiry: expiry, day: day)
                WidgetCenter.shared.reloadAllTimelines()
            } catch {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}
