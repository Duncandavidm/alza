import SwiftUI
import UIKit

@MainActor
final class EmailVerificationViewModel: ObservableObject {
    @Published private(set) var email: String?
    @Published var code = ""
    @Published private(set) var isSending = false
    @Published private(set) var isVerifying = false
    @Published private(set) var cooldownRemaining = 0
    @Published private(set) var didSendCode = false
    @Published private(set) var didVerify = false
    @Published var errorMessage: String?

    private var hasStarted = false
    private var cooldownTask: Task<Void, Never>?
    private let service = EmailVerificationService.shared

    var explanation: String { EmailVerificationLogic.explanation(email: email) }
    var resendTitle: String { EmailVerificationLogic.resendTitle(remainingSeconds: cooldownRemaining) }
    var canResend: Bool { email != nil && cooldownRemaining == 0 && !isSending && !isVerifying }

    /// Al aparecer: lee el correo de la sesion y manda el primer codigo.
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        email = await service.currentEmail()
        guard email != nil else {
            errorMessage = "No encontramos un correo en tu cuenta. Cierra sesión y vuelve a entrar."
            return
        }
        await sendCode()
    }

    func sendCode() async {
        guard let email, !isSending, cooldownRemaining == 0 else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            try await service.sendCode(to: email)
            didSendCode = true
            startCooldown()
        } catch {
            errorMessage = EmailVerificationLogic.sendErrorMessage(
                forErrorText: EmailVerificationLogic.errorText(error)
            )
            // Si Supabase dijo "espera", igual arrancar la espera para no
            // insistir.
            if errorMessage?.hasPrefix("Ya te enviamos") == true {
                startCooldown()
            }
        }
    }

    /// Se llama en cada cambio del campo: deja solo 6 digitos y envia
    /// solo al completar.
    func codeChanged(_ newValue: String) {
        let sanitized = EmailVerificationLogic.sanitizedCode(newValue)
        if sanitized != newValue {
            // onChange vuelve a llamar con el valor limpio.
            code = sanitized
            return
        }
        if !sanitized.isEmpty { errorMessage = nil }
        if EmailVerificationLogic.isComplete(sanitized) {
            Task { await verify(sanitized) }
        }
    }

    private func verify(_ submitted: String) async {
        guard let email, !isVerifying, !didVerify else { return }
        isVerifying = true
        defer { isVerifying = false }
        do {
            try await service.verify(email: email, code: submitted)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            didVerify = true
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            if error is EmailVerificationError {
                errorMessage = "Tu código se aceptó, pero no pudimos guardar la verificación. Pide un código nuevo e inténtalo otra vez."
            } else {
                errorMessage = EmailVerificationLogic.verifyErrorMessage(
                    forErrorText: EmailVerificationLogic.errorText(error)
                )
            }
            code = ""
        }
    }

    private func startCooldown() {
        cooldownTask?.cancel()
        cooldownRemaining = EmailVerificationLogic.resendCooldownSeconds
        cooldownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                if self.cooldownRemaining <= 1 {
                    self.cooldownRemaining = 0
                    return
                }
                self.cooldownRemaining -= 1
            }
        }
    }

    func stop() {
        cooldownTask?.cancel()
        cooldownTask = nil
    }
}

/// Verificacion del correo con un codigo de 6 digitos, solo antes del
/// primer canje (o desde "Mi perfil"). Manda el codigo al aparecer y lo
/// verifica solo al escribir (o autocompletar) los 6 digitos.
struct EmailVerificationSheet: View {
    /// Se llama despues de verificar, justo antes de cerrar la hoja.
    var onVerified: () -> Void

    init(onVerified: @escaping () -> Void = {}) {
        self.onVerified = onVerified
    }

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = EmailVerificationViewModel()
    @FocusState private var isCodeFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "envelope.badge.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(MonAviBrand.primary)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Confirma tu correo")
                            .font(.system(.title2, design: MonAviBrand.fontDesign, weight: .bold))
                        Text(viewModel.explanation)
                            .font(.system(.subheadline, design: MonAviBrand.fontDesign))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    codeField

                    if viewModel.isVerifying {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Verificando…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else if viewModel.isSending {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Enviando código…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(MonAviBrand.alert)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        Task { await viewModel.sendCode() }
                    } label: {
                        Text(viewModel.resendTitle)
                            .font(.system(.subheadline, design: MonAviBrand.fontDesign, weight: .semibold))
                            .monospacedDigit()
                    }
                    .disabled(!viewModel.canResend)

                    Text("Revisa también la carpeta de spam o promociones.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .navigationTitle("Verificar correo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(viewModel.isVerifying)
        .task {
            isCodeFocused = true
            await viewModel.start()
        }
        .onChange(of: viewModel.code) { _, newValue in
            viewModel.codeChanged(newValue)
        }
        .onChange(of: viewModel.isVerifying) { _, verifying in
            // Tras un codigo incorrecto, el teclado vuelve al campo.
            if !verifying && !viewModel.didVerify { isCodeFocused = true }
        }
        .onChange(of: viewModel.didVerify) { _, verified in
            guard verified else { return }
            viewModel.stop()
            onVerified()
            dismiss()
        }
        .onDisappear { viewModel.stop() }
    }

    private var codeField: some View {
        TextField("000000", text: $viewModel.code)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .font(.system(size: 34, weight: .semibold, design: .monospaced))
            .multilineTextAlignment(.center)
            .focused($isCodeFocused)
            .disabled(viewModel.isVerifying)
            .frame(height: 64)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
            .accessibilityLabel("Código de 6 dígitos")
    }
}
