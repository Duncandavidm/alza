import SwiftUI

/// "Facturas que suman": lista de facturas escaneadas + saldo de puntos.
/// El saldo real (Fase 3, libro de movimientos) todavia no existe —
/// mientras tanto se muestra en 0 para no prometer algo que no se puede
/// cumplir todavia.
struct DgiReceiptsListView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = DgiReceiptsViewModel()
    @StateObject private var accountsViewModel = DashboardViewModel()
    @State private var isShowingConsent = false
    @State private var isShowingScanner = false

    var body: some View {
        List {
            Section {
                pointsSummary
            }

            if viewModel.receipts.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "Sin facturas escaneadas",
                    systemImage: "qrcode.viewfinder",
                    description: Text("Escanea el QR de una factura electronica y la registramos como gasto de una vez.")
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
        .alert("Algo salio mal", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var pointsSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Confirmados").font(.caption).foregroundStyle(.secondary)
                    Text("0 pts").font(.title.weight(.bold))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pendientes").font(.caption).foregroundStyle(.secondary)
                    Text("0 pts").font(.title.weight(.bold))
                }
                Spacer()
            }
            if pendingCount > 0 {
                Text("Tienes \(pendingCount) factura\(pendingCount == 1 ? "" : "s") esperando confirmacion de la DGI — los puntos llegan en cuanto se acredite esa parte.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private var pendingCount: Int {
        viewModel.receipts.filter { $0.status == .pendiente }.count
    }

    @ViewBuilder
    private func receiptRow(_ receipt: DgiReceipt) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("RUC \(receipt.ruc)").font(.body)
                Spacer()
                statusBadge(receipt.status)
            }
            Text(receipt.fechaFacturaValue.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(receipt.status.statusExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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
