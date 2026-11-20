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

                    bullet("Guardamos el CUFE (código único), el RUC, la sucursal y la fecha de la factura — no guardamos la foto del recibo.")
                    bullet("Ganas 1% de cashback de cada factura verificada: por una factura de $84.25 recibes $0.84 para canjear en comercios aliados.")
                    bullet("Verificamos tu factura al escanearla: si ya está publicada, tu cashback se suma enseguida. Si todavía no aparece, la revisamos de nuevo en 24 horas y el cashback queda pendiente hasta confirmarla.")
                    bullet("Verificamos cada factura con la información oficial de facturación electrónica de Panamá.")
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
