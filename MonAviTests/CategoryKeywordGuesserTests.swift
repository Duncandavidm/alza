import XCTest
@testable import MonAvi

/// Sugerencia de categoria a partir de "¿Qué fue?" en Anotar movimiento.
final class CategoryKeywordGuesserTests: XCTestCase {
    private func expense(_ text: String) -> TransactionCategory? {
        CategoryKeywordGuesser.category(for: text, isInflow: false)
    }

    private func income(_ text: String) -> TransactionCategory? {
        CategoryKeywordGuesser.category(for: text, isInflow: true)
    }

    func testFoodWords() {
        XCTAssertEqual(expense("Hamburguesa"), .food)
        XCTAssertEqual(expense("pizzas con los panas"), .food)
        XCTAssertEqual(expense("Almuerzo"), .food)
        XCTAssertEqual(expense("café"), .food)
        XCTAssertEqual(expense("CAFE de la mañana"), .food)
        XCTAssertEqual(expense("Restaurante"), .food)
    }

    func testGroceriesBeatsFood() {
        XCTAssertEqual(expense("Super"), .groceries)
        XCTAssertEqual(expense("supermercado"), .groceries)
        XCTAssertEqual(expense("Mercado de abastos"), .groceries)
    }

    func testTransport() {
        XCTAssertEqual(expense("gasolina"), .transport)
        XCTAssertEqual(expense("Taxi al trabajo"), .transport)
        XCTAssertEqual(expense("uber"), .transport)
        XCTAssertEqual(expense("peaje corredor"), .transport)
    }

    func testUtilities() {
        XCTAssertEqual(expense("Luz"), .utilities)
        XCTAssertEqual(expense("ENSA"), .utilities)
        XCTAssertEqual(expense("Naturgy"), .utilities)
        XCTAssertEqual(expense("Cable Onda"), .utilities)
        XCTAssertEqual(expense("pago del internet"), .utilities)
    }

    func testOtherCategories() {
        XCTAssertEqual(expense("Alquiler"), .housing)
        XCTAssertEqual(expense("farmacia"), .health)
        XCTAssertEqual(expense("zapatos nuevos"), .clothing)
        XCTAssertEqual(expense("Netflix"), .subscriptions)
        XCTAssertEqual(expense("cine"), .entertainment)
        XCTAssertEqual(expense("libros del colegio"), .education)
        XCTAssertEqual(expense("Veterinario"), .pets)
        XCTAssertEqual(expense("regalo de cumpleaños"), .gifts)
        XCTAssertEqual(expense("vuelo a Bocas"), .travel)
    }

    func testIncomeWordsOnlyForInflow() {
        XCTAssertEqual(income("Quincena"), .income)
        XCTAssertEqual(income("salario"), .income)
        XCTAssertEqual(income("me pagaron el sueldo"), .income)
        XCTAssertEqual(income("Pago de cliente"), .income)
        XCTAssertNil(expense("quincena"))
    }

    func testMatchesStartOfWordOnly() {
        // "bar" no debe coincidir dentro de "barberia".
        XCTAssertNotEqual(expense("barberia"), .goingOut)
        // "super" si coincide al inicio de "supermercado".
        XCTAssertEqual(expense("el supermercado"), .groceries)
    }

    func testNoMatchReturnsNil() {
        XCTAssertNil(expense(""))
        XCTAssertNil(expense("x"))
        XCTAssertNil(expense("qwerty zxcv"))
    }
}
