import SwiftUI

struct DashboardTabView: View {
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
    }
}
