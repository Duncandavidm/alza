import DeviceCheck
import Foundation
import Supabase

/// DeviceCheck de Apple (1.1.0). Una vez al día por cuenta, manda al
/// servidor un token de este iPhone para que lea y marque los dos bits que
/// Apple guarda por dispositivo (sobreviven a borrar el iPhone). Sirve para
/// la revisión de cashback; no identifica a la persona. Si falla o el
/// servidor aún no tiene la clave, no pasa nada.
enum DeviceCheckService {
    private static var client: SupabaseClient { SupabaseManager.shared.client }

    static func checkIfDue(userId: UUID) async {
        guard DCDevice.current.isSupported else { return }
        let key = "monavi.devicecheck.\(userId.uuidString)"
        if let last = UserDefaults.standard.object(forKey: key) as? Date,
           Date().timeIntervalSince(last) < 24 * 60 * 60 {
            return
        }
        do {
            let token = try await DCDevice.current.generateToken()
            struct Body: Encodable {
                let deviceToken: String
                let deviceId: String
                enum CodingKeys: String, CodingKey {
                    case deviceToken = "device_token"
                    case deviceId = "device_id"
                }
            }
            try await client.functions.invoke(
                "device-check",
                options: FunctionInvokeOptions(body: Body(deviceToken: token.base64EncodedString(), deviceId: DeviceIdentity.id))
            )
            UserDefaults.standard.set(Date(), forKey: key)
        } catch {
            // Sin conexión o Apple no disponible: se intenta en el próximo arranque.
        }
    }
}
