import SwiftUI
import Supabase

/// Se muestra DESPUES de un login exitoso (Apple/Google/correo) cuando el
/// usuario tiene verificacion en 2 pasos activada — RootView la pone en
/// vez del dashboard hasta que se resuelva. No hay forma de "saltarsela":
/// o completa el codigo, o cierra sesion.
struct MFAChallengeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var code = ""
    @State private var isVerifying = false
    @State private var isSigningOut = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(MonAviBrand.primary)

                VStack(spacing: 6) {
                    Text("Verificación en 2 pasos")
                        .font(.system(.title3, design: MonAviBrand.fontDesign, weight: .bold))
                    Text("Escribe el código de 6 dígitos de tu app de autenticación.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                TextField("Código de 6 dígitos", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .multilineTextAlignment(.center)
                    .font(.title2.monospacedDigit())
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                    .padding(.horizontal, 40)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(MonAviBrand.alert)
                }

                Button {
                    Task { await verify() }
                } label: {
                    if isVerifying {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Verificar").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(MonAviBrand.primary)
                .disabled(code.count != 6 || isVerifying)
                .padding(.horizontal, 40)

                Button(role: .destructive) {
                    Task {
                        isSigningOut = true
                        await appState.signOut()
                        isSigningOut = false
                    }
                } label: {
                    if isSigningOut { ProgressView() } else { Text("Cerrar sesión") }
                }
                .font(.footnote)
                .disabled(isSigningOut)

                Spacer()
                Spacer()
            }
            .padding()
        }
    }

    private func verify() async {
        isVerifying = true
        defer { isVerifying = false }
        errorMessage = nil

        do {
            guard let factor = try await MFAService.listVerifiedFactors().first else {
                errorMessage = "No se encontró tu factor de verificación."
                return
            }
            try await MFAService.verify(factorId: factor.id, code: code)
            await appState.refreshMFAStatus()
        } catch {
            errorMessage = "Código incorrecto o expirado. Intenta de nuevo."
        }
    }
}
