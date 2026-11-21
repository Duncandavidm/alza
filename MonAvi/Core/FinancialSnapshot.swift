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
            case .fair: return "Vas bien, con cosas por ajustar"
            case .attention: return "Hay que poner orden"
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

    /// Ingreso fijo del mes (salario, quincenas...). 0 si no anotó uno.
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

    // MARK: - Números

    /// Pago mínimo de cada deuda; si no lo puso, se estima en 3% del saldo
    /// (lo típico de una tarjeta) para no dejarla fuera de la cuenta.
    static func minimum(for debt: DebtInput) -> Decimal {
        if let minimum = debt.minimumPayment, minimum > 0 { return minimum }
        return (debt.balance * Decimal(3) / Decimal(100)).roundedTo(0)
    }

    var debtPayments: Decimal { debts.reduce(0) { $0 + Self.minimum(for: $1) } }
    var commitments: Decimal { fixedExpenses + debtPayments }
    var freeMoney: Decimal { monthlyIncome - commitments }
    var totalDebt: Decimal { debts.reduce(0) { $0 + $1.balance } }

    var fixedShare: Double? { ratio(fixedExpenses, monthlyIncome) }
    var commitmentShare: Double? { ratio(commitments, monthlyIncome) }

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

    // MARK: - Diagnóstico

    var health: Health {
        let commitment = commitmentShare ?? 0
        let utilization = creditUtilization ?? 0
        if !overdueDebts.isEmpty || (monthlyIncome > 0 && freeMoney < 0) || commitment > 0.7 || utilization > 0.7 {
            return .attention
        }
        if commitment > 0.5 || utilization > 0.3 || (emergencyMonths ?? 0) < 1 || !expensiveDebts.isEmpty {
            return .fair
        }
        return .good
    }

    /// Lo que se ve en los números, en frases cortas.
    var observations: [Line] {
        var lines: [Line] = []
        if monthlyIncome > 0 {
            lines.append(Line("💵", "Te entran unos \(Self.money(monthlyIncome)) al mes de ingreso fijo\(hasVariableIncome ? ", más lo que varía" : "")."))
            if let share = fixedShare, fixedExpenses > 0 {
                lines.append(Line("🏠", "Tus gastos fijos son \(Self.money(fixedExpenses)) al mes: el \(Self.percent(share)) de tu ingreso\(share > 0.5 ? " (lo sano es 50% o menos)" : "")."))
            }
            if debtPayments > 0 {
                lines.append(Line("💳", "En pagos de deudas se te van unos \(Self.money(debtPayments)) al mes."))
            }
            if freeMoney >= 0 {
                lines.append(Line("🟢", "Después de lo fijo te quedan unos \(Self.money(freeMoney)) al mes para comida, transporte, gustos y ahorro."))
            } else {
                lines.append(Line("🔴", "Tus pagos fijos superan tu ingreso fijo por \(Self.money(-freeMoney)) al mes."))
            }
        } else {
            lines.append(Line("💵", hasVariableIncome
                ? "Tus ingresos varían: anota cada entrada para que MonAvi calcule cuánto te entra al mes."
                : "No anotaste un ingreso fijo: cuando registres tus ingresos, el análisis se vuelve más preciso."))
            if fixedExpenses > 0 {
                lines.append(Line("🏠", "Tus gastos fijos suman \(Self.money(fixedExpenses)) al mes."))
            }
        }

        for debt in debts {
            if let use = Self.utilization(of: debt), let limit = debt.creditLimit {
                lines.append(Line(use > 0.3 ? "⚠️" : "💳", "\(debt.name): debes \(Self.money(debt.balance)) de \(Self.money(limit)) de cupo, usas el \(Self.percent(use))\(use > 0.3 ? " (lo ideal es menos del 30%)" : "")."))
            }
        }
        if totalDebt > 0, debts.count > 1 {
            lines.append(Line("📋", "En total debes \(Self.money(totalDebt)) en \(debts.count) deudas."))
        }
        if let months = emergencyMonths {
            if months >= 1 {
                lines.append(Line("🛟", "Con lo que tienes en cuentas y ahorros cubres \(Self.months(months)) de pagos fijos."))
            } else {
                lines.append(Line("🛟", "Lo que tienes guardado no alcanza para un mes de pagos fijos: todavía no tienes colchón para imprevistos."))
            }
        }
        return lines
    }

    /// Hasta 3 pasos concretos, del más urgente al menos.
    var plan: [Line] {
        var steps: [Line] = []

        if let overdue = overdueDebts.first {
            steps.append(Line("⏰", "Ponte al día con \(overdue.name). La mora suma intereses y recargos, y afecta tu historial de crédito."))
        }
        if monthlyIncome > 0, freeMoney < 0 {
            steps.append(Line("✂️", "Recorta \(Self.money(-freeMoney)) al mes en gastos fijos: revisa suscripciones que no uses y planes que puedas bajar."))
        }
        let sortedByUse = debts
            .compactMap { debt -> (DebtInput, Double)? in Self.utilization(of: debt).map { (debt, $0) } }
            .sorted { $0.1 > $1.1 }
        if let top = sortedByUse.first, top.1 > 0.3, let limit = top.0.creditLimit {
            let card = top.0
            let target = (limit * Decimal(30) / Decimal(100)).roundedTo(0)
            steps.append(Line("💳", "Baja \(card.name) a menos de \(Self.money(target)) (30% del cupo). Mientras tanto, evita usarla para gastos del día a día."))
        }
        if let expensive = expensiveDebts.max(by: { ($0.monthlyRate ?? 0) < ($1.monthlyRate ?? 0) }), steps.count < 3 {
            steps.append(Line("🔥", "Abona extra a \(expensive.name) primero: es tu deuda más cara (\(Self.decimalText(expensive.monthlyRate ?? 0))% al mes)."))
        }
        if (emergencyMonths ?? 0) < 1, steps.count < 3 {
            let goal = max(commitments, 100).roundedTo(0)
            let monthly = monthlyIncome > 0 && freeMoney > 0
                ? " Separa \(Self.money(max((freeMoney * Decimal(20) / Decimal(100)).roundedTo(0), 5))) al mes (20% de lo que te queda libre)."
                : ""
            steps.append(Line("🛟", "Arma un fondo de emergencia de \(Self.money(goal)), un mes de tus pagos fijos.\(monthly)"))
        }
        if let share = fixedShare, share > 0.5, freeMoney >= 0, steps.count < 3 {
            steps.append(Line("🏠", "Busca bajar tus gastos fijos al 50% de tu ingreso (\(Self.money((monthlyIncome / 2).roundedTo(0))) al mes)."))
        }
        if steps.count < 3 {
            if monthlyIncome > 0, freeMoney > 0 {
                let monthly = max((freeMoney * Decimal(20) / Decimal(100)).roundedTo(0), 5)
                let goal = firstGoal.map { " para «\($0)»" } ?? ""
                steps.append(Line("🎯", "Ahorra \(Self.money(monthly)) al mes\(goal) apenas te paguen, antes de gastar."))
            }
            steps.append(Line("📝", "Anota tus gastos del día en MonAvi (con la voz es un segundo) para ver en qué se va lo variable."))
        }
        return Array(steps.prefix(3))
    }

    // MARK: - Formato

    static func money(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        let rounded = value.roundedTo(2)
        formatter.maximumFractionDigits = rounded == rounded.roundedTo(0) ? 0 : 2
        formatter.minimumFractionDigits = formatter.maximumFractionDigits
        return formatter.string(from: NSDecimalNumber(decimal: rounded)) ?? "$\(rounded)"
    }

    static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    static func months(_ value: Double) -> String {
        let whole = Int(value.rounded(.down))
        if whole >= 12 { return "más de un año" }
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
