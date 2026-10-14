import SwiftUI

struct AddAccountView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: AccountType = .checking
    @State private var balanceText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre (ej. BBVA cheques)", text: $name)

                Picker("Tipo", selection: $type) {
                    ForEach(AccountType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }

                TextField("Balance actual", text: $balanceText)
                    .keyboardType(.decimalPad)

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Nueva cuenta")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }
                        .disabled(name.isEmpty || isSaving)
                }
            }
        }
    }

    private func save() async {
        guard let userId = appState.currentUserId else { return }
        let balance = Decimal(string: balanceText.replacingOccurrences(of: ",", with: ".")) ?? 0
        isSaving = true
        defer { isSaving = false }

        do {
            try await viewModel.addAccount(
                NewAccount(userId: userId, name: name, type: type, balance: balance, currency: "USD")
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
