import SwiftUI

struct AddBillView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: BillsViewModel
    let accounts: [Account]
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var amountText = ""
    @State private var dueDate = Date()
    @State private var category: TransactionCategory = .other
    @State private var movementType: MovementType = .gasto
    @State private var priority: BillPriority = .normal
    @State private var selectedAccountId: UUID?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre (ej. Recibo de luz)", text: $name)

                TextField("Monto", text: $amountText)
                    .keyboardType(.decimalPad)

                DatePicker("Vence", selection: $dueDate, displayedComponents: .date)

                Picker("Cuenta", selection: $selectedAccountId) {
                    ForEach(accounts) { account in
                        Text(account.name).tag(Optional(account.id))
                    }
                }

                Picker("Tipo", selection: $movementType) {
                    Text("Gasto").tag(MovementType.gasto)
                    Text("Pago a proveedor").tag(MovementType.pagoProveedor)
                }

                Picker("Categoria", selection: $category) {
                    ForEach(TransactionCategory.allCases) { category in
                        Text("\(category.emoji) \(category.rawValue)").tag(category)
                    }
                }

                Picker("Prioridad", selection: $priority) {
                    ForEach(BillPriority.allCases) { priority in
                        Text(priority.displayName).tag(priority)
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Nueva cuenta por pagar")
            .onAppear { selectedAccountId = selectedAccountId ?? accounts.first?.id }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }
                        .disabled(name.isEmpty || amountText.isEmpty || selectedAccountId == nil || isSaving)
                }
            }
        }
    }

    private func save() async {
        guard
            let userId = appState.currentUserId,
            let accountId = selectedAccountId,
            let amount = Decimal(string: amountText.replacingOccurrences(of: ",", with: "."))
        else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            try await viewModel.add(
                NewBill(
                    userId: userId,
                    accountId: accountId,
                    name: name,
                    amount: amount,
                    dueDate: BillDateFormat.string(from: dueDate),
                    category: category.rawValue,
                    movementType: movementType,
                    priority: priority
                )
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
