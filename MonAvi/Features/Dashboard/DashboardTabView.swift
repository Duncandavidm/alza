import SwiftUI

struct DashboardTabView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var router = NotificationRouter.shared
    /// Camara pedida desde fuera (widget, control, Siri) o factura compartida.
    @State private var isScanningInvoice = false
    @State private var sharedPayload: String?

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
                presentPendingInvoiceScan()
                presentPendingQuickAdd()
            }
        }
        .invoiceScanner(isPresented: $isScanningInvoice, payload: sharedPayload) {
            sharedPayload = nil
        }
        .task { presentPendingInvoiceScan() }
        .task { presentPendingQuickAdd() }
        .onReceive(NotificationCenter.default.publisher(for: QuickAddRequest.notification)) { _ in
            presentPendingQuickAdd()
        }
        .onReceive(NotificationCenter.default.publisher(for: InvoiceScanRequest.notification)) { _ in
            presentPendingInvoiceScan()
        }
        .onChange(of: router.sharedInvoicePayload) { _, payload in
            if payload != nil { presentPendingInvoiceScan() }
        }
        .alert("No encontramos la factura", isPresented: isSharedInvoiceErrorShown) {
            Button("Escanear con la cámara") {
                router.sharedInvoiceError = nil
                InvoiceScanRequest.request()
            }
            Button("Cerrar", role: .cancel) { router.sharedInvoiceError = nil }
        } message: {
            Text(router.sharedInvoiceError ?? "")
        }
        // Tocar una notificacion con destino (ej. "¡Sumaste X puntos!")
        // abre esa pantalla encima de la que este abierta.
        .sheet(item: $router.destination) { destination in
            destinationView(destination)
        }
        // "Hoy vence tu Visa": tocar el aviso abre el pago de esa tarjeta.
        .sheet(item: $router.cardPayment) { request in
            QuickDebtPaymentView(preselectedDebtId: request.debtId)
        }
        // "¿Ya está disponible tu dinero?" > "Sí, pasarlo a otra cuenta".
        .sheet(item: $router.accountTransfer) { request in
            AccountTransferView(sourceAccountId: request.sourceAccountId)
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

    private var isSharedInvoiceErrorShown: Binding<Bool> {
        Binding(
            get: { router.sharedInvoiceError != nil },
            set: { if !$0 { router.sharedInvoiceError = nil } }
        )
    }

    /// Abre la camara (o la revision de la factura compartida) si hay un
    /// pedido pendiente. Cierra antes la hoja de una notificacion, si hay.
    private func presentPendingInvoiceScan() {
        let payload = router.sharedInvoicePayload
        guard payload != nil || InvoiceScanRequest.consume() else { return }
        router.sharedInvoicePayload = nil
        sharedPayload = payload
        if router.destination != nil {
            router.destination = nil
            Task {
                try? await Task.sleep(nanoseconds: 600_000_000)
                isScanningInvoice = true
            }
        } else {
            isScanningInvoice = true
        }
    }

    /// Botón "Anotar gasto" del Centro de control: Hoy abre Anotar movimiento.
    private func presentPendingQuickAdd() {
        guard QuickAddRequest.consume() else { return }
        router.destination = nil
        router.quickAddRequestedAt = Date()
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
