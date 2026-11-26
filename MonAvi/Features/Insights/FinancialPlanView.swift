import SwiftUI
import Supabase

/// Enseñanza del Método MonAvi (finance_teachings), administrada desde el
/// panel. La app solo ve las activas que se muestran como lección.
struct FinanceTeaching: Decodable, Identifiable, Hashable {
    let id: UUID
    let step: Int?
    let title: String
    let body: String
}

/// Análisis > "Tu plan en 7 pasos": en qué paso va la persona, qué hacer
/// esta semana, lecciones de cada paso y "¿Estás listo para invertir?".
struct FinancialPlanView: View {
    @EnvironmentObject private var appState: AppState
    @State private var plan: FinancialPlan?
    @State private var teachings: [FinanceTeaching] = []
    @State private var expandedStep: Int?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let plan {
                headerSection(plan)
                stepsSection(plan)
                readinessSection(plan.readiness)
                lessonsSection
                Section {
                    Text("El Método MonAvi es educación financiera general. No es asesoría de inversión ni recomienda productos o entidades.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let errorMessage {
                ContentUnavailableView("No se pudo cargar", systemImage: "wifi.exclamationmark", description: Text(errorMessage))
            } else {
                MonAviCatLoader(message: "Armando tu plan…")
                    .padding(.vertical, 40)
            }
        }
        .navigationTitle("Tu plan")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Secciones

    private func headerSection(_ plan: FinancialPlan) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Método MonAvi")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(MonAviBrand.primary)
                Text(plan.currentStep.map { "Vas en el paso \($0.number): \($0.title)" } ?? "¡Completaste los 7 pasos! 🎉")
                    .font(.title3.weight(.bold))
                ProgressView(value: Double(plan.completedCount), total: 7)
                    .tint(MonAviBrand.primary)
                Text("\(plan.completedCount) de 7 pasos listos")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let current = plan.currentStep {
                    Label(current.mission, systemImage: "flag.fill")
                        .font(.subheadline)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(MonAviBrand.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func stepsSection(_ plan: FinancialPlan) -> some View {
        Section("Los 7 pasos") {
            ForEach(plan.steps) { step in
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        withAnimation(.snappy) {
                            expandedStep = expandedStep == step.number ? nil : step.number
                        }
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(circleColor(step.status))
                                    .frame(width: 34, height: 34)
                                if step.status == .done {
                                    Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(.white)
                                } else {
                                    Text("\(step.number)").font(.footnote.weight(.bold))
                                        .foregroundStyle(step.status == .current ? .white : .secondary)
                                }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(step.emoji) \(step.title)")
                                    .font(.body.weight(step.status == .current ? .semibold : .regular))
                                    .foregroundStyle(.primary)
                                Text(step.goal)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: expandedStep == step.number ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if expandedStep == step.number || (expandedStep == nil && step.status == .current) {
                        VStack(alignment: .leading, spacing: 8) {
                            if step.status != .done {
                                ProgressView(value: step.progress).tint(MonAviBrand.primary)
                            }
                            Text(step.detail).font(.subheadline)
                            Label(step.mission, systemImage: "flag")
                                .font(.subheadline)
                                .foregroundStyle(MonAviBrand.primaryDark)
                            ForEach(teachings.filter { $0.step == step.number }.prefix(2)) { lesson in
                                lessonCard(lesson)
                            }
                        }
                        .padding(.leading, 46)
                        .transition(.opacity)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func readinessSection(_ readiness: FinancialPlan.Readiness) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(readiness.isReady ? "✅ ¿Estás listo para invertir?" : "🌱 ¿Estás listo para invertir?")
                    .font(.headline)
                Text(readiness.headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(readiness.isReady ? MonAviBrand.primary : .primary)
                if readiness.isReady {
                    if let amount = readiness.monthlyAmount {
                        Text("Como referencia, podrías destinar unos \(FinancialSnapshot.money(amount)) al mes (la mitad de tu dinero libre), sin tocar tu colchón.")
                            .font(.subheadline)
                    }
                    Text("Empieza aprendiendo las opciones básicas y compara riesgo, plazo, comisiones y que la entidad esté regulada.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(readiness.blockers.enumerated()), id: \.offset) { index, blocker in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(MonAviBrand.alert.opacity(0.15)))
                                .foregroundStyle(MonAviBrand.alert)
                            Text(blocker).font(.subheadline)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var lessonsSection: some View {
        if !teachings.isEmpty {
            Section("Lecciones") {
                ForEach(1...7, id: \.self) { step in
                    let lessons = teachings.filter { $0.step == step }
                    if !lessons.isEmpty {
                        DisclosureGroup("Paso \(step)") {
                            ForEach(lessons) { lessonCard($0) }
                        }
                    }
                }
                let general = teachings.filter { $0.step == nil }
                if !general.isEmpty {
                    DisclosureGroup("Para todos los días") {
                        ForEach(general) { lessonCard($0) }
                    }
                }
            }
        }
    }

    private func lessonCard(_ lesson: FinanceTeaching) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("💡 \(lesson.title)").font(.subheadline.weight(.semibold))
            Text(lesson.body).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private func circleColor(_ status: FinancialPlan.Status) -> Color {
        switch status {
        case .done: return MonAviBrand.primary
        case .current: return MonAviBrand.primaryDark
        case .upcoming: return Color(.tertiarySystemFill)
        }
    }

    // MARK: - Datos

    private func load() async {
        guard let userId = appState.currentUserId else { return }
        do {
            plan = try await FinancialPlanLoader.load(userId: userId)
            errorMessage = nil
        } catch {
            if plan == nil { errorMessage = error.localizedDescription }
        }
        // Las lecciones son un extra: si fallan, el plan igual se muestra.
        teachings = (try? await FinancialPlanLoader.teachings()) ?? teachings
    }
}

enum FinancialPlanLoader {
    private struct IdRow: Decodable { let id: UUID }

    static func load(userId: UUID) async throws -> FinancialPlan {
        let supabase = SupabaseManager.shared.client
        let since90 = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        async let healthTask = FinancialHealthLoader.load(userId: userId)
        async let accountsTask: [IdRow] = supabase
            .from("accounts").select("id").eq("user_id", value: userId).execute().value
        async let budgetsTask: [IdRow] = supabase
            .from("budgets").select("id").eq("user_id", value: userId).execute().value
        async let transactionsTask = TransactionsRepository.shared.fetchSince(userId: userId, date: since90, limit: 3000)

        let (health, accounts, budgets, transactions) = try await (healthTask, accountsTask, budgetsTask, transactionsTask)
        return FinancialPlan(FinancialPlan.Inputs(
            snapshot: health.snapshot,
            accountsCount: accounts.count,
            recentTransactions: transactions.count,
            trackedDays30: trackedDays(transactions.map(\.occurredAt)),
            budgetsCount: budgets.count
        ))
    }

    /// Días distintos con movimientos en los últimos 30 días.
    static func trackedDays(_ dates: [Date], now: Date = Date(), calendar: Calendar = .current) -> Int {
        guard let start = calendar.date(byAdding: .day, value: -30, to: now) else { return 0 }
        return Set(dates.filter { $0 >= start && $0 <= now }.map { calendar.startOfDay(for: $0) }).count
    }

    static func teachings() async throws -> [FinanceTeaching] {
        // Las generales (country nil) y las del país de la cuenta.
        try await SupabaseManager.shared.client
            .from("finance_teachings")
            .select("id, step, title, body")
            .or("country.is.null,country.eq.\(AppCountry.current.rawValue)")
            .order("step", ascending: true)
            .order("sort", ascending: true)
            .execute()
            .value
    }
}
