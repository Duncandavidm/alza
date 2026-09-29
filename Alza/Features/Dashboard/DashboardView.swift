import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = DashboardViewModel()
    @State private var isAddingAccount = false
    @State private var isAddingTransaction = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Balance total")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(viewModel.totalBalance, format: .currency(code: "USD"))
                            .font(.system(size: 34, weight: .bold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                }

                Section("Cuentas") {
                    ForEach(viewModel.accounts) { account in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(account.name)
                                Text(account.type.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(account.balance, format: .currency(code: account.currency))
                                .fontWeight(.medium)
                        }
                    }

                    Button {
                        isAddingAccount = true
                    } label: {
                        Label("Agregar cuenta", systemImage: "plus.circle")
                    }
                }

                Section("Movimientos recientes") {
                    if viewModel.recentTransactions.isEmpty {
                        Text("Sin movimientos todavia")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(viewModel.recentTransactions) { transaction in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(transaction.description ?? transaction.category ?? "Movimiento")
                                if let category = transaction.category {
                                    Text(category)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(transaction.amount, format: .currency(code: "USD"))
                                .foregroundStyle(transaction.amount < 0 ? .red : .green)
                        }
                    }

                    Button {
                        isAddingTransaction = true
                    } label: {
                        Label("Agregar movimiento", systemImage: "plus.circle")
                    }
                    .disabled(viewModel.accounts.isEmpty)
                }
            }
            .navigationTitle("Alza")
            .refreshable { await refresh() }
            .task { await refresh() }
            .sheet(isPresented: $isAddingAccount) {
                AddAccountView(viewModel: viewModel)
            }
            .sheet(isPresented: $isAddingTransaction) {
                AddTransactionView(viewModel: viewModel, accounts: viewModel.accounts)
            }
            .alert("Algo salio mal", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.clearError() }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private func refresh() async {
        guard let userId = appState.currentUserId else { return }
        await viewModel.refresh(userId: userId)
    }
}
