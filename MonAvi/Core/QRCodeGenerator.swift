import CoreImage.CIFilterBuiltins
import SwiftUI

/// Genera un codigo QR nativo (CoreImage) a partir de un string — se usa
/// para mostrar el QR del enrolamiento TOTP (otpauth://...) sin depender
/// de parsear/renderizar el SVG que regresa Supabase, que SwiftUI no
/// soporta de forma nativa.
enum QRCodeGenerator {
    static func image(from string: String, scale: CGFloat = 10) -> Image? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext()
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }

        return Image(decorative: cgImage, scale: 1, orientation: .up)
    }
}
