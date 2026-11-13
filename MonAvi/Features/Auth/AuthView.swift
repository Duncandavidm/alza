import SwiftUI
import UIKit
import AuthenticationServices

struct AuthView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = AuthViewModel()
    @State private var appeared = false
    @State private var showsPasswordReset = false

    var body: some View {
        ZStack {
            form
                .opacity(viewModel.showsSignInOverlay ? 0 : 1)

            if viewModel.showsSignInOverlay {
                BrandLoadingView(message: viewModel.signInOverlayMessage)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: viewModel.showsSignInOverlay)
        .sheet(isPresented: $showsPasswordReset) {
            PasswordResetSheet(initialEmail: viewModel.email) { hold in
                appState.setHoldingAuthScreen(hold)
            }
        }
        .onChange(of: viewModel.showsSignInOverlay) { _, isShowing in
            if isShowing {
                // Que el teclado no se quede encima de la pantalla de carga.
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
            }
        }
    }

    private var form: some View {
        VStack(spacing: 0) {
            header
                .frame(height: 280)
                .scaleEffect(appeared ? 1 : 1.06, anchor: .top)
                .opacity(appeared ? 1 : 0)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Bienvenido")
                            .font(.system(.largeTitle, design: MonAviBrand.fontDesign, weight: .bold))
                        Text(viewModel.emailAuthMode == .signUp
                             ? "Crea tu cuenta en segundos."
                             : "Tus gastos, tu ahorro y tus premios, en un solo lugar.")
                            .font(.system(.subheadline, design: MonAviBrand.fontDesign))
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
            .fill(MonAviBrand.headerGradient)
            .clipped()
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    EmbeddedLogo.monAviMarkWhite
                        .resizable()
                        .scaledToFit()
                        .frame(width: 52, height: 52)

                    Text("Ordena. Ahorra. Avanza.")
                        .font(.system(.subheadline, design: MonAviBrand.fontDesign))
                        .foregroundStyle(MonAviBrand.onDarkSurface.opacity(0.75))
                }
                .padding(.horizontal, 28)
                .padding(.top, 64)
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

            separator

            emailForm

            if viewModel.isSigningIn && !viewModel.showsSignInOverlay {
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
                    .foregroundStyle(MonAviBrand.alert)
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

            RevealablePasswordField(
                title: "Contraseña",
                text: $viewModel.password,
                contentType: viewModel.emailAuthMode == .signUp ? .newPassword : .password
            )

            if viewModel.emailAuthMode == .signUp {
                Text(PasswordPolicy.requirementsText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if viewModel.emailAuthMode == .signUp {
                RevealablePasswordField(
                    title: "Confirma tu contraseña",
                    text: $viewModel.confirmPassword,
                    contentType: .newPassword
                )
            }

            Button {
                Task { await viewModel.submitEmailForm() }
            } label: {
                Text(viewModel.emailAuthMode == .signIn ? "Iniciar sesión" : "Crear cuenta")
                    .font(.system(.headline, design: MonAviBrand.fontDesign))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(MonAviBrand.primary)
            .pressable()
            .disabled(!viewModel.isEmailFormValid)

            HStack {
                Button {
                    viewModel.emailAuthMode = viewModel.emailAuthMode == .signIn ? .signUp : .signIn
                    viewModel.errorMessage = nil
                    viewModel.infoMessage = nil
                } label: {
                    Text(viewModel.emailAuthMode == .signIn ? "¿No tienes cuenta? Créala" : "¿Ya tienes cuenta? Inicia sesión")
                        .font(.footnote)
                }

                Spacer()

                if viewModel.emailAuthMode == .signIn {
                    Button {
                        viewModel.errorMessage = nil
                        viewModel.infoMessage = nil
                        showsPasswordReset = true
                    } label: {
                        Text("¿Olvidaste tu contraseña?")
                            .font(.footnote)
                    }
                }
            }
        }
    }
}

