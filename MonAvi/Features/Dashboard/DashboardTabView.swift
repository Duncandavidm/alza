import SwiftUI

struct DashboardTabView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var router = NotificationRouter.shared

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
        // Tocar una notificacion con destino (ej. "¡Sumaste X puntos!")
        // abre esa pantalla encima de la que este abierta.
        .sheet(item: $router.destination) { destination in
            destinationView(destination)
        }
    }

    @ViewBuilder
    private func destinationView(_ destination: NotificationDestination) -> some View {
        switch destination {
        case .points:
            NavigationStack {
                PointsHubView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cerrar") { router.destination = nil }
                        }
                    }
            }
        }
    }

    private func refreshReminders() async {
        guard let userId = appState.currentUserId else { return }
        await ReminderScheduler.refreshAll(userId: userId)
    }
}
