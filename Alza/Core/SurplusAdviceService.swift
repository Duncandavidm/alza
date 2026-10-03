import Foundation
import Supabase

/// Cuando el cliente termina de pagar todas sus cuentas pendientes y le
/// queda dinero en la cuenta, arma un consejo real con sus propios datos
/// (no un texto generico): si tiene una deuda activa, esa va primero
/// (ningun ahorro rinde mas que dejar de pagar intereses); si no, mira su
/// meta de ahorro mas cercana; si no tiene ninguna, da un consejo por
/// rangos segun el monto.
enum SurplusAdviceService {
    static func buildAdvice(userId: UUID, surplus: Decimal) async -> String? {
        guard surplus > 0 else { return nil }
        let supabase = SupabaseManager.shared.client
        let amountText = surplus.formatted(.currency(code: "USD"))

        let debts: [Debt] = (try? await supabase
            .from("debts")
            .select()
            .eq("user_id", value: userId)
            .eq("status", value: DebtStatus.active.rawValue)
            .order("interest_rate_monthly", ascending: false)
            .execute()
            .value) ?? []

        if let worstDebt = debts.first {
            let rateText = worstDebt.interestRateMonthly.map { rate in
                " (\(rate.formatted(.number.precision(.fractionLength(1))))%/mes de interes)"
            } ?? ""
            return "Pagaste tus cuentas y te quedaron \(amountText). Antes de ahorrarlo o invertirlo, te conviene abonarlo a tu deuda con \(worstDebt.creditor)\(rateText) — ningun ahorro te rinde mas que dejar de pagar esos intereses."
        }

        let goals: [SavingsGoal] = (try? await supabase
            .from("savings_goals")
            .select()
            .eq("user_id", value: userId)
            .order("target_date", ascending: true)
            .execute()
            .value) ?? []

        if let goal = goals.first(where: { !$0.isAchieved }) {
            if surplus >= goal.remainingAmount {
                return "Pagaste tus cuentas y te quedaron \(amountText) — eso alcanza para completar tu meta \"\(goal.name)\" \(goal.emoji). ¿Lo aportamos?"
            }
            let newProgress = min(1, NSDecimalNumber(decimal: (goal.currentAmount + surplus) / goal.targetAmount).doubleValue)
            let pct = Int((newProgress * 100).rounded())
            return "Pagaste tus cuentas y te quedaron \(amountText). Si lo aportas a tu meta \"\(goal.name)\" \(goal.emoji), llegarias al \(pct)% — vas en \(Int((goal.progress * 100).rounded()))% ahorita."
        }

        switch surplus {
        case ..<20:
            return "Pagaste tus cuentas y te quedaron \(amountText). Es poco para invertir, pero es perfecto para empezar tu fondo de emergencia — cada poquito cuenta."
        case 20..<100:
            return "Pagaste tus cuentas y te quedaron \(amountText). Buen momento para crear una meta de ahorro en Amadai — hasta un fondo de emergencia chico te da colchon para el proximo imprevisto."
        case 100..<500:
            return "Pagaste tus cuentas y te quedaron \(amountText). Si ya tienes de 3 a 6 meses de gastos ahorrados, es buen monto para empezar a invertir; si no, te conviene completar ese fondo primero."
        default:
            return "Pagaste tus cuentas y te quedaron \(amountText) — un sobrante grande. Antes de invertirlo, confirma que ya cubres de 3 a 6 meses de gastos en tu fondo de emergencia; si ya los tienes, este es buen momento para ponerlo a trabajar."
        }
    }
}
