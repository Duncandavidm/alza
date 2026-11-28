import SwiftUI

struct DebtsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = DebtsViewModel()
    @State private var showingAdd = false
    @State private var editingDebt: Debt?
    /// "Agregar cupo" en una tarjeta que no lo tiene.
    @State private var limitDebt: Debt?
    @State private var limitText = ""
    @State private var dayDebt: Debt?
    @State private var dayText = ""
    @State private var paymentRequest: CardPaymentRequest?
    @AppStorage(DebtPayoffStrategy.storageKey) private var payoffStrategy: DebtPayoffStrategy = .avalanche

    var body: some View {
        List {
            if !viewModel.debts.isEmpty {
                Section {
                    LabeledContent("Deuda total activa", value: viewModel.totalActiveBalance.formatted(.appCurrency))
                        .font(.headline)
                }
            }

            if viewModel.debts.count > 1 {
                Section {
                    Picker("Estrategia", selection: $payoffStrategy) {
                        ForEach(DebtPayoffStrategy.allCases) { strategy in
                            Text(strategy.displayName).tag(strategy)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(payoffStrategy.explanation + L(" Solo afecta el orden entre tus deudas en el plan de \"qué pagar primero\" al registrar un ingreso."))
                }
            }

            if viewModel.debts.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "Sin deudas registradas",
                    systemImage: "creditcard.trianglebadge.exclamationmark",
                    description: Text("Tarjetas de crédito, préstamos o sobregiros — regístralos para que MonAvi los tome en cuenta al aconsejarte qué pagar primero.")
                )
            }

            ForEach(viewModel.debts) { debt in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(debt.creditor).font(.headline)
                        Spacer()
                        Text(debt.balance, format: .appCurrency).font(.headline)
                    }

                    if let limit = debt.creditLimit, limit > 0 {
                        CreditUseRow(
                            utilization: NSDecimalNumber(decimal: debt.balance / limit).doubleValue,
                            balance: debt.balance,
                            limit: limit
                        )
                    } else if debt.status != .paidOff {
                        Button {
                            limitText = ""
                            limitDebt = debt
                        } label: {
                            Label("¿Es tarjeta? Agrega su cupo", systemImage: "plus.circle")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.borderless)
                    }

                    HStack(spacing: 10) {
                        if let rate = debt.interestRateMonthly, rate > 0 {
                            Text("Interés: \(CreditCardMath.rateText(monthly: rate))")
                        }
                        if let min = debt.minimumPayment {
                            Text("Mínimo: \(min, format: .appCurrency)")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if debt.status != .paidOff && debt.balance > 0 {
                        HStack(spacing: 14) {
                            Button {
                                paymentRequest = CardPaymentRequest(debtId: debt.id)
                            } label: {
                                Label("Registrar pago", systemImage: "arrow.down.circle")
                            }
                            Button {
                                dayText = debt.paymentDay.map(String.init) ?? ""
                                dayDebt = debt
                            } label: {
                                Label(debt.paymentDay.map { "Vence el día \($0)" } ?? "Poner día de pago", systemImage: "calendar")
                            }
                            Button {
                                editingDebt = debt
                            } label: {
                                Label("Editar", systemImage: "pencil")
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                    }

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
        .alert("Cupo total de \(limitDebt?.creditor ?? "la tarjeta")", isPresented: Binding(get: { limitDebt != nil }, set: { if !$0 { limitDebt = nil } })) {
            TextField("ej. 3000", text: $limitText)
                .keyboardType(.decimalPad)
            Button("Guardar") {
                if let debt = limitDebt, let limit = RecurringAmountParser.parse(limitText) {
                    Task { await viewModel.setCreditLimit(limit, for: debt) }
                }
                limitDebt = nil
            }
            Button("Cancelar", role: .cancel) { limitDebt = nil }
        } message: {
            Text("Con el cupo calculamos cuánto usas de tu tarjeta. Lo ideal es menos del 30%.")
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Agregar deuda")
            }
        }
        .sheet(item: $editingDebt) { debt in
            NavigationStack { AddDebtView(viewModel: viewModel, existing: debt) }
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack { AddDebtView(viewModel: viewModel) }
        }
        .task {
            guard let userId = appState.currentUserId else { return }
            await viewModel.refresh(userId: userId)
        }
        .alert("¿Qué día del mes vence \(dayDebt?.creditor ?? "")?", isPresented: Binding(get: { dayDebt != nil }, set: { if !$0 { dayDebt = nil } })) {
            TextField("ej. 15", text: $dayText)
                .keyboardType(.numberPad)
            Button("Guardar") {
                if let debt = dayDebt, let day = Int(dayText.filter(\.isNumber)), (1...31).contains(day) {
                    Task { await viewModel.setPaymentDay(day, for: debt) }
                }
                dayDebt = nil
            }
            Button("Cancelar", role: .cancel) { dayDebt = nil }
        } message: {
            Text("Te avisamos 3 días antes y el mismo día para registrar el pago y de qué cuenta salió.")
        }
        .sheet(item: $paymentRequest, onDismiss: {
            Task {
                guard let userId = appState.currentUserId else { return }
                await viewModel.refresh(userId: userId)
            }
        }) { request in
            QuickDebtPaymentView(preselectedDebtId: request.debtId)
        }
        .alert("Algo salió mal", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
