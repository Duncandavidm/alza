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

/// Espera con personalidad: un gato verde MonAvi boca arriba en su cojin,
/// jugando con una bola de lana. Se muestra mientras se lee una factura
/// compartida o mientras la IA hace un analisis.
///
/// La ilustracion son 48 cuadros (MonAviCat00...MonAviCat47 en
/// Assets.xcassets) que se pasan a 24 por segundo; el sistema los guarda
/// en cache y los libera si hace falta memoria. Con "Reducir movimiento"
/// se muestra un solo cuadro quieto.
struct MonAviCatLoader: View {
    var message: String
    var size: CGFloat = 240
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let frameCount = 48
    private static let framesPerSecond = 24.0

    var body: some View {
        VStack(spacing: 12) {
            TimelineView(.animation(minimumInterval: 1 / Self.framesPerSecond, paused: reduceMotion)) { context in
                let index = reduceMotion
                    ? 10
                    : Int(context.date.timeIntervalSinceReferenceDate * Self.framesPerSecond) % Self.frameCount
                Image(String(format: "MonAviCat%02d", index))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            }
            .frame(width: size, height: size * 0.75)
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
