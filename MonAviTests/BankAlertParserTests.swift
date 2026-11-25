import XCTest
@testable import MonAvi

/// Avisos del banco (Atajos: Notificación, Mensaje o Correo) → movimiento
/// por confirmar. Mismos casos que el prototipo con que se armaron las reglas.
final class BankAlertParserTests: XCTestCase {
    private func assertParsed(
        _ text: String, amount: Decimal, income: Bool, counterpart: String?, last4: String?,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard let parsed = BankAlertParser.parse(text) else {
            return XCTFail("No se leyó: \(text)", file: file, line: line)
        }
        XCTAssertEqual(parsed.amount, amount, file: file, line: line)
        XCTAssertEqual(parsed.isIncome, income, file: file, line: line)
        XCTAssertEqual(parsed.counterpart, counterpart, file: file, line: line)
        XCTAssertEqual(parsed.last4, last4, file: file, line: line)
    }

    func testCompraConTarjeta() {
        assertParsed("Banco General: Compra por B/.12.40 en CAFE LA ESQUINA con tarjeta terminada en 4021 el 24/11 10:32.",
                     amount: Decimal(string: "12.40")!, income: false, counterpart: "Cafe La Esquina", last4: "4021")
        assertParsed("BAC: Se realizó un consumo de USD 86.20 en SUPER 99 VIA ESPANA con su tarjeta ****1234.",
                     amount: Decimal(string: "86.20")!, income: false, counterpart: "Super 99 Via Espana", last4: "1234")
        assertParsed("Comercio: AMAZON MKTPLACE, monto 23.99 USD, tarjeta xxxx9876",
                     amount: Decimal(string: "23.99")!, income: false, counterpart: "Amazon Mktplace", last4: "9876")
        assertParsed("Compra aprobada: $9.50, Heladeria Brisa. Tarjeta final 4021",
                     amount: Decimal(string: "9.50")!, income: false, counterpart: nil, last4: "4021")
    }

    func testPagosYRetiros() {
        assertParsed("Pagaste $15.75 a Farmacia Arrocha con Yappy",
                     amount: Decimal(string: "15.75")!, income: false, counterpart: "Farmacia Arrocha", last4: nil)
        assertParsed("Retiro en cajero por B/. 100.00 tarjeta *5678",
                     amount: 100, income: false, counterpart: nil, last4: "5678")
        assertParsed("Se debitó B/.30.00 de tu cuenta por pago de Luz ENSA",
                     amount: 30, income: false, counterpart: nil, last4: nil)
    }

    func testIngresos() {
        assertParsed("Te enviaron $800.000. Entra a tu app y revisa tu saldo.",
                     amount: 800_000, income: true, counterpart: nil, last4: nil)
        assertParsed("Recibiste $25.00 de Juan Perez por Yappy",
                     amount: 25, income: true, counterpart: "Juan Perez", last4: nil)
        assertParsed("Depósito de $1,250.00 acreditado a su cuenta ...4321",
                     amount: 1250, income: true, counterpart: nil, last4: "4321")
        assertParsed("Te enviaron plata por Bre-B: $45.000 de Maria Lopez",
                     amount: 45_000, income: true, counterpart: "Maria Lopez", last4: nil)
    }

    func testIgnoraLoQueNoEsUnMovimiento() {
        XCTAssertNil(BankAlertParser.parse("Tu código de verificación es 123456. No lo compartas."))
        XCTAssertNil(BankAlertParser.parse("Transacción rechazada por $50.00 en AMAZON"))
        XCTAssertNil(BankAlertParser.parse("Gana $50 en tu próxima compra con nuestra promo"))
        XCTAssertNil(BankAlertParser.parse("Ingresaste a tu Banca en Línea el 24/11."))
        XCTAssertNil(BankAlertParser.parse("Tu tarjeta 4021 vence pronto"))
        XCTAssertNil(BankAlertParser.parse(""))
    }

    func testNumeros() {
        XCTAssertEqual(BankAlertParser.parseNumber("1,250.00"), 1250)
        XCTAssertEqual(BankAlertParser.parseNumber("800.000"), 800_000)
        XCTAssertEqual(BankAlertParser.parseNumber("12,40"), Decimal(string: "12.40"))
        XCTAssertEqual(BankAlertParser.parseNumber("12.4"), Decimal(string: "12.4"))
        XCTAssertEqual(BankAlertParser.parseNumber("1.234.567,89"), Decimal(string: "1234567.89"))
    }

    func testTextoDeLaNotificacion() {
        let movement = DetectedMovement(id: UUID(), amount: Decimal(string: "12.40")!, isIncome: false,
                                        counterpart: "Café La Esquina", last4: "4021", source: nil,
                                        detectedAt: Date(), possibleDuplicate: false)
        XCTAssertTrue(movement.notificationBody.hasPrefix("Compra de "))
        XCTAssertTrue(movement.notificationBody.hasSuffix(" en Café La Esquina (•4021)."))
        XCTAssertEqual(movement.signedAmount, Decimal(string: "-12.40"))
    }
}
