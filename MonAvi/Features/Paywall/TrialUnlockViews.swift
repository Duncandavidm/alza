import SwiftUI

/// Durante la prueba gratis los descuentos, bonos y canjes se ven pero en
/// gris: se desbloquean solos cuando empieza el plan pagado (el servidor
/// tambien los bloquea, migracion 0096). Este aviso va arriba de esas
/// pantallas.
struct TrialLockedBanner: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(MonAviBrand.primary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(MonAviBrand.primary.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text("Se desbloquean con tu plan Pro")
                    .font(.subheadline.weight(.semibold))
                Text(TrialUnlockText.bannerDetail(endDate: appState.trialEndDate))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MonAviBrand.primary.opacity(0.08)))
    }
}

extension View {
    /// En gris y sin poder tocarse mientras dure la prueba gratis.
    func trialLocked(_ locked: Bool) -> some View {
        self
            .grayscale(locked ? 1 : 0)
            .opacity(locked ? 0.5 : 1)
            .allowsHitTesting(!locked)
            .accessibilityHint(locked ? "Se desbloquea con tu plan Pro" : "")
    }
}

enum TrialUnlockText {
    static func dayText(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "es_PA")))
    }

    static func bannerDetail(endDate: Date?) -> String {
        if let endDate {
            return "Durante la prueba gratis puedes verlos. El \(dayText(endDate)) empieza tu plan y se activan solos."
        }
        return "Durante la prueba gratis puedes verlos. Cuando empiece tu plan se activan solos."
    }
}

extension AppState {
    /// Ultimo dia de la prueba gratis (cuando empieza a cobrarse el plan).
    var trialEndDate: Date? {
        guard isInFreeTrial, case .active(let expiresAt) = subscriptionStatus else { return nil }
        return expiresAt
    }
}
