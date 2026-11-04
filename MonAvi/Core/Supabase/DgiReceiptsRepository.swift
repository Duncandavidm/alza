import Foundation
import Supabase

/// Se guarda aparte de un Error generico para que la UI pueda mostrar un
/// mensaje especifico ("esta factura ya fue registrada") en vez del
/// texto crudo del error de Postgres.
enum DgiReceiptError: LocalizedError {
    case alreadyScanned

    var errorDescription: String? {
        switch self {
        case .alreadyScanned:
            return "Esta factura ya fue registrada (por ti o por otra cuenta)."
        }
    }
}

/// Datos de "Facturas que suman": escaneo, lista, y el candidato a
/// fusion cuando ya existe un gasto parecido (misma fecha, monto
/// similar) para no duplicar el movimiento.
@MainActor
final class DgiReceiptsRepository {
    static let shared = DgiReceiptsRepository()
    private let supabase = SupabaseManager.shared.client
    private init() {}

    func fetchAll(userId: UUID) async throws -> [DgiReceipt] {
        try await supabase
            .from("dgi_receipts")
            .select()
            .eq("user_id", value: userId)
            .order("scanned_at", ascending: false)
            .execute()
            .value
    }

    func merchant(forRUC ruc: String) async -> Merchant? {
        try? await supabase
            .from("merchants")
            .select()
            .eq("ruc", value: ruc)
            .maybeSingle()
            .execute()
            .value
    }

    /// true si TU cuenta ya escaneo este CUFE antes — util para avisar
    /// de una vez, sin esperar al error del insert. No detecta un CUFE
    /// ya usado por OTRO usuario (RLS no deja leer filas ajenas): ese
    /// caso lo atrapa la restriccion UNIQUE de la base al insertar (ver
    /// `add(_:)`).
    func isAlreadyScannedByMe(cufe: String, userId: UUID) async -> Bool {
        let existing: [DgiReceipt] = (try? await supabase
            .from("dgi_receipts")
            .select()
            .eq("user_id", value: userId)
            .eq("cufe", value: cufe)
            .execute()
            .value) ?? []
        return !existing.isEmpty
    }

    /// Candidato a fusionar en vez de duplicar: una transaccion del
    /// mismo dia con un monto parecido que todavia no esta vinculada a
    /// ningun otro escaneo. Se OFRECE al usuario, nunca se fusiona sola.
    func duplicateCandidate(userId: UUID, date: Date, amount: Decimal, tolerance: Decimal = 0.5) async -> FinanceTransaction? {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }

        guard
            let candidates: [FinanceTransaction] = try? await supabase
                .from("transactions")
                .select()
                .eq("user_id", value: userId)
                .gte("occurred_at", value: start)
                .lt("occurred_at", value: end)
                .execute()
                .value
        else { return nil }

        let existingReceipts = (try? await fetchAll(userId: userId)) ?? []
        let linkedIds = Set(existingReceipts.compactMap(\.transactionId))

        return candidates.first {
            !linkedIds.contains($0.id) && abs(abs($0.amount) - amount) <= tolerance
        }
    }

    /// NOTA: `error.localizedDescription.contains("duplicate")` es un
    /// heuristico de respaldo, no un match tipado contra el codigo
    /// 23505 de Postgres — no se pudo verificar en este entorno el
    /// nombre/forma exacta del tipo de error que lanza supabase-swift
    /// (no hay compilador Swift aqui). Revisar cuando compiles: si
    /// `supabase-swift` expone `PostgrestError.code`, cambiar esto por
    /// un `catch let error as PostgrestError where error.code == "23505"`
    /// tipado, que es mas confiable que un contains() sobre texto.
    @discardableResult
    func add(_ new: NewDgiReceipt) async throws -> DgiReceipt {
        do {
            return try await supabase
                .from("dgi_receipts")
                .insert(new)
                .select()
                .single()
                .execute()
                .value
        } catch {
            if error.localizedDescription.lowercased().contains("duplicate")
                || error.localizedDescription.contains("23505") {
                throw DgiReceiptError.alreadyScanned
            }
            throw error
        }
    }

    func delete(_ receipt: DgiReceipt) async throws {
        try await supabase.from("dgi_receipts").delete().eq("id", value: receipt.id).execute()
    }
}
