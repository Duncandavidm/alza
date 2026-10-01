import Foundation
import Security
import Supabase

/// Guarda la sesion de Supabase (access/refresh token) en el Keychain de
/// iOS — cifrado por el Secure Enclave del dispositivo — en vez de
/// confiar en el storage por defecto de la libreria. Es el equivalente
/// nativo de "el token de sesion no debe estar en localStorage": en iOS
/// no existe localStorage, pero UserDefaults/plist es su equivalente
/// inseguro (sin cifrar, legible en un backup o con acceso al
/// filesystem de la app), asi que el token NUNCA debe pasar por ahi.
///
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`:
/// - "AfterFirstUnlock": disponible para refresh en background aunque el
///   telefono este bloqueado de nuevo (necesario para que la sesion siga
///   viva sin pedir login cada vez).
/// - "ThisDeviceOnly": excluido de iCloud Keychain / backups de iCloud —
///   el token de este dispositivo nunca viaja a otro dispositivo o a la
///   nube de Apple.
struct KeychainAuthLocalStorage: AuthLocalStorage {
    private let service = "app.alza.supabase.auth"

    func store(key: String, value: Data) throws {
        var query = baseQuery(key: key)
        SecItemDelete(query as CFDictionary)

        query[kSecValueData as String] = value
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainStorageError.unhandled(status)
        }
    }

    func retrieve(key: String) throws -> Data? {
        var query = baseQuery(key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainStorageError.unhandled(status)
        }
    }

    func remove(key: String) throws {
        let status = SecItemDelete(baseQuery(key: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStorageError.unhandled(status)
        }
    }

    private func baseQuery(key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}

enum KeychainStorageError: Error {
    case unhandled(OSStatus)
}
