import SwiftUI

/// "Crea transacciones recurrentes para que nunca olvides nada": gastos e
/// ingresos fijos, con un iconito de repetir, gestionables desde Ajustes.
struct RecurringTransactionsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = RecurringTransactionsViewModel()
    @StateObject private var accountsViewModel = DashboardViewModel()
    @State private var isAdding = false

    var body: some View {
        List {
            if viewModel.items.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "Sin recurrentes todavia",
                    systemImage: "arrow.trianglehead.2.clockwise",
                    description: Text("Agrega tus pagos fijos (renta, suscripciones) y te los recordamos cada mes.")
                )
            }

            ForEach(viewModel.items) { item in
                HStack(spacing: 12) {
                    ZStack(alignment: .bottomTrailing) {
                        Circle()
                            .fill(Color(.secondarySystemBackground))
                            .frame(width: 40, height: 40)
                            .overlay(Text(iconEmoji(for: item)).font(.title3))

                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(Circle().fill(Color.accentColor))
                            .offset(x: 4, y: 4)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.body)
                        Text("\(item.category ?? item.movementType.displayName) · dia \(item.dayOfMonth)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(item.amount, format: .currency(code: "USD"))
                        .font(.body.weight(.semibold))
                }
                .padding(.vertical, 2)
            }
            .onDelete { indexSet in
                Task { await delete(at: indexSet) }
            }
        }
        .navigationTitle("Recurrentes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAdding = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task {
            await refresh()
        }
        .sheet(isPresented: $isAdding) {
            AddRecurringTransactionView(viewModel: viewModel, accounts: accountsViewModel.accounts)
        }
        .alert("Algo salio mal", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func iconEmoji(for item: RecurringTransaction) -> String {
        TransactionCategory(rawValue: item.category ?? "")?.emoji ?? item.movementType.emoji
    }

    private func refresh() async {
        guard let userId = appState.currentUserId else { return }
        await viewModel.refresh(userId: userId)
        await accountsViewModel.refresh(userId: userId)
    }

    private func delete(at indexSet: IndexSet) async {
        for index in indexSet {
            try? await viewModel.delete(viewModel.items[index])
        }
    }
}
