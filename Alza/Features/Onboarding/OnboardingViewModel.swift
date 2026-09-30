import Foundation
import Supabase

/// El "estudio financiero" al entrar por primera vez: junta ingresos fijos
/// y variables, cuentas fijas comunes, suscripciones y otras cuentas fijas,
/// y al terminar crea todo de una vez (cuenta + recurrentes) para que el
/// resto de Alza (consejo de pago, insights) tenga panorama completo desde
/// el primer dia, en vez de que el usuario lo vaya descubriendo solo.
@MainActor
final class OnboardingViewModel: ObservableObject {
    // Paso 1: datos personales
    @Published var fullName = ""

    // Paso 2: cuenta principal
    @Published var accountName = "Cuenta principal"

    // Paso 3: ingreso fijo
    @Published var hasFixedIncome = false
    @Published var fixedIncomeAmountText = ""
    @Published var fixedIncomeDay = 1

    // Paso 4: ingresos variables
    @Published var hasVariableIncome = false
    @Published var variableIncomeNotes = ""

    // Paso 5: cuentas fijas comunes
    @Published var commonBills = CommonBillDraft.defaults()

    // Paso 6: suscripciones
    @Published var subscriptions: [CustomFixedItemDraft] = []

    // Paso 7: otras cuentas fijas
    @Published var otherFixedItems: [CustomFixedItemDraft] = []

    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    private let supabase = SupabaseManager.shared.client

    @discardableResult
    func finish(userId: UUID) async -> Bool {
        isSaving = true
        defer { isSaving = false }

        do {
            let accountsViewModel = DashboardViewModel()
            try await accountsViewModel.addAccount(
                NewAccount(
                    userId: userId,
                    name: accountName.isEmpty ? "Cuenta principal" : accountName,
                    type: .checking,
                    balance: 0,
                    currency: "USD"
                )
            )
            guard let accountId = accountsViewModel.accounts.first?.id else {
                errorMessage = "No se pudo crear tu cuenta principal."
                return false
            }

            let recurringViewModel = RecurringTransactionsViewModel()

            if hasFixedIncome, let amount = Decimal(string: fixedIncomeAmountText.replacingOccurrences(of: ",", with: ".")), amount > 0 {
                try await recurringViewModel.add(
                    NewRecurringTransaction(
                        userId: userId,
                        accountId: accountId,
                        name: "Salario / ingreso fijo",
                        amount: amount,
                        movementType: .ingreso,
                        category: TransactionCategory.income.rawValue,
                        dayOfMonth: fixedIncomeDay
                    )
                )
            }

            for bill in commonBills where bill.isEnabled {
                guard let amount = Decimal(string: bill.amountText.replacingOccurrences(of: ",", with: ".")), amount > 0 else { continue }
                try await recurringViewModel.add(
                    NewRecurringTransaction(
                        userId: userId,
                        accountId: accountId,
                        name: bill.name,
                        amount: amount,
                        movementType: .gasto,
                        category: bill.category.rawValue,
                        dayOfMonth: bill.dayOfMonth
                    )
                )
            }

            for item in subscriptions {
                guard !item.name.isEmpty, let amount = Decimal(string: item.amountText.replacingOccurrences(of: ",", with: ".")), amount > 0 else { continue }
                try await recurringViewModel.add(
                    NewRecurringTransaction(
                        userId: userId,
                        accountId: accountId,
                        name: item.name,
                        amount: amount,
                        movementType: .gasto,
                        category: TransactionCategory.entertainment.rawValue,
                        dayOfMonth: item.dayOfMonth
                    )
                )
            }

            for item in otherFixedItems {
                guard !item.name.isEmpty, let amount = Decimal(string: item.amountText.replacingOccurrences(of: ",", with: ".")), amount > 0 else { continue }
                try await recurringViewModel.add(
                    NewRecurringTransaction(
                        userId: userId,
                        accountId: accountId,
                        name: item.name,
                        amount: amount,
                        movementType: .gasto,
                        category: TransactionCategory.other.rawValue,
                        dayOfMonth: item.dayOfMonth
                    )
                )
            }

            struct ProfileUpdate: Encodable {
                let fullName: String?
                let hasVariableIncome: Bool
                let variableIncomeNotes: String?
                let onboardingCompletedAt: String

                enum CodingKeys: String, CodingKey {
                    case fullName = "full_name"
                    case hasVariableIncome = "has_variable_income"
                    case variableIncomeNotes = "variable_income_notes"
                    case onboardingCompletedAt = "onboarding_completed_at"
                }
            }

            try await supabase
                .from("profiles")
                .update(
                    ProfileUpdate(
                        fullName: fullName.isEmpty ? nil : fullName,
                        hasVariableIncome: hasVariableIncome,
                        variableIncomeNotes: hasVariableIncome && !variableIncomeNotes.isEmpty ? variableIncomeNotes : nil,
                        onboardingCompletedAt: ISO8601DateFormatter().string(from: Date())
                    )
                )
                .eq("id", value: userId)
                .execute()

            return true
        } catch {
            errorMessage = "No se pudo guardar tu informacion: \(error.localizedDescription)"
            return false
        }
    }
}
