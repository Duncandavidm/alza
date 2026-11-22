import SwiftUI

// Retos por comercio ("Escanea 3 facturas de Café X y gana un café"). Se
// calcula en el servidor (my_merchant_challenges, 0083); el premio llega
// solo a "Mis canjes", con aviso.

struct MerchantChallenge: Decodable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let merchant: String
    let merchantLogoURL: URL?
    let coupon: String
    let required: Int
    let endsAt: Date?
    let confirmed: Int
    let pending: Int
    let won: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, merchant, coupon, required, confirmed, pending, won
        case merchantLogoURL = "merchant_logo_url"
        case endsAt = "ends_at"
    }

    init(id: UUID = UUID(), title: String, merchant: String, merchantLogoURL: URL? = nil, coupon: String,
         required: Int, endsAt: Date? = nil, confirmed: Int, pending: Int = 0, won: Bool = false) {
        self.id = id
        self.title = title
        self.merchant = merchant
        self.merchantLogoURL = merchantLogoURL
        self.coupon = coupon
        self.required = required
        self.endsAt = endsAt
        self.confirmed = confirmed
        self.pending = pending
        self.won = won
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        merchant = (try? c.decode(String.self, forKey: .merchant)) ?? ""
        merchantLogoURL = (try? c.decodeIfPresent(String.self, forKey: .merchantLogoURL)).flatMap(URL.init(string:))
        coupon = (try? c.decode(String.self, forKey: .coupon)) ?? "Premio"
        required = max((try? c.decode(Int.self, forKey: .required)) ?? 3, 1)
        endsAt = (try? c.decodeIfPresent(String.self, forKey: .endsAt)).flatMap(MerchantChallengesText.date(fromTimestamp:))
        confirmed = (try? c.decode(Int.self, forKey: .confirmed)) ?? 0
        pending = (try? c.decode(Int.self, forKey: .pending)) ?? 0
        won = (try? c.decode(Bool.self, forKey: .won)) ?? false
    }
}

/// Textos (logica pura, probada en MerchantChallengesTests).
enum MerchantChallengesText {
    static func facturas(_ n: Int) -> String { n == 1 ? "1 factura" : "\(n) facturas" }

    static func fraction(confirmed: Int, of goal: Int) -> Double {
        guard goal > 0 else { return 0 }
        return min(Double(confirmed) / Double(goal), 1)
    }

    static func challengeProgress(_ challenge: MerchantChallenge) -> String {
        if challenge.won { return "¡Ganaste! Tu premio está en Mis canjes." }
        let shown = min(challenge.confirmed, challenge.required)
        let pending = challenge.pending > 0 ? " (+\(challenge.pending) por confirmar)" : ""
        return "\(shown) de \(facturas(challenge.required))\(pending)"
    }

    static func date(fromTimestamp value: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: value) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value)
    }
}

enum MerchantChallengesRepository {
    static func fetchChallenges() async -> [MerchantChallenge] {
        (try? await SupabaseManager.shared.client.rpc("my_merchant_challenges").execute().value) ?? []
    }
}

// MARK: - Vistas

/// Retos por comercio en Descuentos.
struct MerchantChallengesSection: View {
    let challenges: [MerchantChallenge]

    var body: some View {
        if !challenges.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Retos de facturas")
                    .font(.headline)
                ForEach(challenges) { challenge in
                    row(challenge)
                }
            }
        }
    }

    private func row(_ challenge: MerchantChallenge) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: challenge.merchantLogoURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Text("🏆").font(.title3)
            }
            .frame(width: 44, height: 44)
            .background(MonAviBrand.primary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(challenge.title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                ProgressView(value: MerchantChallengesText.fraction(confirmed: challenge.won ? challenge.required : challenge.confirmed, of: challenge.required))
                    .tint(MonAviBrand.primary)
                HStack {
                    Text(MerchantChallengesText.challengeProgress(challenge))
                    Spacer()
                    if let endsAt = challenge.endsAt, !challenge.won {
                        Text("Hasta el \(endsAt.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: .monavi)))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
