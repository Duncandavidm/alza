import SwiftUI
import Supabase

/// Ajustes > Seguridad: activar/desactivar verificacion en 2 pasos.
/// Opcional (el usuario decide activarla), pero una vez activa, el login
/// SIEMPRE pide el codigo — no hay manera de que la app lo salte.
struct SecuritySettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var factors: [Factor] = []
    @State private var isLoading = true
    @State private var showingEnroll = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                if isLoading {
                    ProgressView()
                } else if factors.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Verificación en 2 pasos: desactivada")
                            .font(.subheadline.weight(.medium))
                        Text("Agrega una capa extra: además de tu contraseña (o Apple), te va a pedir un código de una app de autenticación cada vez que inicies sesión.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    Button("Activar verificación en 2 pasos") {
                        showingEnroll = true
                    }
                } else {
                    Label("Verificación en 2 pasos: activada", systemImage: "checkmark.shield.fill")
                        .foregroundStyle(.green)

                    ForEach(factors, id: \.id) { factor in
                        Button(role: .destructive) {
                            Task { await unenroll(factor) }
                        } label: {
                            Text("Desactivar")
                        }
                    }
                }
            } header: {
                Text("Verificación en 2 pasos")
            } footer: {
                Text("Si pierdes acceso a tu app de autenticación y no puedes iniciar sesión, contáctanos para verificar tu identidad y desactivarla.")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(MonAviBrand.alert).font(.footnote)
                }
            }
        }
        .navigationTitle("Seguridad")
        .task { await refresh() }
        .sheet(isPresented: $showingEnroll) {
            MFAEnrollView {
                Task { await refresh() }
            }
        }
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            factors = try await MFAService.listVerifiedFactors()
        } catch {
            errorMessage = "No se pudo cargar el estado de verificación: \(error.localizedDescription)"
        }
    }

    private func unenroll(_ factor: Factor) async {
        do {
            try await MFAService.unenroll(factorId: factor.id)
            await refresh()
        } catch {
            errorMessage = "No se pudo desactivar: \(error.localizedDescription)"
        }
    }
}
