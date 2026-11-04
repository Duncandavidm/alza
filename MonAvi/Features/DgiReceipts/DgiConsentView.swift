import SwiftUI

/// Se muestra una sola vez, antes del primer escaneo — que datos se
/// guardan y que se verifica contra la DGI, en lenguaje simple.
struct DgiConsentView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: DgiReceiptsViewModel
    @Environment(\.dismiss) private var dismiss
    var onAccepted: () -> Void

    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("📠").font(.system(size: 56))

                    Text("Antes de escanear tu primera factura")
                        .font(.title2.weight(.bold))

                    bullet("Guardamos el CUFE (codigo unico), el RUC, la sucursal y la fecha de la factura — no guardamos la foto del recibo.")
                    bullet("El monto lo escribes tu. Cuando la DGI confirma la factura (puede tardar de 24 a 72 horas, no es al instante), acreditamos los puntos.")
                    bullet("Verificamos cada factura contra la pagina publica de la DGI (dgi-fep.mef.gob.pa) — nunca contra otra fuente.")
                    bullet("Cada factura solo se puede registrar una vez en toda la app, aunque la escanee otra persona.")

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage).foregroundStyle(.red).font(.footnote)
                    }

                    Button {
                        Task { await accept() }
                    } label: {
                        if isSaving {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Entendido, continuar")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
                    .padding(.top, 8)
                }
                .padding(20)
            }
            .navigationTitle("Facturas que suman")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("•").font(.body.weight(.bold))
            Text(text).font(.subheadline)
        }
    }

    private func accept() async {
        guard let userId = appState.currentUserId else { return }
        isSaving = true
        defer { isSaving = false }
        await viewModel.giveConsent(userId: userId)
        if viewModel.hasConsented == true {
            onAccepted()
            dismiss()
        }
    }
}
