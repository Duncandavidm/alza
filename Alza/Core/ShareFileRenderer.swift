import SwiftUI

/// Convierte cualquier vista de SwiftUI en un PNG temporal, para poder
/// compartirla con ShareLink (facturas, remisiones, recibos de pago) por
/// el medio que el cliente elija — WhatsApp, correo, AirDrop, Mensajes,
/// guardarla en Archivos, lo que sea que ofrezca la hoja de compartir.
@MainActor
enum ShareFileRenderer {
    static func renderPNG(_ view: some View, scale: CGFloat = 3) -> URL? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale

        guard let uiImage = renderer.uiImage, let data = uiImage.pngData() else { return nil }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
