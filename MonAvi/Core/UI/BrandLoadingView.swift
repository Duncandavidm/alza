import SwiftUI

/// Pantalla de carga de marca: el mark de MonAvi al centro con un anillo
/// que "respira", un mensaje corto debajo y billetes verdes cayendo
/// suavemente al fondo sobre el degradado oscuro de marca.
///
/// Se usa en vez de un `ProgressView()` suelto en todos los estados de
/// arranque (sesion, MFA, onboarding, suscripcion) y como overlay al
/// iniciar sesion, para que la app nunca muestre una pantalla en blanco.
struct BrandLoadingView: View {
    var message: String = "Preparando tu MonAvi…"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var gradientVisible = BrandLoadingLaunchState.hasAppearedOnce

    // La primera vez que aparece (justo despues del launch screen) el
    // fondo arranca en `darkSurface` — el mismo color que
    // LaunchBackground — y el degradado entra con un fade, para que el
    // paso launch -> carga no se note. Las siguientes veces el degradado
    // ya esta puesto desde el inicio (ver BrandLoadingLaunchState).

    var body: some View {
        ZStack {
            background

            FallingBillsLayer(animated: !reduceMotion)
                .accessibilityHidden(true)

            ZStack {
                Circle()
                    .fill(MonAviBrand.accentOnDark.opacity(0.08))
                    .frame(width: 150, height: 150)
                    .scaleEffect(pulse ? 1.06 : 0.92)

                Circle()
                    .stroke(MonAviBrand.accentOnDark.opacity(0.55), lineWidth: 2)
                    .frame(width: 170, height: 170)
                    .scaleEffect(pulse ? 1.06 : 0.92)
                    .opacity(pulse ? 0.35 : 0.9)

                EmbeddedLogo.monAviMarkWhite
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84, height: 84)
            }

            Text(message.uppercased())
                .font(.system(.caption, design: MonAviBrand.fontDesign).weight(.bold))
                .tracking(3)
                .foregroundStyle(MonAviBrand.onDarkSurface.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .offset(y: 85 + 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
        .onAppear {
            if !gradientVisible {
                withAnimation(.easeOut(duration: 0.7)) {
                    gradientVisible = true
                }
            }
            BrandLoadingLaunchState.hasAppearedOnce = true

            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var background: some View {
        ZStack {
            MonAviBrand.darkSurface
            MonAviBrand.headerGradient
                .opacity(gradientVisible ? 1 : 0)
        }
        .ignoresSafeArea()
    }
}

/// Recuerda si ya se mostro una BrandLoadingView en este lanzamiento
/// (fuera del View para no mezclarlo con el aislamiento de actor de View).
private enum BrandLoadingLaunchState {
    static var hasAppearedOnce = false
}

// MARK: - Billetes cayendo

/// Parametros fijos (pseudo-aleatorios pero deterministas) de cada billete.
private struct FallingBillSpec {
    let x: CGFloat           // 0...1, fraccion del ancho
    let width: CGFloat       // 44...90 pt
    let duration: Double     // 6...11 s por caida completa
    let phase: Double        // 0...1, desfase inicial en la caida
    let swaySpeed: Double    // rad/s del vaiven horizontal
    let swayPhase: Double
    let rotationAmplitude: Double // grados, hasta ±25
    let rotationSpeed: Double
    let rotationPhase: Double
    let opacity: Double      // 0.18...0.45

    static let all: [FallingBillSpec] = {
        var seed: UInt64 = 0x4D6F6E417669 // "MonAvi"
        func next() -> Double {
            // LCG simple: mismo resultado en cada lanzamiento.
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
        }
        func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * next() }

        let count = 14
        return (0..<count).map { index in
            // Repartir las columnas para que no se amontonen, con algo de jitter.
            let column = (Double(index) + range(0.15, 0.85)) / Double(count)
            return FallingBillSpec(
                x: CGFloat(column),
                width: CGFloat(range(44, 90)),
                duration: range(6, 11),
                phase: next(),
                swaySpeed: range(0.6, 1.3),
                swayPhase: range(0, .pi * 2),
                rotationAmplitude: range(10, 25),
                rotationSpeed: range(0.3, 0.8),
                rotationPhase: range(0, .pi * 2),
                opacity: range(0.18, 0.45)
            )
        }
    }()
}

/// Capa de billetes. Las posiciones se calculan a partir del tiempo dentro
/// de un solo `TimelineView` (sin timers por billete). Con "Reducir
/// movimiento" los billetes se quedan quietos.
private struct FallingBillsLayer: View {
    let animated: Bool

    var body: some View {
        GeometryReader { proxy in
            if animated {
                TimelineView(.animation) { context in
                    bills(in: proxy.size, time: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                bills(in: proxy.size, time: 0)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func bills(in size: CGSize, time: Double) -> some View {
        ZStack {
            ForEach(FallingBillSpec.all.indices, id: \.self) { index in
                let spec = FallingBillSpec.all[index]
                let height = spec.width / 2.3
                let progress = (time / spec.duration + spec.phase).truncatingRemainder(dividingBy: 1)
                let travel = size.height + height * 2
                let y = -height + CGFloat(progress) * travel
                let sway = CGFloat(sin(time * spec.swaySpeed + spec.swayPhase)) * 12
                let x = spec.x * size.width + sway
                let angle = sin(time * spec.rotationSpeed + spec.rotationPhase) * spec.rotationAmplitude

                DollarBillView(width: spec.width)
                    .rotationEffect(.degrees(angle))
                    .opacity(spec.opacity)
                    .position(x: x, y: y)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

/// Un billete de dolar estilizado: legible como billete aun en tamaño
/// pequeño.
private struct DollarBillView: View {
    let width: CGFloat

    private static let lightGreen = Color(hex: "#2E9B5F") ?? .green
    private static let darkGreen = Color(hex: "#1E7A48") ?? .green
    private static let ink = Color(hex: "#D9F2E3") ?? .white

    var body: some View {
        let height = width / 2.3
        let inset = max(2, width * 0.05)

        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Self.lightGreen, Self.darkGreen],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .stroke(Self.ink.opacity(0.55), lineWidth: max(0.75, width * 0.015))
                .padding(inset)

            HStack {
                Ellipse()
                    .fill(Self.ink.opacity(0.35))
                    .frame(width: width * 0.12, height: height * 0.3)
                Spacer(minLength: 0)
                Ellipse()
                    .fill(Self.ink.opacity(0.35))
                    .frame(width: width * 0.12, height: height * 0.3)
            }
            .padding(.horizontal, inset + width * 0.06)

            Circle()
                .fill(Self.darkGreen)
                .overlay(
                    Circle().stroke(Self.ink.opacity(0.7), lineWidth: max(0.75, width * 0.015))
                )
                .frame(width: height * 0.62, height: height * 0.62)

            Text("$")
                .font(.system(size: height * 0.42, weight: .heavy, design: .rounded))
                .foregroundStyle(Self.ink)
        }
        .frame(width: width, height: height)
    }
}

#Preview {
    BrandLoadingView()
}

#Preview("Entrando") {
    BrandLoadingView(message: "Entrando…")
}
