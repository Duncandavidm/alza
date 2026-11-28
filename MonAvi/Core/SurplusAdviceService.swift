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
        let amountText = surplus.formatted(.appCurrency)

        async let debtsRequest: [Debt] = (try? await supabase
            .from("debts")
            .select()
            .eq("user_id", value: userId)
            .eq("status", value: DebtStatus.active.rawValue)
            .order("interest_rate_monthly", ascending: false)
            .execute()
            .value) ?? []
        async let goalsRequest: [SavingsGoal] = (try? await supabase
            .from("savings_goals")
            .select()
            .eq("user_id", value: userId)
            .order("target_date", ascending: true)
            .execute()
            .value) ?? []
        let (debts, goals) = await (debtsRequest, goalsRequest)

        if let worstDebt = debts.first {
            let rateText = worstDebt.interestRateMonthly.map { rate in
                L(" (%@%%/mes de interes)", "\(rate.formatted(.number.precision(.fractionLength(1))))")
            } ?? ""
            // Si ya tiene algo apartado en alguna meta (posible colchon —
            // no sabemos si es "fondo de emergencia" porque MonAvi no distingue
            // el tipo de meta, pero es la mejor señal disponible de que no
            // esta en cero), no le ordenamos mandar TODO el sobrante a la
            // deuda sin que lo piense: se lo planteamos como una decision
            // entre reforzar esa reserva y abonar a la deuda, no como un
            // hecho. Sin ninguna meta con avance, sigue siendo cierto que
            // ningun ahorro rinde mas que dejar de pagar esos intereses.
            let hasSomeReserve = goals.contains { $0.currentAmount > 0 }
            if hasSomeReserve {
                return L("Pagaste tus cuentas y te quedaron %@. Tienes deuda con %@%@ — abonarla rinde mas que cualquier ahorro, pero antes revisa si tu colchon actual te alcanza para imprevistos. Si si, destinalo a la deuda; si no, considera repartirlo entre tu reserva y la deuda.", "\(amountText)", "\(worstDebt.creditor)", "\(rateText)")
            }
            return L("Pagaste tus cuentas y te quedaron %@. Antes de ahorrarlo o invertirlo, te conviene abonarlo a tu deuda con %@%@ — ningun ahorro te rinde mas que dejar de pagar esos intereses.", "\(amountText)", "\(worstDebt.creditor)", "\(rateText)")
        }

        if let goal = goals.first(where: { !$0.isAchieved }) {
            if surplus >= goal.remainingAmount {
                return L("Pagaste tus cuentas y te quedaron %@ — eso alcanza para completar tu meta \"%@\" %@. ¿Lo aportamos?", "\(amountText)", "\(goal.name)", "\(goal.emoji)")
            }
            let newProgress = min(1, NSDecimalNumber(decimal: (goal.currentAmount + surplus) / goal.targetAmount).doubleValue)
            let pct = Int((newProgress * 100).rounded())
            return L("Pagaste tus cuentas y te quedaron %@. Si lo aportas a tu meta \"%@\" %@, llegarias al %@%% — vas en %@%% ahorita.", "\(amountText)", "\(goal.name)", "\(goal.emoji)", "\(pct)", "\(Int((goal.progress * 100).rounded()))")
        }

        switch surplus {
        case ..<20:
            return L("Pagaste tus cuentas y te quedaron %@. Es poco para invertir, pero es perfecto para empezar tu fondo de emergencia — cada poquito cuenta.", "\(amountText)")
        case 20..<100:
            return L("Pagaste tus cuentas y te quedaron %@. Buen momento para crear una meta de ahorro en MonAvi — hasta un fondo de emergencia chico te da colchon para el proximo imprevisto.", "\(amountText)")
        case 100..<500:
            return L("Pagaste tus cuentas y te quedaron %@. Si ya tienes de 3 a 6 meses de gastos ahorrados, es buen monto para empezar a invertir; si no, te conviene completar ese fondo primero.", "\(amountText)")
        default:
            return L("Pagaste tus cuentas y te quedaron %@ — un sobrante grande. Antes de invertirlo, confirma que ya cubres de 3 a 6 meses de gastos en tu fondo de emergencia; si ya los tienes, este es buen momento para ponerlo a trabajar.", "\(amountText)")
        }
    }
}
