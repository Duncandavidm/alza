import SwiftUI

/// Abre "Escanear factura" desde cualquier pantalla (descuentos, codigo de
/// un descuento): primero el permiso de la DGI si aun no lo dio, luego la
/// camara. Mismo flujo que Hoy y "Facturas que suman".
///
/// Uso: `.invoiceScanner(isPresented: $isScanning) { await recargar() }`.
/// `isPresented` es el pedido: se apaga solo en cuanto se atiende.
struct InvoiceScanLauncher: ViewModifier {
    @EnvironmentObject private var appState: AppState
    @Binding var isPresented: Bool
    var onFinished: () async -> Void

    @StateObject private var dgiViewModel = DgiReceiptsViewModel()
    @StateObject private var accountsViewModel = DashboardViewModel()
    @State private var isShowingConsent = false
    @State private var isShowingScanner = false

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, requested in
                guard requested else { return }
                isPresented = false
                Task { await start() }
            }
            .sheet(isPresented: $isShowingConsent) {
                DgiConsentView(viewModel: dgiViewModel) {
                    isShowingScanner = true
                }
            }
            .sheet(isPresented: $isShowingScanner, onDismiss: {
                Task { await onFinished() }
            }) {
                ScanInvoiceView(viewModel: dgiViewModel, accounts: accountsViewModel.accounts)
            }
    }

    private func start() async {
        guard let userId = appState.currentUserId else { return }
        await dgiViewModel.refresh(userId: userId)
        await accountsViewModel.refresh(userId: userId)
        if dgiViewModel.hasConsented == true {
            isShowingScanner = true
        } else {
            isShowingConsent = true
        }
    }
}

extension View {
    func invoiceScanner(isPresented: Binding<Bool>, onFinished: @escaping () async -> Void = {}) -> some View {
        modifier(InvoiceScanLauncher(isPresented: isPresented, onFinished: onFinished))
    }
}
