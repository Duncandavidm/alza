import SwiftUI

/// El equivalente nativo de "microinteracciones fluidas" (lo que en web se
/// haria con Framer Motion): el boton se encoge un poco al presionarlo y
/// vuelve con un resorte al soltarlo. Reemplaza el `.buttonStyle(.plain)`
/// o el estilo por defecto en los botones principales de la app.
struct PressableButtonStyle: ButtonStyle {
    var scaleWhenPressed: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scaleWhenPressed : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension View {
    /// Aplica el microinteraction de "presionar" sin perder el
    /// buttonStyle que ya tenga el boton (bordered, borderedProminent,
    /// etc.) — se combina encima en vez de reemplazarlo.
    func pressable(scale: CGFloat = 0.96) -> some View {
        modifier(PressableModifier(scale: scale))
    }
}

private struct PressableModifier: ViewModifier {
    let scale: CGFloat
    @GestureState private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in state = true }
            )
    }
}

// MARK: - Gato de espera

/// Espera con personalidad: un gato verde MonAvi jugando con una bola de
/// lana mientras se lee una factura compartida o se hace un analisis con
/// IA. Todo es dibujo vectorial (Canvas), sin imagenes ni librerias.
/// Con "Reducir movimiento" el gato se queda quieto.
struct MonAviCatLoader: View {
    var message: String
    var size: CGFloat = 240
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 14) {
            TimelineView(.animation(paused: reduceMotion)) { context in
                let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                Canvas { canvas, canvasSize in
                    let scale = canvasSize.width / 240
                    canvas.scaleBy(x: scale, y: scale)
                    CatYarnDrawing.draw(in: &canvas, time: t)
                }
            }
            .frame(width: size, height: size * 170 / 240)
            .accessibilityHidden(true)

            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .animation(.easeInOut, value: message)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

/// El dibujo del gato en un lienzo de 240 x 170 puntos.
private enum CatYarnDrawing {
    static let body = MonAviBrand.primary
    static let dark = MonAviBrand.primaryDark
    static let light = Color.white.opacity(0.9)
    static let ink = MonAviBrand.darkSurface
    static let yarn = MonAviBrand.alertOnDark
    static let yarnDark = MonAviBrand.alert

    static func draw(in c: inout GraphicsContext, time t: Double) {
        let phase = sin(t * 2.2)
        // La bola rueda de un lado a otro frente al gato.
        let ballX = 178 + 26 * phase
        let ballY = 131.0
        let ballR = 19.0
        let swat = max(0, -phase) // 0 lejos ... 1 cuando la bola llega al gato

        // Sombras en el piso
        c.fill(Path(ellipseIn: CGRect(x: 22, y: 146, width: 120, height: 12)), with: .color(.black.opacity(0.08)))
        c.fill(Path(ellipseIn: CGRect(x: ballX - 18, y: 147, width: 36, height: 8)), with: .color(.black.opacity(0.08)))

        // Hilo suelto de la bola
        var thread = Path()
        thread.move(to: CGPoint(x: ballX - ballR * 0.7, y: ballY + ballR * 0.6))
        thread.addCurve(
            to: CGPoint(x: ballX + 34, y: 151),
            control1: CGPoint(x: ballX - 12, y: 156),
            control2: CGPoint(x: ballX + 18, y: 142 + 6 * sin(t * 3))
        )
        c.stroke(thread, with: .color(yarnDark), style: StrokeStyle(lineWidth: 2, lineCap: .round))

        // Cola: se mece
        let wag = sin(t * 3.1)
        var tail = Path()
        tail.move(to: CGPoint(x: 40, y: 128))
        tail.addCurve(
            to: CGPoint(x: 22 + 8 * wag, y: 70 + 4 * wag),
            control1: CGPoint(x: 10, y: 124),
            control2: CGPoint(x: 10 + 10 * wag, y: 88)
        )
        c.stroke(tail, with: .color(body), style: StrokeStyle(lineWidth: 12, lineCap: .round))
        c.fill(Path(ellipseIn: CGRect(x: 15.5 + 8 * wag, y: 63.5 + 4 * wag, width: 13, height: 13)), with: .color(dark))

        // Cuerpo
        let torso = Path(ellipseIn: CGRect(x: 30, y: 88, width: 92, height: 62))
        c.fill(torso, with: .color(body))
        // Rayas del lomo
        for i in 0..<3 {
            var stripe = Path()
            let x = 52.0 + Double(i) * 16
            stripe.move(to: CGPoint(x: x, y: 92))
            stripe.addQuadCurve(to: CGPoint(x: x + 4, y: 106), control: CGPoint(x: x + 6, y: 97))
            c.stroke(stripe, with: .color(dark), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
        // Pecho claro
        c.fill(Path(ellipseIn: CGRect(x: 90, y: 104, width: 30, height: 38)), with: .color(light))

        // Pata trasera
        c.fill(Path(ellipseIn: CGRect(x: 44, y: 138, width: 30, height: 14)), with: .color(dark))

        // Pata delantera quieta
        c.fill(Path(roundedRect: CGRect(x: 92, y: 126, width: 13, height: 24), cornerRadius: 6.5), with: .color(body))
        c.fill(Path(ellipseIn: CGRect(x: 90, y: 143, width: 18, height: 9)), with: .color(light))

        // Pata que le da a la bola
        let shoulder = CGPoint(x: 112, y: 122)
        let paw = CGPoint(x: 122 + 26 * swat, y: 146 - 22 * swat)
        var arm = Path()
        arm.move(to: shoulder)
        arm.addLine(to: paw)
        c.stroke(arm, with: .color(body), style: StrokeStyle(lineWidth: 13, lineCap: .round))
        c.fill(Path(ellipseIn: CGRect(x: paw.x - 8, y: paw.y - 6, width: 17, height: 12)), with: .color(light))

        // Cabeza (mira hacia la bola)
        let look = 2.5 * phase
        let head = CGPoint(x: 116, y: 80)
        // Orejas
        for ear in [[CGPoint(x: 94, y: 70), CGPoint(x: 98, y: 44), CGPoint(x: 114, y: 60)],
                    [CGPoint(x: 120, y: 58), CGPoint(x: 136, y: 42), CGPoint(x: 140, y: 68)]] {
            var p = Path()
            p.addLines(ear)
            p.closeSubpath()
            c.fill(p, with: .color(body))
        }
        for ear in [[CGPoint(x: 99, y: 64), CGPoint(x: 101, y: 51), CGPoint(x: 109, y: 60)],
                    [CGPoint(x: 125, y: 58), CGPoint(x: 133, y: 50), CGPoint(x: 135, y: 64)]] {
            var p = Path()
            p.addLines(ear)
            p.closeSubpath()
            c.fill(p, with: .color(yarn.opacity(0.85)))
        }
        c.fill(Path(ellipseIn: CGRect(x: head.x - 28, y: head.y - 26, width: 56, height: 52)), with: .color(body))
        // Hocico claro
        c.fill(Path(ellipseIn: CGRect(x: head.x - 9 + look, y: head.y + 2, width: 26, height: 18)), with: .color(light))

        // Ojos: siguen la bola y parpadean cada tanto
        let blinkCycle = t.truncatingRemainder(dividingBy: 3.6)
        let eyeOpen = blinkCycle > 3.45 ? 0.15 : 1.0
        for ex in [head.x - 9.0, head.x + 9.0] {
            let h = 11.0 * eyeOpen
            c.fill(Path(ellipseIn: CGRect(x: ex - 4.5 + look, y: head.y - 6 - h / 2, width: 9, height: h)), with: .color(ink))
            if eyeOpen > 0.5 {
                c.fill(Path(ellipseIn: CGRect(x: ex - 1.5 + look + 1.5 * phase, y: head.y - 10, width: 3.5, height: 3.5)), with: .color(.white))
            }
        }
        // Nariz y boca
        var nose = Path()
        nose.move(to: CGPoint(x: head.x + 1 + look, y: head.y + 5))
        nose.addLine(to: CGPoint(x: head.x + 7 + look, y: head.y + 5))
        nose.addLine(to: CGPoint(x: head.x + 4 + look, y: head.y + 9))
        nose.closeSubpath()
        c.fill(nose, with: .color(yarnDark))
        var mouth = Path()
        mouth.move(to: CGPoint(x: head.x - 1 + look, y: head.y + 12))
        mouth.addQuadCurve(to: CGPoint(x: head.x + 4 + look, y: head.y + 11), control: CGPoint(x: head.x + 1.5 + look, y: head.y + 15))
        mouth.addQuadCurve(to: CGPoint(x: head.x + 9 + look, y: head.y + 12), control: CGPoint(x: head.x + 6.5 + look, y: head.y + 15))
        c.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        // Bigotes
        for (dy, tilt) in [(-1.0, -3.0), (3.0, 1.0)] {
            var w = Path()
            w.move(to: CGPoint(x: head.x + 14 + look, y: head.y + 8 + dy))
            w.addLine(to: CGPoint(x: head.x + 34 + look, y: head.y + 6 + dy + tilt))
            w.move(to: CGPoint(x: head.x - 6 + look, y: head.y + 8 + dy))
            w.addLine(to: CGPoint(x: head.x - 24 + look, y: head.y + 6 + dy + tilt))
            c.stroke(w, with: .color(ink.opacity(0.55)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }

        // Bola de lana (rueda: las hebras giran con el avance)
        let ballRect = CGRect(x: ballX - ballR, y: ballY - ballR, width: ballR * 2, height: ballR * 2)
        let ball = Path(ellipseIn: ballRect)
        c.fill(ball, with: .color(yarn))
        var inside = c
        inside.clip(to: ball)
        inside.translateBy(x: ballX, y: ballY)
        inside.rotate(by: .radians((ballX - 178) / ballR))
        for i in 0..<4 {
            var strand = Path()
            let off = Double(i) * 9 - 13
            strand.move(to: CGPoint(x: -ballR, y: off))
            strand.addQuadCurve(to: CGPoint(x: ballR, y: off - 6), control: CGPoint(x: 0, y: off + 9))
            inside.stroke(strand, with: .color(yarnDark.opacity(0.7)), style: StrokeStyle(lineWidth: 2))
        }
        var cross = Path()
        cross.move(to: CGPoint(x: -6, y: -ballR))
        cross.addQuadCurve(to: CGPoint(x: 4, y: ballR), control: CGPoint(x: 14, y: 0))
        inside.stroke(cross, with: .color(yarnDark.opacity(0.7)), style: StrokeStyle(lineWidth: 2))
        c.stroke(ball, with: .color(yarnDark.opacity(0.5)), lineWidth: 1)
    }
}
