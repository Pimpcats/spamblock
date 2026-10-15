import Foundation
import Security

/// The GitHub token SpamBlock files reports with.
///
/// In the Keychain rather than the App Group, which every extension can read,
/// and only on this device: never in a backup or synced through iCloud.
/// Available after the first unlock, so it works without the app on screen.
enum SharedListToken {

    private static let item: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "SpamBlock",
        kSecAttrAccount as String: "github-token",
    ]

    static func load() -> String? {
        var query = item
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String) throws {
        delete()
        var added = item
        added[kSecValueData as String] = Data(token.utf8)
        added[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(added as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    static func delete() {
        SecItemDelete(item as CFDictionary)
    }
}
