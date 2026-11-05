import SwiftUI

/// Teclado numerico propio para el monto: siempre visible (sin tener que
/// tocar un campo), con tecla +/− para cambiar entre gasto e ingreso.
struct AmountKeypad: View {
    @Binding var text: String
    let isInflow: Bool
    let onToggleSign: () -> Void

    enum Key: Hashable {
        case digit(Int)
        case dot
        case delete
    }

    private static let rows: [[Key]] = [
        [.digit(1), .digit(2), .digit(3)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(7), .digit(8), .digit(9)],
        [.dot, .digit(0), .delete],
    ]

    var body: some View {
        VStack(spacing: 8) {
            Button(action: onToggleSign) {
                HStack(spacing: 6) {
                    Image(systemName: "plusminus")
                    Text(isInflow ? "Ingreso" : "Gasto")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color(.tertiarySystemFill)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isInflow ? "Cambiar a gasto" : "Cambiar a ingreso")

            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(Self.rows, id: \.self) { row in
                    GridRow {
                        ForEach(row, id: \.self) { key in
                            keyButton(key)
                        }
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: text)
    }

    private func keyButton(_ key: Key) -> some View {
        Button {
            text = Self.applying(key, to: text)
        } label: {
            Group {
                switch key {
                case .digit(let value):
                    Text("\(value)")
                case .dot:
                    Text(".")
                case .delete:
                    Image(systemName: "delete.left")
                }
            }
            .font(.title2.weight(.medium))
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(key == .delete || key == .dot ? Color.clear : Color(.secondarySystemBackground))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: key))
    }

    private func accessibilityLabel(for key: Key) -> String {
        switch key {
        case .digit(let value): return "\(value)"
        case .dot: return "Punto decimal"
        case .delete: return "Borrar"
        }
    }

    /// Reglas del teclado, aparte para poder probarlas: un solo punto,
    /// maximo 2 decimales, sin ceros a la izquierda, maximo 9 enteros.
    static func applying(_ key: Key, to text: String) -> String {
        switch key {
        case .delete:
            return String(text.dropLast())
        case .dot:
            if text.contains(".") { return text }
            return text.isEmpty ? "0." : text + "."
        case .digit(let value):
            let digit = String(value)
            if let dotIndex = text.firstIndex(of: ".") {
                let decimals = text[text.index(after: dotIndex)...]
                return decimals.count >= 2 ? text : text + digit
            }
            if text == "0" { return digit }
            if text.count >= 9 { return text }
            return text + digit
        }
    }
}
