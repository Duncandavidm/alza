import Foundation

/// Cuenta fija comun (luz, alquiler, agua...) que el usuario activa y le
/// pone monto/dia si aplica a su caso.
struct CommonBillDraft: Identifiable {
    let id = UUID()
    let name: String
    let category: TransactionCategory
    var isEnabled: Bool = false
    var amountText: String = ""
    var dayOfMonth: Int = 1

    static func defaults() -> [CommonBillDraft] {
        [
            CommonBillDraft(name: "Luz", category: .housing),
            CommonBillDraft(name: "Alquiler / Renta", category: .housing),
            CommonBillDraft(name: "Agua", category: .housing),
            CommonBillDraft(name: "Telefono", category: .other),
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
    var interestRateText: String = ""
    var minimumPaymentText: String = ""
    var isOverdue: Bool = false
}

/// Una meta de texto libre (corto o largo plazo), ej. "liquidar las
/// tarjetas de credito".
struct GoalDraft: Identifiable {
    let id = UUID()
    var text: String = ""
}
