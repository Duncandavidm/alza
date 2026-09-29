import SwiftUI

/// Animacion para cuando entra un pago (movementType == .ingreso): un
/// recibo "imprime" saliendo de una impresora, y al terminar le cae un
/// sello de PAGADO. Contraparte de CartLoadingView (esa es para cuando el
/// dinero sale, esta es para cuando el dinero entra).
struct ReceiptStampView: View {
    let description: String
    let amount: Decimal
    let message: String

    @State private var receiptHeight: CGFloat = 0
    @State private var stampScale: CGFloat = 2.4
    @State private var stampOpacity: Double = 0
    @State private var stampRotation: Double = -20

    private let receiptWidth: CGFloat = 190
    private let maxReceiptHeight: CGFloat = 140
    private let printerHeight: CGFloat = 30

    var body: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .top) {
                receipt
                    .frame(height: receiptHeight, alignment: .top)
                    .clipped()
                    .offset(y: printerHeight - 2)

                printer
            }
            .frame(width: receiptWidth, height: printerHeight + maxReceiptHeight)

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

    private var printer: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                LinearGradient(
                    colors: [Color(.systemGray3), Color(.systemGray5)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: receiptWidth + 14, height: printerHeight)
            .overlay(
                Capsule()
                    .fill(Color.black.opacity(0.85))
                    .frame(width: receiptWidth - 10, height: 4)
            )
    }

    private var receipt: some View {
        VStack(spacing: 6) {
            Text("ALZA")
                .font(.system(size: 15, weight: .black, design: .monospaced))
                .padding(.top, 16)
            Text("RECIBO DE PAGO")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)

            Rectangle()
                .frame(height: 1)
                .foregroundStyle(.secondary.opacity(0.35))
                .padding(.horizontal, 14)
                .padding(.top, 2)

            VStack(spacing: 3) {
                HStack {
                    Text(description.isEmpty ? "Pago recibido" : description)
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                    Spacer()
                }
                HStack {
                    Text("TOTAL")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                    Spacer()
                    Text(amount, format: .currency(code: "USD"))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)

            Spacer(minLength: 6)

            Text("PAGADO")
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.green, lineWidth: 3))
                .rotationEffect(.degrees(stampRotation))
                .scaleEffect(stampScale)
                .opacity(stampOpacity)
                .padding(.bottom, 14)
        }
        .frame(width: receiptWidth)
        .background(Color(.systemBackground))
        .clipShape(ReceiptShape())
    }

    private func animate() {
        withAnimation(.easeOut(duration: 0.9)) {
            receiptHeight = maxReceiptHeight
        }
        withAnimation(.interpolatingSpring(stiffness: 200, damping: 13).delay(0.85)) {
            stampScale = 1
            stampOpacity = 1
            stampRotation = -12
        }
    }
}

/// Rectangulo con el borde inferior en zigzag, como el filo de un recibo
/// de impresora termica al arrancarlo.
private struct ReceiptShape: Shape {
    var teeth: Int = 9

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
