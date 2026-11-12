import SwiftUI

/// Fila de iconos grandes para elegir el tipo de movimiento (mejora #3:
/// tipos claramente diferenciados). Compartida entre el ingreso ultra-rapido
/// y el formulario detallado.
struct MovementTypePicker: View {
    @Binding var selection: MovementType
    /// Tipos que se ofrecen (por default todos).
    var types: [MovementType] = MovementType.allCases
    /// true = una sola fila deslizable de capsulas chicas (emoji + nombre),
    /// para el ingreso rapido, donde el monto y el teclado necesitan el
    /// espacio. false = la cuadricula de tarjetas grandes de siempre.
    var compact: Bool = false

    /// Cuadricula que se acomoda sola: en vez de una fila horizontal que
    /// escondia "Transferencia" detras del borde (y obligaba a deslizar sin
    /// que se notara), se ven TODOS los tipos a la vez, envolviendose a una
    /// segunda fila cuando no caben — mas intuitivo en pantallas chicas.
    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 10)]

    @Namespace private var segmentNamespace

    var body: some View {
        if compact && types.count <= 3 {
            segmented
        } else if compact {
            compactRow
        } else {
            grid
        }
    }

    /// Control segmentado de ancho completo (hasta 3 tipos): centrado, con
    /// la opcion elegida resaltada en su color y una transicion suave.
    private var segmented: some View {
        HStack(spacing: 4) {
            ForEach(types) { type in
                let isSelected = selection == type
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = type }
                } label: {
                    HStack(spacing: 6) {
                        Text(type.emoji).font(.system(size: 17))
                        Text(type.displayName)
                            .font(.subheadline.weight(isSelected ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(isSelected ? type.tintColor : .primary)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(Color(.systemBackground))
                                .overlay(Capsule().strokeBorder(type.tintColor.opacity(0.6), lineWidth: 1.5))
                                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                                .matchedGeometryEffect(id: "selected", in: segmentNamespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(Color(.secondarySystemBackground)))
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(types) { type in
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

    /// Una fila (~36 pt de alto) que se desplaza sola hasta el tipo elegido,
    /// para que nunca quede escondido detras del borde.
    private var compactRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(types) { type in
                        let isSelected = selection == type
                        Button {
                            selection = type
                        } label: {
                            HStack(spacing: 5) {
                                Text(type.emoji).font(.system(size: 16))
                                Text(type.displayName)
                                    .font(.footnote.weight(isSelected ? .semibold : .medium))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(isSelected ? type.tintColor.opacity(0.18) : Color(.secondarySystemBackground))
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(isSelected ? type.tintColor : .clear, lineWidth: 1.5)
                            )
                            .foregroundStyle(isSelected ? type.tintColor : .primary)
                        }
                        .buttonStyle(.plain)
                        .id(type)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 1)
                .padding(.horizontal, 1)
            }
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
            .onChange(of: selection) { _, newValue in
                withAnimation(.snappy) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .accessibilityLabel("Tipo de movimiento")
    }
}
