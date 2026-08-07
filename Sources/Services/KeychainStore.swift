import Foundation
import Security

enum KeychainStore {
    private static let service = "com.foodrescuebar.app"

    enum Key: String {
        case accessToken
        case refreshToken
        case selectedLocation
        case userProfile
    }

    static func set(_ value: String, for key: Key) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: Key) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func setCodable<T: Encodable>(_ value: T, for key: Key) {
        guard let data = try? JSONEncoder().encode(value),
              let str = String(data: data, encoding: .utf8) else { return }
        set(str, for: key)
    }

    static func getCodable<T: Decodable>(_ type: T.Type, for key: Key) -> T? {
        guard let str = get(key), let data = str.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func clearSession() {
        delete(.accessToken)
        delete(.refreshToken)
        delete(.userProfile)
        // keep selected location optional — clear for privacy
        delete(.selectedLocation)
    }
}
