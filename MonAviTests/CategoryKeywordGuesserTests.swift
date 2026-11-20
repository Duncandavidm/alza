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

    func testHousingRent() {
        XCTAssertEqual(expense("arriendo"), .housing)
        XCTAssertEqual(expense("Arriendo"), .housing)
        XCTAssertEqual(expense("pago del arriendo"), .housing)
        XCTAssertEqual(expense("alquiler del apto"), .housing)
        XCTAssertEqual(expense("Cuota de mantenimiento"), .housing)
        XCTAssertEqual(expense("hipoteca"), .housing)
    }

    func testPhrasesBeatSingleWords() {
        XCTAssertEqual(expense("comida de perro"), .pets)
        XCTAssertEqual(expense("comida para el perro"), .pets)
        XCTAssertEqual(expense("seguro médico"), .health)
        XCTAssertEqual(expense("uber eats"), .food)
        XCTAssertEqual(expense("perro caliente"), .food)
        XCTAssertEqual(expense("Metro Plus"), .health)
    }

    func testBrandsAndCommonWords() {
        XCTAssertEqual(expense("uber"), .transport)
        XCTAssertEqual(expense("Netflix"), .subscriptions)
        XCTAssertEqual(expense("super 99"), .groceries)
        XCTAssertEqual(expense("Riba Smith"), .groceries)
        XCTAssertEqual(expense("+Móvil"), .utilities)
        XCTAssertEqual(expense("Disney+"), .subscriptions)
        XCTAssertEqual(expense("gasolina"), .transport)
        XCTAssertEqual(expense("aguacate"), .groceries)
        XCTAssertEqual(expense("Conway"), .shopping)
        XCTAssertEqual(expense("Yappy a Juan"), .transfers)
        XCTAssertEqual(expense("mercancía"), .suppliers)
    }

    func testShortKeywordsNeedWholeWord() {
        // "gas" (Servicios) no debe coincidir dentro de "gasolina".
        XCTAssertEqual(expense("gas"), .utilities)
        XCTAssertEqual(expense("gasolina"), .transport)
        XCTAssertEqual(expense("bar"), .goingOut)
    }

    func testQuincenaIsIncomeOnlyForInflow() {
        XCTAssertEqual(income("quincena"), .income)
        XCTAssertEqual(income("décimo tercer mes"), .income)
        XCTAssertNil(expense("quincena"))
    }

    func testHistoryLearnerPicksHabitualCategory() {
        let learner = CategoryHistoryLearner(entries: [
            .init(description: "Chino de la esquina", category: "Comida rápida", isInflow: false),
            .init(description: "chino", category: "Comida rápida", isInflow: false),
            .init(description: "Chino de la esquina", category: "Supermercado", isInflow: false),
            .init(description: "Pago arriendo", category: "Vivienda", isInflow: false),
        ])
        // Descripcion completa: la mas usada.
        XCTAssertEqual(learner.category(for: "chino de la esquina", isInflow: false), "Comida rápida")
        // Primera palabra significativa ("pago" se salta).
        XCTAssertEqual(learner.category(for: "chino nuevo", isInflow: false), "Comida rápida")
        XCTAssertEqual(learner.category(for: "pago del arriendo", isInflow: false), "Vivienda")
        // Entradas y salidas no se mezclan; sin historial → nil.
        XCTAssertNil(learner.category(for: "chino", isInflow: true))
        XCTAssertNil(learner.category(for: "netflix", isInflow: false))
    }

    func testHistoryLearnerTieGoesToMostRecent() {
        // Las entradas vienen de la mas nueva a la mas vieja.
        let learner = CategoryHistoryLearner(entries: [
            .init(description: "Farmacia", category: "Salud", isInflow: false),
            .init(description: "Farmacia", category: "Compras", isInflow: false),
        ])
        XCTAssertEqual(learner.category(for: "farmacia", isInflow: false), "Salud")
    }

    func testNoMatchReturnsNil() {
        XCTAssertNil(expense(""))
        XCTAssertNil(expense("x"))
        XCTAssertNil(expense("qwerty zxcv"))
    }
}
