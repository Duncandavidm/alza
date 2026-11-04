import SwiftUI

/// Consentimiento separado y revocable para "Ahorro verificado" — dice
/// exactamente que se comparte (el periodo, si la meta se cumplio, y el
/// saldo promedio que reporta el banco — nunca movimientos detallados)
/// y con quien (MonAvi y ese banco). El usuario puede revocarlo despues
/// en cualquier momento desde "Mis metas".
struct SponsoredSavingsConsentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    var onEnrolled: () -> Void

    @State private var bankPartners: [BankPartner] = []
    @State private var selectedBankPartnerId: UUID?
    @State private var externalAccountRef = ""
    @State private var hasConsented = false
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let repository = CardPointsRepository.shared

    private var isValid: Bool {
        selectedBankPartnerId != nil
            && !externalAccountRef.trimmingCharacters(in: .whitespaces).isEmpty
            && hasConsented
    }

    var body: some View {
        NavigationStack {
            Form {
                if bankPartners.isEmpty && !isLoading {
                    Section {
                        Text("Todavia no hay ningun banco patrocinador disponible.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Picker("Banco", selection: $selectedBankPartnerId) {
                            ForEach(bankPartners) { partner in
                                Text(partner.name).tag(Optional(partner.id))
                            }
                        }

                        TextField("Identificador que te dio el banco", text: $externalAccountRef)
                            .autocorrectionDisabled()
                    } footer: {
                        Text("Nunca pidas ni escribas tu numero de cuenta real aqui — usa solo el identificador o token que tu banco te entrego para este programa.")
                    }

                    Section {
                        bullet("Cada mes le vamos a decir a este banco: cual es tu meta de ahorro y el periodo.")
                        bullet("El banco nos reporta de vuelta si tu saldo promedio del mes alcanzo la meta — nunca el detalle de tus movimientos.")
                        bullet("Puedes revocar este consentimiento cuando quieras desde \"Mis metas\" — esto detiene futuros reportes, pero no borra el historial.")
                    }

                    Section {
                        Toggle(isOn: $hasConsented) {
                            Text("Autorizo a MonAvi a compartir mi meta de ahorro con este banco y a recibir su reporte mensual de cumplimiento.")
                                .font(.footnote)
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Ahorro verificado")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Inscribirme") { Task { await save() } }
                        .disabled(!isValid || isSaving)
                }
            }
            .task { await loadBankPartners() }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("•").font(.body.weight(.bold))
            Text(text).font(.subheadline)
        }
    }

    private func loadBankPartners() async {
        isLoading = true
        defer { isLoading = false }
        bankPartners = (try? await repository.fetchActiveBankPartners()) ?? []
        selectedBankPartnerId = bankPartners.first?.id
    }

    private func save() async {
        guard let userId = appState.currentUserId, let bankPartnerId = selectedBankPartnerId else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.enroll(
                NewSponsoredSavingsEnrollment(
                    userId: userId,
                    bankPartnerId: bankPartnerId,
                    externalAccountRef: externalAccountRef.trimmingCharacters(in: .whitespaces)
                )
            )
            onEnrolled()
            dismiss()
        } catch {
            errorMessage = "No se pudo inscribir: \(error.localizedDescription)"
        }
    }
}
