import SwiftUI

/// Lo que se le pide a una tarjeta de credito: cupo, lo usado, el
/// disponible (se calcula solo), la tasa (al año o al mes), el pago minimo
/// y el dia de pago. Se usa en "Nueva cuenta" (tipo tarjeta) y en
/// "Nueva / Editar deuda".
struct CreditCardFieldsDraft: Equatable {
    var limitText = ""
    var usedText = ""
    var rateText = ""
    var ratePeriod: InterestPeriod = .annual
    var minimumText = ""
    var hasPaymentDay = false
    var paymentDay = 15

    var limit: Decimal? { CreditCardMath.parse(limitText) }
    var used: Decimal? { CreditCardMath.parse(usedText) }
    var monthlyRate: Decimal? { CreditCardMath.monthlyRate(rateText, period: ratePeriod) }
    var minimum: Decimal? { CreditCardMath.parse(minimumText) }

    init() {}

    /// Para editar una tarjeta ya guardada (la tasa se muestra al año).
    init(debt: Debt) {
        limitText = debt.creditLimit.map { DgiInvoiceLookupLogic.amountText(for: $0) } ?? ""
        usedText = DgiInvoiceLookupLogic.amountText(for: debt.balance)
        if let monthly = debt.interestRateMonthly {
            rateText = "\(CreditCardMath.annualRate(monthly: monthly))"
            ratePeriod = .annual
        }
        minimumText = debt.minimumPayment.map { DgiInvoiceLookupLogic.amountText(for: $0) } ?? ""
        if let day = debt.paymentDay {
            hasPaymentDay = true
            paymentDay = day
        }
    }
}

struct CreditCardFieldsSections: View {
    @Binding var draft: CreditCardFieldsDraft
    /// En una deuda que no es tarjeta, el cupo es opcional.
    var limitIsOptional = false

    var body: some View {
        Section {
            LabeledContent(limitIsOptional ? "Cupo (si es tarjeta)" : "Cupo total") {
                AmountField(placeholder: "ej. 2000", text: $draft.limitText)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Usado (lo que debes)") {
                AmountField(placeholder: "ej. 600", text: $draft.usedText)
                    .multilineTextAlignment(.trailing)
            }
            if let summary = CreditCardMath.summary(limit: draft.limit, used: draft.used) {
                let use = CreditCardMath.utilization(limit: draft.limit, used: draft.used) ?? 0
                Text(summary)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(use > 0.3 ? .orange : MonAviBrand.primary)
            }
        } header: {
            Text("Cupo")
        } footer: {
            Text("Lo ideal es usar menos del 30% del cupo.")
        }

        Section {
            Picker("Tasa de interés", selection: $draft.ratePeriod) {
                ForEach(InterestPeriod.allCases) { period in
                    Text(period.label).tag(period)
                }
            }
            .pickerStyle(.segmented)
            LabeledContent(draft.ratePeriod == .annual ? "Interés al año" : "Interés al mes") {
                PercentField(placeholder: draft.ratePeriod == .annual ? "ej. 24" : "ej. 2", text: $draft.rateText)
                    .multilineTextAlignment(.trailing)
            }
            if let monthly = draft.monthlyRate, monthly > 0 {
                Text(CreditCardMath.rateText(monthly: monthly))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Pago mínimo") {
                AmountField(placeholder: "opcional", text: $draft.minimumText)
                    .multilineTextAlignment(.trailing)
            }
            Toggle("Tiene día de pago cada mes", isOn: $draft.hasPaymentDay)
            if draft.hasPaymentDay {
                DayOfMonthField(label: "Día de pago", day: $draft.paymentDay)
            }
        } header: {
            Text("Pago")
        } footer: {
            Text(draft.hasPaymentDay
                 ? "Te avisamos 3 días antes y el mismo día, y registras de qué cuenta salió el pago."
                 : "Búscala en tu estado de cuenta: los bancos suelen dar la tasa al año.")
        }
    }
}
