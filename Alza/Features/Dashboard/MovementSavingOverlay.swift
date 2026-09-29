import SwiftUI

/// Elige que animacion mostrar al guardar un movimiento: recibo + sello de
/// PAGADO cuando entra dinero (ingreso, alguien te pago), o el carrito
/// cuando sale (gasto, pago a proveedor, inversion, transferencia).
struct MovementSavingOverlay: View {
    let movementType: MovementType
    let itemEmoji: String
    let description: String
    let amount: Decimal

    var body: some View {
        Color(.systemBackground).opacity(0.85).ignoresSafeArea()

        if movementType == .ingreso {
            ReceiptStampView(
                description: description,
                amount: amount,
                message: "Imprimiendo tu recibo..."
            )
        } else {
            CartLoadingView(
                itemEmoji: itemEmoji,
                message: "Anotando tu \(movementType.displayName.lowercased())..."
            )
        }
    }

    /// Cuanto esperar como minimo antes de cerrar, para que la animacion no
    /// se sienta cortada aunque el guardado en el servidor sea instantaneo.
    static func minDisplayNanoseconds(for movementType: MovementType) -> UInt64 {
        movementType == .ingreso ? 1_600_000_000 : 1_200_000_000
    }
}
