import Foundation

struct Entitlement: Codable, Equatable {
    var firstOpen: Date
    var proStartedAt: Date?
    var trialClaimedAt: Date?
    var purchasedPro = false

    var trialStart: Date {
        let localStart = proStartedAt ?? firstOpen
        return min(localStart, trialClaimedAt ?? localStart)
    }
    var trialEnd: Date { trialStart.addingTimeInterval(30 * 86_400) }
    func hasPro(at now: Date, free: Bool = Launch.freePeriod) -> Bool {
        free || purchasedPro || (trialClaimedAt != nil && now >= trialStart && now < trialEnd)
    }
}
