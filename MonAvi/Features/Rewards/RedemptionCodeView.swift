import SwiftUI

/// El codigo que el usuario muestra en caja: grande, monoespaciado y
/// con su QR, mas el comercio, el producto y el vencimiento.
struct RedemptionCodeView: View {
    let redemption: RewardRedemption
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    merchantHeader
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
    }

    private var merchantHeader: some View {
        HStack(spacing: 14) {
            RewardPhotoView(urlString: redemption.item?.photoUrl, cornerRadius: 14)
                .frame(width: 96)
            VStack(alignment: .leading, spacing: 4) {
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
                RewardPointsPill(points: redemption.pointsCost)
            }
            Spacer(minLength: 0)
        }
    }

    private var codeCard: some View {
        VStack(spacing: 16) {
            Text("Tu código")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(redemption.code)
                .font(.system(size: 52, weight: .bold, design: .monospaced))
                .tracking(8)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(MonAviBrand.primaryDark)
                .textSelection(.enabled)
                .accessibilityLabel(spelledCode)
            qrImage
            RedemptionStatusBadge(status: redemption.effectiveStatus())
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    @ViewBuilder
    private var qrImage: some View {
        if let qr = QRCodeGenerator.image(from: redemption.code) {
            qr
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 180, height: 180)
                .padding(10)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    private var instructions: some View {
        VStack(spacing: 6) {
            Text("Muéstralo en caja para recibir tu \(redemption.itemName)")
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

    /// "A B C 1 2 3" para que VoiceOver lo lea letra por letra.
    private var spelledCode: String {
        redemption.code.map { String($0) }.joined(separator: " ")
    }
}
