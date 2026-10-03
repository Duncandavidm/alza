import SwiftUI

/// Cuentas por pagar: facturas/recibos pendientes con fecha de vencimiento.
/// El diferenciador de Amadai se apoya en esta lista para aconsejar que pagar
/// primero cuando entra un ingreso (ver PaymentAdviceView).
struct BillsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = BillsViewModel()
    @StateObject private var accountsViewModel = DashboardViewModel()
    @State private var isAdding = false

    var body: some View {
        List {
            if viewModel.pending.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "Sin cuentas por pagar",
                    systemImage: "tray.full",
                    description: Text("Agrega una factura o recibo pendiente para que Amadai te ayude a priorizar los pagos.")
                )
            }

            ForEach(viewModel.pending) { bill in
                billRow(bill)
            }
            .onDelete { indexSet in
                Task { await delete(at: indexSet) }
            }
        }
        .navigationTitle("Cuentas por pagar")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAdding = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .refreshable { await refresh() }
        .task { await refresh() }
        .sheet(isPresented: $isAdding) {
            AddBillView(viewModel: viewModel, accounts: accountsViewModel.accounts)
        }
        .alert("Algo salio mal", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func billRow(_ bill: Bill) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(bill.name).font(.body)
                HStack(spacing: 6) {
                    Text(bill.dueDateValue.formatted(date: .abbreviated, time: .omitted))
                    if bill.isOverdue {
                        Text("Vencida").foregroundStyle(.red).fontWeight(.semibold)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(bill.amount, format: .currency(code: "USD"))
                    .fontWeight(.medium)
                Text(bill.priority.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color(.tertiarySystemFill)))
            }

            Button {
                Task { await markPaid(bill) }
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private func refresh() async {
        guard let userId = appState.currentUserId else { return }
        await viewModel.refresh(userId: userId)
        await accountsViewModel.refresh(userId: userId)
    }

    private func markPaid(_ bill: Bill) async {
        guard let userId = appState.currentUserId else { return }
        try? await viewModel.markPaid(bill, userId: userId)
    }

    private func delete(at indexSet: IndexSet) async {
        for index in indexSet {
            try? await viewModel.delete(viewModel.pending[index])
        }
    }
}
