import SwiftUI

/// "Facturas que suman": lista de facturas escaneadas. El saldo de
/// puntos (ledger compartido) vive en PointsHubView, no aqui — esta
/// pantalla se enfoca solo en el estado de cada factura.
struct DgiReceiptsListView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = DgiReceiptsViewModel()
    @StateObject private var accountsViewModel = DashboardViewModel()
    @State private var isShowingConsent = false
    @State private var isShowingScanner = false

    var body: some View {
        List {
            if viewModel.receipts.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "Sin facturas escaneadas",
                    systemImage: "qrcode.viewfinder",
                    description: Text("Escanea el QR de una factura electrónica y la registramos como gasto de una vez.")
                )
            } else {
                Section("Tus facturas") {
                    ForEach(viewModel.receipts) { receipt in
                        receiptRow(receipt)
                    }
                    .onDelete { offsets in
                        Task { await delete(at: offsets) }
                    }
                }
            }
        }
        .navigationTitle("Facturas que suman")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    startScan()
                } label: {
                    Image(systemName: "qrcode.viewfinder")
                }
                .accessibilityLabel("Escanear factura")
            }
        }
        .refreshable { await refresh() }
        .task { await refresh() }
        .sheet(isPresented: $isShowingConsent) {
            DgiConsentView(viewModel: viewModel) {
                isShowingScanner = true
            }
        }
        .sheet(isPresented: $isShowingScanner) {
            ScanInvoiceView(viewModel: viewModel, accounts: accountsViewModel.accounts)
        }
        .alert("Algo salió mal", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func receiptRow(_ receipt: DgiReceipt) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(receipt.displayTitle)
                    .font(.body.weight(receipt.hasMerchantName ? .semibold : .regular))
                    .lineLimit(1)
                Spacer()
                statusBadge(receipt.status)
            }
            if receipt.hasMerchantName {
                Text("RUC \(receipt.ruc)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(receiptDateText(receipt))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(receipt.status.statusExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let paymentMethod = receipt.paymentMethod, !paymentMethod.isEmpty {
                Text("Forma de pago (DGI): \(paymentMethod)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    /// Con la hora real de la compra (DGI) si ya la tenemos; si no, solo
    /// la fecha del QR.
    private func receiptDateText(_ receipt: DgiReceipt) -> String {
        if let authorizedAt = receipt.authorizedAt {
            return authorizedAt.formatted(date: .abbreviated, time: .shortened)
        }
        return receipt.fechaFacturaValue.formatted(date: .abbreviated, time: .omitted)
    }

    private func statusBadge(_ status: DgiReceiptStatus) -> some View {
        Text(status.displayName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColor(status).opacity(0.15), in: Capsule())
            .foregroundStyle(statusColor(status))
    }

    private func statusColor(_ status: DgiReceiptStatus) -> Color {
        switch status {
        case .pendiente: return .orange
        case .confirmada: return .green
        case .rechazada: return .red
        case .expirada: return .secondary
        }
    }

    private func startScan() {
        if viewModel.hasConsented == true {
            isShowingScanner = true
        } else {
            isShowingConsent = true
        }
    }

    private func refresh() async {
        guard let userId = appState.currentUserId else { return }
        await viewModel.refresh(userId: userId)
        await accountsViewModel.refresh(userId: userId)
    }

    private func delete(at offsets: IndexSet) async {
        for index in offsets {
            await viewModel.delete(viewModel.receipts[index])
        }
    }
}
