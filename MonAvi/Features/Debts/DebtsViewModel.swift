import Foundation
import Supabase

@MainActor
final class DebtsViewModel: ObservableObject {
    @Published private(set) var debts: [Debt] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let supabase = SupabaseManager.shared.client

    var totalActiveBalance: Decimal {
        debts.filter { $0.status != .paidOff }.reduce(0) { $0 + $1.balance }
    }

    func refresh(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        do {
            debts = try await supabase
                .from("debts")
                .select()
                .eq("user_id", value: userId)
                .order("is_overdue", ascending: false)
                .order("balance", ascending: false)
                .execute()
                .value
            NotificationManager.scheduleCardPayments(debts)
        } catch {
            errorMessage = L("No se pudo cargar tus deudas: %@", "\(error.localizedDescription)")
        }
    }

    /// Cupo total de una tarjeta (para ver cuanto del cupo se usa). Las
    /// deudas creadas en el onboarding de 1.0.3 no lo pedian.
    func setCreditLimit(_ limit: Decimal, for debt: Debt) async {
        struct LimitUpdate: Encodable {
            let creditLimit: Decimal
            enum CodingKeys: String, CodingKey { case creditLimit = "credit_limit" }
        }
        do {
            try await supabase.from("debts").update(LimitUpdate(creditLimit: limit)).eq("id", value: debt.id).execute()
            if let index = debts.firstIndex(where: { $0.id == debt.id }) {
                debts[index].creditLimit = limit
            }
        } catch {
            errorMessage = L("No se pudo guardar el cupo: %@", "\(error.localizedDescription)")
        }
    }

    /// Dia del mes en que vence (para avisar y registrar el pago).
    func setPaymentDay(_ day: Int, for debt: Debt) async {
        struct DayUpdate: Encodable {
            let paymentDay: Int
            enum CodingKeys: String, CodingKey { case paymentDay = "payment_day" }
        }
        do {
            try await supabase.from("debts").update(DayUpdate(paymentDay: day)).eq("id", value: debt.id).execute()
            if let index = debts.firstIndex(where: { $0.id == debt.id }) {
                debts[index].paymentDay = day
            }
            NotificationManager.scheduleCardPayments(debts)
        } catch {
            errorMessage = L("No se pudo guardar el día de pago: %@", "\(error.localizedDescription)")
        }
    }

    /// Editar una deuda (tarjeta: cupo, usado, tasa, minimo, dia de pago).
    /// Si es tarjeta con cuenta vinculada, el saldo de la cuenta se ajusta
    /// solo (trigger de 0079).
    func update(
        _ debt: Debt,
        creditor: String,
        balance: Decimal,
        creditLimit: Decimal?,
        interestRateMonthly: Decimal?,
        minimumPayment: Decimal?,
        paymentDay: Int?,
        dueDate: String?,
        isOverdue: Bool
    ) async throws {
        struct Update: Encodable {
            let creditor: String
            let balance: Decimal
            let creditLimit: Decimal?
            let interestRateMonthly: Decimal?
            let minimumPayment: Decimal?
            let paymentDay: Int?
            let dueDate: String?
            let isOverdue: Bool
            let status: String
            enum CodingKeys: String, CodingKey {
                case creditor, balance, status
                case creditLimit = "credit_limit"
                case interestRateMonthly = "interest_rate_monthly"
                case minimumPayment = "minimum_payment"
                case paymentDay = "payment_day"
                case dueDate = "due_date"
                case isOverdue = "is_overdue"
            }
            // null explicito para poder borrar un campo opcional.
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(creditor, forKey: .creditor)
                try c.encode(balance, forKey: .balance)
                try c.encode(creditLimit, forKey: .creditLimit)
                try c.encode(interestRateMonthly, forKey: .interestRateMonthly)
                try c.encode(minimumPayment, forKey: .minimumPayment)
                try c.encode(paymentDay, forKey: .paymentDay)
                try c.encode(dueDate, forKey: .dueDate)
                try c.encode(isOverdue, forKey: .isOverdue)
                try c.encode(status, forKey: .status)
            }
        }
        let status = balance <= 0 ? DebtStatus.paidOff.rawValue
            : (debt.status == .paidOff ? DebtStatus.active.rawValue : debt.status.rawValue)
        let updated: Debt = try await supabase
            .from("debts")
            .update(Update(
                creditor: creditor, balance: balance, creditLimit: creditLimit,
                interestRateMonthly: interestRateMonthly, minimumPayment: minimumPayment,
                paymentDay: paymentDay, dueDate: dueDate, isOverdue: isOverdue, status: status
            ))
            .eq("id", value: debt.id)
            .select()
            .single()
            .execute()
            .value
        if let index = debts.firstIndex(where: { $0.id == debt.id }) {
            debts[index] = updated
        }
        NotificationManager.scheduleCardPayments(debts)
    }

    @discardableResult
    func add(_ new: NewDebt) async throws -> Debt {
        let created: Debt = try await supabase
            .from("debts")
            .insert(new)
            .select()
            .single()
            .execute()
            .value
        debts.append(created)
        return created
    }

    func delete(_ debt: Debt) async {
        do {
            try await supabase.from("debts").delete().eq("id", value: debt.id).execute()
            debts.removeAll { $0.id == debt.id }
        } catch {
            errorMessage = L("No se pudo borrar: %@", "\(error.localizedDescription)")
        }
    }
}
