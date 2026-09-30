import SwiftUI

/// Vincular el numero de WhatsApp del usuario con su cuenta de Alza, para
/// poder anotar gastos por WhatsApp (inspirado en MonAi 1.10: "Escribe al
/// bot de MonAi por WhatsApp, con texto o una nota de voz, y aparece en tu
/// lista como transaccion" — aqui, solo texto por ahora, ver README).
struct WhatsAppLinkView: View {
    @EnvironmentObject private var appState: AppState
    @State private var linkedNumber: String?
    @State private var generatedCode: String?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let supabase = SupabaseManager.shared.client

    var body: some View {
        List {
            if let linkedNumber {
                Section("Vinculado") {
                    LabeledContent("Numero", value: linkedNumber)
                    Button("Desvincular", role: .destructive) {
                        Task { await unlink() }
                    }
                }
            } else {
                Section {
                    Text("Vincula tu WhatsApp para anotar gastos e ingresos escribiendole al bot de Alza, sin abrir la app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let code = generatedCode {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("1. Guarda este numero: \(Config.whatsappBotNumber)")
                            Text("2. Mandale por WhatsApp:")
                            Text("VINCULAR \(code)")
                                .font(.system(.body, design: .monospaced).bold())
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
                        }
                        .font(.subheadline)
                        .padding(.vertical, 4)
                    } else {
                        Button {
                            Task { await generateCode() }
                        } label: {
                            if isLoading {
                                ProgressView()
                            } else {
                                Text("Generar codigo de vinculacion")
                            }
                        }
                        .disabled(isLoading)
                    }
                }
            }
        }
        .navigationTitle("WhatsApp")
        .task { await refresh() }
        .alert("Algo salio mal", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func refresh() async {
        guard let userId = appState.currentUserId else { return }
        struct Profile: Decodable { let whatsappNumber: String?
            enum CodingKeys: String, CodingKey { case whatsappNumber = "whatsapp_number" }
        }
        do {
            let profile: Profile = try await supabase
                .from("profiles")
                .select("whatsapp_number")
                .eq("id", value: userId)
                .single()
                .execute()
                .value
            linkedNumber = profile.whatsappNumber
        } catch {
            // Si no hay profile o falla, se deja como "no vinculado".
        }
    }

    private func generateCode() async {
        guard let userId = appState.currentUserId else { return }
        isLoading = true
        defer { isLoading = false }

        let code = String((0..<6).map { _ in "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".randomElement()! })

        struct NewCode: Encodable {
            let code: String
            let userId: UUID
            enum CodingKeys: String, CodingKey { case code; case userId = "user_id" }
        }

        do {
            try await supabase.from("whatsapp_link_codes").insert(NewCode(code: code, userId: userId)).execute()
            generatedCode = code
        } catch {
            errorMessage = "No se pudo generar el codigo: \(error.localizedDescription)"
        }
    }

    private func unlink() async {
        guard let userId = appState.currentUserId else { return }
        do {
            try await supabase
                .from("profiles")
                .update(["whatsapp_number": String?.none])
                .eq("id", value: userId)
                .execute()
            linkedNumber = nil
            generatedCode = nil
        } catch {
            errorMessage = "No se pudo desvincular: \(error.localizedDescription)"
        }
    }
}
