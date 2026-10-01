import SwiftUI
import UIKit

/// Envuelve el share sheet nativo de iOS (UIActivityViewController), para
/// que facturas y recibos se puedan compartir por CUALQUIER medio que el
/// cliente elija (WhatsApp, correo, Mensajes, AirDrop, guardar en
/// Archivos...), no solo uno fijo.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Wrapper para poder usar `.sheet(item:)` con una URL (URL no es
/// Identifiable por si sola).
struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}
