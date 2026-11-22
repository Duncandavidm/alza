import Foundation
import PDFKit
import UIKit
import Vision

/// Facturas que llegan por correo o WhatsApp (PDF o imagen) y se abren con
/// "Compartir → MonAvi". Saca de ahi lo mismo que leeria la camara: el
/// enlace del QR de la DGI. En orden: enlaces del PDF, el QR dibujado en
/// sus paginas y, si nada de eso, el enlace o el CUFE escritos en el texto.
enum InvoiceFileReader {
    /// Maximo de paginas a revisar (una factura casi siempre es 1–2).
    static let maxPages = 4

    static func payload(from url: URL) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        if let document = PDFDocument(url: url) {
            return payload(from: document)
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return GalleryQRScanner.scan(imageData: data)
    }

    static func payload(from document: PDFDocument) -> String? {
        let pages = (0..<min(document.pageCount, maxPages)).compactMap { document.page(at: $0) }

        // 1) Un enlace de la DGI puesto como link en el PDF.
        for page in pages {
            for annotation in page.annotations {
                if let link = annotation.url?.absoluteString, isDgiLink(link) { return link }
            }
        }

        // 2) El QR impreso en la factura.
        for page in pages {
            let bounds = page.bounds(for: .mediaBox)
            guard bounds.width > 0, bounds.height > 0 else { continue }
            let width: CGFloat = 2400
            let size = CGSize(width: width, height: width * bounds.height / bounds.width)
            let image = page.thumbnail(of: size, for: .mediaBox)
            if let cgImage = image.cgImage, let found = GalleryQRScanner.scan(cgImage: cgImage) {
                return found
            }
        }

        // 3) El enlace o el CUFE escritos como texto.
        return document.string.flatMap(payload(fromText:))
    }

    /// Busca en el texto un enlace de consulta de la DGI o, si no hay, un
    /// CUFE (FE + 64 cifras, a veces con guiones o espacios) y arma el
    /// enlace corto de consulta por CUFE.
    static func payload(fromText text: String) -> String? {
        let host = NSRegularExpression.escapedPattern(for: CufeParser.dgiHost)
        if let range = text.range(of: "https://\(host)/Consultas/[^\\s\"<>]+", options: .regularExpression) {
            return String(text[range])
        }
        guard let range = text.range(of: "FE[0-9][0-9\\- ]{63,100}", options: .regularExpression) else { return nil }
        var digits = ""
        for character in text[range].dropFirst(2) {
            if character.isNumber { digits.append(character) }
            else if character == "-" || character == " " { continue }
            else { break }
            if digits.count == 64 { break }
        }
        guard digits.count == 64 else { return nil }
        return "https://\(CufeParser.dgiHost)\(CufeParser.cufePathPrefix)FE\(digits)"
    }

    static func isDgiLink(_ link: String) -> Bool {
        guard let url = URL(string: link) else { return false }
        return url.host == CufeParser.dgiHost && url.path.hasPrefix("/Consultas/")
    }
}

extension GalleryQRScanner {
    static func scan(cgImage: CGImage) -> String? {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        return request.results?.first { $0.symbology == .qr }?.payloadStringValue
    }
}
