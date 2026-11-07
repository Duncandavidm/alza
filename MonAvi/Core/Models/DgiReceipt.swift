import Foundation

enum DgiReceiptStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case pendiente
    case confirmada
    case rechazada
    case expirada

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pendiente: return "Pendiente"
        case .confirmada: return "Confirmada"
        case .rechazada: return "Rechazada"
        case .expirada: return "Expirada"
        }
    }

    /// Texto claro para la lista — nunca dejar al usuario adivinando que
    /// significa el estado o cuanto tiene que esperar.
    var statusExplanation: String {
        switch self {
        case .pendiente: return "Pendiente: la revisamos contra la DGI varias veces al día."
        case .confirmada: return "Confirmada por la DGI — cashback acreditado."
        case .rechazada: return "Rechazada — el código no es válido o ya fue usado por otra cuenta."
        case .expirada: return "La DGI no la reconoció a tiempo. El gasto queda registrado, sin cashback."
        }
    }
}

/// Formato de la columna `fecha_factura` (Postgres `date`, sin hora):
/// mismo patron que BillDateFormat/InvoiceDateFormat — se maneja como
/// String de punta a punta.
enum DgiReceiptDateFormat {
    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from string: String) -> Date {
        formatter.date(from: string) ?? Date()
    }
}

/// Una factura electronica panameña escaneada por QR — "factura
/// RECIBIDA" (compra/gasto del usuario), distinta de `Invoice` (facturas
/// que el usuario EMITE a sus clientes) y de `Bill` (cuenta por pagar
/// programada a mano). Ver `MonAvi/Core/DGI/CufeParser.swift` para el
/// parseo del QR y `supabase/migrations/0022_dgi_receipts.sql` para el
/// esquema completo.
struct DgiReceipt: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    var transactionId: UUID?
    var merchantId: UUID?

    let cufe: String
    let iAmb: String
    let digestValue: String?
    let jwt: String?

    let tipoDoc: String
    let tipoContribuyente: String
    let ruc: String
    let dv: String
    let sucursal: String
    let fechaFactura: String
    let numeroDocumento: String
    let puntoFacturacion: String
    let tipoEmision: String
    let numeroSeguridad: String
    let digitoVerificador: String

    var status: DgiReceiptStatus
    var confirmedAmount: Decimal?
    /// Forma de pago que reporto la propia factura DGI (ej. "Tarjeta
    /// Crédito") — nil hasta que se confirma. Si incluye "tarjeta", ya
    /// se evaluo el bono de comercio aliado (ver verify-dgi-receipt).
    var paymentMethod: String?
    /// Nombre del comercio segun la DGI (migracion 0031) — nil hasta que
    /// el verificador lo llena.
    var merchantName: String?
    /// Fecha y hora real de la compra (autorizacion DGI), si se conoce.
    var authorizedAt: Date?

    let scannedAt: Date
    var dgiCheckedAt: Date?
    var dgiCheckCount: Int

    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case transactionId = "transaction_id"
        case merchantId = "merchant_id"
        case cufe
        case iAmb = "i_amb"
        case digestValue = "digest_value"
        case jwt
        case tipoDoc = "tipo_doc"
        case tipoContribuyente = "tipo_contribuyente"
        case ruc
        case dv
        case sucursal
        case fechaFactura = "fecha_factura"
        case numeroDocumento = "numero_documento"
        case puntoFacturacion = "punto_facturacion"
        case tipoEmision = "tipo_emision"
        case numeroSeguridad = "numero_seguridad"
        case digitoVerificador = "digito_verificador"
        case status
        case confirmedAmount = "confirmed_amount"
        case paymentMethod = "payment_method"
        case merchantName = "merchant_name"
        case authorizedAt = "authorized_at"
        case scannedAt = "scanned_at"
        case dgiCheckedAt = "dgi_checked_at"
        case dgiCheckCount = "dgi_check_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var fechaFacturaValue: Date { DgiReceiptDateFormat.date(from: fechaFactura) }

    /// Titulo para la lista: el nombre del comercio si ya lo tenemos;
    /// si no, el RUC.
    var displayTitle: String {
        if let name = merchantName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return "RUC \(ruc)"
    }

    var hasMerchantName: Bool {
        guard let name = merchantName?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !name.isEmpty
    }
}

struct NewDgiReceipt: Encodable {
    let userId: UUID
    var transactionId: UUID?
    var merchantId: UUID?

    let cufe: String
    let iAmb: String
    let digestValue: String?
    let jwt: String?

    let tipoDoc: String
    let tipoContribuyente: String
    let ruc: String
    let dv: String
    let sucursal: String
    let fechaFactura: String
    let numeroDocumento: String
    let puntoFacturacion: String
    let tipoEmision: String
    let numeroSeguridad: String
    let digitoVerificador: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case transactionId = "transaction_id"
        case merchantId = "merchant_id"
        case cufe
        case iAmb = "i_amb"
        case digestValue = "digest_value"
        case jwt
        case tipoDoc = "tipo_doc"
        case tipoContribuyente = "tipo_contribuyente"
        case ruc
        case dv
        case sucursal
        case fechaFactura = "fecha_factura"
        case numeroDocumento = "numero_documento"
        case puntoFacturacion = "punto_facturacion"
        case tipoEmision = "tipo_emision"
        case numeroSeguridad = "numero_seguridad"
        case digitoVerificador = "digito_verificador"
    }

    /// `status` no se manda — la columna cae en su default `'pendiente'`
    /// (y la policy de insert exige exactamente eso), para que el
    /// cliente nunca pueda insertar una factura ya "confirmada".
    init(
        userId: UUID,
        transactionId: UUID? = nil,
        merchantId: UUID? = nil,
        parsed: ParsedDgiReceipt
    ) {
        self.userId = userId
        self.transactionId = transactionId
        self.merchantId = merchantId
        self.cufe = parsed.cufe
        self.iAmb = parsed.iAmb
        self.digestValue = parsed.digestValue
        self.jwt = parsed.jwt
        self.tipoDoc = parsed.fields.tipoDoc
        self.tipoContribuyente = parsed.fields.tipoContribuyente
        self.ruc = parsed.fields.ruc
        self.dv = parsed.fields.dv
        self.sucursal = parsed.fields.sucursal
        self.fechaFactura = parsed.fields.fechaISO
        self.numeroDocumento = parsed.fields.numeroDocumento
        self.puntoFacturacion = parsed.fields.puntoFacturacion
        self.tipoEmision = parsed.fields.tipoEmision
        self.numeroSeguridad = parsed.fields.numeroSeguridad
        self.digitoVerificador = parsed.fields.digitoVerificador
    }
}
