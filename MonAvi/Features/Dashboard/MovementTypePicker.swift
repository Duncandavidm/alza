import SwiftUI

/// Fila de iconos grandes para elegir el tipo de movimiento (mejora #3:
/// tipos claramente diferenciados). Compartida entre el ingreso ultra-rapido
/// y el formulario detallado.
struct MovementTypePicker: View {
    @Binding var selection: MovementType

    /// Cuadricula que se acomoda sola: en vez de una fila horizontal que
    /// escondia "Transferencia" detras del borde (y obligaba a deslizar sin
    /// que se notara), se ven TODOS los tipos a la vez, envolviendose a una
    /// segunda fila cuando no caben — mas intuitivo en pantallas chicas.
    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(MovementType.allCases) { type in
                Button {
                    selection = type
                } label: {
                    VStack(spacing: 4) {
                        Text(type.emoji).font(.system(size: 26))
                        Text(type.displayName)
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(selection == type ? type.tintColor.opacity(0.18) : Color(.secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(selection == type ? type.tintColor : .clear, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
