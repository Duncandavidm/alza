import SwiftUI

/// "Mis metas" (B2, ahorro verificado): progreso del mes, cuanto falta,
/// y los puntos en juego (pendientes vs confirmados) — separado del
/// resto del ledger porque estos puntos son de alto valor y SOLO se
/// confirman cuando el banco patrocinador lo verifica (ver
/// reconcile-savings-reports). Nunca se otorgan desde el cliente.
struct MySavingsGoalsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var enrollments: [SponsoredSavingsEnrollment] = []
    @State private var bankPartnersById: [UUID: BankPartner] = [:]
    @State private var goalsByEnrollment: [UUID: [SponsoredSavingsGoal]] = [:]
    @State private var pendingPoints = 0
    @State private var confirmedPoints = 0
    @State private var isLoading = true
    @State private var isEnrolling = false
    @State private var creatingGoalFor: SponsoredSavingsEnrollment?
    @State private var errorMessage: String?

    private let repository = CardPointsRepository.shared

    var body: some View {
        List {
            Section {
                pointsSummary
            }

            if enrollments.isEmpty && !isLoading {
                Section {
                    ContentUnavailableView(
                        "Sin banco inscrito",
                        systemImage: "building.columns",
                        description: Text("Inscribete con un banco patrocinador para poner una meta mensual de ahorro y ganar puntos verificados.")
                    )
                    Button("Inscribirme con un banco") { isEnrolling = true }
                }
            } else {
                ForEach(enrollments) { enrollment in
                    enrollmentSection(enrollment)
                }

                Section {
                    Button("Inscribir otro banco") { isEnrolling = true }
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Mis metas")
        .task { await refresh() }
        .refreshable { await refresh() }
        .overlay {
            if isLoading { ProgressView() }
        }
        .sheet(isPresented: $isEnrolling) {
            SponsoredSavingsConsentView(onEnrolled: { Task { await refresh() } })
        }
        .sheet(item: $creatingGoalFor) { enrollment in
            NewSavingsGoalView(enrollment: enrollment, onCreated: { Task { await refresh() } })
        }
    }

    private var pointsSummary: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Confirmados").font(.caption).foregroundStyle(.secondary)
                Text("\(confirmedPoints) pts").font(.title.weight(.bold))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Pendientes").font(.caption).foregroundStyle(.secondary)
                Text("\(pendingPoints) pts").font(.title.weight(.bold))
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func enrollmentSection(_ enrollment: SponsoredSavingsEnrollment) -> some View {
        let goals = goalsByEnrollment[enrollment.id] ?? []
        let currentGoal = goals.first { $0.periodMonth == SavingsPeriod.currentMonthString }
        let pastGoals = goals.filter { $0.periodMonth != SavingsPeriod.currentMonthString }

        Section(bankPartnersById[enrollment.bankPartnerId]?.name ?? "Banco") {
            if let currentGoal {
                goalRow(currentGoal)
            } else {
                Button("Poner meta de este mes") { creatingGoalFor = enrollment }
            }

            ForEach(pastGoals) { goal in
                goalRow(goal)
            }

            Button("Revocar consentimiento", role: .destructive) {
                Task { await revoke(enrollment) }
            }
        }
    }

    private func goalRow(_ goal: SponsoredSavingsGoal) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(MonthYearFormat.string(from: goal.periodMonthDate))
                    .font(.body)
                Text(goal.targetAmount, format: .currency(code: "USD"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(goal.status.displayName)
                .font(.caption.weight(.medium))
                .foregroundStyle(statusColor(goal.status))
        }
    }

    private func statusColor(_ status: SavingsGoalStatus) -> Color {
        switch status {
        case .active: return .secondary
        case .met: return .green
        case .missed: return .red
        }
    }

    private func refresh() async {
        guard let userId = appState.currentUserId else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let activeEnrollments = try await repository.fetchActiveSavingsEnrollments(userId: userId)
            enrollments = activeEnrollments

            let partners = try await repository.fetchAllBankPartners()
            bankPartnersById = Dictionary(uniqueKeysWithValues: partners.map { ($0.id, $0) })

            var goalsMap: [UUID: [SponsoredSavingsGoal]] = [:]
            for enrollment in activeEnrollments {
                goalsMap[enrollment.id] = (try? await repository.fetchSavingsGoals(enrollmentId: enrollment.id)) ?? []
            }
            goalsByEnrollment = goalsMap
        } catch {
            errorMessage = "No se pudo cargar: \(error.localizedDescription)"
        }

        let breakdown = await repository.savingsPointsBreakdown(userId: userId)
        pendingPoints = breakdown.pending
        confirmedPoints = breakdown.confirmed
    }

    private func revoke(_ enrollment: SponsoredSavingsEnrollment) async {
        do {
            try await repository.revokeConsent(enrollment)
            await refresh()
        } catch {
            errorMessage = "No se pudo revocar: \(error.localizedDescription)"
        }
    }
}
