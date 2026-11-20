import XCTest
@testable import MonAvi

/// Token de APNs a hex, genero del perfil, validacion de edad en
/// "Mi perfil" y el titulo de una factura DGI con/sin nombre de comercio.
final class PushAndProfileTests: XCTestCase {
    func testPushTokenHexIsLowercaseAndZeroPadded() {
        let data = Data([0x00, 0x0A, 0xFF, 0x7B, 0xC4])
        XCTAssertEqual(PushTokenFormatter.hexString(from: data), "000aff7bc4")
    }

    func testPushTokenHexOfEmptyDataIsEmpty() {
        XCTAssertEqual(PushTokenFormatter.hexString(from: Data()), "")
    }

    func testProfileGenderRawValuesMatchDatabaseCheck() {
        XCTAssertEqual(
            ProfileGender.allCases.map(\.rawValue),
            ["femenino", "masculino", "otro", "prefiero_no_decir"]
        )
        XCTAssertEqual(ProfileGender.prefieroNoDecir.displayName, "Prefiero no decir")
    }

    func testParseAge() {
        XCTAssertEqual(try ProfileSettingsViewModel.parseAge("").get(), nil)
        XCTAssertEqual(try ProfileSettingsViewModel.parseAge(" 34 ").get(), 34)
        XCTAssertThrowsError(try ProfileSettingsViewModel.parseAge("0").get())
        XCTAssertThrowsError(try ProfileSettingsViewModel.parseAge("abc").get())
        XCTAssertThrowsError(try ProfileSettingsViewModel.parseAge("130").get())
    }

    func testParsePhoneMatchesDatabaseCheck() {
        XCTAssertEqual(try ProfileSettingsViewModel.parsePhone("").get(), nil)
        XCTAssertEqual(try ProfileSettingsViewModel.parsePhone("  ").get(), nil)
        XCTAssertEqual(try ProfileSettingsViewModel.parsePhone(" +507 6123-4567 ").get(), "+507 6123-4567")
        XCTAssertEqual(try ProfileSettingsViewModel.parsePhone("(507) 6123 4567").get(), "(507) 6123 4567")
        XCTAssertThrowsError(try ProfileSettingsViewModel.parsePhone("123456").get())
        XCTAssertThrowsError(try ProfileSettingsViewModel.parsePhone("6123-4567 ext. 2").get())
        XCTAssertThrowsError(try ProfileSettingsViewModel.parsePhone("507+61234567").get())
        XCTAssertThrowsError(try ProfileSettingsViewModel.parsePhone(String(repeating: "1", count: 22)).get())
    }

    func testCleanedTextTurnsBlankIntoNil() {
        XCTAssertNil(ProfileSettingsViewModel.cleanedText("   "))
        XCTAssertEqual(ProfileSettingsViewModel.cleanedText(" Ana "), "Ana")
    }

    func testOffersConsentPurposeRawValue() {
        XCTAssertEqual(ConsentPurpose.ofertas.rawValue, "ofertas")
    }

    private func receiptJSON(merchantName: String?) -> String {
        let nameValue = merchantName.map { "\"\($0)\"" } ?? "null"
        return """
        {
          "id": "1F9619FF-8B86-D011-B42D-00C04FC964FF",
          "user_id": "2F9619FF-8B86-D011-B42D-00C04FC964FF",
          "transaction_id": null,
          "merchant_id": null,
          "cufe": "FE0120000155-1-2024-0000",
          "i_amb": "1",
          "digest_value": null,
          "jwt": null,
          "tipo_doc": "01",
          "tipo_contribuyente": "2",
          "ruc": "155-1-2024",
          "dv": "12",
          "sucursal": "0001",
          "fecha_factura": "2026-11-01",
          "numero_documento": "0000001",
          "punto_facturacion": "001",
          "tipo_emision": "01",
          "numero_seguridad": "123456789",
          "digito_verificador": "1",
          "status": "confirmada",
          "confirmed_amount": 12.5,
          "payment_method": null,
          "merchant_name": \(nameValue),
          "authorized_at": "2026-11-01T15:30:00Z",
          "scanned_at": "2026-11-01T16:00:00Z",
          "dgi_checked_at": null,
          "dgi_check_count": 1,
          "created_at": "2026-11-01T16:00:00Z",
          "updated_at": "2026-11-01T16:00:00Z"
        }
        """
    }

    func testDgiReceiptTitlePrefersMerchantName() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let named = try decoder.decode(DgiReceipt.self, from: Data(receiptJSON(merchantName: "Super 99").utf8))
        XCTAssertEqual(named.displayTitle, "Super 99")
        XCTAssertTrue(named.hasMerchantName)
        XCTAssertNotNil(named.authorizedAt)

        let unnamed = try decoder.decode(DgiReceipt.self, from: Data(receiptJSON(merchantName: nil).utf8))
        XCTAssertEqual(unnamed.displayTitle, "RUC 155-1-2024")
        XCTAssertFalse(unnamed.hasMerchantName)
    }
}
