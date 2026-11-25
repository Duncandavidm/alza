import SwiftUI

/// Fila que se desliza como en las listas de iOS, para filas que no estan
/// dentro de un `List` (Hoy y Resumen usan VStack dentro de un ScrollView):
/// - a la izquierda: «Eliminar» (deslizar hasta el final tambien elimina)
/// - a la derecha: «Editar» (o un candado si el movimiento no se edita)
///
/// El gesto solo toma el control si el dedo se mueve mas en horizontal que
/// en vertical, para no estorbar el scroll.
struct SwipeActionsRow<Content: View>: View {
    /// nil = no se puede editar (movimiento de una factura): a la derecha
    /// se muestra un candado y la fila vuelve a su lugar.
    let onEdit: (() -> Void)?
    let onDelete: () -> Void
    /// Fondo de la fila (tapa los botones mientras esta cerrada).
    var rowBackground: Color = Color(.systemBackground)
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var restingOffset: CGFloat = 0
    @State private var axis: Axis?

    private let actionWidth: CGFloat = 88
    private let fullSwipe: CGFloat = 190
    private let lockedPeek: CGFloat = 96

    var body: some View {
        ZStack {
            actionsLayer
            content()
                .background(rowBackground)
                .offset(x: offset)
                // Con la fila abierta, un toque la cierra en vez de abrir el movimiento.
                .overlay {
                    if restingOffset != 0 {
                        Color.clear
                            .contentShape(Rectangle())
                            .offset(x: offset)
                            .onTapGesture { close() }
                    }
                }
        }
        .clipped()
        .simultaneousGesture(dragGesture)
        .accessibilityActions {
            if let onEdit {
                Button("Editar", action: onEdit)
            }
            Button("Eliminar", action: onDelete)
        }
    }

    // MARK: - Botones de atras

    private var actionsLayer: some View {
        HStack(spacing: 0) {
            if offset > 0 {
                leadingAction
                    .frame(width: offset)
            }
            Spacer(minLength: 0)
            if offset < 0 {
                Button {
                    close()
                    onDelete()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "trash.fill")
                        Text("Eliminar").font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: -offset)
                .background(Color.red)
                .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var leadingAction: some View {
        if let onEdit {
            Button {
                close()
                onEdit()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "pencil")
                    Text("Editar").font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(MonAviBrand.primary)
            .accessibilityHidden(true)
        } else {
            VStack(spacing: 4) {
                Image(systemName: "lock.fill")
                Text("Con factura").font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.gray)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Gesto

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .local)
            .onChanged { value in
                if axis == nil {
                    let dx = abs(value.translation.width)
                    let dy = abs(value.translation.height)
                    axis = dx > dy * 1.4 ? .horizontal : .vertical
                }
                guard axis == .horizontal else { return }
                var proposed = restingOffset + value.translation.width
                if onEdit == nil {
                    // Sin edicion: solo se asoma el candado.
                    proposed = min(proposed, lockedPeek)
                }
                offset = proposed
            }
            .onEnded { value in
                defer { axis = nil }
                guard axis == .horizontal else { return }
                let predicted = restingOffset + value.predictedEndTranslation.width
                withAnimation(.snappy(duration: 0.25)) {
                    if predicted <= -fullSwipe {
                        offset = 0
                        restingOffset = 0
                        onDelete()
                    } else if predicted <= -actionWidth / 2 {
                        offset = -actionWidth
                        restingOffset = -actionWidth
                    } else if predicted >= fullSwipe, let onEdit {
                        offset = 0
                        restingOffset = 0
                        onEdit()
                    } else if predicted >= actionWidth / 2, onEdit != nil {
                        offset = actionWidth
                        restingOffset = actionWidth
                    } else {
                        offset = 0
                        restingOffset = 0
                    }
                }
            }
    }

    private func close() {
        withAnimation(.snappy(duration: 0.25)) {
            offset = 0
            restingOffset = 0
        }
    }
}

/// Textos para eliminar o tocar un movimiento (Hoy y Resumen).
enum TransactionRowText {
    static let deleteTitle = "¿Eliminar este movimiento?"

    static func deleteMessage(for transaction: FinanceTransaction) -> String {
        if transaction.isFromInvoice {
            return "Se borra de tus movimientos y su monto vuelve al saldo de la cuenta. La factura sigue registrada y su cashback no cambia."
        }
        return "Se borra de tus movimientos y su monto vuelve al saldo de la cuenta."
    }

    static let lockedTitle = "Movimiento con factura"
    static let lockedMessage = "Este movimiento viene de una factura leída y no se puede editar. Si no corresponde, puedes eliminarlo deslizándolo a la izquierda."
}
