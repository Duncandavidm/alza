import Foundation
import Supabase

/// Texto claro por cada motivo de rechazo del parser — nunca un error
/// tecnico crudo en pantalla.
extension DgiUrlParseError {
    var userMessage: String {
        switch self {
        case .notDgiHost:
            return "Ese código no es de una factura electrónica."
        case .missingParams:
            return "El código QR está incompleto."
        case .notProduction:
            return "Ese código es de ambiente de pruebas, no de una factura real."
        case .cufeWrongLength, .cufeBadPrefix, .cufeMalformed:
            return "El código de la factura (CUFE) no tiene el formato esperado."
        case .ambienteMismatch, .jwtFieldMismatch:
            return "Los datos del código QR no coinciden entre sí — podría estar alterado."
        case .jwtMalformed:
            return "No se pudo leer la firma del código QR."
        }
    }
}

/// Lo que se arma despues de escanear y validar, antes de guardarlo —
/// el usuario todavia tiene que confirmar/editar el monto y la cuenta.
/// `id` = el CUFE: es el identificador real y unico de esta factura, asi
/// que sirve tal cual para `.sheet(item:)`.
struct ScanDraft: Identifiable {
    let parsed: ParsedDgiReceipt
    var merchant: Merchant?
    var amountText: String = ""
    var category: TransactionCategory?
    var mergeCandidate: FinanceTransaction?
    var mergeWithCandidate: Bool = true

    var id: String { parsed.cufe }
}

@MainActor
final class DgiReceiptsViewModel: ObservableObject {
    @Published private(set) var receipts: [DgiReceipt] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasConsented: Bool?
    @Published var errorMessage: String?

    private let repository = DgiReceiptsRepository.shared
    private let supabase = SupabaseManager.shared.client

    func refresh(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        async let consentTask = fetchConsent(userId: userId)
        async let receiptsTask: [DgiReceipt] = (try? await repository.fetchAll(userId: userId)) ?? []

        hasConsented = await consentTask
        receipts = await receiptsTask
    }

    private func fetchConsent(userId: UUID) async -> Bool {
        struct Row: Decodable {
            let dgiScanConsentAt: Date?
            enum CodingKeys: String, CodingKey { case dgiScanConsentAt = "dgi_scan_consent_at" }
        }
        guard
            let row: Row = try? await supabase
                .from("profiles")
                .select("dgi_scan_consent_at")
                .eq("id", value: userId)
                .single()
                .execute()
                .value
        else { return false }
        return row.dgiScanConsentAt != nil
    }

    func giveConsent(userId: UUID) async {
        struct Update: Encodable {
            let dgiScanConsentAt: Date
            enum CodingKeys: String, CodingKey { case dgiScanConsentAt = "dgi_scan_consent_at" }
        }
        do {
            try await supabase
                .from("profiles")
                .update(Update(dgiScanConsentAt: Date()))
                .eq("id", value: userId)
                .execute()
            hasConsented = true
        } catch {
            errorMessage = "No se pudo guardar tu confirmación: \(error.localizedDescription)"
        }
    }

    enum ScanProcessResult {
        case invalid(String)
        case ready(ScanDraft)
    }

    /// Todo lo que pasa ENTRE escanear y mostrar la pantalla de revision:
    /// parseo, validaciones de frescura/duplicado propio, y el intento de
    /// autocompletar comercio/categoria por RUC. Nunca toca la DGI real
    /// (eso es Fase 2).
    func processScan(raw: String, userId: UUID) async -> ScanProcessResult {
        let parsed: ParsedDgiReceipt
        switch CufeParser.parse(raw) {
        case .success(let value):
            parsed = value
        case .failure(let error):
            return .invalid(error.userMessage)
        }

        switch DgiReceiptValidation.checkFreshness(fechaISO: parsed.fields.fechaISO) {
        case .future:
            return .invalid("Esta factura tiene fecha futura — revisa que sea el código correcto.")
        case .tooOld:
            return .invalid("Esta factura tiene más de \(DgiReceiptValidation.maxDaysInPast) días — ya no se puede registrar por este medio.")
        case .invalidDate:
            return .invalid("No se pudo leer la fecha de la factura.")
        case .ok:
            break
        }

        if await repository.isAlreadyScannedByMe(cufe: parsed.cufe, userId: userId) {
            return .invalid("Ya escaneaste esta factura antes.")
        }

        let merchant = await repository.merchant(forRUC: parsed.fields.ruc)
        var draft = ScanDraft(parsed: parsed, merchant: merchant)
        if let categoryRaw = merchant?.category {
            draft.category = TransactionCategory(rawValue: categoryRaw)
        }
        return .ready(draft)
    }

    /// Se llama cuando el usuario ya escribio un monto, para ofrecer
    /// fusionar en vez de duplicar si hay algo parecido ese mismo dia.
    func mergeCandidate(for draft: ScanDraft, userId: UUID, amount: Decimal) async -> FinanceTransaction? {
        await repository.duplicateCandidate(
            userId: userId,
            date: draft.parsed.fields.fechaISODate,
            amount: amount
        )
    }

    /// Guarda el escaneo: fusiona con `mergeCandidate` si el usuario lo
    /// acepto, o crea un gasto nuevo. Siempre crea la fila de
    /// `dgi_receipts` como 'pendiente'.
    func confirmScan(
        draft: ScanDraft,
        userId: UUID,
        accountId: UUID,
        amount: Decimal
    ) async throws {
        let transactionId: UUID
        if draft.mergeWithCandidate, let candidate = draft.mergeCandidate {
            transactionId = candidate.id
        } else {
            let merchantName = draft.merchant?.name
            let created = try await TransactionsRepository.shared.add(
                NewTransaction(
                    userId: userId,
                    accountId: accountId,
                    amount: MovementType.gasto.signedAmount(from: amount),
                    movementType: .gasto,
                    category: draft.category?.rawValue,
                    description: merchantName ?? "Factura \(draft.parsed.fields.ruc)",
                    occurredAt: draft.parsed.fields.fechaISODate
                )
            )
            transactionId = created.id
        }

        try await repository.add(
            NewDgiReceipt(
                userId: userId,
                transactionId: transactionId,
                merchantId: draft.merchant?.id,
                parsed: draft.parsed
            )
        )

        receipts = (try? await repository.fetchAll(userId: userId)) ?? receipts
    }

    func delete(_ receipt: DgiReceipt) async {
        do {
            try await repository.delete(receipt)
            receipts.removeAll { $0.id == receipt.id }
        } catch {
            errorMessage = "No se pudo borrar: \(error.localizedDescription)"
        }
    }
}

private extension CufeFields {
    var fechaISODate: Date {
        DgiReceiptDateFormat.date(from: fechaISO)
    }
}
