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

    /// Tasa mensual desde la que una deuda se considera cara: ≈18% al año
    /// en Panamá y ≈24% en Colombia (allá las tasas de consumo son más altas).
    static func expensiveMonthlyRate(for country: AppCountry) -> Decimal {
        country == .colombia ? 2 : Decimal(string: "1.5")!
    }
    static let trackedDaysGoal = 20
    static let budgetsGoal = 3
    static let transactionsGoal = 30
    /// Meses de colchón que pide "¿Estás listo para invertir?".
    static let investReadyMonths: Decimal = 3

    let inputs: Inputs
    let country: AppCountry

    init(_ inputs: Inputs, country: AppCountry = AppCountry.current) {
        self.inputs = inputs
        self.country = country
    }

    /// Ingreso extra de fin de año para el colchón: el décimo tercer mes en
    /// Panamá, la prima en Colombia.
    private var bonusName: String { country == .colombia ? "la prima" : "el décimo tercer mes" }

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
            .filter { $0.balance > 0 && ($0.monthlyRate ?? 0) >= Self.expensiveMonthlyRate(for: country) }
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
            detail = L("Agrega tus cuentas para ver tu foto completa.")
        } else {
            detail = L("Tu patrimonio hoy: %@ (tienes %@ y debes %@).", "\(money(netWorth))", "\(money(snapshot.cash + snapshot.savings))", "\(money(snapshot.totalDebt))")
        }
        return Step(
            number: 1, emoji: "📸", title: L("Conoce tu foto"),
            goal: L("Saber cuánto tienes, cuánto debes y en qué se te va el dinero."),
            status: done ? .done : .upcoming,
            progress: done ? 1 : Double(min(inputs.recentTransactions, Self.transactionsGoal)) / Double(Self.transactionsGoal),
            detail: detail,
            mission: done
                ? L("Revisa tu patrimonio una vez al mes y procura que suba.")
                : L("Anota todos tus gastos durante un mes, sin juzgarte. Llevas %@ movimientos.", "\(inputs.recentTransactions)")
        )
    }

    private var step2: Step {
        let done = inputs.budgetsCount >= Self.budgetsGoal
        return Step(
            number: 2, emoji: "🧭", title: L("Dale un trabajo a cada dólar"),
            goal: L("Decidir antes en qué vas a usar tu dinero."),
            status: done ? .done : .upcoming,
            progress: done ? 1 : Double(inputs.budgetsCount) / Double(Self.budgetsGoal),
            detail: inputs.budgetsCount == 0
                ? L("Todavía no tienes presupuestos.")
                : "Tienes \(inputs.budgetsCount) \(inputs.budgetsCount == 1 ? "presupuesto" : "presupuestos").",
            mission: done
                ? L("El día que cobres, aparta primero tu ahorro y vive con el resto.")
                : L("Crea presupuestos para tus categorías principales (comida, transporte, gustos). Te faltan %@.", "\(Self.budgetsGoal - inputs.budgetsCount)")
        )
    }

    private var step3: Step {
        let days = inputs.trackedDays30
        let done = days >= Self.trackedDaysGoal
        return Step(
            number: 3, emoji: "📅", title: "Control constante",
            goal: L("Anotar tus movimientos casi todos los días."),
            status: done ? .done : .upcoming,
            progress: Double(min(days, Self.trackedDaysGoal)) / Double(Self.trackedDaysGoal),
            detail: L("Anotaste algo en %@ de los últimos 30 días.", "\(days)"),
            mission: done
                ? L("Cada quincena compara lo gastado con tus presupuestos.")
                : L("Cierra el día antes de dormir: un minuto para anotar lo que gastaste. Meta: %@ de 30 días.", "\(Self.trackedDaysGoal)")
        )
    }

    /// Cuánto apartar por quincena para llegar a `target` en ~3 meses,
    /// redondeado a montos fáciles: de $5 en $5 (mínimo $10) en Panamá y de
    /// $5.000 en $5.000 (mínimo $20.000) en Colombia.
    private func perQuincena(toReach target: Decimal) -> Decimal {
        let missing = max(0, target - saved)
        let raw = NSDecimalNumber(decimal: missing / 6).doubleValue
        let (step, minimum): (Double, Double) = country == .colombia ? (5000, 20000) : (5, 10)
        let rounded = max(minimum, (raw / step).rounded(.up) * step)
        return Decimal(rounded)
    }

    private var step4: Step {
        guard let need = monthlyNeed else {
            return Step(
                number: 4, emoji: "🛟", title: L("Colchón inicial"),
                goal: L("Tener al menos un mes de gastos guardado."),
                status: .upcoming, progress: 0,
                detail: L("Anota un mes de gastos para calcular tu meta."),
                mission: L("Mientras tanto, abre una cuenta de ahorro aparte para tu fondo de emergencia.")
            )
        }
        let done = saved >= need
        return Step(
            number: 4, emoji: "🛟", title: L("Colchón inicial"),
            goal: L("Tener al menos un mes de gastos guardado."),
            status: done ? .done : .upcoming,
            progress: ratio(saved, need),
            detail: L("Tienes %@ de %@ (un mes de tus gastos).", "\(money(saved))", "\(money(need))"),
            mission: done
                ? L("Guarda este fondo en una cuenta aparte y úsalo solo para imprevistos.")
                : L("Aparta %@ cada quincena. Te faltan %@.", "\(money(perQuincena(toReach: need)))", "\(money(need - saved))")
        )
    }

    private var step5: Step {
        let overdue = overdueDebts
        let expensive = expensiveDebts
        let done = overdue.isEmpty && expensive.isEmpty
        let detail: String
        let mission: String
        if let late = overdue.first {
            detail = L("%@ está en mora.", "\(late.name)")
            mission = L("Ponte al día con %@ antes que nada: la mora sube los intereses y daña tu historial.", "\(late.name)")
        } else if let top = expensive.first {
            detail = expensive.count == 1
                ? L("%@ te cobra %@ al año.", "\(top.name)", "\(Self.annualRateText(top))")
                : L("Tienes %@ deudas caras; la más cara es %@ (%@ al año).", "\(expensive.count)", "\(top.name)", "\(Self.annualRateText(top))")
            mission = L("Paga el mínimo de todas y manda todo lo extra a %@. Cuando la termines, sigue con la siguiente.", "\(top.name)")
        } else if snapshot.debts.contains(where: { $0.balance > 0 }) {
            detail = L("Tus deudas no tienen tasas altas.")
            mission = L("Sigue pagando a tiempo y no sumes deudas nuevas para gustos.")
        } else {
            detail = L("No tienes deudas. ¡Excelente!")
            mission = L("Usa la tarjeta solo para lo presupuestado y págala completa cada mes.")
        }
        return Step(
            number: 5, emoji: "✂️", title: L("Adiós deudas caras"),
            goal: L("Salir de las deudas con intereses altos o en mora."),
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
                number: 6, emoji: "🏰", title: L("Colchón completo"),
                goal: L("Tener %@ meses de gastos guardados.", "\(months)"),
                status: .upcoming, progress: 0,
                detail: L("Anota un mes de gastos para calcular tu meta."),
                mission: L("Usa %@ y los bonos para tu fondo.", "\(bonusName)")
            )
        }
        let target = need * months
        let done = saved >= target
        return Step(
            number: 6, emoji: "🏰", title: L("Colchón completo"),
            goal: snapshot.hasVariableIncome
                ? L("Tener 6 meses de gastos guardados (tus ingresos varían).")
                : L("Tener al menos 3 meses de gastos guardados (lo ideal, hasta 6)."),
            status: done ? .done : .upcoming,
            progress: ratio(saved, target),
            detail: L("Tienes %@ de %@.", "\(money(saved))", "\(money(target))"),
            mission: done
                ? L("Tu colchón está completo: protégelo y no lo uses para gustos.")
                : L("Aparta %@ cada quincena y usa al menos la mitad de %@ y de los bonos.", "\(money(perQuincena(toReach: target)))", "\(bonusName)")
        )
    }

    private var step7: Step {
        let readiness = self.readiness
        return Step(
            number: 7, emoji: "🌱", title: L("Pon tu dinero a trabajar"),
            goal: L("Empezar a invertir con lo que no vas a necesitar pronto."),
            status: readiness.isReady ? .done : .upcoming,
            progress: readiness.isReady ? 1 : 0,
            detail: readiness.headline,
            mission: readiness.isReady
                ? L("Aprende las opciones básicas (plazo fijo, bonos, fondos) y compara riesgo, plazo y comisiones antes de elegir.")
                : (readiness.blockers.first ?? L("Completa los pasos anteriores."))
        )
    }

    // MARK: - ¿Estás listo para invertir?

    var readiness: Readiness {
        var blockers: [String] = []
        for debt in overdueDebts {
            blockers.append(L("Ponte al día con %@: está en mora y eso sube los intereses y daña tu historial.", "\(debt.name)"))
        }
        for debt in expensiveDebts where !debt.isOverdue {
            blockers.append(L("Primero termina de pagar %@: te cobra %@ al año y ninguna inversión segura te paga eso.", "\(debt.name)", "\(Self.annualRateText(debt))"))
        }
        if let over = snapshot.overspending, over > 0 {
            blockers.append(L("Hoy gastas %@ más de lo que te entra al mes. Primero equilibra eso.", "\(money(over))"))
        }
        if let need = monthlyNeed {
            let target = need * Self.investReadyMonths
            if saved < target {
                blockers.append(L("Completa tu fondo de emergencia: te faltan %@ para tener 3 meses de gastos.", "\(money(target - saved))"))
            }
        } else {
            blockers.append(L("Anota al menos un mes de movimientos para saber si estás listo."))
        }

        guard blockers.isEmpty else {
            return Readiness(
                isReady: false,
                headline: L("Todavía no: primero asegura tu base."),
                blockers: blockers,
                monthlyAmount: nil
            )
        }
        let free = max(0, snapshot.freeMoney - (snapshot.overspending ?? 0))
        let amount = (free / 2).roundedTo(0)
        return Readiness(
            isReady: true,
            headline: L("¡Sí! Tienes tu colchón, no tienes deudas caras y gastas menos de lo que ganas."),
            blockers: [],
            monthlyAmount: amount > 0 ? amount : nil
        )
    }
}
