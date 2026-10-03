import SwiftUI

struct DebtsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = DebtsViewModel()
    @State private var showingAdd = false

    var body: some View {
        List {
            if !viewModel.debts.isEmpty {
                Section {
                    LabeledContent("Deuda total activa", value: viewModel.totalActiveBalance.formatted(.currency(code: "USD")))
                        .font(.headline)
                }
            }

            if viewModel.debts.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "Sin deudas registradas",
                    systemImage: "creditcard.trianglebadge.exclamationmark",
                    description: Text("Tarjetas de credito, prestamos o sobregiros — registralos para que Amadai los tome en cuenta al aconsejarte que pagar primero.")
                )
            }

            ForEach(viewModel.debts) { debt in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(debt.creditor).font(.headline)
                        Spacer()
                        Text(debt.balance, format: .currency(code: "USD")).font(.headline)
                    }

                    HStack(spacing: 10) {
                        if let rate = debt.interestRateMonthly {
                            Text("Interes: \(rate, format: .number.precision(.fractionLength(1)))%/mes")
                        }
                        if let min = debt.minimumPayment {
                            Text("Minimo: \(min, format: .currency(code: "USD"))")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        if debt.isOverdue {
                            Label("En mora", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                        }
                        Text(debt.status.displayName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .onDelete { offsets in
                for index in offsets {
                    let debt = viewModel.debts[index]
                    Task { await viewModel.delete(debt) }
                }
            }
        }
        .navigationTitle("Deudas")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack { AddDebtView(viewModel: viewModel) }
        }
        .task {
            guard let userId = appState.currentUserId else { return }
            await viewModel.refresh(userId: userId)
        }
        .alert("Algo salio mal", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
