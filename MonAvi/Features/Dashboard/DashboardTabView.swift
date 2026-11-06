import SwiftUI

struct DashboardTabView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            DayJournalView()
                .tabItem { Label("Hoy", systemImage: "book.fill") }

            SummaryView()
                .tabItem { Label("Resumen", systemImage: "chart.pie.fill") }

            BudgetsView()
                .tabItem { Label("Presupuestos", systemImage: "wallet.pass.fill") }

            InsightsView()
                .tabItem { Label("Análisis", systemImage: "sparkles") }

            SettingsView()
                .tabItem { Label("Ajustes", systemImage: "gearshape.fill") }
        }
        .tint(MonAviBrand.primary)
        .task {
            await ReminderScheduler.requestPermissionIfNeeded()
            await refreshReminders()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refreshReminders() }
            }
        }
    }

    private func refreshReminders() async {
        guard let userId = appState.currentUserId else { return }
        await ReminderScheduler.refreshAll(userId: userId)
    }
}
