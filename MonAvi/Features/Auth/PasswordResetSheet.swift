import SwiftUI
import UIKit
import Supabase

@MainActor
final class PasswordResetViewModel: ObservableObject {
    enum Step: Equatable {
        /// Escribir el correo y pedir el codigo.
        case email
        /// Codigo de 6 digitos + nueva contraseña.
        case reset
        /// La cuenta tiene verificacion en 2 pasos: antes de guardar la
        /// contraseña hay que subir la sesion a AAL2.
        case twoFactor
        case done
    }

    @Published private(set) var step: Step = .email
    @Published var email: String
    @Published private(set) var sentToEmail = ""
    @Published var code = ""
    @Published var newPassword = ""
    @Published var confirmPassword = ""
    @Published var twoFactorCode = ""
    @Published private(set) var isSending = false
    @Published private(set) var isWorking = false
    @Published private(set) var cooldownRemaining = 0
    /// true despues de verifyOTP: ya hay sesion y el codigo se consumio,
    /// asi que un reintento (p. ej. contraseña rechazada por el servidor)
    /// no lo vuelve a verificar.
    @Published private(set) var codeVerified = false
    @Published var errorMessage: String?

    private var cooldownTask: Task<Void, Never>?
    private let supabase = SupabaseManager.shared.client

    init(initialEmail: String) {
        email = PasswordResetLogic.trimmedEmail(initialEmail)
    }

    var codeSentMessage: String { PasswordResetLogic.codeSentMessage(email: sentToEmail) }
    var resendTitle: String { EmailVerificationLogic.resendTitle(remainingSeconds: cooldownRemaining) }
    var canSendFirstCode: Bool { PasswordResetLogic.isPlausibleEmail(email) && !isSending }
    var canResend: Bool {
        step == .reset && !codeVerified && cooldownRemaining == 0 && !isSending && !isWorking
    }
    var canSubmit: Bool {
        !isWorking && PasswordResetLogic.canSubmit(
            code: code,
            codeAlreadyVerified: codeVerified,
            password: newPassword,
            confirmation: confirmPassword
        )
    }

    /// Ayuda en vivo bajo los campos de contraseña: solo cuando ya
    /// escribio algo.
    var passwordHint: String? {
        guard !newPassword.isEmpty else { return nil }
        if !PasswordPolicy.isValid(newPassword) {
            return PasswordPolicy.failureReason(for: newPassword)
        }
        if !confirmPassword.isEmpty && newPassword != confirmPassword {
            return PasswordResetLogic.mismatchMessage
        }
        return nil
    }

    // MARK: - Enviar codigo

    /// Paso 1 (y "Reenviar codigo"). Nunca dice si el correo existe: el
    /// paso 2 siempre muestra "Si el correo esta registrado...".
    func sendCode() async {
        let target = step == .email ? PasswordResetLogic.trimmedEmail(email) : sentToEmail
        guard PasswordResetLogic.isPlausibleEmail(target) else {
            errorMessage = "Escribe un correo válido."
            return
        }
        guard !isSending, cooldownRemaining == 0 else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            try await supabase.auth.resetPasswordForEmail(target)
            moveToResetStep(email: target)
        } catch {
            let message = EmailVerificationLogic.sendErrorMessage(
                forErrorText: EmailVerificationLogic.errorText(error)
            )
            // Si Supabase dijo "espera", puede que ya tenga un codigo de
            // hace un momento: pasar al paso 2 igual y arrancar la espera.
            if message.hasPrefix("Ya te enviamos") {
                moveToResetStep(email: target)
            }
            errorMessage = message
        }
    }

    private func moveToResetStep(email target: String) {
        sentToEmail = target
        if step == .email {
            code = ""
            step = .reset
        }
        startCooldown()
    }

    /// "Cambiar correo": volver al paso 1.
    func editEmail() {
        guard !isWorking, !codeVerified else { return }
        stopCooldown()
        cooldownRemaining = 0
        code = ""
        errorMessage = nil
        email = sentToEmail
        step = .email
    }

    /// Se llama en cada cambio del campo del codigo: solo digitos, maximo 6.
    func codeChanged(_ newValue: String) {
        let sanitized = EmailVerificationLogic.sanitizedCode(newValue)
        if sanitized != newValue {
            code = sanitized
            return
        }
        if !sanitized.isEmpty { errorMessage = nil }
    }

    func twoFactorCodeChanged(_ newValue: String) {
        let sanitized = EmailVerificationLogic.sanitizedCode(newValue)
        if sanitized != newValue {
            twoFactorCode = sanitized
            return
        }
        if !sanitized.isEmpty { errorMessage = nil }
        if EmailVerificationLogic.isComplete(sanitized) {
            Task { await verifyTwoFactor() }
        }
    }

    // MARK: - Cambiar contraseña

    func changePassword() async {
        guard !isWorking else { return }
        if !codeVerified && !EmailVerificationLogic.isComplete(code) {
            errorMessage = "Escribe el código de 6 dígitos que te enviamos."
            return
        }
        if let passwordError = PasswordResetLogic.newPasswordError(
            password: newPassword,
            confirmation: confirmPassword
        ) {
            errorMessage = passwordError
            return
        }

        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        if !codeVerified {
            do {
                // Verificar el codigo de recuperacion crea la sesion.
                _ = try await supabase.auth.verifyOTP(
                    email: sentToEmail,
                    token: code,
                    type: .recovery
                )
                codeVerified = true
                stopCooldown()
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                errorMessage = EmailVerificationLogic.verifyErrorMessage(
                    forErrorText: EmailVerificationLogic.errorText(error)
                )
                code = ""
                return
            }
        }

        if await MFAService.isChallengeRequired() {
            step = .twoFactor
            return
        }
        await savePassword()
    }

    private func verifyTwoFactor() async {
        let submitted = EmailVerificationLogic.sanitizedCode(twoFactorCode)
        guard codeVerified, !isWorking, EmailVerificationLogic.isComplete(submitted) else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            guard let factor = try await MFAService.listVerifiedFactors().first else {
                errorMessage = "No encontramos tu verificación en 2 pasos. Inténtalo de nuevo."
                return
            }
            try await MFAService.verify(factorId: factor.id, code: submitted)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = "El código de tu app de autenticación no es correcto. Inténtalo de nuevo."
            twoFactorCode = ""
            return
        }
        await savePassword()
    }

    /// Guarda la nueva contraseña con la sesion que dejo verifyOTP.
    /// Se llama con isWorking ya en true.
    private func savePassword() async {
        do {
            _ = try await supabase.auth.update(user: UserAttributes(password: newPassword))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            errorMessage = nil
            step = .done
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            let text = EmailVerificationLogic.errorText(error)
            errorMessage = PasswordResetLogic.updateErrorMessage(forErrorText: text)
            let lower = text.lowercased()
            if lower.contains("insufficient_aal") || lower.contains("aal2") {
                step = .twoFactor
            } else if step == .twoFactor {
                // Contraseña rechazada (debil, igual a la anterior...):
                // volver a los campos para escribir otra.
                step = .reset
            }
        }
    }

    /// Al cerrar la hoja sin terminar: si el codigo ya se verifico (hay
    /// sesion) pero la contraseña no se cambio, cerrar esa sesion para
    /// que "Cancelar" de verdad no cambie nada.
    func abandonIfIncomplete() async {
        stopCooldown()
        guard codeVerified, step != .done else { return }
        // Solo este dispositivo: no cerrar otras sesiones del usuario.
        try? await supabase.auth.signOut(scope: .local)
    }

    // MARK: - Espera para reenviar

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

    private func stopCooldown() {
        cooldownTask?.cancel()
        cooldownTask = nil
    }
}

/// "¿Olvidaste tu contraseña?": todo dentro de la app con un codigo de 6
/// digitos (plantilla "Reset Password" de Supabase con `{{ .Token }}`),
/// sin links que abran la web ni que consuman los escaneres de correo.
/// Al terminar el usuario queda con sesion iniciada.
struct PasswordResetSheet: View {
    /// true al aparecer, false al cerrar: mientras dure, RootView sigue
    /// mostrando AuthView aunque verifyOTP ya haya creado la sesion, para
    /// que la hoja no desaparezca antes de guardar la contraseña.
    var onHoldAuthScreen: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PasswordResetViewModel
    @State private var isPasswordRevealed = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case email, code, password, confirmation, twoFactor
    }

    init(initialEmail: String, onHoldAuthScreen: @escaping (Bool) -> Void = { _ in }) {
        self.onHoldAuthScreen = onHoldAuthScreen
        _viewModel = StateObject(wrappedValue: PasswordResetViewModel(initialEmail: initialEmail))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch viewModel.step {
                    case .email:
                        emailStep
                    case .reset:
                        resetStep
                    case .twoFactor:
                        twoFactorStep
                    case .done:
                        doneStep
                    }
                }
                .padding(24)
            }
            .navigationTitle("Recuperar contraseña")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel.step != .done {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") { dismiss() }
                            .disabled(viewModel.isWorking)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(viewModel.isWorking || viewModel.step == .done)
        .onAppear {
            onHoldAuthScreen(true)
            if viewModel.step == .email && viewModel.email.isEmpty {
                focusedField = Field.email
            }
        }
        .onDisappear {
            let release = onHoldAuthScreen
            let model = viewModel
            Task {
                await model.abandonIfIncomplete()
                release(false)
            }
        }
        .onChange(of: viewModel.code) { _, newValue in
            viewModel.codeChanged(newValue)
        }
        .onChange(of: viewModel.twoFactorCode) { _, newValue in
            viewModel.twoFactorCodeChanged(newValue)
        }
        .onChange(of: viewModel.step) { _, step in
            switch step {
            case .reset: focusedField = .code
            case .twoFactor: focusedField = .twoFactor
            case .email: focusedField = .email
            case .done: focusedField = nil
            }
        }
        .task(id: viewModel.step) {
            guard viewModel.step == .done else { return }
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            dismiss()
        }
    }

    // MARK: - Paso 1: correo

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            header(
                icon: "key.fill",
                title: "¿Olvidaste tu contraseña?",
                subtitle: "Escribe tu correo y te enviaremos un código de 6 dígitos para crear una nueva."
            )

            TextField("Correo", text: $viewModel.email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .focused($focusedField, equals: .email)
                .onSubmit { Task { await viewModel.sendCode() } }
                .modifier(AuthFieldStyle())

            errorText

            primaryButton(
                title: "Enviar código",
                isLoading: viewModel.isSending,
                isEnabled: viewModel.canSendFirstCode
            ) {
                Task { await viewModel.sendCode() }
            }
        }
    }

    // MARK: - Paso 2: codigo + nueva contraseña

    private var resetStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            header(
                icon: "envelope.badge.fill",
                title: "Revisa tu correo",
                subtitle: viewModel.codeSentMessage
            )

            if !viewModel.codeVerified {
                VStack(alignment: .leading, spacing: 10) {
                    codeField(text: $viewModel.code, field: .code, label: "Código de 6 dígitos")

                    HStack {
                        Button {
                            Task { await viewModel.sendCode() }
                        } label: {
                            Text(viewModel.resendTitle)
                                .font(.system(.footnote, design: MonAviBrand.fontDesign, weight: .semibold))
                                .monospacedDigit()
                        }
                        .disabled(!viewModel.canResend)

                        Spacer()

                        Button("Cambiar correo") { viewModel.editEmail() }
                            .font(.footnote)
                            .disabled(viewModel.isWorking)
                    }

                    Text("Revisa también la carpeta de spam o promociones.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Nueva contraseña")
                    .font(.system(.headline, design: MonAviBrand.fontDesign))

                PasswordInputField(
                    title: "Nueva contraseña",
                    text: $viewModel.newPassword,
                    isRevealed: isPasswordRevealed
                )
                .focused($focusedField, equals: .password)
                .submitLabel(.next)
                .onSubmit { focusedField = .confirmation }

                PasswordInputField(
                    title: "Confirma la contraseña",
                    text: $viewModel.confirmPassword,
                    isRevealed: isPasswordRevealed
                )
                .focused($focusedField, equals: .confirmation)
                .submitLabel(.done)
                .onSubmit {
                    if viewModel.canSubmit { Task { await viewModel.changePassword() } }
                }

                HStack(alignment: .top) {
                    Text(viewModel.passwordHint ?? PasswordPolicy.requirementsText)
                        .font(.caption)
                        .foregroundStyle(viewModel.passwordHint == nil ? Color.secondary : MonAviBrand.alert)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    Button {
                        isPasswordRevealed.toggle()
                    } label: {
                        Image(systemName: isPasswordRevealed ? "eye.slash" : "eye")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(isPasswordRevealed ? "Ocultar contraseña" : "Mostrar contraseña")
                }
            }

            errorText

            primaryButton(
                title: "Cambiar contraseña",
                isLoading: viewModel.isWorking,
                isEnabled: viewModel.canSubmit
            ) {
                Task { await viewModel.changePassword() }
            }
        }
    }

    // MARK: - Paso extra: verificacion en 2 pasos

    private var twoFactorStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            header(
                icon: "lock.shield.fill",
                title: "Verificación en 2 pasos",
                subtitle: "Para cambiar la contraseña, escribe el código de 6 dígitos de tu app de autenticación."
            )

            codeField(text: $viewModel.twoFactorCode, field: .twoFactor, label: "Código de tu app de autenticación")

            if viewModel.isWorking {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Verificando…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            errorText
        }
    }

    // MARK: - Listo

    private var doneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(MonAviBrand.primary)
                .accessibilityHidden(true)
            Text("¡Listo! Tu contraseña se cambió.")
                .font(.system(.title3, design: MonAviBrand.fontDesign, weight: .bold))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Piezas

    private func header(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(MonAviBrand.primary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(.title2, design: MonAviBrand.fontDesign, weight: .bold))
                Text(subtitle)
                    .font(.system(.subheadline, design: MonAviBrand.fontDesign))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var errorText: some View {
        if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(MonAviBrand.alert)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func codeField(text: Binding<String>, field: Field, label: String) -> some View {
        TextField("000000", text: text)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .font(.system(size: 34, weight: .semibold, design: .monospaced))
            .multilineTextAlignment(.center)
            .focused($focusedField, equals: field)
            .disabled(viewModel.isWorking)
            .frame(height: 64)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
            .accessibilityLabel(label)
    }

    private func primaryButton(
        title: String,
        isLoading: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(.system(.headline, design: MonAviBrand.fontDesign))
                    .opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .buttonStyle(.borderedProminent)
        .tint(MonAviBrand.primary)
        .pressable()
        .disabled(!isEnabled || isLoading)
    }
}

/// Campo de contraseña con opcion de mostrarla.
private struct PasswordInputField: View {
    let title: String
    @Binding var text: String
    let isRevealed: Bool

    var body: some View {
        Group {
            if isRevealed {
                TextField(title, text: $text)
            } else {
                SecureField(title, text: $text)
            }
        }
        .textContentType(.newPassword)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .modifier(AuthFieldStyle())
    }
}

private struct AuthFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }
}
