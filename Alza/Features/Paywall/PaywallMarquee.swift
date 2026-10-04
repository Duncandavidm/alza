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

    @State private var contentWidth: CGFloat = 0

    var body: some View {
        // El contenido que se desliza va como OVERLAY sobre una base flexible
        // (Color.clear de ancho .infinity). Antes iba directo con
        // .fixedSize(horizontal: true) + .frame(maxWidth: .infinity): dentro
        // del ScrollView vertical del paywall ese ancho intrinseco gigante se
        // propagaba al VStack contenedor, que crecia mas que la pantalla y
        // empujaba a las vistas hermanas (toggles, tarjetas) fuera del area
        // visible — su texto parecia "no renderizarse". Como overlay, el ancho
        // del contenido ya no afecta el tamaño de la fila.
        //
        // Se usa TimelineView en vez de withAnimation(.repeatForever): el
        // offset se calcula por frame a partir del tiempo transcurrido, sin
        // animacion implicita.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .overlay(alignment: .leading) {
                TimelineView(.animation) { timeline in
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
                                }
                                .onChange(of: geo.size.width) { _, newValue in
                                    contentWidth = newValue / 2
                                }
                        }
                    )
                    .offset(x: offset(at: timeline.date))
                }
            }
            .clipped()
    }

    private var chipRow: some View {
        HStack(spacing: 12) {
            ForEach(chips) { chip in
                MarqueeChipView(chip: chip)
            }
        }
    }

    /// Posicion horizontal de la fila en un instante dado. El contenido se
    /// duplica, asi que al recorrer exactamente `contentWidth` la segunda
    /// copia queda donde empezo la primera y el bucle se ve continuo.
    private func offset(at date: Date) -> CGFloat {
        guard contentWidth > 0 else { return reversed ? -contentWidth : 0 }
        let travelled = CGFloat(date.timeIntervalSinceReferenceDate * Double(speed))
            .truncatingRemainder(dividingBy: contentWidth)
        return reversed ? -contentWidth + travelled : -travelled
    }
}

private struct MarqueeChipView: View {
    let chip: MarqueeChip

    var body: some View {
        HStack(spacing: 6) {
            Text(chip.icon)
            Text(chip.text)
                .font(.system(.subheadline, design: AviBrand.fontDesign, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color(.secondarySystemBackground)))
    }
}
