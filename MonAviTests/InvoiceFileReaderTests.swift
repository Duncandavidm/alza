import XCTest
@testable import MonAvi

final class InvoiceFileReaderTests: XCTestCase {

    func testFindsQrLinkInText() {
        let text = "Consulte su factura en https://dgi-fep.mef.gob.pa/Consultas/FacturasPorQR?chFE=FE01&iAmb=1 gracias"
        XCTAssertEqual(
            InvoiceFileReader.payload(fromText: text),
            "https://dgi-fep.mef.gob.pa/Consultas/FacturasPorQR?chFE=FE01&iAmb=1"
        )
    }

    func testBuildsCufeLinkFromWrittenCufeWithSeparators() {
        let digits = String(repeating: "1234567890", count: 6) + "1234"
        XCTAssertEqual(digits.count, 64)
        let spaced = "CUFE: FE" + digits.prefix(20) + " " + digits.dropFirst(20).prefix(20) + "-" + digits.dropFirst(40) + "\nTotal"
        XCTAssertEqual(
            InvoiceFileReader.payload(fromText: spaced),
            "https://dgi-fep.mef.gob.pa/Consultas/FacturasPorCUFE/FE" + digits
        )
    }

    func testIgnoresTextWithoutInvoice() {
        XCTAssertNil(InvoiceFileReader.payload(fromText: "Hola, te mando la cotización. FE de erratas: 123"))
    }

    func testDgiLinkDetection() {
        XCTAssertTrue(InvoiceFileReader.isDgiLink("https://dgi-fep.mef.gob.pa/Consultas/FacturasPorQR?chFE=1"))
        XCTAssertFalse(InvoiceFileReader.isDgiLink("https://example.com/Consultas/x"))
    }
}

final class InvoiceScanRequestTests: XCTestCase {
    func testScanURL() {
        XCTAssertTrue(InvoiceScanRequest.isScanURL(URL(string: "monavi://scan")!))
        XCTAssertTrue(InvoiceScanRequest.isScanURL(URL(string: "MonAvi://SCAN")!))
        XCTAssertFalse(InvoiceScanRequest.isScanURL(URL(string: "monavi://otra")!))
        XCTAssertFalse(InvoiceScanRequest.isScanURL(URL(string: "https://monavi.app/scan")!))
    }

    func testRequestExpires() {
        let now = Date()
        XCTAssertTrue(InvoiceScanRequest.isFresh(requestedAt: now.addingTimeInterval(-30), now: now))
        XCTAssertFalse(InvoiceScanRequest.isFresh(requestedAt: now.addingTimeInterval(-600), now: now))
    }
}
