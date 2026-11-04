import SwiftUI

/// "Habitos financieros" (B1): racha de registrar gastos varios dias
/// seguidos, y tope mensual visible — nada se otorga desde aqui, todo lo
/// calcula y acredita el servidor (`award-habit-points`); esta pantalla
/// solo muestra el mismo criterio para que lo que el usuario ve
/// coincida con lo que se va a premiar.
struct HabitsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var streakDays = 0
    @State private var pointsThisMonth = 0
    @State private var monthlyCap = 200
    @State private var isLoading = true

    private var remainingPoints: Int {
        max(0, monthlyCap - pointsThisMonth)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Text("🔥").font(.largeTitle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(streakDays) dia\(streakDays == 1 ? "" : "s") seguidos")
                                .font(.title3.weight(.bold))
                            Text("Anotando al menos un movimiento")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Te quedan \(remainingPoints) puntos de habitos este mes")
                            .font(.subheadline.weight(.medium))
                        ProgressView(value: Double(pointsThisMonth), total: Double(max(monthlyCap, 1)))
                            .tint(MonAviBrand.primary)
                        Text("\(pointsThisMonth) de \(monthlyCap) pts — se reinicia cada mes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            } footer: {
                Text("Ganas puntos por cada semana completa de racha, por cerrar una semana sin pasarte de un presupuesto semanal, y por terminar el mes dentro de un presupuesto mensual. Son puntos de poco valor, pensados para animarte — no para premios grandes.")
            }
        }
        .navigationTitle("Habitos")
        .task { await refresh() }
        .refreshable { await refresh() }
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
    }

    private func refresh() async {
        guard let userId = appState.currentUserId else { return }
        isLoading = true
        defer { isLoading = false }

        async let streakTask = CardPointsRepository.shared.currentStreakDays(userId: userId)
        async let pointsTask = CardPointsRepository.shared.habitPointsThisMonth(userId: userId)
        async let capTask = CardPointsRepository.shared.habitMonthlyCap()

        streakDays = await streakTask
        pointsThisMonth = await pointsTask
        monthlyCap = await capTask
    }
}
