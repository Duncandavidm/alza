import Foundation

/// Método MonAvi: el plan de 7 pasos de cada persona, calculado con sus
/// datos reales (cuentas, movimientos, presupuestos y deudas). Lógica pura,
/// sin red, para poder probarla.
///
/// 1. Conoce tu foto        — un mes anotando movimientos.
/// 2. Dale un trabajo a cada dólar — al menos 3 presupuestos.
/// 3. Control constante     — anotar 20 de los últimos 30 días.
/// 4. Colchón inicial       — 1 mes de gastos ahorrado.
/// 5. Adiós deudas caras    — sin deudas en mora ni con tasa alta.
/// 6. Colchón completo      — 3 meses de gastos (6 si sus ingresos varían).
/// 7. Pon tu dinero a trabajar — "¿Estás listo para invertir?".
///
/// El paso actual es el primero que falta. Un paso ya cumplido aparece como
/// hecho aunque los anteriores no lo estén (ej. sin deudas = paso 5 listo).
struct FinancialPlan {
    struct Inputs {
        var snapshot: FinancialSnapshot
        var accountsCount: Int
        /// Movimientos de los últimos 90 días.
        var recentTransactions: Int
        /// Días distintos con al menos un movimiento en los últimos 30.
        var trackedDays30: Int
        var budgetsCount: Int
    }

    enum Status: Equatable { case done, current, upcoming }

    struct Step: Identifiable, Equatable {
        let number: Int
        let emoji: String
        let title: String
        /// Qué se logra en este paso (una línea).
        let goal: String
        var status: Status
        /// 0...1, para la barra.
        let progress: Double
        /// Cómo va la persona, con sus números.
        let detail: String
        /// Lo que puede hacer esta semana.
        let mission: String
        var id: Int { number }
    }

    struct Readiness: Equatable {
        let isReady: Bool
        let headline: String
        /// Qué falta antes de invertir, en orden de prioridad.
        let blockers: [String]
        /// Si está lista: cuánto podría destinar al mes (la mitad de su
        /// dinero libre), como referencia.
        let monthlyAmount: Decimal?
    }

    // MARK: - Reglas

    /// Tasa mensual desde la que una deuda se considera cara (≈18% al año).
    static let expensiveMonthlyRate: Decimal = Decimal(string: "1.5")!
    static let trackedDaysGoal = 20
    static let budgetsGoal = 3
    static let transactionsGoal = 30
    /// Meses de colchón que pide "¿Estás listo para invertir?".
    static let investReadyMonths: Decimal = 3

    let inputs: Inputs

    init(_ inputs: Inputs) {
        self.inputs = inputs
    }

    private var snapshot: FinancialSnapshot { inputs.snapshot }

    /// Gasto mensual de referencia: lo real si hay datos; si no, los pagos
    /// fijos y mínimos. nil si todavía no se sabe.
    var monthlyNeed: Decimal? {
        let need = max(snapshot.realSpending ?? 0, snapshot.commitments)
        return need > 0 ? need : nil
    }

    /// Lo que tiene disponible para emergencias (cuentas + ahorros).
    var saved: Decimal { max(0, snapshot.cash + snapshot.savings) }

    var netWorth: Decimal { snapshot.cash + snapshot.savings - snapshot.totalDebt }

    /// Meses de colchón para el paso 6.
    var fullCushionMonths: Decimal { snapshot.hasVariableIncome ? 6 : 3 }

    var overdueDebts: [FinancialSnapshot.DebtInput] {
        snapshot.debts.filter { $0.isOverdue && $0.balance > 0 }
    }

    /// Deudas caras, de la tasa más alta a la más baja (método avalancha).
    var expensiveDebts: [FinancialSnapshot.DebtInput] {
        snapshot.debts
            .filter { $0.balance > 0 && ($0.monthlyRate ?? 0) >= Self.expensiveMonthlyRate }
            .sorted { ($0.monthlyRate ?? 0) > ($1.monthlyRate ?? 0) }
    }

    static func annualRateText(_ debt: FinancialSnapshot.DebtInput) -> String {
        let annual = NSDecimalNumber(decimal: (debt.monthlyRate ?? 0) * 12).doubleValue
        return "\(Int(annual.rounded()))%"
    }

    // MARK: - Pasos

    var steps: [Step] {
        var list = [step1, step2, step3, step4, step5, step6, step7]
        let currentIndex = list.firstIndex { $0.status != .done }
        for index in list.indices where list[index].status != .done {
            list[index].status = index == currentIndex ? .current : .upcoming
        }
        return list
    }

    var currentStep: Step? { steps.first { $0.status == .current } }
    var completedCount: Int { steps.filter { $0.status == .done }.count }

    private func ratio(_ part: Decimal, _ whole: Decimal) -> Double {
        guard whole > 0 else { return 0 }
        return min(1, max(0, NSDecimalNumber(decimal: part / whole).doubleValue))
    }

    private func money(_ value: Decimal) -> String { FinancialSnapshot.money(value) }

    private var step1: Step {
        let enough = snapshot.realMonths >= 1 || inputs.recentTransactions >= Self.transactionsGoal
        let done = inputs.accountsCount > 0 && enough
        let detail: String
        if inputs.accountsCount == 0 {
            detail = "Agrega tus cuentas para ver tu foto completa."
        } else {
            detail = "Tu patrimonio hoy: \(money(netWorth)) (tienes \(money(snapshot.cash + snapshot.savings)) y debes \(money(snapshot.totalDebt)))."
        }
        return Step(
            number: 1, emoji: "📸", title: "Conoce tu foto",
            goal: "Saber cuánto tienes, cuánto debes y en qué se te va el dinero.",
            status: done ? .done : .upcoming,
            progress: done ? 1 : Double(min(inputs.recentTransactions, Self.transactionsGoal)) / Double(Self.transactionsGoal),
            detail: detail,
            mission: done
                ? "Revisa tu patrimonio una vez al mes y procura que suba."
                : "Anota todos tus gastos durante un mes, sin juzgarte. Llevas \(inputs.recentTransactions) movimientos."
        )
    }

    private var step2: Step {
        let done = inputs.budgetsCount >= Self.budgetsGoal
        return Step(
            number: 2, emoji: "🧭", title: "Dale un trabajo a cada dólar",
            goal: "Decidir antes en qué vas a usar tu dinero.",
            status: done ? .done : .upcoming,
            progress: done ? 1 : Double(inputs.budgetsCount) / Double(Self.budgetsGoal),
            detail: inputs.budgetsCount == 0
                ? "Todavía no tienes presupuestos."
                : "Tienes \(inputs.budgetsCount) \(inputs.budgetsCount == 1 ? "presupuesto" : "presupuestos").",
            mission: done
                ? "El día que cobres, aparta primero tu ahorro y vive con el resto."
                : "Crea presupuestos para tus categorías principales (comida, transporte, gustos). Te faltan \(Self.budgetsGoal - inputs.budgetsCount)."
        )
    }

    private var step3: Step {
        let days = inputs.trackedDays30
        let done = days >= Self.trackedDaysGoal
        return Step(
            number: 3, emoji: "📅", title: "Control constante",
            goal: "Anotar tus movimientos casi todos los días.",
            status: done ? .done : .upcoming,
            progress: Double(min(days, Self.trackedDaysGoal)) / Double(Self.trackedDaysGoal),
            detail: "Anotaste algo en \(days) de los últimos 30 días.",
            mission: done
                ? "Cada quincena compara lo gastado con tus presupuestos."
                : "Cierra el día antes de dormir: un minuto para anotar lo que gastaste. Meta: \(Self.trackedDaysGoal) de 30 días."
        )
    }

    /// Cuánto apartar por quincena para llegar a `target` en ~3 meses.
    private func perQuincena(toReach target: Decimal) -> Decimal {
        let missing = max(0, target - saved)
        let raw = NSDecimalNumber(decimal: missing / 6).doubleValue
        let rounded = max(10, (raw / 5).rounded(.up) * 5)
        return Decimal(rounded)
    }

    private var step4: Step {
        guard let need = monthlyNeed else {
            return Step(
                number: 4, emoji: "🛟", title: "Colchón inicial",
                goal: "Tener al menos un mes de gastos guardado.",
                status: .upcoming, progress: 0,
                detail: "Anota un mes de gastos para calcular tu meta.",
                mission: "Mientras tanto, abre una cuenta de ahorro aparte para tu fondo de emergencia."
            )
        }
        let done = saved >= need
        return Step(
            number: 4, emoji: "🛟", title: "Colchón inicial",
            goal: "Tener al menos un mes de gastos guardado.",
            status: done ? .done : .upcoming,
            progress: ratio(saved, need),
            detail: "Tienes \(money(saved)) de \(money(need)) (un mes de tus gastos).",
            mission: done
                ? "Guarda este fondo en una cuenta aparte y úsalo solo para imprevistos."
                : "Aparta \(money(perQuincena(toReach: need))) cada quincena. Te faltan \(money(need - saved))."
        )
    }

    private var step5: Step {
        let overdue = overdueDebts
        let expensive = expensiveDebts
        let done = overdue.isEmpty && expensive.isEmpty
        let detail: String
        let mission: String
        if let late = overdue.first {
            detail = "\(late.name) está en mora."
            mission = "Ponte al día con \(late.name) antes que nada: la mora sube los intereses y daña tu historial."
        } else if let top = expensive.first {
            detail = expensive.count == 1
                ? "\(top.name) te cobra \(Self.annualRateText(top)) al año."
                : "Tienes \(expensive.count) deudas caras; la más cara es \(top.name) (\(Self.annualRateText(top)) al año)."
            mission = "Paga el mínimo de todas y manda todo lo extra a \(top.name). Cuando la termines, sigue con la siguiente."
        } else if snapshot.debts.contains(where: { $0.balance > 0 }) {
            detail = "Tus deudas no tienen tasas altas."
            mission = "Sigue pagando a tiempo y no sumes deudas nuevas para gustos."
        } else {
            detail = "No tienes deudas. ¡Excelente!"
            mission = "Usa la tarjeta solo para lo presupuestado y págala completa cada mes."
        }
        return Step(
            number: 5, emoji: "✂️", title: "Adiós deudas caras",
            goal: "Salir de las deudas con intereses altos o en mora.",
            status: done ? .done : .upcoming,
            progress: done ? 1 : 0,
            detail: detail,
            mission: mission
        )
    }

    private var step6: Step {
        let months = fullCushionMonths
        guard let need = monthlyNeed else {
            return Step(
                number: 6, emoji: "🏰", title: "Colchón completo",
                goal: "Tener \(months) meses de gastos guardados.",
                status: .upcoming, progress: 0,
                detail: "Anota un mes de gastos para calcular tu meta.",
                mission: "Usa el décimo tercer mes y los bonos para tu fondo."
            )
        }
        let target = need * months
        let done = saved >= target
        return Step(
            number: 6, emoji: "🏰", title: "Colchón completo",
            goal: snapshot.hasVariableIncome
                ? "Tener 6 meses de gastos guardados (tus ingresos varían)."
                : "Tener al menos 3 meses de gastos guardados (lo ideal, hasta 6).",
            status: done ? .done : .upcoming,
            progress: ratio(saved, target),
            detail: "Tienes \(money(saved)) de \(money(target)).",
            mission: done
                ? "Tu colchón está completo: protégelo y no lo uses para gustos."
                : "Aparta \(money(perQuincena(toReach: target))) cada quincena y usa al menos la mitad del décimo tercer mes y de los bonos."
        )
    }

    private var step7: Step {
        let readiness = self.readiness
        return Step(
            number: 7, emoji: "🌱", title: "Pon tu dinero a trabajar",
            goal: "Empezar a invertir con lo que no vas a necesitar pronto.",
            status: readiness.isReady ? .done : .upcoming,
            progress: readiness.isReady ? 1 : 0,
            detail: readiness.headline,
            mission: readiness.isReady
                ? "Aprende las opciones básicas (plazo fijo, bonos, fondos) y compara riesgo, plazo y comisiones antes de elegir."
                : (readiness.blockers.first ?? "Completa los pasos anteriores.")
        )
    }

    // MARK: - ¿Estás listo para invertir?

    var readiness: Readiness {
        var blockers: [String] = []
        for debt in overdueDebts {
            blockers.append("Ponte al día con \(debt.name): está en mora y eso sube los intereses y daña tu historial.")
        }
        for debt in expensiveDebts where !debt.isOverdue {
            blockers.append("Primero termina de pagar \(debt.name): te cobra \(Self.annualRateText(debt)) al año y ninguna inversión segura te paga eso.")
        }
        if let over = snapshot.overspending, over > 0 {
            blockers.append("Hoy gastas \(money(over)) más de lo que te entra al mes. Primero equilibra eso.")
        }
        if let need = monthlyNeed {
            let target = need * Self.investReadyMonths
            if saved < target {
                blockers.append("Completa tu fondo de emergencia: te faltan \(money(target - saved)) para tener 3 meses de gastos.")
            }
        } else {
            blockers.append("Anota al menos un mes de movimientos para saber si estás listo.")
        }

        guard blockers.isEmpty else {
            return Readiness(
                isReady: false,
                headline: "Todavía no: primero asegura tu base.",
                blockers: blockers,
                monthlyAmount: nil
            )
        }
        let free = max(0, snapshot.freeMoney - (snapshot.overspending ?? 0))
        let amount = (free / 2).roundedTo(0)
        return Readiness(
            isReady: true,
            headline: "¡Sí! Tienes tu colchón, no tienes deudas caras y gastas menos de lo que ganas.",
            blockers: [],
            monthlyAmount: amount > 0 ? amount : nil
        )
    }
}
