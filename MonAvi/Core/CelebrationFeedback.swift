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

    /// Canje: vibracion de exito, el "cha-ching" y unos golpecitos como
    /// billetes cayendo, para que se sienta como ganar algo.
    @MainActor
    static func playRedemption() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if chimeSoundID != 0 {
            AudioServicesPlaySystemSound(chimeSoundID)
        }
        let tap = UIImpactFeedbackGenerator(style: .rigid)
        tap.prepare()
        Task { @MainActor in
            for intensity in [0.9, 0.7, 0.5, 0.35] {
                try? await Task.sleep(nanoseconds: 140_000_000)
                tap.impactOccurred(intensity: intensity)
            }
        }
    }

    static func playIncome() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if chimeSoundID != 0 {
            AudioServicesPlaySystemSound(chimeSoundID)
        }
    }
}
