import SwiftUI

/// Paleta pastel de marca para pintar las barras de presupuesto — version
/// Amadai (teal) del picker de colores del diseño de referencia (que usaba
/// tonos durazno/rosa genericos). Un presupuesto sin color guardado cae a
/// uno de estos por su posicion en la lista, asi los existentes (creados
/// antes de que existiera esta opcion) igual se ven bien sin migrar datos.
enum BudgetColorPalette {
    static let swatches: [Color] = [
        Color(hex: "#00A585") ?? AmadaiBrand.primary, // teal de marca
        Color(hex: "#F4A07A") ?? .orange, // durazno
        Color(hex: "#F2B8C6") ?? .pink, // rosa
        Color(hex: "#F6DDA0") ?? .yellow, // crema
        Color(hex: "#9AD1C5") ?? .mint, // menta
        Color(hex: "#B8C9F2") ?? .blue, // azul suave
        Color(hex: "#D6C2EC") ?? .purple, // lavanda
        Color(hex: "#C9C9C9") ?? .gray, // gris neutro
    ]

    /// Color real de un presupuesto: el que eligio a mano, o uno
    /// determinista segun su posicion (para que no "salte" de color cada
    /// vez que se recalcula la lista).
    static func color(for budget: Budget, index: Int) -> Color {
        if let hex = budget.color, let stored = Color(hex: hex) {
            return stored
        }
        return swatches[index % swatches.count]
    }
}
