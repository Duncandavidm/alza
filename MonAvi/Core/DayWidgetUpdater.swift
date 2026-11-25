import Foundation
import WidgetKit

/// Arma el snapshot del widget "Tu día" (DayWidgetSnapshot) con los
/// movimientos del mes y le pide a WidgetKit que lo vuelva a dibujar. Lo
/// llama Hoy cada vez que se recarga (abrir la app, anotar, registrar…).
@MainActor
enum DayWidgetUpdater {
    static func refresh(userId: UUID, now: Date = Date()) async {
        let calendar = Calendar.current
        guard let monthStart = calendar.dateInterval(of: .month, for: now)?.start,
              let transactions = try? await TransactionsRepository.shared.fetchSince(
                userId: userId, date: monthStart, limit: 1500
              ) else { return }
        snapshot(from: transactions, now: now, calendar: calendar).save()
        WidgetCenter.shared.reloadTimelines(ofKind: DayWidgetSnapshot.widgetKind)
    }

    /// Gastos: lo que sale (sin transferencias ni inversiones). Ingresos:
    /// solo los movimientos de tipo ingreso.
    static func snapshot(from transactions: [FinanceTransaction], now: Date, calendar: Calendar) -> DayWidgetSnapshot {
        func isExpense(_ t: FinanceTransaction) -> Bool {
            t.amount < 0 && t.movementType != .transferencia && t.movementType != .inversion
        }
        func value(_ decimal: Decimal) -> Double { NSDecimalNumber(decimal: decimal).doubleValue }

        let today = transactions.filter { calendar.isDate($0.occurredAt, inSameDayAs: now) }
        let todaySpent = today.filter(isExpense).reduce(0) { $0 + value(-$1.amount) }
        let monthSpent = transactions.filter(isExpense).reduce(0) { $0 + value(-$1.amount) }
        let monthIncome = transactions.filter { $0.movementType == .ingreso }.reduce(0) { $0 + value($1.amount) }

        let recent = transactions
            .sorted { $0.occurredAt > $1.occurredAt }
            .prefix(5)
            .map { t -> DayWidgetSnapshot.Recent in
                let category = t.category.flatMap(TransactionCategory.init(rawValue:))
                let title = t.description?.trimmingCharacters(in: .whitespacesAndNewlines)
                return DayWidgetSnapshot.Recent(
                    id: t.id.uuidString,
                    title: (title?.isEmpty ?? true) ? (t.category ?? t.movementType.displayName) : title!,
                    emoji: category?.emoji ?? t.movementType.emoji,
                    amount: value(abs(t.amount)),
                    isIncome: t.amount > 0
                )
            }

        return DayWidgetSnapshot(
            todaySpent: todaySpent,
            todayCount: today.count,
            monthSpent: monthSpent,
            monthLeft: monthIncome > 0 ? monthIncome - monthSpent : nil,
            recent: Array(recent),
            updatedAt: now
        )
    }
}
