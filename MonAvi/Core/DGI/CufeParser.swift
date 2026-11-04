import Foundation

/// Modulo "Facturas que suman": parseo y validacion del QR de una factura
/// electronica panameña, sin tocar red ni base de datos — solo texto
/// entrando, resultado saliendo. Separado a proposito del resto de la app
/// para poder probarlo con fixtures reales sin depender de Supabase.
///
/// Acepta dos formas de URL que emite la DGI:
/// 1. `https://dgi-fep.mef.gob.pa/Consultas/FacturasPorQR?chFE=...&iAmb=...&digestValue=...&jwt=...`
///    (el QR estandar — valida los 4 parametros entre si).
/// 2. `https://dgi-fep.mef.gob.pa/Consultas/FacturasPorCUFE/<CUFE>`
///    (link corto impreso en algunos recibos — solo trae el CUFE, se
///    valida la estructura y el ambiente embebido en el mismo CUFE).
enum DgiUrlParseError: Error, Equatable {
    /// La URL no es del dominio/ruta de la DGI (QR de otro sitio).
    case notDgiHost
    /// Faltan parametros en la query (chFE/iAmb/digestValue/jwt) o el
    /// CUFE del link corto viene vacio.
    case missingParams
    /// iAmb (o el ambiente embebido en el CUFE del link corto) no es "1"
    /// — es un QR de pruebas, nunca se debe aceptar como factura real.
    case notProduction
    /// El CUFE no mide exactamente 66 caracteres.
    case cufeWrongLength
    /// El CUFE no empieza con "FE".
    case cufeBadPrefix
    /// Alguno de los separadores/campos fijos del CUFE no calza (ej. el
    /// guion despues del RUC, o el digito de ambiente no es numerico).
    case cufeMalformed
    /// El ambiente embebido en el CUFE no coincide con el iAmb de la URL.
    case ambienteMismatch
    /// El JWT no tiene 3 partes separadas por "." o su payload no es
    /// JSON valido una vez decodificado.
    case jwtMalformed
    /// El payload del JWT (chFE/iAmb/digestValue) no coincide con los
    /// mismos valores en la URL — posible QR alterado a mano.
    case jwtFieldMismatch
}

/// Los campos que trae embebidos el CUFE en posiciones fijas (ver Ficha
/// Tecnica de Factura Electronica de la DGI). `ruc` ya viene sin los
/// ceros de relleno a la izquierda.
struct CufeFields: Equatable {
    let tipoDoc: String
    let tipoContribuyente: String
    let ruc: String
    let dv: String
    let sucursal: String
    /// "yyyy-MM-dd", calculado de los 8 digitos AAAAMMDD del CUFE.
    let fechaISO: String
    let numeroDocumento: String
    let puntoFacturacion: String
    let tipoEmision: String
    let ambiente: String
    let numeroSeguridad: String
    let digitoVerificador: String
}

/// Resultado completo de parsear un QR/link de la DGI ya validado.
/// `digestValue`/`jwt` son nil cuando vino del link corto
/// (`FacturasPorCUFE/<CUFE>`, que no los trae).
struct ParsedDgiReceipt: Equatable {
    let cufe: String
    let iAmb: String
    let digestValue: String?
    let jwt: String?
    let fields: CufeFields
}

enum CufeParser {
    static let dgiHost = "dgi-fep.mef.gob.pa"
    static let qrPath = "/Consultas/FacturasPorQR"
    static let cufePathPrefix = "/Consultas/FacturasPorCUFE/"

    private static let cufeLength = 66

    /// Posiciones fijas del CUFE, EN ORDEN. Si la DGI actualiza la Ficha
    /// Tecnica, este es el unico lugar que hay que tocar — el resto del
    /// parser solo recorre esta tabla.
    private static let fieldSpecs: [(name: String, length: Int)] = [
        ("prefix", 2),              // "FE"
        ("tipoDoc", 2),
        ("tipoContribuyente", 1),
        ("rucPadded", 20),
        ("dash", 1),                // literal "-"
        ("dv", 2),
        ("sucursal", 4),
        ("fecha", 8),                // AAAAMMDD
        ("numeroDocumento", 10),
        ("puntoFacturacion", 3),
        ("tipoEmision", 2),
        ("ambiente", 1),
        ("numeroSeguridad", 9),
        ("digitoVerificador", 1),
    ]

    static func parse(_ raw: String) -> Result<ParsedDgiReceipt, DgiUrlParseError> {
        guard let url = URL(string: raw), url.scheme == "https", url.host == dgiHost else {
            return .failure(.notDgiHost)
        }

        if url.path == qrPath {
            return parseQrForm(url: url)
        }
        if url.path.hasPrefix(cufePathPrefix) {
            let cufe = String(url.path.dropFirst(cufePathPrefix.count))
            return parseShortForm(cufe: cufe)
        }
        return .failure(.notDgiHost)
    }

    /// Parsea la query a mano (sin `URLComponents.queryItems`) para
    /// controlar exactamente la decodificacion: solo porcentaje (%XX),
    /// NUNCA "+" -> espacio (esa es una convencion de
    /// application/x-www-form-urlencoded que NO aplica aqui — el "+"
    /// real que trae `digestValue` en base64 se tiene que quedar como
    /// "+", nunca convertirse en un espacio).
    private static func rawQueryPairs(_ query: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in query.split(separator: "&", omittingEmptySubsequences: true) {
            guard let eqIndex = pair.firstIndex(of: "=") else { continue }
            let key = String(pair[pair.startIndex..<eqIndex])
            let value = String(pair[pair.index(after: eqIndex)...])
            result[key.removingPercentEncoding ?? key] = value.removingPercentEncoding ?? value
        }
        return result
    }

    private static func parseQrForm(url: URL) -> Result<ParsedDgiReceipt, DgiUrlParseError> {
        guard let query = url.query else { return .failure(.missingParams) }
        let params = rawQueryPairs(query)
        guard
            let cufe = params["chFE"], !cufe.isEmpty,
            let iAmb = params["iAmb"], !iAmb.isEmpty,
            let digestValue = params["digestValue"], !digestValue.isEmpty,
            let jwt = params["jwt"], !jwt.isEmpty
        else {
            return .failure(.missingParams)
        }

        guard iAmb == "1" else { return .failure(.notProduction) }

        let fields: CufeFields
        switch parseCufeFields(cufe) {
        case .success(let value): fields = value
        case .failure(let error): return .failure(error)
        }
        guard fields.ambiente == iAmb else { return .failure(.ambienteMismatch) }

        guard let payload = decodeJwtPayload(jwt) else { return .failure(.jwtMalformed) }
        guard
            payload["chFE"] as? String == cufe,
            payload["iAmb"] as? String == iAmb,
            payload["digestValue"] as? String == digestValue
        else {
            return .failure(.jwtFieldMismatch)
        }

        return .success(ParsedDgiReceipt(cufe: cufe, iAmb: iAmb, digestValue: digestValue, jwt: jwt, fields: fields))
    }

    private static func parseShortForm(cufe: String) -> Result<ParsedDgiReceipt, DgiUrlParseError> {
        guard !cufe.isEmpty else { return .failure(.missingParams) }
        let fields: CufeFields
        switch parseCufeFields(cufe) {
        case .success(let value): fields = value
        case .failure(let error): return .failure(error)
        }
        guard fields.ambiente == "1" else { return .failure(.notProduction) }
        return .success(ParsedDgiReceipt(cufe: cufe, iAmb: fields.ambiente, digestValue: nil, jwt: nil, fields: fields))
    }

    static func parseCufeFields(_ cufe: String) -> Result<CufeFields, DgiUrlParseError> {
        guard cufe.count == cufeLength else { return .failure(.cufeWrongLength) }
        guard cufe.hasPrefix("FE") else { return .failure(.cufeBadPrefix) }

        var values: [String: String] = [:]
        var index = cufe.startIndex
        for spec in fieldSpecs {
            guard let end = cufe.index(index, offsetBy: spec.length, limitedBy: cufe.endIndex) else {
                return .failure(.cufeMalformed)
            }
            values[spec.name] = String(cufe[index..<end])
            index = end
        }

        guard values["dash"] == "-" else { return .failure(.cufeMalformed) }
        guard let ambiente = values["ambiente"], ambiente.allSatisfy(\.isNumber), ambiente.count == 1 else {
            return .failure(.cufeMalformed)
        }

        let rucPadded = values["rucPadded"] ?? ""
        let ruc = String(rucPadded.drop { $0 == "0" })

        let fecha = values["fecha"] ?? ""
        guard fecha.count == 8, fecha.allSatisfy(\.isNumber) else { return .failure(.cufeMalformed) }
        let fechaISO = "\(fecha.prefix(4))-\(fecha.dropFirst(4).prefix(2))-\(fecha.suffix(2))"

        return .success(CufeFields(
            tipoDoc: values["tipoDoc"] ?? "",
            tipoContribuyente: values["tipoContribuyente"] ?? "",
            ruc: ruc,
            dv: values["dv"] ?? "",
            sucursal: values["sucursal"] ?? "",
            fechaISO: fechaISO,
            numeroDocumento: values["numeroDocumento"] ?? "",
            puntoFacturacion: values["puntoFacturacion"] ?? "",
            tipoEmision: values["tipoEmision"] ?? "",
            ambiente: ambiente,
            numeroSeguridad: values["numeroSeguridad"] ?? "",
            digitoVerificador: values["digitoVerificador"] ?? ""
        ))
    }

    /// Decodifica (sin verificar firma — no tenemos la clave del PAC) el
    /// payload del JWT HS256. Solo se usa para comparar sus campos
    /// contra los de la URL, nunca para confiar en el JWT por si solo.
    private static func decodeJwtPayload(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        guard let data = base64UrlDecode(String(parts[1])) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func base64UrlDecode(_ segment: String) -> Data? {
        var base64 = segment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}
