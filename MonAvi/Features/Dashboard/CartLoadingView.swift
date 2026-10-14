import SwiftUI

/// Animacion que se muestra al guardar un movimiento: el emoji de la
/// categoria (o del tipo de movimiento, cuando no hay categoria) cae dentro
/// de un carrito que se mece y se va "llenando", y luego se regresa a la
/// pantalla principal. Inspirada en el patron de "Adding to your bag" de
/// apps de e-commerce, adaptada para confirmar que se anoto un movimiento.
struct CartLoadingView: View {
    let itemEmoji: String
    let message: String

    @State private var itemOffset: CGFloat = -90
    @State private var itemOpacity: Double = 0
    @State private var itemScale: CGFloat = 0.6
    @State private var cartRock: Double = -4
    @State private var fillProgress: CGFloat = 0

    private let cartSize: CGFloat = 72

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                cart
                    .rotationEffect(.degrees(cartRock), anchor: .bottom)

                Text(itemEmoji)
                    .font(.system(size: 30))
                    .scaleEffect(itemScale)
                    .offset(y: itemOffset)
                    .opacity(itemOpacity)
            }
            .frame(height: cartSize + 40)

            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 12, y: 4)
        .onAppear { animate() }
    }

    private var cart: some View {
        ZStack {
            Image(systemName: "cart.fill")
                .font(.system(size: cartSize))
                .foregroundStyle(Color(.tertiarySystemFill))

            Image(systemName: "cart.fill")
                .font(.system(size: cartSize))
                .foregroundStyle(Color.accentColor)
                .mask(alignment: .bottom) {
                    Rectangle()
                        .frame(maxWidth: .infinity)
                        .frame(height: cartSize * fillProgress)
                }
        }
    }

    private func animate() {
        // El "producto" cae, rebota un toque, y se desvanece como si ya
        // hubiera entrado al carrito.
        withAnimation(.interpolatingSpring(stiffness: 170, damping: 12).delay(0.1)) {
            itemOffset = 4
            itemScale = 1
            itemOpacity = 1
        }
        withAnimation(.easeIn(duration: 0.25).delay(0.55)) {
            itemOffset = -6
            itemOpacity = 0
        }

        // El carrito se "llena" de color como indicador de progreso.
        withAnimation(.easeInOut(duration: 1.1)) {
            fillProgress = 1
        }

        // Se mece suavemente todo el tiempo que este visible.
        withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) {
            cartRock = 5
        }
    }
}
