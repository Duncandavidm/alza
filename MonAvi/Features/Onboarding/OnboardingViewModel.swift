import Foundation
import Supabase

/// El "estudio financiero" al entrar por primera vez: junta ingresos fijos
/// y variables, cuentas fijas comunes, suscripciones y otras cuentas fijas,
/// y al terminar crea todo de una vez (cuenta + recurrentes) para que el
/// resto de MonAvi (consejo de pago, insights) tenga panorama completo desde
/// el primer dia, en vez de que el usuario lo vaya descubriendo solo.
@MainActor
final class OnboardingViewModel: ObservableObject {
    // Paso 1: datos personales
    @Published var fullName = ""

    // Paso 1b: panorama personal (edad, estado civil, dependientes, ocupacion)
    @Published var ageText = ""
    @Published var maritalStatus: MaritalStatus?
    @Published var gender: ProfileGender?
    @Published var dependentsCountText = ""
    @Published var occupation = ""

    // Paso 2: cuenta principal
    @Published var accountName = "Cuenta principal"

    // Paso 3: ingreso fijo
    @Published var hasFixedIncome = false
    @Published var fixedIncomeFrequency: PayFrequency = .monthly
    /// Monto de CADA pago (por mes, por quincena, por semana o por dia).
    @Published var fixedIncomeAmountText = ""
    /// Mensual: el dia de pago. Quincenal: el primer dia.
    @Published var fixedIncomeDay = 15
    /// Quincenal: el segundo dia (28 = fin de mes; el esquema topa en 28).
    @Published var fixedIncomeSecondDay = 28
    /// Semanal: 1 = domingo ... 7 = sabado. Viernes por defecto.
    @Published var fixedIncomeWeekday = 6

    // Paso 4: ingresos variables
    @Published var hasVariableIncome = false
    @Published var variableIncomeNotes = ""

    // Paso 5: cuentas fijas comunes
    @Published var commonBills = CommonBillDraft.defaults()

    // Paso 6: suscripciones
    @Published var subscriptions: [CustomFixedItemDraft] = []

    // Paso 7: otras cuentas fijas
    @Published var otherFixedItems: [CustomFixedItemDraft] = []

    // Paso 8: deudas
    @Published var debts: [DebtDraft] = []

    // Paso 9: ahorros/inversiones actuales
    @Published var hasSavings = false
    @Published var savingsAmountText = ""
    @Published var savingsNote = ""

    // Paso 10: tolerancia al riesgo
    @Published var riskTolerance: RiskTolerance?

    // Paso 11 y 12: metas
    @Published var shortTermGoals: [GoalDraft] = [GoalDraft()]
    @Published var longTermGoals: [GoalDraft] = [GoalDraft()]

    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    private let supabase = SupabaseManager.shared.client

    /// El salario segun la frecuencia elegida. Quincenal = dos recurrentes
    /// mensuales con el monto de cada quincena, para que recordatorios y
    /// plan de pagos (que razonan por "dia del mes") funcionen sin cambios.
    func fixedIncomeRecurrences(userId: UUID, accountId: UUID, amount: Decimal) -> [NewRecurringTransaction] {
        func income(_ name: String, day: Int, frequency: RecurrenceFrequency = .monthly, weekday: Int? = nil) -> NewRecurringTransaction {
            NewRecurringTransaction(
                userId: userId,
                accountId: accountId,
                name: name,
                amount: amount,
                movementType: .ingreso,
                category: TransactionCategory.income.rawValue,
                dayOfMonth: min(max(day, 1), 28),
                frequency: frequency,
                weekday: weekday
            )
        }

        switch fixedIncomeFrequency {
        case .monthly:
            return [income("Salario / ingreso fijo", day: fixedIncomeDay)]
        case .biweekly:
            let days = [fixedIncomeDay, fixedIncomeSecondDay].map { min(max($0, 1), 28) }
            let first = days.min() ?? 15
            let second = days.max() ?? 28
            // Mismo dia dos veces no es quincenal: una sola fila mensual.
            guard first != second else { return [income("Salario / ingreso fijo", day: first)] }
            return [
                income("Salario (1ra quincena)", day: first),
                income("Salario (2da quincena)", day: second),
            ]
        case .weekly:
            return [income("Salario semanal", day: 1, frequency: .weekly, weekday: min(max(fixedIncomeWeekday, 1), 7))]
        case .daily:
            return [income("Ingreso diario", day: 1, frequency: .daily)]
        }
    }

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
                for income in fixedIncomeRecurrences(userId: userId, accountId: accountId, amount: amount) {
                    try await recurringViewModel.add(income)
                }
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

            for debt in debts where !debt.creditor.isEmpty {
                guard let balance = Decimal(string: debt.balanceText.replacingOccurrences(of: ",", with: ".")) else { continue }
                try await supabase
                    .from("debts")
                    .insert(
                        NewDebt(
                            userId: userId,
                            creditor: debt.creditor,
                            balance: balance,
                            creditLimit: nil,
                            interestRateMonthly: Decimal(string: debt.interestRateText.replacingOccurrences(of: ",", with: ".")),
                            minimumPayment: Decimal(string: debt.minimumPaymentText.replacingOccurrences(of: ",", with: ".")),
                            dueDate: nil,
                            isOverdue: debt.isOverdue
                        )
                    )
                    .execute()
            }

            if hasSavings, let savingsAmount = Decimal(string: savingsAmountText.replacingOccurrences(of: ",", with: ".")), savingsAmount > 0 {
                try await accountsViewModel.addAccount(
                    NewAccount(
                        userId: userId,
                        name: savingsNote.isEmpty ? "Ahorro / inversion" : savingsNote,
                        type: .savings,
                        balance: savingsAmount,
                        currency: "USD"
                    )
                )
            }

            let shortTermGoalTexts = shortTermGoals.map { $0.text.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let longTermGoalTexts = longTermGoals.map { $0.text.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

            struct ProfileUpdate: Encodable {
                let fullName: String?
                let hasVariableIncome: Bool
                let variableIncomeNotes: String?
                let age: Int?
                let maritalStatus: String?
                let gender: String?
                let dependentsCount: Int?
                let occupation: String?
                let riskTolerance: String?
                let shortTermGoals: [String]?
                let longTermGoals: [String]?
                let onboardingCompletedAt: String

                enum CodingKeys: String, CodingKey {
                    case fullName = "full_name"
                    case hasVariableIncome = "has_variable_income"
                    case variableIncomeNotes = "variable_income_notes"
                    case age
                    case maritalStatus = "marital_status"
                    case gender
                    case dependentsCount = "dependents_count"
                    case occupation
                    case riskTolerance = "risk_tolerance"
                    case shortTermGoals = "short_term_goals"
                    case longTermGoals = "long_term_goals"
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
                        age: Int(ageText),
                        maritalStatus: maritalStatus?.rawValue,
                        gender: gender?.rawValue,
                        dependentsCount: Int(dependentsCountText),
                        occupation: occupation.isEmpty ? nil : occupation,
                        riskTolerance: riskTolerance?.rawValue,
                        shortTermGoals: shortTermGoalTexts.isEmpty ? nil : shortTermGoalTexts,
                        longTermGoals: longTermGoalTexts.isEmpty ? nil : longTermGoalTexts,
                        onboardingCompletedAt: ISO8601DateFormatter().string(from: Date())
                    )
                )
                .eq("id", value: userId)
                .execute()

            return true
        } catch {
            errorMessage = "No se pudo guardar tu información: \(error.localizedDescription)"
            return false
        }
    }
}
