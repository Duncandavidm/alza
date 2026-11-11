import AppIntents
import Foundation
import Supabase

/// "Registrar gasto o ingreso con voz": abre MonAvi directo en la pantalla
/// de captura por voz (VoiceCaptureView), que escucha, interpreta y guarda
/// el movimiento sola. Pensado para Siri ("Oye Siri, anota en MonAvi") y
/// para Tocar atrás (Ajustes > Accesibilidad > Tocar > Tocar atrás), via un
/// atajo que corre esta accion — ver VoiceBackTapGuideView.
///
/// El reconocimiento de voz necesita la app en primer plano (microfono +
/// Speech), por eso `openAppWhenRun`. perform() corre dentro del proceso de
/// la app: solo deja el pedido en NotificationRouter y DashboardTabView lo
/// muestra en cuanto aparece (app recien abierta o ya abierta). Si no hay
/// sesion, la app simplemente se abre en la pantalla de entrar. Si no hay
/// suscripcion activa, RootView muestra el paywall (como con todo lo demas,
/// incluida la voz dentro de la app) y el pedido caduca solo.
struct RecordByVoiceIntent: AppIntent {
    static var title: LocalizedStringResource = "Registrar gasto o ingreso con voz"
    static var description = IntentDescription(
        "Abre MonAvi escuchando: di un gasto o un ingreso (por ejemplo «gasté 12 dólares en almuerzo» o «me pagaron 500 de salario») y MonAvi lo anota solo."
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        guard (try? await SupabaseManager.shared.client.auth.session) != nil else {
            // Sin sesion: solo se abre la app (pantalla de entrar).
            return .result()
        }
        NotificationRouter.shared.requestVoiceCapture()
        return .result()
    }
}

/// Permite que un Atajo de Apple (ej. una automatizacion personal disparada
/// por el disparador "Transaccion"/"Wallet" de la app Atajos, que si existe
/// desde iOS 17 para tarjetas de Wallet/Apple Pay) anote un gasto en MonAvi
/// sin abrir la app.
///
/// Esto NO le da a MonAvi acceso directo a Apple Pay/Wallet en si — expone un
/// App Intent que CUALQUIER Atajo puede llamar. Armar la automatizacion
/// "cuando pague con mi tarjeta, corre este atajo" es algo que David
/// configura a mano en la app Atajos; ver el README y, dentro de la app,
/// "Conecta tus pagos con Wallet" (WalletAutomationGuideView).
///
/// Si el comercio coincide con un comercio aliado activo, ademas avisa
/// (notificacion local, una por comercio por dia) que escanee la factura:
/// la factura DGI es la prueba del pago con tarjeta para el bono.
struct AddMonAviExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Anotar un gasto en MonAvi"
    static var description = IntentDescription(
        "Registra un gasto en MonAvi, adivinando la categoria por el nombre del comercio. Pensado para usarse desde un Atajo, por ejemplo disparado por una transaccion de Apple Pay/Wallet."
    )

    @Parameter(title: "Monto")
    var amount: Double

    @Parameter(title: "Comercio")
    var merchant: String

    /// Opcional: si no se elige, cae en la primera cuenta del usuario
    /// (mismo comportamiento de antes) — pero si David arma una cuenta
    /// tipo "Tarjeta debito" y la selecciona aqui al armar el Atajo, cada
    /// automatizacion puede apuntar a una cuenta distinta.
    @Parameter(title: "Cuenta (opcional)")
    var account: MonAviAccountEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Anotar \(\.$amount) de \(\.$merchant) en MonAvi") {
            \.$account
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let supabase = SupabaseManager.shared.client

        guard let session = try? await supabase.auth.session else {
            return .result(dialog: "Abre MonAvi e inicia sesion primero.")
        }

        let userId = session.user.id
        let accountId: UUID

        if let chosen = account {
            accountId = chosen.id
        } else {
            let accounts: [Account] = (try? await supabase
                .from("accounts")
                .select()
                .eq("user_id", value: userId)
                .order("created_at", ascending: true)
                .limit(1)
                .execute()
                .value) ?? []

            guard let first = accounts.first?.id else {
                return .result(dialog: "Crea al menos una cuenta en MonAvi antes de anotar por Atajos.")
            }
            accountId = first
        }

        let category = MerchantCategoryGuesser.category(for: merchant)

        try await TransactionsRepository.shared.add(
            NewTransaction(
                userId: userId,
                accountId: accountId,
                amount: MovementType.gasto.signedAmount(from: Decimal(amount)),
                movementType: .gasto,
                category: category?.rawValue,
                description: merchant,
                occurredAt: Date()
            )
        )

        let categoryNote = category.map { " (\($0.emoji) \($0.rawValue))" } ?? ""
        var dialog = "Anotado: \(merchant) por \(amount.formatted(.currency(code: "USD")))\(categoryNote)."

        // Si se pago en un comercio aliado, recordar escanear la factura:
        // la factura DGI (que dice "tarjeta") es la prueba para el bono.
        if let partnerName = await Self.matchingPartnerMerchant(for: merchant) {
            NotificationManager.sendPartnerCardPaymentHint(merchantName: partnerName)
            dialog += " \(partnerName) es comercio aliado: escanea tu factura para ganar tu cashback y el bono por pagar con tarjeta."
        }

        return .result(dialog: "\(dialog)")
    }

    /// Best-effort: cualquier error (red, RLS) simplemente no avisa nada.
    @MainActor
    private static func matchingPartnerMerchant(for merchant: String) async -> String? {
        struct Row: Decodable { let name: String }
        let rows: [Row] = (try? await SupabaseManager.shared.client
            .from("partner_merchants")
            .select("name")
            .eq("status", value: "active")
            .execute()
            .value) ?? []
        return PartnerMerchantMatcher.match(merchant: merchant, partnerNames: rows.map(\.name))
    }
}

/// Representa una cuenta de MonAvi para que Atajos la pueda mostrar como una
/// lista para elegir al armar la automatizacion.
struct MonAviAccountEntity: AppEntity {
    let id: UUID
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Cuenta de MonAvi"
    static var defaultQuery = MonAviAccountQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct MonAviAccountQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [MonAviAccountEntity] {
        try await Self.fetchAccounts().filter { identifiers.contains($0.id) }.map {
            MonAviAccountEntity(id: $0.id, name: $0.name)
        }
    }

    func suggestedEntities() async throws -> [MonAviAccountEntity] {
        try await Self.fetchAccounts().map { MonAviAccountEntity(id: $0.id, name: $0.name) }
    }

    private static func fetchAccounts() async throws -> [Account] {
        let supabase = SupabaseManager.shared.client
        guard let session = try? await supabase.auth.session else { return [] }

        return try await supabase
            .from("accounts")
            .select()
            .eq("user_id", value: session.user.id)
            .order("created_at", ascending: true)
            .execute()
            .value
    }
}

struct MonAviShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordByVoiceIntent(),
            phrases: [
                "Registra con voz en \(.applicationName)",
                "Anota un movimiento en \(.applicationName)",
                "Anota en \(.applicationName)"
            ],
            shortTitle: "Registrar con voz",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: AddMonAviExpenseIntent(),
            phrases: [
                "Anota un gasto en \(.applicationName)",
                "Registra un gasto en \(.applicationName)"
            ],
            shortTitle: "Anotar gasto",
            systemImageName: "mic.and.signal.meter"
        )
    }
}
