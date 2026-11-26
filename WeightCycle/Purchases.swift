import Foundation
import Security
import StoreKit

actor PurchaseDisk {
    private let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.hgsldswk.weightcycle",
        kSecAttrAccount as String: "entitlement-v1"
    ]

    func load() throws -> Entitlement {
        var read = query
        read[kSecMatchLimit as String] = kSecMatchLimitOne
        read[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &result)
        if status == errSecItemNotFound {
            let now = Date()
            let value = Entitlement(firstOpen: now, proStartedAt: Launch.freePeriod ? nil : now)
            try save(value)
            return value
        }
        guard status == errSecSuccess, let data = result as? Data else { throw RecordError.storage }
        var value = try JSONDecoder().decode(Entitlement.self, from: data)
        if !Launch.freePeriod && value.proStartedAt == nil {
            value.proStartedAt = Date()
            try save(value)
        }
        return value
    }

    func save(_ entitlement: Entitlement) throws {
        let data = try JSONEncoder().encode(entitlement)
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var new = query
            new[kSecValueData as String] = data
            new[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(new as CFDictionary, nil) == errSecSuccess else { throw RecordError.storage }
        } else if status != errSecSuccess {
            throw RecordError.storage
        }
    }

    func apply(product: String, original: Date, revoked: Bool) throws -> Entitlement {
        var value = try load()
        if product == Launch.proID {
            value.purchasedPro = !revoked
        } else if revoked {
            value.trialClaimedAt = nil
        } else {
            value.trialClaimedAt = min(value.trialClaimedAt ?? original, original)
        }
        try save(value)
        return value
    }
}
