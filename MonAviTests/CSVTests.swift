import XCTest
@testable import MonAvi

/// Exportar/importar CSV (Ajustes): el parser debe sobrevivir a comas y
/// comillas dentro de una descripcion, y leer bien filas de movimiento y
/// de recurrente.
final class CSVTests: XCTestCase {

    // MARK: - CSV crudo (comillas/comas)

    func testFieldQuotesOnlyWhenNeeded() {
        XCTAssertEqual(CSV.field("simple"), "simple")
        XCTAssertEqual(CSV.field("a,b"), "\"a,b\"")
        XCTAssertEqual(CSV.field("dice \"hola\""), "\"dice \"\"hola\"\"\"")
    }

    func testFieldParseLineRoundTrip() {
        let values = ["Café, \"el bueno\"", "Comida", "", "sin comillas"]
        let encoded = CSV.row(values).trimmingCharacters(in: .newlines)
        XCTAssertEqual(CSV.parseLine(encoded), values)
    }

    // MARK: - CSVTransactions.parse (import)

    func testParseMovementAndRecurringRows() {
        // Delimitador extendido (#"""..."""#) para poder escribir las
        // comillas dobles del CSV tal cual, sin que Swift las confunda.
        let csv = #"""
        tipo,fecha,dia_del_mes,nombre,categoria,tipo_movimiento,monto,etiquetas
        movimiento,2023-11-14T22:13:20Z,,"Café, ""el bueno""",Comida,gasto,-12.5,cine|viaje
        recurrente,,15,Netflix,Entretenimiento,gasto,10.99,
        """#

        let rows = CSVTransactions.parse(csv)
        XCTAssertEqual(rows.count, 2)

        let movement = rows[0]
        XCTAssertFalse(movement.isRecurring)
        XCTAssertEqual(movement.name, "Café, \"el bueno\"")
        XCTAssertEqual(movement.category, "Comida")
        XCTAssertEqual(movement.movementType, .gasto)
        XCTAssertEqual(movement.amount, Decimal(string: "-12.5"))
        XCTAssertEqual(movement.tags, ["cine", "viaje"])
        XCTAssertNotNil(movement.occurredAt)

        let recurring = rows[1]
        XCTAssertTrue(recurring.isRecurring)
        XCTAssertEqual(recurring.dayOfMonth, 15)
        XCTAssertEqual(recurring.name, "Netflix")
        XCTAssertEqual(recurring.amount, Decimal(string: "10.99"))
        XCTAssertTrue(recurring.tags.isEmpty)
        XCTAssertNil(recurring.occurredAt)
    }

    // Filas incompletas o con tipo de movimiento desconocido no deben
    // tumbar la importacion: se saltan o caen a un default seguro.
    func testParseSkipsShortRowsAndDefaultsUnknownType() {
        let csv = #"""
        tipo,fecha,dia_del_mes,nombre,categoria,tipo_movimiento,monto,etiquetas
        movimiento,,,Fila corta
        movimiento,,,Raro,Otro,xxxx,5,
        """#
        let rows = CSVTransactions.parse(csv)
        XCTAssertEqual(rows.count, 1) // la fila corta (4 campos) se salta
        XCTAssertEqual(rows[0].movementType, .gasto) // "xxxx" -> default
        XCTAssertEqual(rows[0].amount, 5)
    }

    func testEmptyOrHeaderOnlyIsEmpty() {
        XCTAssertTrue(CSVTransactions.parse("").isEmpty)
        XCTAssertTrue(CSVTransactions.parse("tipo,fecha,dia_del_mes,nombre,categoria,tipo_movimiento,monto,etiquetas").isEmpty)
    }
}
