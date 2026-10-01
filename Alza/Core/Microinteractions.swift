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
