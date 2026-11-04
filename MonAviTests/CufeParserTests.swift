import XCTest
@testable import MonAvi

final class CufeParserTests: XCTestCase {
    /// Factura real de prueba (dada por David, verificada contra un QR
    /// real de la DGI) — el fixture canonico de este modulo.
    private let realURL = "https://dgi-fep.mef.gob.pa/Consultas/FacturasPorQR?chFE=FE0120000155719930-2-2022-6100022026110416079758690020316384200653&iAmb=1&digestValue=q+bMOXEF4T3AxQLH3qptmAlG5jwsF/pnrexgeK+mpPk=&jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJjaEZFIjoiRkUwMTIwMDAwMTU1NzE5OTMwLTItMjAyMi02MTAwMDIyMDI2MTEwNDE2MDc5NzU4NjkwMDIwMzE2Mzg0MjAwNjUzIiwiaUFtYiI6IjEiLCJkaWdlc3RWYWx1ZSI6InErYk1PWEVGNFQzQXhRTEgzcXB0bUFsRzVqd3NGL3BucmV4Z2VLK21wUGs9In0.5PHVyDKJtdGzC3f2kIIDRSG6eza88dGiF_nNtLmSs6I"

    func testFixtureReal() throws {
        let result = try CufeParser.parse(realURL).get()

        XCTAssertEqual(result.fields.tipoDoc, "01")
        XCTAssertEqual(result.fields.tipoContribuyente, "2")
        XCTAssertEqual(result.fields.ruc, "155719930-2-2022")
        XCTAssertEqual(result.fields.dv, "61")
        XCTAssertEqual(result.fields.sucursal, "0002")
        XCTAssertEqual(result.fields.fechaISO, "2026-11-04")
        XCTAssertEqual(result.fields.numeroDocumento, "1607975869")
        XCTAssertEqual(result.fields.ambiente, "1")
        XCTAssertEqual(result.digestValue, "q+bMOXEF4T3AxQLH3qptmAlG5jwsF/pnrexgeK+mpPk=")
    }

    func testPlusEnDigestValueNoSeVuelveEspacio() throws {
        let result = try CufeParser.parse(realURL).get()
        let digest = try XCTUnwrap(result.digestValue)
        XCTAssertTrue(digest.contains("+"), "el + se perdio (se convirtio en espacio u otra cosa): \(digest)")
        XCTAssertFalse(digest.contains(" "), "el digestValue no deberia tener espacios")
    }

    func testSitioDistintoALaDGI() {
        let url = realURL.replacingOccurrences(of: "dgi-fep.mef.gob.pa", with: "evil.example.com")
        let result = CufeParser.parse(url)
        XCTAssertEqual(result, .failure(.notDgiHost))
    }

    func testAmbienteDePruebasRechazado() {
        let url = realURL.replacingOccurrences(of: "iAmb=1", with: "iAmb=2")
        let result = CufeParser.parse(url)
        XCTAssertEqual(result, .failure(.notProduction))
    }

    func testJwtQueNoCoincideConLaURL() {
        let url = realURL.replacingOccurrences(
            of: "digestValue=q+bMOXEF4T3AxQLH3qptmAlG5jwsF/pnrexgeK+mpPk=",
            with: "digestValue=XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX="
        )
        let result = CufeParser.parse(url)
        XCTAssertEqual(result, .failure(.jwtFieldMismatch))
    }

    func testCufeDeLongitudIncorrecta() {
        let url = realURL.replacingOccurrences(
            of: "chFE=FE0120000155719930-2-2022-6100022026110416079758690020316384200653",
            with: "chFE=FE012000015571993"
        )
        let result = CufeParser.parse(url)
        XCTAssertEqual(result, .failure(.cufeWrongLength))
    }

    func testFaltaUnParametro() {
        let url = realURL.replacingOccurrences(of: "&jwt=", with: "&otraCosa=")
        let result = CufeParser.parse(url)
        XCTAssertEqual(result, .failure(.missingParams))
    }

    func testLinkCortoFacturasPorCUFE() throws {
        let url = "https://dgi-fep.mef.gob.pa/Consultas/FacturasPorCUFE/FE0120000155719930-2-2022-6100022026110416079758690020316384200653"
        let result = try CufeParser.parse(url).get()
        XCTAssertEqual(result.fields.ruc, "155719930-2-2022")
        XCTAssertNil(result.digestValue)
        XCTAssertNil(result.jwt)
    }

    func testLinkCortoConAmbienteDePruebasEmbebidoRechazado() {
        // Mismo CUFE del fixture pero con el digito de ambiente (posicion
        // fija 53, 0-indexed) cambiado de "1" a "2".
        var cufe = Array("FE0120000155719930-2-2022-6100022026110416079758690020316384200653")
        let ambienteIndex = 2 + 2 + 1 + 20 + 1 + 2 + 4 + 8 + 10 + 3 + 2 // 55
        XCTAssertEqual(cufe[ambienteIndex], "1")
        cufe[ambienteIndex] = "2"
        let url = "https://dgi-fep.mef.gob.pa/Consultas/FacturasPorCUFE/\(String(cufe))"
        let result = CufeParser.parse(url)
        XCTAssertEqual(result, .failure(.notProduction))
    }
}
