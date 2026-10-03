import SwiftUI

/// Fondo sutil de billetes flotando hacia arriba — solo para el momento
/// de celebracion al registrar un ingreso (detras del recibo en
/// ReceiptStampView), nunca como decoracion permanente de pantalla,
/// para no distraer del resto de la app minimalista.
struct FloatingBillsBackground: View {
    private let emojis = ["💵", "💸", "💵", "💰", "💵", "💸"]

    var body: some View {
        TimelineView(.animation) { timeline in
            GeometryReader { geo in
                let t = timeline.date.timeIntervalSinceReferenceDate
                ForEach(0..<emojis.count, id: \.self) { index in
                    bill(index: index, time: t, size: geo.size)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func bill(index: Int, time: Double, size: CGSize) -> some View {
        let seed = Double(index)
        let duration = 6.5 + (seed * 1.7).truncatingRemainder(dividingBy: 3)
        let phase = seed / Double(emojis.count)
        let progress = ((time / duration) + phase).truncatingRemainder(dividingBy: 1)

        let baseX = size.width * (0.1 + 0.8 * fractionalNoise(seed))
        let sway = sin((progress + phase) * 2 * .pi * 2) * 16
        let y = size.height * (1.08 - progress * 1.16)
        // Muy sutil a proposito: nunca pasa de ~0.14 de opacidad.
        let opacity = sin(progress * .pi) * 0.14
        let rotation = sin((progress + phase) * 2 * .pi) * 12

        return Text(emojis[index])
            .font(.system(size: 20))
            .opacity(max(0, opacity))
            .rotationEffect(.degrees(rotation))
            .position(x: baseX + sway, y: y)
    }

    private func fractionalNoise(_ seed: Double) -> Double {
        let x = sin(seed * 12.9898) * 43758.5453
        return x - x.rounded(.down)
    }
}
