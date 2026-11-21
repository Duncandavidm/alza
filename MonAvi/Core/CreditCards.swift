import Foundation

/// Recuerda en este iPhone que pago de tarjeta/deuda ya se registro en el
/// mes, para no volver a pedirlo (aviso del dia de pago y tarjeta en Hoy).
enum CardPaymentTracker {
    private static func key(_ debtId: UUID, _ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return "monavi.cardPaid.\(debtId.uuidString).\(parts.year ?? 0)-\(parts.month ?? 0)"
    }

    static func markPaid(debtId: UUID, on date: Date = Date(), calendar: Calendar = .current) {
        UserDefaults.standard.set(true, forKey: key(debtId, date, calendar))
    }

    /// Pagado para el vencimiento `due`: cuenta un pago hecho en el mes del
    /// vencimiento o en los ~10 dias antes (pagos adelantados a fin de mes).
    static func isPaid(debtId: UUID, due: Date, calendar: Calendar = .current) -> Bool {
        if UserDefaults.standard.bool(forKey: key(debtId, due, calendar)) { return true }
        if calendar.component(.day, from: due) <= 10,
           let previous = calendar.date(byAdding: .month, value: -1, to: due) {
            return UserDefaults.standard.bool(forKey: key(debtId, previous, calendar))
        }
        return false
    }
}

/// Fechas de pago de tarjetas y prestamos (logica pura).
enum CreditCardSchedule {
    /// Proximo vencimiento (hoy cuenta) para un dia de pago 1-31; en meses
    /// cortos, 29-31 = ultimo dia del mes.
    static func nextDueDate(paymentDay: Int, now: Date = Date(), calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: now)
        for offset in 0...1 {
            guard let month = calendar.date(byAdding: .month, value: offset, to: today),
                  let range = calendar.range(of: .day, in: .month, for: month)
            else { continue }
            var parts = calendar.dateComponents([.year, .month], from: month)
            parts.day = min(max(paymentDay, 1), range.count)
            if let date = calendar.date(from: parts), date >= today { return date }
        }
        return nil
    }

    static func daysUntil(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// Deudas con pago pendiente que vence en los proximos `withinDays`
    /// dias (hoy incluido), de la mas proxima a la mas lejana.
    struct Upcoming: Identifiable {
        let debt: Debt
        let due: Date
        var id: UUID { debt.id }
    }

    static func upcoming(_ debts: [Debt], withinDays: Int = 5, now: Date = Date(), calendar: Calendar = .current) -> [Upcoming] {
        debts.compactMap { debt -> Upcoming? in
            guard debt.status != .paidOff, debt.balance > 0, let day = debt.paymentDay,
                  let due = nextDueDate(paymentDay: day, now: now, calendar: calendar),
                  daysUntil(due, now: now, calendar: calendar) <= withinDays,
                  !CardPaymentTracker.isPaid(debtId: debt.id, due: due, calendar: calendar)
            else { return nil }
            return Upcoming(debt: debt, due: due)
        }
        .sorted { $0.due < $1.due }
    }
}
