import SwiftUI

/// Fila de iconos grandes para elegir el tipo de movimiento (mejora #3:
/// tipos claramente diferenciados). Compartida entre el ingreso ultra-rapido
/// y el formulario detallado.
struct MovementTypePicker: View {
    @Binding var selection: MovementType

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(MovementType.allCases) { type in
                    Button {
                        selection = type
                    } label: {
                        VStack(spacing: 4) {
                            Text(type.emoji).font(.system(size: 26))
                            Text(type.displayName)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
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
}
