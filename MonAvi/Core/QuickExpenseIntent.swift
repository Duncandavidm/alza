import AppIntents
import Foundation
import Supabase

/// Categorias de gasto para que Atajos las muestre como lista al preguntar.
/// rawValue = lo que se guarda en `transactions.category` (mismos textos
/// que TransactionCategory). Las etiquetas van literales: Atajos las lee
/// al compilar.
enum QuickExpenseCategory: String, AppEnum {
    case housing = "Vivienda"
    case food = "Comida"
    case groceries = "Supermercado"
    case utilities = "Servicios"
    case transport = "Transporte"
    case shopping = "Compras"
    case clothing = "Ropa"
    case goingOut = "Salir"
    case entertainment = "Entretenimiento"
    case subscriptions = "Suscripciones"
    case health = "Salud"
    case education = "Educación"
    case pets = "Mascotas"
    case gifts = "Regalos"
    case travel = "Viajes"
    case other = "Otro"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Categoría"

    static var caseDisplayRepresentations: [QuickExpenseCategory: DisplayRepresentation] = [
        .housing: "🏠 Vivienda",
        .food: "🍔 Comida",
        .groceries: "🛒 Supermercado",
        .utilities: "💡 Servicios",
        .transport: "🚗 Transporte",
        .shopping: "🛍️ Compras",
        .clothing: "👕 Ropa",
        .goingOut: "🍻 Salir",
        .entertainment: "🎬 Entretenimiento",
        .subscriptions: "📺 Suscripciones",
        .health: "💊 Salud",
        .education: "📚 Educación",
        .pets: "🐾 Mascotas",
        .gifts: "🎁 Regalos",
        .travel: "✈️ Viajes",
        .other: "🏷️ Otro",
    ]

    var transactionCategory: TransactionCategory? { TransactionCategory(rawValue: rawValue) }
}

/// "Anotar gasto rápido": pide el monto, la categoría y qué fue, y anota el
/// gasto SIN abrir MonAvi. Pensado para Tocar atrás (doble toque, funciona
/// hasta con la pantalla bloqueada), el botón de Acción o un widget de
/// Atajos. La sesion se lee del Keychain (disponible tras el primer
/// desbloqueo), asi que no hace falta abrir la app.
struct QuickExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Anotar gasto rápido"
    static var description = IntentDescription(
        "Te pide el monto, la categoría y qué fue, y anota el gasto en MonAvi sin abrir la app. Ideal para el doble toque atrás del iPhone."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Monto", requestValueDialog: IntentDialog("Ingresa el monto"))
    var amount: Double

    @Parameter(title: "Categoría", requestValueDialog: IntentDialog("¿En qué categoría?"))
    var category: QuickExpenseCategory

    @Parameter(title: "Qué fue", requestValueDialog: IntentDialog("¿Qué fue? (ej. Almuerzo)"))
    var note: String

    @Parameter(title: "Cuenta (opcional)")
    var account: MonAviAccountEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Anotar \(\.$amount) en \(\.$category)") {
            \.$note
            \.$account
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let supabase = SupabaseManager.shared.client
        guard let session = try? await supabase.auth.session else {
            return .result(dialog: "Abre MonAvi e inicia sesión primero.")
        }
        guard amount > 0 else {
            return .result(dialog: "El monto tiene que ser mayor que cero.")
        }
        let userId = session.user.id

        let accountId: UUID
        if let account {
            accountId = account.id
        } else {
            // La primera cuenta de uso diario (no tarjeta, prestamo ni ahorro);
            // si no hay, la primera que exista.
            struct Row: Decodable { let id: UUID; let type: String }
            let rows: [Row] = (try? await supabase
                .from("accounts")
                .select("id, type")
                .eq("user_id", value: userId)
                .order("created_at", ascending: true)
                .execute()
                .value) ?? []
            let everyday = rows.first { !["credit_card", "loan", "savings", "investment"].contains($0.type) }
            guard let first = (everyday ?? rows.first)?.id else {
                return .result(dialog: "Crea al menos una cuenta en MonAvi antes de anotar con el atajo.")
            }
            accountId = first
        }

        let description = note.trimmingCharacters(in: .whitespacesAndNewlines)
        try await TransactionsRepository.shared.add(
            NewTransaction(
                userId: userId,
                accountId: accountId,
                amount: MovementType.gasto.signedAmount(from: Decimal(amount)),
                movementType: .gasto,
                category: category.rawValue,
                description: description.isEmpty ? nil : description,
                occurredAt: Date()
            )
        )

        let label = category.transactionCategory.map { "\($0.emoji) \($0.rawValue)" } ?? category.rawValue
        let what = description.isEmpty ? "" : " (\(description))"
        return .result(dialog: "Anotado: \(amount.formatted(.currency(code: "USD"))) en \(label)\(what).")
    }
}
