import SwiftUI

// MARK: - Modelos (RPC my_habit_coupons, migracion 0068)

/// Como va la persona en el mes: sale de lo que registra en la app.
struct FinancialMonth: Decodable, Hashable {
    var month: String
    var income: Double
    var expenses: Double
    var savingsRate: Double?
    var loggedDays: Int
    var budgets: Int
    var budgetsMet: Int
    var receipts: Int
    var overdueBills: Int
    var score: Double

    enum CodingKeys: String, CodingKey {
        case month, income, expenses, budgets, receipts, score
        case savingsRate = "savings_rate"
        case loggedDays = "logged_days"
        case budgetsMet = "budgets_met"
        case overdueBills = "overdue_bills"
    }
}

/// Un cupon que se gana con buenos habitos (lo crea MonAvi en el panel).
struct HabitCouponRule: Decodable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var reason: String
    var ruleType: String
    var threshold: Double
    var minLoggedDays: Int
    var coupon: String
    var merchant: String
    var merchantLogoUrl: String?
    var photoUrl: String?
    var earnedCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name, reason, threshold, coupon, merchant
        case ruleType = "rule_type"
        case minLoggedDays = "min_logged_days"
        case merchantLogoUrl = "merchant_logo_url"
        case photoUrl = "photo_url"
        case earnedCount = "earned_count"
    }
}

struct HabitCouponsResponse: Decodable, Hashable {
    var thisMonth: FinancialMonth?
    var rules: [HabitCouponRule]

    static let empty = HabitCouponsResponse(thisMonth: nil, rules: [])

    init(thisMonth: FinancialMonth?, rules: [HabitCouponRule]) {
        self.thisMonth = thisMonth
        self.rules = rules
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        thisMonth = try? container.decodeIfPresent(FinancialMonth.self, forKey: .thisMonth)
        rules = (try? container.decodeIfPresent([HabitCouponRule].self, forKey: .rules)) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case thisMonth = "this_month"
        case rules
    }
}

/// Textos de progreso (logica pura, para probarla aparte).
enum HabitCouponsMath {
    private static func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// Como va este mes frente a la regla: "Vas en 12% de ahorro (meta 20%)".
    static func progressText(rule: HabitCouponRule, month: FinancialMonth?) -> String {
        guard let month else { return L("Empieza a anotar tus movimientos para ver cómo vas.") }
        switch rule.ruleType {
        case "ahorro_ingresos":
            guard let rate = month.savingsRate else { return L("Anota tus ingresos del mes para medir tu ahorro (meta %@%%).", "\(number(rule.threshold))") }
            return L("Este mes vas en %@%% de ahorro (meta %@%%).", "\(number(rate))", "\(number(rule.threshold))")
        case "presupuestos":
            if month.budgets == 0 { return L("Crea al menos %@ presupuestos y cúmplelos este mes.", "\(max(1, Int(rule.threshold)))") }
            return L("Vas cumpliendo %@ de %@ presupuestos.", "\(month.budgetsMet)", "\(month.budgets)")
        case "dias_registrados":
            return L("Llevas %@ de %@ días anotados este mes.", "\(month.loggedDays)", "\(Int(rule.threshold))")
        case "salud_financiera":
            return L("Tu salud financiera este mes: %@/100 (meta %@).", "\(number(month.score))", "\(number(rule.threshold))")
        case "todos":
            return rule.earnedCount > 0
                ? L("Ya está en Mis cupones y canjes con su código.")
                : L("Es para todos los clientes de MonAvi: te llega en la próxima entrega.")
        case "meta_a_tiempo":
            return L("Llega al monto de una meta de al menos $%@ antes de su fecha.", "\(number(rule.threshold))")
        default:
            return rule.reason
        }
    }

    /// Recordatorio del minimo de dias anotados, o nil si ya lo cumple.
    static func loggedDaysHint(rule: HabitCouponRule, month: FinancialMonth?) -> String? {
        guard rule.minLoggedDays > 0, rule.ruleType != "dias_registrados", rule.ruleType != "todos" else { return nil }
        let logged = month?.loggedDays ?? 0
        guard logged < rule.minLoggedDays else { return nil }
        return L("Anota tus movimientos al menos %@ días del mes (llevas %@).", "\(rule.minLoggedDays)", "\(logged)")
    }

    /// "¡Ganado!" / "Ganado 3 veces" / nil.
    static func earnedText(_ count: Int) -> String? {
        switch count {
        case ..<1: return nil
        case 1: return L("¡Ya lo ganaste!")
        default: return "Ganado \(count) veces"
        }
    }
}

// MARK: - Datos

@MainActor
final class HabitCouponsViewModel: ObservableObject {
    @Published private(set) var response: HabitCouponsResponse = .empty
    @Published private(set) var hasLoaded = false

    func refresh() async {
        defer { hasLoaded = true }
        let fetched: HabitCouponsResponse? = try? await SupabaseManager.shared.client
            .rpc("my_habit_coupons")
            .execute()
            .value
        response = fetched ?? .empty
    }
}

// MARK: - Pantalla

/// "Cupones por buenos hábitos": lo que puedes ganar ahorrando, cumpliendo
/// metas y presupuestos, y como vas este mes. Los cupones ganados llegan
/// a "Mis canjes" como regalo, con su codigo para caja.
struct HabitCouponsView: View {
    @StateObject private var viewModel = HabitCouponsViewModel()

    var body: some View {
        List {
            if let month = viewModel.response.thisMonth {
                Section {
                    healthCard(month)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                if !viewModel.hasLoaded {
                    ProgressView().frame(maxWidth: .infinity)
                } else if viewModel.response.rules.isEmpty {
                    Text("Pronto habrá cupones para ganar con tus buenos hábitos. Mientras tanto, sigue anotando tus movimientos y ahorrando.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.response.rules) { rule in
                        couponRow(rule)
                    }
                }
            } header: {
                Text("Cupones que puedes ganar")
            } footer: {
                Text("Los cupones los paga MonAvi y se entregan solos cuando cumples. Te avisamos y aparecen en Mis cupones y canjes con su código para caja.")
            }

            Section {
                NavigationLink {
                    MyRedemptionsView()
                } label: {
                    Label("Mis cupones y canjes", systemImage: "ticket.fill")
                }
                NavigationLink {
                    SavingsGoalsView()
                } label: {
                    Label("Metas de ahorro", systemImage: "banknote.fill")
                }
            }
        }
        .navigationTitle("Cupones por hábitos")
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.refresh() }
    }

    private func healthCard(_ month: FinancialMonth) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tu salud financiera este mes")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MonAviBrand.onDarkSurface.opacity(0.9))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(month.score.rounded()))")
                    .font(.system(size: 44, weight: .bold, design: MonAviBrand.fontDesign))
                    .foregroundStyle(MonAviBrand.onDarkSurface)
                Text("/ 100")
                    .font(.headline)
                    .foregroundStyle(MonAviBrand.accentOnDark)
            }
            ProgressView(value: min(max(month.score, 0), 100), total: 100)
                .tint(MonAviBrand.accentOnDark)
            HStack(spacing: 14) {
                metric(L("Ahorro"), month.savingsRate.map { "\(Int($0.rounded()))%" } ?? "—")
                metric(L("Días"), "\(month.loggedDays)")
                metric("Presupuestos", "\(month.budgetsMet)/\(month.budgets)")
                metric("Facturas", "\(month.receipts)")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MonAviBrand.headerGradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
                .foregroundStyle(MonAviBrand.onDarkSurface)
            Text(title)
                .font(.caption2)
                .foregroundStyle(MonAviBrand.accentOnDark)
        }
    }

    private func couponRow(_ rule: HabitCouponRule) -> some View {
        HStack(alignment: .top, spacing: 12) {
            MerchantLogoView(urlString: rule.photoUrl ?? rule.merchantLogoUrl, name: rule.merchant, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(rule.coupon) en \(rule.merchant)")
                    .font(.body.weight(.semibold))
                Text(rule.reason.prefix(1).uppercased() + rule.reason.dropFirst())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(HabitCouponsMath.progressText(rule: rule, month: viewModel.response.thisMonth))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(MonAviBrand.primaryDark)
                if let hint = HabitCouponsMath.loggedDaysHint(rule: rule, month: viewModel.response.thisMonth) {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let earned = HabitCouponsMath.earnedText(rule.earnedCount) {
                    Label(earned, systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MonAviBrand.primary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
