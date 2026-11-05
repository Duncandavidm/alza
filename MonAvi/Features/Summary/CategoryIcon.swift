import SwiftUI

/// Emoji de la categoria dentro de un circulo con el color de la
/// categoria — el mismo icono en el Resumen, el selector y las listas.
struct CategoryIcon: View {
    let emoji: String
    let color: Color
    var size: CGFloat = 40

    init(emoji: String, color: Color, size: CGFloat = 40) {
        self.emoji = emoji
        self.color = color
        self.size = size
    }

    init(category: TransactionCategory?, size: CGFloat = 40) {
        self.emoji = category?.emoji ?? "🏷️"
        self.color = category?.color ?? .gray
        self.size = size
    }

    var body: some View {
        Text(emoji)
            .font(.system(size: size * 0.48))
            .frame(width: size, height: size)
            .background(Circle().fill(color.opacity(0.16)))
            .overlay(Circle().strokeBorder(color, lineWidth: 2))
            .accessibilityHidden(true)
    }
}
