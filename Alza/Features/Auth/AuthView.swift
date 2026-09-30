import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @StateObject private var viewModel = AuthViewModel()
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: 280)
                .scaleEffect(appeared ? 1 : 1.06, anchor: .top)
                .opacity(appeared ? 1 : 0)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Bienvenido")
                            .font(.largeTitle.bold())
                        Text("Inicia sesion para ver como va tu negocio.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    buttons
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 24)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 18)
            }
        }
        .ignoresSafeArea(edges: .top)
        .onAppear {
            withAnimation(.easeOut(duration: 0.55)) {
                appeared = true
            }
        }
    }

    private var header: some View {
        AuthHeaderShape()
            .fill(Color.black)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 12) {
                    Image("AlzaMarkWhite")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Alza")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Tu asesor financiero con IA")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
            }
    }

    private var buttons: some View {
        VStack(spacing: 14) {
            SignInWithAppleButton(.signIn) { request in
                viewModel.prepareAppleRequest(request)
            } onCompletion: { result in
                Task { await viewModel.handleAppleCompletion(result) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Button {
                if let root = PresentationHelper.rootViewController {
                    Task { await viewModel.signInWithGoogle(presenting: root) }
                }
            } label: {
                HStack(spacing: 10) {
                    GoogleGlyph()
                    Text("Continuar con Google")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
            }
            .buttonStyle(SubtleBorderedButtonStyle())

            separator

            emailForm

            if viewModel.isSigningIn {
                ProgressView()
                    .padding(.top, 4)
            }

            if let infoMessage = viewModel.infoMessage {
                Text(infoMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.leading)
            }
        }
        .disabled(viewModel.isSigningIn)
    }

    private var separator: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color(.separator)).frame(height: 1)
            Text("o con tu correo")
                .font(.caption)
                .foregroundStyle(.secondary)
            Rectangle().fill(Color(.separator)).frame(height: 1)
        }
        .padding(.vertical, 4)
    }

    private var emailForm: some View {
        VStack(spacing: 12) {
            TextField("Correo", text: $viewModel.email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))

            SecureField("Contraseña", text: $viewModel.password)
                .textContentType(viewModel.emailAuthMode == .signUp ? .newPassword : .password)
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))

            if viewModel.emailAuthMode == .signUp {
                SecureField("Confirma tu contraseña", text: $viewModel.confirmPassword)
                    .textContentType(.newPassword)
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
            }

            Button {
                Task { await viewModel.submitEmailForm() }
            } label: {
                Text(viewModel.emailAuthMode == .signIn ? "Iniciar sesion" : "Crear cuenta")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(.black)
            .disabled(!viewModel.isEmailFormValid)

            HStack {
                Button {
                    viewModel.emailAuthMode = viewModel.emailAuthMode == .signIn ? .signUp : .signIn
                    viewModel.errorMessage = nil
                    viewModel.infoMessage = nil
                } label: {
                    Text(viewModel.emailAuthMode == .signIn ? "¿No tienes cuenta? Creala" : "¿Ya tienes cuenta? Inicia sesion")
                        .font(.footnote)
                }

                Spacer()

                if viewModel.emailAuthMode == .signIn {
                    Button {
                        Task { await viewModel.sendPasswordReset() }
                    } label: {
                        Text("Olvidaste tu contraseña?")
                            .font(.footnote)
                    }
                }
            }
        }
    }
}

/// "G" simplificada para no depender de un asset con los colores oficiales
/// de Google. TODO(David): si quieres el isotipo oficial, reemplaza esto
/// por un ImageAsset con el logo real de Google.
private struct GoogleGlyph: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 22, height: 22)
                .overlay(Circle().stroke(Color(.separator), lineWidth: 0.5))
            Text("G")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.26, green: 0.52, blue: 0.96),
                            Color(red: 0.85, green: 0.27, blue: 0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
}

private struct SubtleBorderedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(.separator), lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
