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
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 12) {
                    Image("AlzaMark")
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

            if viewModel.isSigningIn {
                ProgressView()
                    .padding(.top, 4)
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
