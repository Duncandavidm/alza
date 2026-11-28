import Foundation

/// "Tu foto financiera": un análisis corto y en lenguaje simple de cómo
/// está la persona (cuánto se le va en pagos fijos, cuánto le queda libre,
/// cuánto usa de sus tarjetas, para cuántos meses le alcanza lo ahorrado)
/// y un plan de hasta 3 pasos para mejorar. Lógica pura, sin red: la usan
/// el final del onboarding y "Tu salud financiera" en Análisis.
struct FinancialSnapshot {
    struct DebtInput: Equatable {
        var name: String
        var balance: Decimal
        var creditLimit: Decimal? = nil
        var minimumPayment: Decimal? = nil
        /// % mensual (ej. 3.5 = 3.5% al mes).
        var monthlyRate: Decimal? = nil
        var isOverdue: Bool = false
    }

    enum Health: Equatable {
        case good, fair, attention

        var title: String {
            switch self {
            case .good: return "Vas bien"
            case .fair: return L("Vas bien, con cosas por ajustar")
            case .attention: return L("Hay que poner orden")
            }
        }

        var emoji: String {
            switch self {
            case .good: return "💪"
            case .fair: return "👀"
            case .attention: return "🚨"
            }
        }
    }

    struct Line: Identifiable, Equatable {
        let id: String
        let emoji: String
        let text: String

        init(_ emoji: String, _ text: String) {
            self.id = text
            self.emoji = emoji
            self.text = text
        }
    }

    /// Ingreso fijo del mes que declaro (salario, quincenas...). 0 si no
    /// anoto uno.
    var monthlyIncome: Decimal
    /// Cuentas fijas + suscripciones + otras fijas, por mes.
    var fixedExpenses: Decimal
    var debts: [DebtInput]
    /// Lo que tiene hoy en sus cuentas (sin contar tarjetas ni préstamos).
    var cash: Decimal
    /// Ahorros e inversiones.
    var savings: Decimal
    /// Primera meta que escribió, para nombrarla en el plan.
    var firstGoal: String? = nil
    var hasVariableIncome: Bool = false
    /// Lo REAL, sacado de sus movimientos (promedio mensual de los ultimos
    /// meses). nil si todavia no hay al menos un mes de movimientos.
    var realIncome: Decimal? = nil
    var realSpending: Decimal? = nil
    /// Cuantos meses de movimientos respaldan lo real (1 a 3).
    var realMonths: Int = 0

    // MARK: - Números

    /// Pago mínimo de cada deuda; si no lo puso, se estima en 3% del saldo
    /// (lo típico de una tarjeta) para no dejarla fuera de la cuenta.
    static func minimum(for debt: DebtInput) -> Decimal {
        if let minimum = debt.minimumPayment, minimum > 0 { return minimum }
        return (debt.balance * Decimal(3) / Decimal(100)).roundedTo(0)
    }

    /// true si el estudio usa lo que de verdad le entra (sus movimientos)
    /// y no solo lo que dijo en el onboarding.
    var usesRealData: Bool { realMonths > 0 && (realIncome ?? 0) > 0 }

    /// El ingreso con el que se calcula todo: el real si hay, si no el
    /// declarado.
    var income: Decimal { usesRealData ? (realIncome ?? 0) : monthlyIncome }

    var debtPayments: Decimal { debts.reduce(0) { $0 + Self.minimum(for: $1) } }
    var commitments: Decimal { fixedExpenses + debtPayments }
    var freeMoney: Decimal { income - commitments }
    var totalDebt: Decimal { debts.reduce(0) { $0 + $1.balance } }

    var fixedShare: Double? { ratio(fixedExpenses, income) }
    var commitmentShare: Double? { ratio(commitments, income) }
    /// Cuánto de lo que gana se va en pagos de deudas (lo sano: < 36%).
    var paymentShare: Double? { debtPayments > 0 ? ratio(debtPayments, income) : nil }
    /// Toda la deuda comparada con un mes de ingreso (1.0 = debe lo que
    /// gana en un mes).
    var debtToIncome: Double? { totalDebt > 0 ? ratio(totalDebt, income) : nil }

    /// Gasta más de lo que gana (con datos reales): cuánto se sobregira al mes.
    var overspending: Decimal? {
        guard usesRealData, let spending = realSpending, let real = realIncome, spending > real else { return nil }
        return (spending - real).roundedTo(0)
    }

    /// Uso del cupo de todas las tarjetas que tienen cupo anotado.
    var creditUtilization: Double? {
        let cards = debts.filter { ($0.creditLimit ?? 0) > 0 }
        let limit = cards.reduce(Decimal(0)) { $0 + ($1.creditLimit ?? 0) }
        return ratio(cards.reduce(Decimal(0)) { $0 + $1.balance }, limit)
    }

    static func utilization(of debt: DebtInput) -> Double? {
        guard let limit = debt.creditLimit, limit > 0 else { return nil }
        return NSDecimalNumber(decimal: debt.balance / limit).doubleValue
    }

    /// Para cuántos meses de pagos fijos alcanza lo que tiene.
    var emergencyMonths: Double? { ratio(cash + savings, commitments) }

    private func ratio(_ part: Decimal, _ whole: Decimal) -> Double? {
        guard whole > 0 else { return nil }
        return NSDecimalNumber(decimal: part / whole).doubleValue
    }

    var overdueDebts: [DebtInput] { debts.filter(\.isOverdue) }
    /// 3% al mes o más (~43% al año): muy cara.
    var expensiveDebts: [DebtInput] { debts.filter { ($0.monthlyRate ?? 0) >= 3 } }

    // MARK: - Nivel de endeudamiento

    enum DebtLevel: Int, Comparable {
        case none, healthy, caution, high, critical

        static func < (lhs: DebtLevel, rhs: DebtLevel) -> Bool { lhs.rawValue < rhs.rawValue }

        var title: String {
            switch self {
            case .none: return L("Sin deudas")
            case .healthy: return "Deuda sana"
            case .caution: return L("Cuidado")
            case .high: return L("Te estás sobreendeudando")
            case .critical: return L("Sobreendeudado")
            }
        }
    }

    /// Criterios usados por bancos y asesores: pagos de deuda sobre el
    /// ingreso (20% / 36% / 50%), deuda total en meses de ingreso (1 / 3 /
    /// 6) y uso del cupo de las tarjetas (30% / 70% / 90%).
    var debtLevel: DebtLevel {
        guard totalDebt > 0 else { return .none }
        let payments = paymentShare ?? 0
        let total = debtToIncome ?? 0
        let use = creditUtilization ?? 0
        let noIncome = income <= 0
        if payments > 0.5 || total > 6 || use > 0.9 || (overspending != nil && total > 1) { return .critical }
        if payments > 0.36 || total > 3 || use > 0.7 || (noIncome && totalDebt > 0) { return .high }
        if payments > 0.2 || total > 1 || use > 0.3 { return .caution }
        return .healthy
    }

    /// Cuánto tendría que subir su ingreso al mes para que los pagos de
    /// deuda queden en 36% o menos.
    var incomeNeededIncrease: Decimal? {
        guard debtPayments > 0 else { return nil }
        let needed = (debtPayments * Decimal(100) / Decimal(36)).roundedTo(0)
        return needed > income ? needed - income : nil
    }

    struct Alert: Equatable {
        let title: String
        let message: String
    }

    /// Aviso fuerte para Hoy: gasta más de lo que gana o se está
    /// sobreendeudando. nil si todo está en rango.
    var debtAlert: Alert? {
        if let over = overspending {
            return Alert(
                title: L("Estás gastando más de lo que ganas"),
                message: "En \(realMonths == 1 ? "el último mes" : "los últimos \(realMonths) meses") gastaste en promedio \(Self.money(realSpending ?? 0)) al mes y te entraron \(Self.money(realIncome ?? 0)): te sobregiras \(Self.money(over)) al mes. Si lo cubres con la tarjeta, tu deuda crece cada mes."
            )
        }
        guard debtLevel >= .high else { return nil }
        var parts: [String] = []
        if let total = debtToIncome {
            parts.append(L("Debes %@, el %@ de lo que ganas en un mes", "\(Self.money(totalDebt))", "\(Self.percent(total))"))
        } else {
            parts.append(L("Debes %@ y no vemos ingresos para pagarlo", "\(Self.money(totalDebt))"))
        }
        if let payments = paymentShare {
            parts.append(L("los pagos mínimos se llevan el %@ de tus ingresos (lo sano es menos del 36%%)", "\(Self.percent(payments))"))
        }
        var message = parts.joined(separator: " y ") + "."
        if let increase = incomeNeededIncrease {
            message += L(" Para no sobreendeudarte necesitas aumentar tus ingresos en unos %@ al mes o bajar tus deudas, y no usar más la tarjeta por ahora.", "\(Self.money(increase))")
        } else {
            message += L(" No tomes deuda nueva y usa la tarjeta solo si la pagas completa.")
        }
        return Alert(title: debtLevel.title, message: message)
    }

    // MARK: - Diagnóstico

    var health: Health {
        let commitment = commitmentShare ?? 0
        let utilization = creditUtilization ?? 0
        if !overdueDebts.isEmpty || (income > 0 && freeMoney < 0) || commitment > 0.7 || utilization > 0.7
            || overspending != nil || debtLevel >= .high {
            return .attention
        }
        if commitment > 0.5 || utilization > 0.3 || (emergencyMonths ?? 0) < 1 || !expensiveDebts.isEmpty || debtLevel == .caution {
            return .fair
        }
        return .good
    }

    /// De dónde salen los números, para decirlo claro.
    var sourceText: String {
        if usesRealData {
            return "Con tus movimientos reales de \(realMonths == 1 ? "el último mes" : "los últimos \(realMonths) meses"), tus pagos fijos, deudas y cuentas."
        }
        return L("Con lo que nos contaste. Cuando tengas un mes de movimientos anotados, lo calculamos con tus números reales.")
    }

    /// Lo que se ve en los números, en frases cortas.
    var observations: [Line] {
        var lines: [Line] = []
        if usesRealData, let real = realIncome {
            lines.append(Line("💵", L("Te entran en promedio %@ al mes (lo que anotaste como ingreso).", "\(Self.money(real))")))
            if monthlyIncome > 0, real < monthlyIncome * Decimal(string: "0.85")! {
                lines.append(Line("📉", L("Es menos que el ingreso fijo que nos dijiste (%@). ¿Te falta anotar algún ingreso?", "\(Self.money(monthlyIncome))")))
            }
            if let spending = realSpending {
                let share = ratio(spending, real) ?? 0
                lines.append(Line(spending > real ? "🔴" : "🧾", L("Gastas en promedio %@ al mes: el %@ de lo que te entra.", "\(Self.money(spending))", "\(Self.percent(share))")))
            }
        } else if monthlyIncome > 0 {
            lines.append(Line("💵", L("Te entran unos %@ al mes de ingreso fijo%@.", "\(Self.money(monthlyIncome))", "\(hasVariableIncome ? ", más lo que varía" : "")")))
        } else {
            lines.append(Line("💵", hasVariableIncome
                ? L("Tus ingresos varían: anota cada entrada para que MonAvi calcule cuánto te entra al mes.")
                : L("No anotaste un ingreso fijo: cuando registres tus ingresos, el análisis se vuelve más preciso.")))
        }

        if income > 0 {
            if let share = fixedShare, fixedExpenses > 0 {
                lines.append(Line("🏠", L("Tus gastos fijos son %@ al mes: el %@ de tu ingreso%@.", "\(Self.money(fixedExpenses))", "\(Self.percent(share))", "\(share > 0.5 ? " (lo sano es 50% o menos)" : "")")))
            }
            if freeMoney >= 0 {
                lines.append(Line("🟢", L("Después de lo fijo y los pagos de deudas te quedan unos %@ al mes.", "\(Self.money(freeMoney))")))
            } else {
                lines.append(Line("🔴", L("Tus pagos fijos y de deudas superan tu ingreso por %@ al mes.", "\(Self.money(-freeMoney))")))
            }
        } else if fixedExpenses > 0 {
            lines.append(Line("🏠", L("Tus gastos fijos suman %@ al mes.", "\(Self.money(fixedExpenses))")))
        }

        if totalDebt > 0 {
            if let total = debtToIncome {
                lines.append(Line(debtLevel >= .high ? "🚨" : "📋", L("Debes %@ en total: el %@ de lo que ganas en un mes.", "\(Self.money(totalDebt))", "\(Self.percent(total))")))
            } else {
                lines.append(Line("📋", L("Debes %@ en total.", "\(Self.money(totalDebt))")))
            }
            if let payments = paymentShare {
                lines.append(Line(payments > 0.36 ? "⚠️" : "💳", L("Los pagos mínimos de tus deudas (%@ al mes) se llevan el %@ de tus ingresos%@.", "\(Self.money(debtPayments))", "\(Self.percent(payments))", "\(payments > 0.36 ? ": más del 36% es sobreendeudamiento" : "")")))
            }
        }

        for debt in debts {
            if let use = Self.utilization(of: debt), let limit = debt.creditLimit {
                let available = max(limit - debt.balance, 0)
                lines.append(Line(use > 0.3 ? "⚠️" : "💳", L("%@: debes %@ de %@ de cupo (te quedan %@ disponibles), usas el %@%@.", "\(debt.name)", "\(Self.money(debt.balance))", "\(Self.money(limit))", "\(Self.money(available))", "\(Self.percent(use))", "\(use > 0.3 ? "; lo ideal es menos del 30%" : "")")))
            }
        }
        if let months = emergencyMonths {
            if months >= 1 {
                lines.append(Line("🛟", L("Con lo que tienes en cuentas y ahorros cubres %@ de pagos fijos.", "\(Self.months(months))")))
            } else {
                lines.append(Line("🛟", L("Lo que tienes guardado no alcanza para un mes de pagos fijos: todavía no tienes colchón para imprevistos.")))
            }
        }
        return lines
    }

    /// Hasta 3 pasos concretos, del más urgente al menos.
    var plan: [Line] {
        var steps: [Line] = []

        if let overdue = overdueDebts.first {
            steps.append(Line("⏰", L("Ponte al día con %@. La mora suma intereses y recargos, y afecta tu historial de crédito.", "\(overdue.name)")))
        }
        if let over = overspending {
            steps.append(Line("✂️", L("Deja de sobregirarte: necesitas gastar %@ menos al mes o ganar eso de más. Empieza por lo que no es necesario.", "\(Self.money(over))")))
        } else if income > 0, freeMoney < 0 {
            steps.append(Line("✂️", L("Recorta %@ al mes en gastos fijos: revisa suscripciones que no uses y planes que puedas bajar.", "\(Self.money(-freeMoney))")))
        }
        if debtLevel >= .high {
            if let increase = incomeNeededIncrease {
                steps.append(Line("📈", L("Para salir del sobreendeudamiento, aumenta tus ingresos en unos %@ al mes (un trabajo extra, ventas) y no tomes deuda nueva.", "\(Self.money(increase))")))
            } else {
                steps.append(Line("🛑", L("No tomes deuda nueva ni uses la tarjeta para gastos del día a día hasta bajar lo que debes.")))
            }
        }
        let sortedByUse = debts
            .compactMap { debt -> (DebtInput, Double)? in Self.utilization(of: debt).map { (debt, $0) } }
            .sorted { $0.1 > $1.1 }
        if let top = sortedByUse.first, top.1 > 0.3, let limit = top.0.creditLimit {
            let card = top.0
            let target = (limit * Decimal(30) / Decimal(100)).roundedTo(0)
            steps.append(Line("💳", L("Baja %@ a menos de %@ (30%% del cupo). Mientras tanto, evita usarla para gastos del día a día.", "\(card.name)", "\(Self.money(target))")))
        }
        if let expensive = expensiveDebts.max(by: { ($0.monthlyRate ?? 0) < ($1.monthlyRate ?? 0) }), steps.count < 3 {
            steps.append(Line("🔥", L("Abona extra a %@ primero: es tu deuda más cara (%@%% al mes).", "\(expensive.name)", "\(Self.decimalText(expensive.monthlyRate ?? 0))")))
        }
        if (emergencyMonths ?? 0) < 1, steps.count < 3 {
            let goal = max(commitments, 100).roundedTo(0)
            let monthly = income > 0 && freeMoney > 0
                ? L(" Separa %@ al mes (20%% de lo que te queda libre).", "\(Self.money(max((freeMoney * Decimal(20) / Decimal(100)).roundedTo(0), 5)))")
                : ""
            steps.append(Line("🛟", L("Arma un fondo de emergencia de %@, un mes de tus pagos fijos.%@", "\(Self.money(goal))", "\(monthly)")))
        }
        if let share = fixedShare, share > 0.5, freeMoney >= 0, steps.count < 3 {
            steps.append(Line("🏠", L("Busca bajar tus gastos fijos al 50%% de tu ingreso (%@ al mes).", "\(Self.money((income / 2).roundedTo(0)))")))
        }
        if steps.count < 3 {
            if income > 0, freeMoney > 0, overspending == nil {
                let monthly = max((freeMoney * Decimal(20) / Decimal(100)).roundedTo(0), 5)
                let goal = firstGoal.map { L(" para «%@»", "\($0)") } ?? ""
                steps.append(Line("🎯", L("Ahorra %@ al mes%@ apenas te paguen, antes de gastar.", "\(Self.money(monthly))", "\(goal)")))
            }
            steps.append(Line("📝", L("Anota tus gastos del día en MonAvi (con la voz es un segundo) para ver en qué se va lo variable.")))
        }
        return Array(steps.prefix(3))
    }

    // MARK: - Formato

    static func money(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        let country = AppCountry.current
        formatter.currencyCode = country.currencyCode
        formatter.locale = country.formatLocale ?? Locale(identifier: "en_US")
        let rounded = value.roundedTo(2)
        formatter.maximumFractionDigits = (rounded == rounded.roundedTo(0) || country.fractionDigits == 0) ? 0 : 2
        formatter.minimumFractionDigits = formatter.maximumFractionDigits
        return formatter.string(from: NSDecimalNumber(decimal: rounded)) ?? "$\(rounded)"
    }

    static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    static func months(_ value: Double) -> String {
        let whole = Int(value.rounded(.down))
        if whole >= 12 { return L("más de un año") }
        return whole == 1 ? "1 mes" : "\(whole) meses"
    }

    static func decimalText(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value.roundedTo(1))
        return number.stringValue.replacingOccurrences(of: ".", with: ",")
    }
}

extension Decimal {
    func roundedTo(_ scale: Int) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, .plain)
        return result
    }
}
