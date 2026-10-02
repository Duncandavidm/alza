import AppIntents
import Foundation
import Supabase

/// Permite que un Atajo de Apple (ej. una automatizacion personal disparada
/// por el disparador "Transaccion"/"Wallet" de la app Atajos, que si existe
/// desde iOS 17 para tarjetas de Wallet/Apple Pay) anote un gasto en Alza
/// sin abrir la app.
///
/// Esto NO le da a Alza acceso directo a Apple Pay/Wallet en si — expone un
/// App Intent que CUALQUIER Atajo puede llamar. Armar la automatizacion
/// "cuando pague con mi tarjeta, corre este atajo" es algo que David
/// configura a mano en la app Atajos; ver el README para el paso a paso.
struct AddAlzaExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Anotar un gasto en Alza"
    static var description = IntentDescription(
        "Registra un gasto en Alza, adivinando la categoria por el nombre del comercio. Pensado para usarse desde un Atajo, por ejemplo disparado por una transaccion de Apple Pay/Wallet."
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
    var account: AlzaAccountEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Anotar \(\.$amount) de \(\.$merchant) en Alza") {
            \.$account
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let supabase = SupabaseManager.shared.client

        guard let session = try? await supabase.auth.session else {
            return .result(dialog: "Abre Alza e inicia sesion primero.")
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
                return .result(dialog: "Crea al menos una cuenta en Alza antes de anotar por Atajos.")
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
        return .result(dialog: "Anotado: \(merchant) por \(amount.formatted(.currency(code: "USD")))\(categoryNote).")
    }
}

/// Representa una cuenta de Alza para que Atajos la pueda mostrar como una
/// lista para elegir al armar la automatizacion.
struct AlzaAccountEntity: AppEntity {
    let id: UUID
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Cuenta de Alza"
    static var defaultQuery = AlzaAccountQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct AlzaAccountQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [AlzaAccountEntity] {
        try await Self.fetchAccounts().filter { identifiers.contains($0.id) }.map {
            AlzaAccountEntity(id: $0.id, name: $0.name)
        }
    }

    func suggestedEntities() async throws -> [AlzaAccountEntity] {
        try await Self.fetchAccounts().map { AlzaAccountEntity(id: $0.id, name: $0.name) }
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
