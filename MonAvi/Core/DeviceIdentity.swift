import Foundation
import Security

/// Identificador de este iPhone para MonAvi (1.1.0). Vive en el llavero,
/// así sobrevive a borrar y reinstalar la app. Solo se usa para detectar
/// muchas cuentas en el mismo teléfono (revisión de cashback); no
/// identifica a la persona ni se comparte con nadie.
enum DeviceIdentity {
    private static let service = "app.monavi.device-identity"
    private static let account = "device-id"

    static var id: String {
        if let existing = read() { return existing }
        let new = UUID().uuidString
        save(new)
        return new
    }

    private static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func save(_ value: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var attributes = base
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
