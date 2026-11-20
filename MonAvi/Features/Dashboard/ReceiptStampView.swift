import SwiftUI

/// Animacion para cuando entra un pago (movementType == .ingreso): un
/// recibo "imprime" saliendo de una impresora, y al terminar le cae un
/// sello de PAGADO. Contraparte de CartLoadingView (esa es para cuando el
/// dinero sale, esta es para cuando el dinero entra).
///
/// La tarjeta es solida (no material translucido) y el papel siempre es
/// blanco con texto negro, como un recibo termico real, para que se lea
/// bien sobre el fondo oscurecido en modo claro y oscuro. El sello cae
/// dentro del papel, debajo del total, asi nunca queda cortado.
struct ReceiptStampView: View {
    let description: String
    let amount: Decimal
    let message: String

    @State private var receiptHeight: CGFloat = 0
    @State private var stampScale: CGFloat = 1.8
    @State private var stampOpacity: Double = 0
    @State private var stampRotation: Double = -24

    private let receiptWidth: CGFloat = 220
    private let maxReceiptHeight: CGFloat = 228
    private let printerHeight: CGFloat = 34
    /// Cuanto del papel queda escondido dentro de la ranura de la impresora.
    private let slotOverlap: CGFloat = 6

    private static let logo = EmbeddedLogo.monAviMark
    private let printedAt = Date()

    private let ink = Color.black.opacity(0.88)
    private let fadedInk = Color.black.opacity(0.55)
    private let stampGreen = Color(red: 0.0, green: 0.58, blue: 0.40)

    var body: some View {
        VStack(spacing: 20) {
            ZStack(alignment: .top) {
                receipt
                    .frame(height: receiptHeight, alignment: .top)
                    .clipped()
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 3)
                    .offset(y: printerHeight - slotOverlap)

                printer
            }
            .frame(
                width: receiptWidth + 28,
                height: printerHeight - slotOverlap + maxReceiptHeight,
                alignment: .top
            )

            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 26)
        .padding(.top, 24)
        .padding(.bottom, 22)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recibo de pago de MonAvi. \(description.isEmpty ? "Pago recibido" : description). Total \(amount.formatted(.currency(code: "USD"))). Pagado.")
        .onAppear { animate() }
    }

    // MARK: - Impresora

    private var printer: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.30), Color(white: 0.16)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Ranura por donde sale el papel.
            Capsule()
                .fill(Color.black)
                .frame(width: receiptWidth + 6, height: 5)
                .offset(y: printerHeight / 2 - 8)

            // Luz verde de "imprimiendo".
            Circle()
                .fill(stampGreen)
                .frame(width: 6, height: 6)
                .shadow(color: stampGreen.opacity(0.8), radius: 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 8)
                .padding(.trailing, 12)
        }
        .frame(width: receiptWidth + 28, height: printerHeight)
        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
    }

    // MARK: - Papel

    private var receipt: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MonAvi")
                        .font(.system(size: 17, weight: .black, design: .monospaced))
                        .foregroundStyle(ink)
                    Text("RECIBO DE PAGO")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(fadedInk)
                }
                Spacer(minLength: 4)
                Self.logo
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
            }

            DashedLine()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(fadedInk)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(description.isEmpty ? "Pago recibido" : description)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("FECHA")
                    Spacer()
                    Text(printedAt.formatted(Date.FormatStyle(date: .numeric, time: .shortened, locale: .monavi)))
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(fadedInk)
            }

            DashedLine()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(fadedInk)
                .frame(height: 1)

            HStack(alignment: .firstTextBaseline) {
                Text("TOTAL")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                Spacer()
                Text(amount, format: .currency(code: "USD"))
                    .font(.system(size: 15, weight: .heavy, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(ink)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        // Espacio para el sello y los dientes del borde inferior.
        .padding(.bottom, 14)
        .frame(width: receiptWidth, height: maxReceiptHeight, alignment: .top)
        .overlay(alignment: .bottom) {
            stamp
                .padding(.bottom, 22)
        }
        .background(Color.white)
        .clipShape(ReceiptShape())
    }

    private var stamp: some View {
        Text("PAGADO")
            .font(.system(size: 24, weight: .black, design: .rounded))
            .tracking(2)
            .foregroundStyle(stampGreen)
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(stampGreen, lineWidth: 3)
            )
            .rotationEffect(.degrees(stampRotation))
            .scaleEffect(stampScale)
            .opacity(stampOpacity)
    }

    private func animate() {
        withAnimation(.easeOut(duration: 0.9)) {
            receiptHeight = maxReceiptHeight
        }
        withAnimation(.interpolatingSpring(stiffness: 200, damping: 13).delay(0.85)) {
            stampScale = 1
            stampOpacity = 0.92
            stampRotation = -10
        }
        // Vibracion + sonido justo cuando cae el sello — es el instante
        // que se "siente" como la celebracion, no cuando empieza a imprimir.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            CelebrationFeedback.playIncome()
        }
    }
}

/// Linea horizontal (se dibuja punteada con un StrokeStyle con dash).
private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// Rectangulo con el borde inferior en zigzag, como el filo de un recibo
/// de impresora termica al arrancarlo.
private struct ReceiptShape: Shape {
    var teeth: Int = 11

    func path(in rect: CGRect) -> Path {
        let toothHeight: CGFloat = 8
        let bodyBottom = rect.minY + rect.height - toothHeight
        let step = rect.width / CGFloat(teeth)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: bodyBottom))

        var x = rect.maxX
        for _ in 0..<teeth {
            let midX = x - step / 2
            let nextX = x - step
            path.addLine(to: CGPoint(x: midX, y: bodyBottom + toothHeight))
            path.addLine(to: CGPoint(x: nextX, y: bodyBottom))
            x = nextX
        }

        path.addLine(to: CGPoint(x: rect.minX, y: bodyBottom))
        path.closeSubpath()
        return path
    }
}
