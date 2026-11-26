import Foundation
import HealthKit

actor HealthReader {
    private let store = HKHealthStore()

    private func type(_ kind: HealthKind) -> HKSampleType {
        switch kind {
        case .weight: return HKObjectType.quantityType(forIdentifier: .bodyMass)!
        case .period: return HKObjectType.categoryType(forIdentifier: .menstrualFlow)!
        }
    }

    func authorize(_ kinds: Set<HealthKind>) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw RecordError.unavailable }
        let types: Set<HKObjectType> = Set(kinds.map { type($0) as HKObjectType })
        try await store.requestAuthorization(toShare: [], read: types)
    }

    func changes(_ kind: HealthKind, since saved: Data?) async throws -> HealthChange {
        guard HKHealthStore.isHealthDataAvailable() else { throw RecordError.unavailable }
        let anchor = try saved.flatMap {
            try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0)
        }
        let zone = TimeZone.current
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(type: type(kind), predicate: nil, anchor: anchor,
                                              limit: HKObjectQueryNoLimit) { _, samples, deleted, next, failure in
                if let failure {
                    continuation.resume(throwing: failure)
                    return
                }
                guard let next else {
                    continuation.resume(throwing: RecordError.unavailable)
                    return
                }
                do {
                    var change = HealthChange(deleted: (deleted ?? []).map(\.uuid),
                                              anchor: try NSKeyedArchiver.archivedData(withRootObject: next, requiringSecureCoding: true))
                    for sample in samples ?? [] {
                        let sampleZone = (sample.metadata?[HKMetadataKeyTimeZone] as? String)
                            .flatMap(TimeZone.init(identifier:)) ?? zone
                        let day = Day(sample.startDate, zone: sampleZone)
                        let source = sample.sourceRevision.source.bundleIdentifier
                        if let weight = sample as? HKQuantitySample {
                            let kg = weight.quantity.doubleValue(for: .gramUnit(with: .kilo))
                            guard WeightEntry.valid(kg) else { continue }
                            change.weights.append(WeightEntry(id: weight.uuid, day: day, date: weight.startDate,
                                                               zoneID: sampleZone.identifier, kg: kg,
                                                               source: .health, sourceID: source))
                        } else if let flow = sample as? HKCategorySample {
                            let starts = (flow.metadata?[HKMetadataKeyMenstrualCycleStart] as? NSNumber)?.boolValue ?? false
                            let end = PeriodSample.lastDay(start: flow.startDate, end: flow.endDate, zone: sampleZone)
                            change.flow.append(PeriodSample(id: flow.uuid, date: flow.startDate, endDate: flow.endDate,
                                                            zoneID: sampleZone.identifier, start: day, end: end,
                                                            sourceID: source, starts: starts,
                                                            hasFlow: flow.value != HKCategoryValueMenstrualFlow.none.rawValue))
                        }
                    }
                    continuation.resume(returning: change)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            store.execute(query)
        }
    }
}
