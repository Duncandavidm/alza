import UIKit
import AudioToolbox

/// Vibracion + sonido corto cuando entra un pago — para que registrar un
/// ingreso se sienta distinto (una pequeña celebracion) a registrar un
/// gasto. El sonido respeta el switch de silencio del telefono, igual que
/// cualquier otro sonido de UI corto.
enum CelebrationFeedback {
    private static let chimeSoundID: SystemSoundID = {
        var soundID: SystemSoundID = 0
        if let url = Bundle.main.url(forResource: "income-chime", withExtension: "wav") {
            AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
        }
        return soundID
    }()

    static func playIncome() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if chimeSoundID != 0 {
            AudioServicesPlaySystemSound(chimeSoundID)
        }
    }
}
