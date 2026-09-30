import SwiftUI

struct DashboardTabView: View {
    var body: some View {
        TabView {
            DayJournalView()
                .tabItem { Label("Hoy", systemImage: "book.fill") }

            BudgetsView()
                .tabItem { Label("Presupuestos", systemImage: "chart.bar.fill") }

            DashboardView()
                .tabItem { Label("Cuentas", systemImage: "creditcard.fill") }

            InsightsView()
                .tabItem { Label("Insights", systemImage: "sparkles") }

            SettingsView()
                .tabItem { Label("Ajustes", systemImage: "gearshape.fill") }
        }
    }
}
