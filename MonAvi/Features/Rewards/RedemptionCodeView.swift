import SwiftUI
import UIKit

/// El codigo que el usuario muestra en caja: grande, monoespaciado y
/// con su QR, mas el comercio, el producto y el vencimiento.
struct RedemptionCodeView: View {
    let redemption: RewardRedemption
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    /// Brillo que tenia la pantalla antes de abrir el codigo, para
    /// devolverlo al cerrar (el brillo al maximo ayuda al lector de caja).
    @State private var previousBrightness: CGFloat?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    merchantHeader
                    giftMessageCard
                    codeCard
                    instructions
                    directionsButton
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Tu canje")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
        .onAppear { raiseBrightness() }
        .onDisappear { restoreBrightness() }
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
            RewardPhotoView(urlString: redemption.item?.photoUrl, cornerRadius: 14)
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
                } else {
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
            RedemptionStatusBadge(status: redemption.effectiveStatus())
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
                .frame(width: 260, height: 260)
                .padding(16)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    private var instructions: some View {
        VStack(spacing: 6) {
            Text("Muéstralo en caja. El comercio lo valida con su PIN.")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Vence el \(redemption.expiresAt.formatted(date: .long, time: .shortened))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var directionsButton: some View {
        if let url = RewardsMath.directionsURL(for: redemption.displayMerchant) {
            Button {
                openURL(url)
            } label: {
                Label("Cómo llegar", systemImage: "map.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(MonAviBrand.primary)
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
