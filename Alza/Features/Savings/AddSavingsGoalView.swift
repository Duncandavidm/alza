import SwiftUI

private let commonGoalEmojis = ["🎯", "🚗", "🏠", "✈️", "📱", "💻", "🎓", "💍", "🛋️", "📺", "🏖️", "👶"]

/// Mismo formulario para crear y editar — si `existingGoal` no es nil, se
/// precarga y "Guardar" actualiza en vez de insertar. El numero clave que
/// pidio el cliente ("cuanto debo ahorrar al mes") se recalcula en vivo
/// cada vez que cambia el monto o la fecha, antes de guardar nada.
struct AddSavingsGoalView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: SavingsGoalsViewModel
    let accounts: [Account]
    var existingGoal: SavingsGoal?
    @Environment(\.dismiss) private var dismiss

    @State private var emoji = "🎯"
    @State private var name = ""
    @State private var targetAmountText = ""
    @State private var targetDate = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    @State private var selectedAccountId: UUID?
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var targetAmount: Decimal {
        Decimal(string: targetAmountText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    /// Misma cuenta que `SavingsGoal.monthsRemaining`/`monthlyContributionNeeded`
    /// pero calculada aqui en vivo, antes de que exista una meta guardada.
    private var monthsRemaining: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.startOfDay(for: targetDate)
        guard end > start else { return 1 }
        let components = calendar.dateComponents([.month, .day], from: start, to: end)
        let months = components.month ?? 0
        let extraDay = (components.day ?? 0) > 0 ? 1 : 0
        return max(1, months + extraDay)
    }

    private var monthlyContributionNeeded: Decimal {
        let alreadySaved = existingGoal?.currentAmount ?? 0
        let remaining = max(0, targetAmount - alreadySaved)
        guard remaining > 0 else { return 0 }
        return remaining / Decimal(monthsRemaining)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("¿Que estas ahorrando?") {
                    emojiPicker
                    TextField("Nombre (ej. Carro nuevo)", text: $name)
                }

                Section("Meta") {
                    AmountField(placeholder: "Monto objetivo", text: $targetAmountText)
                    DatePicker("Fecha limite", selection: $targetDate, in: Date()..., displayedComponents: .date)
                }

                Section {
                    Picker("Cuenta (opcional)", selection: $selectedAccountId) {
                        Text("Ninguna").tag(UUID?.none)
                        ForEach(accounts) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }
                } footer: {
                    Text("Si eliges una cuenta, cada aporte que registres tambien se anota como movimiento ahi.")
                }

                if targetAmount > 0 {
                    Section("Cuota sugerida") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(monthlyContributionNeeded, format: .currency(code: "USD"))
                                .font(.title2.bold())
                                .foregroundStyle(AlzaBrand.primary)
                            Text("por mes durante \(monthsRemaining) mes\(monthsRemaining == 1 ? "" : "es") para llegar a tiempo.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(AlzaBrand.alert)
                }
            }
            .navigationTitle(existingGoal == nil ? "Nueva meta de ahorro" : "Editar meta")
            .onAppear(perform: loadExistingGoal)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }
                        .disabled(name.isEmpty || targetAmount <= 0 || isSaving)
                }
            }
        }
    }

    private var emojiPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(commonGoalEmojis, id: \.self) { option in
                    Button {
                        emoji = option
                    } label: {
                        Text(option)
                            .font(.title2)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle().fill(
                                    emoji == option ? AlzaBrand.primary.opacity(0.18) : Color(.secondarySystemBackground)
                                )
                            )
                            .overlay(
                                Circle().stroke(AlzaBrand.primary, lineWidth: emoji == option ? 2 : 0)
                            )
                    }
                }
            }
        }
    }

    private func loadExistingGoal() {
        guard let existingGoal, name.isEmpty else { return }
        emoji = existingGoal.emoji
        name = existingGoal.name
        targetAmountText = NSDecimalNumber(decimal: existingGoal.targetAmount).stringValue
        targetDate = existingGoal.targetDateValue
        selectedAccountId = existingGoal.accountId
    }

    private func save() async {
        guard let userId = appState.currentUserId else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            if let existingGoal {
                try await viewModel.update(
                    existingGoal,
                    name: name,
                    emoji: emoji,
                    targetAmount: targetAmount,
                    targetDate: SavingsGoalDateFormat.string(from: targetDate),
                    accountId: selectedAccountId
                )
            } else {
                try await viewModel.add(
                    NewSavingsGoal(
                        userId: userId,
                        name: name,
                        emoji: emoji,
                        targetAmount: targetAmount,
                        targetDate: SavingsGoalDateFormat.string(from: targetDate),
                        accountId: selectedAccountId
                    )
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
