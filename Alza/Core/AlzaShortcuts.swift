import AppIntents
import Foundation

/// Permite que un Atajo de Apple (ej. una automatizacion personal disparada
/// por "Transaccion de Apple Pay") anote un gasto en Alza sin abrir la app.
/// Inspirado en "Seguimiento automatico de compras con Apple Pay... hecho
/// posible con los atajos de Apple".
///
/// Esto NO le da a Alza acceso directo a Apple Pay/Wallet (eso no existe
/// para apps de terceros) — expone un App Intent que CUALQUIER Atajo puede
/// llamar. Armar la automatizacion "cuando pague con Apple Pay, corre este
/// atajo" es algo que David configura a mano en la app de Atajos; ver el
/// README para el paso a paso.
struct AddAlzaExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Anotar un gasto en Alza"
    static var description = IntentDescription(
        "Registra un gasto en Alza. Pensado para usarse desde un Atajo, por ejemplo disparado por una transaccion de Apple Pay."
    )

    @Parameter(title: "Monto")
    var amount: Double

    @Parameter(title: "Descripcion")
    var merchant: String

    static var parameterSummary: some ParameterSummary {
        Summary("Anotar \(\.$amount) de \(\.$merchant) en Alza")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let supabase = SupabaseManager.shared.client

        guard let session = try? await supabase.auth.session else {
            return .result(dialog: "Abre Alza e inicia sesion primero.")
        }

        let userId = session.user.id

        let accounts: [Account] = (try? await supabase
            .from("accounts")
            .select()
            .eq("user_id", value: userId)
            .order("created_at", ascending: true)
            .limit(1)
            .execute()
            .value) ?? []

        guard let accountId = accounts.first?.id else {
            return .result(dialog: "Crea al menos una cuenta en Alza antes de anotar por Atajos.")
        }

        try await TransactionsRepository.shared.add(
            NewTransaction(
                userId: userId,
                accountId: accountId,
                amount: MovementType.gasto.signedAmount(from: Decimal(amount)),
                movementType: .gasto,
                category: nil,
                description: merchant,
                occurredAt: Date()
            )
        )

        return .result(dialog: "Anotado: \(merchant) por \(amount.formatted(.currency(code: "USD"))).")
    }
}

struct AlzaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddAlzaExpenseIntent(),
            phrases: [
                "Anota un gasto en \(.applicationName)",
                "Registra un gasto en \(.applicationName)"
            ],
            shortTitle: "Anotar gasto",
            systemImageName: "mic.and.signal.meter"
        )
    }
}
