import SwiftUI

/// Celebracion al canjear: llueven billetes de MonAvi (el icono de la app)
/// mezclados con emojis de fiesta (mas billetes que emojis). Va encima de todo, no recibe toques y se
/// quita sola (`onFinish`). Con "Reducir movimiento" no se muestra: solo
/// quedan el sonido y la vibracion.
struct MoneyRainView: View {
    var pieceCount = 46
    var duration: TimeInterval = 2.8
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var pieces: [Piece] = []

    struct Piece: Identifiable {
        enum Kind { case bill, emoji(String) }
        let id = UUID()
        let kind: Kind
        let x: CGFloat          // 0...1 del ancho
        let delay: Double       // segundos
        let fall: Double        // segundos que tarda en caer
        let spin: Double        // vueltas por segundo
        let sway: CGFloat       // vaiven lateral (puntos)
        let scale: CGFloat
    }

    /// Emojis de celebracion que acompañan a los billetes.
    static let celebrationEmojis = ["🎉", "🥳", "🎊", "✨", "⭐", "🙌", "💚", "💸"]

    /// 3 de cada 5 piezas son billetes de MonAvi; el resto, emojis de fiesta.
    static func isBill(_ index: Int) -> Bool { index % 5 < 3 }

    static func makePieces(count: Int) -> [Piece] {
        let emojis = celebrationEmojis
        return (0..<count).map { index in
            let kind: Piece.Kind = isBill(index) ? .bill : .emoji(emojis[index % emojis.count])
            return Piece(
                kind: kind,
                x: .random(in: 0.02...0.98),
                delay: .random(in: 0...0.9),
                fall: .random(in: 1.5...2.3),
                spin: .random(in: -0.9...0.9),
                sway: .random(in: 10...34),
                scale: .random(in: 0.75...1.25)
            )
        }
    }

    var body: some View {
        GeometryReader { proxy in
            if !reduceMotion {
                TimelineView(.animation) { timeline in
                    let elapsed = timeline.date.timeIntervalSince(start)
                    ZStack {
                        ForEach(pieces) { piece in
                            pieceView(piece)
                                .scaleEffect(piece.scale)
                                .rotationEffect(.degrees(360 * piece.spin * max(0, elapsed - piece.delay)))
                                .position(position(of: piece, elapsed: elapsed, in: proxy.size))
                                .opacity(opacity(of: piece, elapsed: elapsed))
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            start = Date()
            pieces = Self.makePieces(count: pieceCount)
            Task {
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                onFinish()
            }
        }
    }

    @ViewBuilder
    private func pieceView(_ piece: Piece) -> some View {
        switch piece.kind {
        case .bill:
            MonAviBill()
        case .emoji(let emoji):
            Text(emoji).font(.system(size: 30))
        }
    }

    private func position(of piece: Piece, elapsed: TimeInterval, in size: CGSize) -> CGPoint {
        let t = max(0, (elapsed - piece.delay) / piece.fall)
        let y = -40 + (size.height + 80) * CGFloat(t)
        let x = size.width * piece.x + piece.sway * CGFloat(sin(elapsed * 3 + Double(piece.x) * 10))
        return CGPoint(x: x, y: y)
    }

    private func opacity(of piece: Piece, elapsed: TimeInterval) -> Double {
        let t = (elapsed - piece.delay) / piece.fall
        if t < 0 { return 0 }
        if t > 0.85 { return max(0, (1 - t) / 0.15) }
        return 1
    }
}

/// Billete verde de MonAvi (como los de la landing y la app).
struct MonAviBill: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(LinearGradient(colors: [MonAviBrand.primary, MonAviBrand.primaryDark], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(Color.white.opacity(0.45), lineWidth: 1)
                .padding(3)
            Circle()
                .stroke(Color.white.opacity(0.8), lineWidth: 1.4)
                .frame(width: 15, height: 15)
            Text("$")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 46, height: 24)
        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
    }
}
