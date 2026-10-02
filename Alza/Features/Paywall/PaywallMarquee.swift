import SwiftUI

/// Chip de un beneficio ("Pregunta lo que sea sobre tu dinero", etc.) —
/// icono + texto corto, en forma de pastilla.
struct MarqueeChip: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
}

/// Una fila de chips que se desliza sola, sin parar, de forma continua —
/// el "carrusel" de beneficios del paywall de referencia. El contenido se
/// duplica una vez y se anima de 0 a -ancho (o al reves si `reversed`),
/// reiniciando sin que se note el salto porque la segunda copia continua
/// exactamente donde termino la primera.
struct MarqueeRow: View {
    let chips: [MarqueeChip]
    var reversed: Bool = false
    /// Puntos por segundo — mas alto = mas rapido.
    var speed: CGFloat = 28

    @State private var offset: CGFloat = 0
    @State private var contentWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            chipRow
            chipRow
        }
        .fixedSize(horizontal: true, vertical: false)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        // La fila duplicada mide el doble del contenido real.
                        contentWidth = geo.size.width / 2
                        startAnimating()
                    }
            }
        )
        .offset(x: offset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 40)
        .clipped()
    }

    private var chipRow: some View {
        HStack(spacing: 12) {
            ForEach(chips) { chip in
                MarqueeChipView(chip: chip)
            }
        }
    }

    private func startAnimating() {
        guard contentWidth > 0 else { return }
        offset = reversed ? -contentWidth : 0
        let duration = Double(contentWidth / speed)
        withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
            offset = reversed ? 0 : -contentWidth
        }
    }
}

private struct MarqueeChipView: View {
    let chip: MarqueeChip

    var body: some View {
        HStack(spacing: 6) {
            Text(chip.icon)
            Text(chip.text)
                .font(.system(.subheadline, design: AlzaBrand.fontDesign, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color(.secondarySystemBackground)))
    }
}
