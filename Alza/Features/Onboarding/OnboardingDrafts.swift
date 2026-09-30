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
