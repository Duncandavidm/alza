import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = DashboardViewModel()
    @State private var isAddingAccount = false
    @State private var isAddingTransaction = false
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                if let results = viewModel.searchResults {
                    Section("Resultados") {
                        if results.isEmpty {
                            Text("Sin resultados para \"\(searchText)\"")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(results) { transaction in
                            transactionRow(transaction)
                        }
                    }
                } else {
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
                            transactionRow(transaction)
                        }

                        Button {
                            isAddingTransaction = true
                        } label: {
                            Label("Agregar movimiento", systemImage: "plus.circle")
                        }
                        .disabled(viewModel.accounts.isEmpty)
                    }
                }
            }
            .navigationTitle("Cuentas")
            .searchable(text: $searchText, prompt: "Buscar por texto o #etiqueta")
            .onChange(of: searchText) { newValue in
                Task { await search(newValue) }
            }
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

    @ViewBuilder
    private func transactionRow(_ transaction: FinanceTransaction) -> some View {
        HStack(alignment: .top) {
            Text(transaction.movementType.emoji)
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.description ?? transaction.category ?? transaction.movementType.displayName)
                if let category = transaction.category {
                    Text(category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !transaction.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(transaction.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color(.tertiarySystemFill)))
                        }
                    }
                }
            }
            Spacer()
            Text(transaction.amount, format: .currency(code: "USD"))
                .foregroundStyle(transaction.movementType.tintColor)
        }
    }

    private func refresh() async {
        guard let userId = appState.currentUserId else { return }
        await viewModel.refresh(userId: userId)
    }

    private func search(_ query: String) async {
        guard let userId = appState.currentUserId else { return }
        await viewModel.search(userId: userId, query: query)
    }
}
