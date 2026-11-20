import XCTest
@testable import MonAvi

/// Interprete local de frases de voz simples: solo responde cuando esta
/// seguro; ante la duda devuelve nil y se usa la IA.
final class SimpleVoiceParserTests: XCTestCase {
    private func assertParsed(
        _ transcript: String,
        amount: Double,
        type: MovementType,
        description: String,
        category: String?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let parsed = SimpleVoiceParser.parse(transcript) else {
            XCTFail("Se esperaba un resultado para «\(transcript)»", file: file, line: line)
            return
        }
        XCTAssertEqual(parsed.amount, amount, accuracy: 0.001, transcript, file: file, line: line)
        XCTAssertEqual(parsed.movementType, type, transcript, file: file, line: line)
        XCTAssertEqual(parsed.description, description, transcript, file: file, line: line)
        XCTAssertEqual(parsed.category, category, transcript, file: file, line: line)
    }

    private func assertNil(_ transcript: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(SimpleVoiceParser.parse(transcript), "«\(transcript)» debería ir a la IA", file: file, line: line)
    }

    // MARK: - Gastos

    func testSpendWithDollars() {
        assertParsed("gasté 12 dólares en almuerzo", amount: 12, type: .gasto, description: "Almuerzo", category: "Comida")
    }

    func testSpendWithDollarSignAndNoAccent() {
        assertParsed("gaste $12 en almuerzo", amount: 12, type: .gasto, description: "Almuerzo", category: "Comida")
        assertParsed("Gasté 12$ en almuerzo.", amount: 12, type: .gasto, description: "Almuerzo", category: "Comida")
    }

    func testDecimalsWithDotOrComma() {
        assertParsed("pagué 45.50 de luz", amount: 45.5, type: .gasto, description: "Luz", category: "Servicios")
        assertParsed("pagué 45,50 de luz", amount: 45.5, type: .gasto, description: "Luz", category: "Servicios")
    }

    func testConceptBeforeAmount() {
        assertParsed("compré café por 3", amount: 3, type: .gasto, description: "Café", category: "Comida")
    }

    func testReflexiveSpendStripsArticle() {
        assertParsed("me gasté 20 en el super", amount: 20, type: .gasto, description: "Super", category: "Supermercado")
    }

    func testVerblessKnownConcept() {
        assertParsed("12 dólares de gasolina", amount: 12, type: .gasto, description: "Gasolina", category: "Transporte")
        assertParsed("almuerzo 8 dólares", amount: 8, type: .gasto, description: "Almuerzo", category: "Comida")
    }

    func testTimeWordsAreNotPartOfTheConcept() {
        assertParsed("hoy gasté 15 en taxi", amount: 15, type: .gasto, description: "Taxi", category: "Transporte")
    }

    func testLongerConceptKeepsWords() {
        assertParsed("gasté 30 en almuerzo con mi esposa", amount: 30, type: .gasto,
                     description: "Almuerzo con mi esposa", category: "Comida")
    }

    // MARK: - Ingresos

    func testIncomeWithConcept() {
        assertParsed("me pagaron 500 de salario", amount: 500, type: .ingreso, description: "Salario", category: "Ingreso")
        assertParsed("recibí 150 de un cliente", amount: 150, type: .ingreso, description: "Cliente", category: "Ingreso")
        assertParsed("ingreso de 300 por venta", amount: 300, type: .ingreso, description: "Venta", category: "Ingreso")
    }

    func testIncomeWithoutConceptUsesGenericDescription() {
        assertParsed("cobré 200", amount: 200, type: .ingreso, description: "Ingreso", category: "Ingreso")
        assertParsed("me depositaron 1000", amount: 1000, type: .ingreso, description: "Ingreso", category: "Ingreso")
        assertParsed("me depositaron 1,000", amount: 1000, type: .ingreso, description: "Ingreso", category: "Ingreso")
    }

    // MARK: - Numeros en palabras

    func testNumberWords() {
        assertParsed("gasté veinticinco en taxi", amount: 25, type: .gasto, description: "Taxi", category: "Transporte")
        assertParsed("gasté treinta y cinco dólares en gasolina", amount: 35, type: .gasto,
                     description: "Gasolina", category: "Transporte")
        assertParsed("pagué doscientos cincuenta de alquiler", amount: 250, type: .gasto,
                     description: "Alquiler", category: "Vivienda")
        assertParsed("me pagaron mil quinientos de salario", amount: 1500, type: .ingreso,
                     description: "Salario", category: "Ingreso")
        assertParsed("cobré cien de una venta", amount: 100, type: .ingreso, description: "Venta", category: "Ingreso")
    }

    func testNumericFormats() {
        XCTAssertEqual(SimpleVoiceParser.parseNumeric("12"), 12)
        XCTAssertEqual(SimpleVoiceParser.parseNumeric("1.000"), 1000)
        XCTAssertEqual(SimpleVoiceParser.parseNumeric("1,250.75"), 1250.75)
        XCTAssertNil(SimpleVoiceParser.parseNumeric("3:30"))
        XCTAssertNil(SimpleVoiceParser.parseNumeric("5k"))
        XCTAssertNil(SimpleVoiceParser.parseNumeric("12.5.3"))
    }

    // MARK: - Casos que van a la IA

    func testTransfersDebtsSuppliersAndInvestmentsGoToAI() {
        assertNil("transferí 100 a ahorros")
        assertNil("pasé 20 de la tarjeta")
        assertNil("le debo 50 a Juan")
        assertNil("pagué el préstamo 200")
        assertNil("pagué 200 al proveedor")
        assertNil("invertí 500 en acciones")
    }

    func testTwoNumbersGoToAI() {
        assertNil("compré 2 cafés por 5")
        assertNil("gasté 12 en almuerzo y 5 en taxi")
        assertNil("gasté 12 dólares con 50 en almuerzo")
        assertNil("compré dos cafés por 5")
    }

    func testMissingPiecesGoToAI() {
        assertNil("")
        assertNil("gasté en almuerzo")        // sin monto
        assertNil("gasté 20")                 // gasto sin concepto
        assertNil("salario 500")              // sin verbo y concepto desconocido
    }

    func testAmbiguousPhrasesGoToAI() {
        assertNil("pagaron 50 de luz")                 // ¿a quien le pagaron?
        assertNil("gasté 12 y me pagaron 20")          // gasto e ingreso
        assertNil("gasté 5 mil en el carro")           // cifra + palabra
        assertNil("gasté 50 centavos en chicle")
        assertNil("pagué 20 por ciento de la cuenta")
        assertNil("¿cuánto gasté en comida?")
        assertNil("no gasté 20 en taxi")
        assertNil("gasté 20 euros en comida")
        assertNil("gasté treinta cinco en taxi")       // falta la "y"
    }
}
