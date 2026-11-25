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
    /// Pais y moneda (1.0.6): Panama = dolar, Colombia = peso colombiano.
    @Published var country: AppCountry = AppCountry.suggested

    // Paso 1b: panorama personal (edad, estado civil, dependientes, ocupacion)
    @Published var ageText = ""
    @Published var maritalStatus: MaritalStatus?
    @Published var gender: ProfileGender?
    @Published var dependentsCountText = ""
    @Published var occupation = ""

    // Paso 2: cuenta principal
    @Published var accountName = "Cuenta principal"
    /// Cuanto tiene hoy en esa cuenta: la cuenta ya no arranca en $0.
    @Published var accountBalanceText = ""

    // Paso 3: ingreso fijo
    @Published var hasFixedIncome = false
    @Published var fixedIncomeFrequency: PayFrequency = .monthly
    /// Monto de CADA pago (por mes, por quincena, por semana o por dia).
    @Published var fixedIncomeAmountText = ""
    /// Mensual: el dia de pago. Quincenal: el primer dia.
    @Published var fixedIncomeDay = 15
    /// Quincenal: el segundo dia. 30/31 en un mes mas corto = ultimo dia.
    @Published var fixedIncomeSecondDay = 30
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

    /// Presupuestos del mes (opcional): los que tengan monto se crean al terminar.
    @Published var budgets = BudgetDraft.defaults()

    // Paso 9: ahorros/inversiones actuales
    @Published var hasSavings = false
    @Published var savingsAmountText = ""
    @Published var savingsNote = ""
    /// Plazo fijo / ahorro navideño: el dinero se libera en una fecha.
    @Published var savingsLocked = false
    @Published var savingsAvailableOn = SavingsAvailability.suggestedDate()

    // Paso 10: tolerancia al riesgo
    @Published var riskTolerance: RiskTolerance?

    // Paso 11 y 12: metas
    @Published var shortTermGoals: [GoalDraft] = [GoalDraft()]
    @Published var longTermGoals: [GoalDraft] = [GoalDraft()]

    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    private let supabase = SupabaseManager.shared.client

    nonisolated static func amount(_ text: String) -> Decimal? {
        AppCountry.parseAmount(text.replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespaces))
    }

    /// Ingreso fijo llevado a un mes: quincenal x2, semanal x52/12, diario
    /// x22 dias habiles (aprox.).
    var monthlyFixedIncome: Decimal {
        guard hasFixedIncome, let amount = Self.amount(fixedIncomeAmountText), amount > 0 else { return 0 }
        switch fixedIncomeFrequency {
        case .monthly: return amount
        case .biweekly: return fixedIncomeDay == fixedIncomeSecondDay ? amount : amount * 2
        case .weekly: return (amount * 52 / 12).roundedTo(2)
        case .daily: return amount * 22
        }
    }

    var monthlyFixedExpenses: Decimal {
        let bills = commonBills.filter(\.isEnabled).compactMap { Self.amount($0.amountText) }
        let others = (subscriptions + otherFixedItems).filter { !$0.name.isEmpty }.compactMap { Self.amount($0.amountText) }
        return (bills + others).filter { $0 > 0 }.reduce(0, +)
    }

    /// "Tu foto financiera" con todo lo que contesto, para el ultimo paso.
    var snapshot: FinancialSnapshot {
        FinancialSnapshot(
            monthlyIncome: monthlyFixedIncome,
            fixedExpenses: monthlyFixedExpenses,
            debts: debts.filter { !$0.creditor.isEmpty }.compactMap { debt -> FinancialSnapshot.DebtInput? in
                guard let balance = Self.amount(debt.balanceText), balance > 0 else { return nil }
                return FinancialSnapshot.DebtInput(
                    name: debt.creditor,
                    balance: balance,
                    creditLimit: Self.amount(debt.creditLimitText),
                    minimumPayment: Self.amount(debt.minimumPaymentText),
                    monthlyRate: CreditCardMath.monthlyRate(debt.interestRateText, period: debt.interestPeriod),
                    isOverdue: debt.isOverdue
                )
            },
            cash: max(Self.amount(accountBalanceText) ?? 0, 0),
            savings: hasSavings ? max(Self.amount(savingsAmountText) ?? 0, 0) : 0,
            firstGoal: shortTermGoals.map { $0.text.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty },
            hasVariableIncome: hasVariableIncome
        )
    }

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
                dayOfMonth: min(max(day, 1), 31),
                frequency: frequency,
                weekday: weekday
            )
        }

        switch fixedIncomeFrequency {
        case .monthly:
            return [income("Salario / ingreso fijo", day: fixedIncomeDay)]
        case .biweekly:
            let days = [fixedIncomeDay, fixedIncomeSecondDay].map { min(max($0, 1), 31) }
            let first = days.min() ?? 15
            let second = days.max() ?? 30
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
                    balance: Self.amount(accountBalanceText) ?? 0,
                    currency: AppCountry.current.currencyCode
                )
            )
            guard let accountId = accountsViewModel.accounts.first?.id else {
                errorMessage = "No se pudo crear tu cuenta principal."
                return false
            }

            let recurringViewModel = RecurringTransactionsViewModel()

            if hasFixedIncome, let amount = AppCountry.parseAmount(fixedIncomeAmountText), amount > 0 {
                for income in fixedIncomeRecurrences(userId: userId, accountId: accountId, amount: amount) {
                    try await recurringViewModel.add(income)
                }
            }

            for bill in commonBills where bill.isEnabled {
                guard let amount = AppCountry.parseAmount(bill.amountText), amount > 0 else { continue }
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
                guard !item.name.isEmpty, let amount = AppCountry.parseAmount(item.amountText), amount > 0 else { continue }
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
                guard !item.name.isEmpty, let amount = AppCountry.parseAmount(item.amountText), amount > 0 else { continue }
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
                guard let balance = AppCountry.parseAmount(debt.balanceText) else { continue }
                try await supabase
                    .from("debts")
                    .insert(
                        NewDebt(
                            userId: userId,
                            creditor: debt.creditor,
                            balance: balance,
                            creditLimit: Self.amount(debt.creditLimitText).flatMap { $0 > 0 ? $0 : nil },
                            interestRateMonthly: CreditCardMath.monthlyRate(debt.interestRateText, period: debt.interestPeriod),
                            minimumPayment: AppCountry.parseAmount(debt.minimumPaymentText),
                            dueDate: nil,
                            isOverdue: debt.isOverdue,
                            paymentDay: Int(debt.paymentDayText.filter(\.isNumber)).flatMap { (1...31).contains($0) ? $0 : nil }
                        )
                    )
                    .execute()
            }

            if hasSavings, let savingsAmount = AppCountry.parseAmount(savingsAmountText), savingsAmount > 0 {
                try await accountsViewModel.addAccount(
                    NewAccount(
                        userId: userId,
                        name: savingsNote.isEmpty ? "Ahorros" : String(savingsNote.prefix(40)),
                        type: .savings,
                        balance: savingsAmount,
                        currency: AppCountry.current.currencyCode,
                        availableOn: savingsLocked ? SavingsAvailability.string(from: savingsAvailableOn) : nil
                    )
                )
            }

            for budget in budgets {
                guard let limit = Self.amount(budget.limitText), limit > 0 else { continue }
                _ = try? await supabase
                    .from("budgets")
                    .insert(NewBudget(userId: userId, category: budget.category.rawValue, period: .monthly, limitAmount: limit))
                    .execute()
            }

            let shortTermGoalTexts = shortTermGoals.map { $0.text.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let longTermGoalTexts = longTermGoals.map { $0.text.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

            struct ProfileUpdate: Encodable {
                let fullName: String?
                let country: String
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
                    case country
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
                        country: country.rawValue,
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
