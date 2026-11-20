import SwiftUI
import UIKit
import Supabase

/// Permiso para usar IA de terceros (Claude, de Anthropic). Apple pide
/// avisar con quien se comparten los datos y pedir permiso explicito antes
/// de mandarlos a una IA externa (App Review 5.1.1 / 5.1.2).
///
/// - La primera vez que la persona usa una funcion con IA (preguntar,
///   generar analisis, nota por voz que no se entiende en el telefono) se
///   muestra `AIConsentSheet` encima de lo que este abierto.
/// - La decision se guarda en `user_consents` (proposito 'ia'). El
///   servidor tambien lo revisa: sin permiso vigente no llama a Claude.
/// - Se puede cambiar en Ajustes > Privacidad.
@MainActor
final class AIConsentCenter {
    static let shared = AIConsentCenter()
    private init() {}

    private var cache: [UUID: Bool] = [:]
    private var waiters: [CheckedContinuation<Bool, Never>] = []
    private weak var presented: UIViewController?

    /// Lo llama el interruptor de Ajustes al cambiar la decision.
    func setCached(_ granted: Bool, userId: UUID) {
        cache[userId] = granted
    }

    private func currentUserId() async -> UUID? {
        try? await SupabaseManager.shared.client.auth.session.user.id
    }

    /// true si ya hay permiso vigente (no pregunta nada).
    func hasConsent() async -> Bool {
        guard let userId = await currentUserId() else { return false }
        if let cached = cache[userId] { return cached }
        guard let decision = try? await ConsentRepository.shared.current(userId: userId, purpose: .ia) else {
            return false
        }
        cache[userId] = decision.granted
        return decision.granted
    }

    /// Devuelve true si hay permiso; si no, lo pide y espera la respuesta.
    func requestIfNeeded() async -> Bool {
        if await hasConsent() { return true }
        guard let userId = await currentUserId() else { return false }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
            if presented == nil { present(userId: userId) }
        }
    }

    private func present(userId: UUID) {
        guard let top = Self.topViewController() else {
            finish(false)
            return
        }
        let sheet = AIConsentSheet(
            onAllow: { [weak self] in
                guard let self else { return false }
                do {
                    try await ConsentRepository.shared.record(userId: userId, purpose: .ia, granted: true)
                    self.cache[userId] = true
                    self.close(granted: true)
                    return true
                } catch {
                    return false
                }
            },
            onDecline: { [weak self] in
                self?.close(granted: false)
            }
        )
        let host = UIHostingController(rootView: sheet)
        host.modalPresentationStyle = .pageSheet
        host.isModalInPresentation = true
        if let controller = host.sheetPresentationController {
            controller.detents = [.large()]
            controller.prefersGrabberVisible = false
        }
        presented = host
        top.present(host, animated: true)
    }

    private func close(granted: Bool) {
        let host = presented
        presented = nil
        host?.dismiss(animated: true)
        finish(granted)
    }

    private func finish(_ granted: Bool) {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume(returning: granted) }
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        var top = window?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed {
            top = next
        }
        return top
    }

    /// Mensaje cuando la persona elige "Ahora no".
    static let declinedMessage = "Para usar esta función necesitas permitir el uso de IA. Puedes activarlo en Ajustes > Privacidad."
}

/// Pantalla de permiso de IA (una sola vez).
struct AIConsentSheet: View {
    let onAllow: @MainActor () async -> Bool
    let onDecline: @MainActor () -> Void

    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "sparkles")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(MonAviBrand.primary)
                    .padding(.top, 8)

                Text("Funciones con IA")
                    .font(.system(.title2, design: MonAviBrand.fontDesign, weight: .bold))

                Text("Para responder tus preguntas, preparar tu análisis y entender tus notas por voz, MonAvi usa **Claude**, la inteligencia artificial de **Anthropic**.")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                item(
                    icon: "arrow.up.doc.fill",
                    title: "Qué se envía",
                    text: "Solo lo necesario para responder: tu perfil (nombre, edad, ocupación y metas), tus cuentas, movimientos, presupuestos, deudas y cuentas por pagar, y lo que escribes o dices. Nunca tu correo ni tu contraseña."
                )
                item(
                    icon: "lock.shield.fill",
                    title: "Cómo se usa",
                    text: "Anthropic procesa los datos para generar la respuesta y no los usa para entrenar sus modelos."
                )
                item(
                    icon: "hand.raised.fill",
                    title: "Tú decides",
                    text: "Sin tu permiso no se envía nada. Lo puedes cambiar cuando quieras en Ajustes > Privacidad. El resto de la app funciona igual."
                )

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                VStack(spacing: 10) {
                    Button {
                        Task {
                            isSaving = true
                            errorMessage = nil
                            let ok = await onAllow()
                            isSaving = false
                            if !ok { errorMessage = "No se pudo guardar. Revisa tu conexión e intenta de nuevo." }
                        }
                    } label: {
                        Text("Permitir")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MonAviBrand.primary)
                    .controlSize(.large)

                    Button {
                        onDecline()
                    } label: {
                        Text("Ahora no")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .disabled(isSaving)
                .padding(.top, 6)

                Link("Ver política de privacidad", destination: Config.privacyPolicyURL)
                    .font(.footnote)
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
        .overlay {
            if isSaving { ProgressView() }
        }
    }

    private func item(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(MonAviBrand.primary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
