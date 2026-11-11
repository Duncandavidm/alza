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
        // "Registrar con voz" desde un Atajo, Siri o Tocar atrás
        // (RecordByVoiceIntent): si la app estaba cerrada, el pedido espera
        // en el router hasta que esta pantalla aparece; si ya estaba
        // abierta, llega por onChange.
        .fullScreenCover(isPresented: $router.isVoiceCapturePresented) {
            VoiceCaptureView()
        }
        .task { presentPendingVoiceCapture() }
        .onChange(of: router.voiceCaptureRequestedAt) { _, requestedAt in
            if requestedAt != nil { presentPendingVoiceCapture() }
        }
    }

    private func presentPendingVoiceCapture() {
        guard router.consumeVoiceCaptureRequest(), !router.isVoiceCapturePresented else { return }
        if router.destination != nil {
            // No se pueden presentar dos hojas a la vez desde aqui: se cierra
            // la de la notificacion y se abre la de voz cuando termina de irse.
            router.destination = nil
            Task {
                try? await Task.sleep(nanoseconds: 600_000_000)
                router.isVoiceCapturePresented = true
            }
        } else {
            router.isVoiceCapturePresented = true
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
        case .rewards:
            NavigationStack {
                RewardsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cerrar") { router.destination = nil }
                        }
                    }
            }
        case .redemptions:
            NavigationStack {
                MyRedemptionsView()
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
