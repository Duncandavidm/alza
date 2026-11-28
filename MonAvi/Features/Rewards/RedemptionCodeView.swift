import SwiftUI
import UIKit

/// El codigo que el usuario muestra en caja: grande, monoespaciado y
/// con su QR, mas el comercio, el producto y el vencimiento.
struct RedemptionCodeView: View {
    let redemption: RewardRedemption
    /// true cuando se acaba de generar el codigo: se abre celebrando.
    var celebrate: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    /// Brillo que tenia la pantalla antes de abrir el codigo, para
    /// devolverlo al cerrar (el brillo al maximo ayuda al lector de caja).
    @State private var previousBrightness: CGFloat?
    @State private var isScanningInvoice = false
    /// Lluvia de billetes (cambia el id para repetirla).
    @State private var isRaining = false
    @State private var rainBurst = 0
    /// Cuando el cajero valida el codigo (se revisa cada pocos segundos
    /// mientras esta pantalla esta abierta).
    @State private var deliveredNow = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    unlockedBanner
                    merchantHeader
                    giftMessageCard
                    codeCard
                    WalletPassSection(redemption: redemption)
                    instructions
                    invoiceCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Tu canje")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
            // "Cómo llegar" fijo abajo: en un iPhone pequeño queda siempre
            // visible sin tener que hacer scroll bajo el QR.
            .safeAreaInset(edge: .bottom) { directionsBar }
        }
        .invoiceScanner(isPresented: $isScanningInvoice)
        .overlay {
            if deliveredNow {
                deliveredCard
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .overlay {
            if isRaining {
                MoneyRainView { isRaining = false }
                    .id(rainBurst)
                    .ignoresSafeArea()
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: deliveredNow)
        .onAppear {
            raiseBrightness()
            if celebrate { celebrateNow() }
        }
        .onDisappear { restoreBrightness() }
        .task { await watchForDelivery() }
    }

    /// "¡Desbloqueaste 20% de descuento en Café La Esquina!" al abrirse
    /// justo despues de desbloquear un descuento o bono con cashback.
    @ViewBuilder
    private var unlockedBanner: some View {
        if celebrate, !redemption.isBenefit, !redemption.isGift, let item = redemption.item, item.kind.isDiscount {
            Text(item.unlockedTitle)
                .font(.system(.title3, design: MonAviBrand.fontDesign, weight: .heavy))
                .multilineTextAlignment(.center)
                .foregroundStyle(MonAviBrand.primaryDark)
                .frame(maxWidth: .infinity)
        }
    }

    private func celebrateNow() {
        CelebrationFeedback.playRedemption()
        rainBurst += 1
        isRaining = true
    }

    /// Mientras el codigo sigue vigente, revisa cada 4 segundos si el
    /// comercio ya lo valido para celebrar con la persona en ese momento.
    private func watchForDelivery() async {
        guard redemption.isUsable() else { return }
        let deadline = Date().addingTimeInterval(20 * 60)
        while !Task.isCancelled && Date() < deadline {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            if let state = await RewardsRepository.shared.fetchRedemptionStatus(id: redemption.id) {
                if state.status == .entregado {
                    restoreBrightness()
                    deliveredNow = true
                    celebrateNow()
                    return
                }
                if state.status != .emitido { return }
            }
        }
    }

    /// "¡Canje listo!": aparece cuando el cajero valida el codigo.
    private var deliveredCard: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("🎉")
                    .font(.system(size: 64))
                Text(redemption.isDiscount ? L("¡Descuento aplicado!") : L("¡Canje listo!"))
                    .font(.system(.title, design: MonAviBrand.fontDesign, weight: .heavy))
                    .multilineTextAlignment(.center)
                Text("\(redemption.itemName) en \(redemption.merchantName)")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Text("¡Disfrútalo! Pide tu factura fiscal y escanéala: cada factura te da cashback para tu próximo canje.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    deliveredNow = false
                    isScanningInvoice = true
                } label: {
                    Label("Escanear mi factura", systemImage: "qrcode.viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(MonAviBrand.primary)
                Button("Listo") { dismiss() }
                    .font(.subheadline.weight(.semibold))
            }
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color(.systemBackground)))
            .padding(.horizontal, 28)
        }
    }

    private func raiseBrightness() {
        guard previousBrightness == nil else { return }
        previousBrightness = UIScreen.main.brightness
        UIScreen.main.brightness = 1.0
    }

    private func restoreBrightness() {
        guard let previousBrightness else { return }
        UIScreen.main.brightness = previousBrightness
        self.previousBrightness = nil
    }

    private var merchantHeader: some View {
        HStack(spacing: 14) {
            RewardPhotoView(
                urlString: redemption.item?.photoUrl,
                cornerRadius: 14,
                placeholderSymbol: (redemption.item?.kind ?? .producto).placeholderSymbol
            )
            .frame(width: 96)
            VStack(alignment: .leading, spacing: 4) {
                if redemption.isGift {
                    GiftBadge()
                }
                HStack(spacing: 6) {
                    MerchantLogoView(
                        urlString: redemption.displayMerchant?.logoUrl,
                        name: redemption.merchantName,
                        size: 22
                    )
                    Text(redemption.merchantName)
                        .font(.system(.headline, design: MonAviBrand.fontDesign, weight: .bold))
                        .lineLimit(1)
                }
                Text(redemption.itemName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if redemption.isGift {
                    Text("Gratis")
                        .font(.system(.subheadline, design: MonAviBrand.fontDesign, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(MonAviBrand.primary.opacity(0.15), in: Capsule())
                        .foregroundStyle(MonAviBrand.primaryDark)
                } else if !redemption.isBenefit {
                    RewardPointsPill(points: redemption.pointsCost, currency: redemption.displayCurrency)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var giftMessageCard: some View {
        if redemption.isGift, let message = redemption.displayGiftMessage {
            HStack(alignment: .top, spacing: 10) {
                Text("🎁").font(.title2)
                Text(message)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.orange.opacity(0.12))
            )
        }
    }

    private var codeCard: some View {
        VStack(spacing: 16) {
            qrImage
            VStack(spacing: 4) {
                Text("Tu código")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(redemption.code)
                    .font(.system(size: 52, weight: .bold, design: .monospaced))
                    .tracking(10)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(MonAviBrand.primaryDark)
                    .textSelection(.enabled)
                    .accessibilityLabel(spelledCode)
            }
            RedemptionStatusBadge(status: redemption.effectiveStatus(), text: redemption.statusText())
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    /// QR grande (260 pt) sin suavizado, con correccion de errores alta y
    /// margen blanco alrededor (zona de silencio) para que el lector de
    /// caja lo lea a la primera, incluso en modo oscuro.
    @ViewBuilder
    private var qrImage: some View {
        if let qr = QRCodeGenerator.image(from: qrPayload, correctionLevel: "H") {
            qr
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 220, height: 220)
                .padding(16)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var instructions: some View {
        if redemption.isBenefit {
            // Codigo de 15 minutos: cuenta regresiva en vivo.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 6) {
                    Text("Muéstralo en caja antes de pagar: te aplican el descuento.")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    if let countdown = BenefitsMath.countdownText(until: redemption.expiresAt, now: context.date) {
                        Label("Vence en \(countdown)", systemImage: "timer")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(MonAviBrand.primaryDark)
                    } else {
                        Text("Este código venció. Vuelve a Descuentos y genera uno nuevo.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MonAviBrand.alert)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: 6) {
                Text(redemption.isDiscount
                     ? L("Muéstralo en caja antes de pagar: te aplican el beneficio.")
                     : L("Muéstralo en caja: el comercio escanea el código y te lo entrega."))
                    .font(.headline)
                    .multilineTextAlignment(.center)
                if let minPurchase = redemption.item?.minPurchaseText {
                    Label(minPurchase, systemImage: "cart")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MonAviBrand.primaryDark)
                }
                Text("Vence el \(redemption.expiresAt.formatted(Date.FormatStyle(date: .long, time: .shortened, locale: .monavi)))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Pedir la factura fiscal: es la que da el cashback (y la que le
    /// muestra al comercio cuanto le trajo el descuento).
    private var invoiceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text("🧾").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pide tu factura fiscal")
                        .font(.subheadline.weight(.bold))
                    Text(redemption.isBenefit
                         ? L("Escanéala después de pagar y ganas cashback además del descuento.")
                         : L("Si compras algo más, escanea la factura y gana cashback."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button {
                isScanningInvoice = true
            } label: {
                Label("Escanear mi factura", systemImage: "qrcode.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(MonAviBrand.primary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(MonAviBrand.primary.opacity(0.10))
        )
    }

    /// Barra de accion fija al fondo (safeAreaInset): solo aparece si el
    /// comercio tiene ubicacion. Fondo propio para separarla del contenido
    /// que pasa por debajo al hacer scroll.
    @ViewBuilder
    private var directionsBar: some View {
        let options = RewardsMath.directionsOptions(for: redemption.displayMerchant)
        if options.count > 1 {
            // Comercio con sucursales: se elige a cual ir.
            Menu {
                ForEach(options) { (option: DirectionsOption) in
                    Button {
                        openURL(option.url)
                    } label: {
                        Text(option.title)
                        if let subtitle = option.subtitle { Text(subtitle) }
                    }
                }
            } label: {
                Label("Cómo llegar (\(options.count) sucursales)", systemImage: "map.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(MonAviBrand.primary)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background(.bar)
        } else if let url = options.first?.url {
            Button {
                openURL(url)
            } label: {
                Label("Cómo llegar", systemImage: "map.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(MonAviBrand.primary)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }

    /// El QR lleva el link de validacion con el codigo
    /// (`https://monavi.maday.app/canjear?code=...`) para que el cajero lo
    /// abra con la camara de cualquier telefono; si no se pudiera armar el
    /// link, cae al codigo solo.
    private var qrPayload: String {
        RewardsMath.redeemURL(code: redemption.code)?.absoluteString ?? redemption.code
    }

    /// "A B C 1 2 3" para que VoiceOver lo lea letra por letra.
    private var spelledCode: String {
        redemption.code.map { String($0) }.joined(separator: " ")
    }
}
