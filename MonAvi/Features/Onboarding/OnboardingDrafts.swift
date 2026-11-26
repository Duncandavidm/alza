import Foundation

/// Cuenta fija comun (luz, alquiler, agua...) que el usuario activa y le
/// pone monto/dia si aplica a su caso.
struct CommonBillDraft: Identifiable {
    let id = UUID()
    var name: String
    var category: TransactionCategory
    var isEnabled: Bool = false
    var amountText: String = ""
    var dayOfMonth: Int = 1

    static func defaults() -> [CommonBillDraft] {
        [
            CommonBillDraft(name: "Luz", category: .housing),
            CommonBillDraft(name: "Alquiler / Renta", category: .housing),
            CommonBillDraft(name: "Agua", category: .housing),
            CommonBillDraft(name: "Teléfono", category: .other),
            CommonBillDraft(name: "Internet", category: .other),
        ]
    }
}

/// Item de lista abierta: suscripciones (Netflix, gym...) u otras cuentas
/// fijas (colegio, mesada...) que el usuario agrega el mismo.
struct CustomFixedItemDraft: Identifiable {
    let id = UUID()
    var name: String = ""
    var amountText: String = ""
    var dayOfMonth: Int = 1
}

/// Deuda que el usuario agrega en el paso de deudas (tarjetas de credito,
/// prestamos, sobregiros).
struct DebtDraft: Identifiable {
    let id = UUID()
    var creditor: String = ""
    var balanceText: String = ""
    /// Cupo total, solo para tarjetas de credito: con esto se calcula
    /// cuanto del cupo se esta usando (salud financiera).
    var creditLimitText: String = ""
    /// Dia del mes en que vence el pago ("" = no lo sabe).
    var paymentDayText: String = ""
    var interestRateText: String = ""
    /// La tasa se escribe como la da el banco: al año (lo normal) o al mes.
    var interestPeriod: InterestPeriod = .annual
    var minimumPaymentText: String = ""
    var isOverdue: Bool = false
}

/// Un presupuesto mensual por categoria ("" = sin presupuesto ahi).
struct BudgetDraft: Identifiable {
    let id = UUID()
    /// Nombre de la categoria: se puede cambiar. Si no coincide con una
    /// categoria fija, al guardar se crea como categoria propia.
    var name: String
    var emoji: String
    var limitText: String = ""

    init(category: TransactionCategory) {
        name = category.rawValue
        emoji = category.emoji
    }

    init(customName: String = "", emoji: String = "🏷️") {
        name = customName
        self.emoji = emoji
    }

    var trimmedName: String { String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)) }

    /// La categoria fija con ese nombre, o nil si es propia.
    var builtIn: TransactionCategory? { TransactionCategory(rawValue: trimmedName) }

    /// Las categorias donde mas se suele gastar dia a dia.
    static func defaults() -> [BudgetDraft] {
        [.food, .groceries, .transport, .goingOut, .shopping, .entertainment].map { BudgetDraft(category: $0) }
    }

    /// Categorias fijas de gasto que se pueden agregar al presupuesto.
    static let addable: [TransactionCategory] = [
        .food, .groceries, .transport, .goingOut, .shopping, .entertainment, .housing, .utilities,
        .clothing, .subscriptions, .health, .education, .pets, .gifts, .travel, .other,
    ]
}

/// Una meta de texto libre (corto o largo plazo), ej. "liquidar las
/// tarjetas de credito".
struct GoalDraft: Identifiable {
    let id = UUID()
    var text: String = ""
}

/// "¿Cada cuánto te pagan?" en el paso de ingreso fijo del onboarding.
/// Quincenal se guarda como dos recurrentes mensuales (ver
/// OnboardingViewModel.fixedIncomeRecurrences).
enum PayFrequency: String, CaseIterable, Identifiable {
    case monthly
    case biweekly
    case weekly
    case daily

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .monthly: return "Mensual"
        case .biweekly: return "Quincenal"
        case .weekly: return "Semanal"
        case .daily: return "Diario"
        }
    }

    var amountPlaceholder: String {
        switch self {
        case .monthly: return "¿Cuánto te pagan al mes?"
        case .biweekly: return "¿Cuánto te pagan cada quincena?"
        case .weekly: return "¿Cuánto te pagan cada semana?"
        case .daily: return "¿Cuánto ganas por día, más o menos?"
        }
    }
}
