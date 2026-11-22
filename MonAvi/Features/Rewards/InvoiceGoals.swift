import SwiftUI

// Meta mensual de facturas ("Llevas 8 de 15 facturas este mes") y retos
// por comercio ("Escanea 3 facturas de Café X y gana un café"). Todo se
// calcula en el servidor (my_invoice_goal / my_merchant_challenges, 0083);
// el premio llega solo a "Mis canjes", con aviso.

struct InvoiceGoal: Decodable, Equatable {
    let confirmed: Int
    let pending: Int
    let goal: Int
    let coupon: String?
    let merchant: String?
    let imageURL: URL?
    let earned: Bool

    enum CodingKeys: String, CodingKey {
        case confirmed, pending, goal, coupon, merchant, earned
        case imageURL = "image_url"
    }

    init(confirmed: Int, pending: Int, goal: Int, coupon: String? = nil, merchant: String? = nil, imageURL: URL? = nil, earned: Bool = false) {
        self.confirmed = confirmed
        self.pending = pending
        self.goal = goal
        self.coupon = coupon
        self.merchant = merchant
        self.imageURL = imageURL
        self.earned = earned
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        confirmed = (try? c.decode(Int.self, forKey: .confirmed)) ?? 0
        pending = (try? c.decode(Int.self, forKey: .pending)) ?? 0
        goal = max((try? c.decode(Int.self, forKey: .goal)) ?? 15, 1)
        coupon = try? c.decodeIfPresent(String.self, forKey: .coupon)
        merchant = try? c.decodeIfPresent(String.self, forKey: .merchant)
        imageURL = (try? c.decodeIfPresent(String.self, forKey: .imageURL)).flatMap(URL.init(string:))
        earned = (try? c.decode(Bool.self, forKey: .earned)) ?? false
    }
}

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
        endsAt = (try? c.decodeIfPresent(String.self, forKey: .endsAt)).flatMap(InvoiceGoalsText.date(fromTimestamp:))
        confirmed = (try? c.decode(Int.self, forKey: .confirmed)) ?? 0
        pending = (try? c.decode(Int.self, forKey: .pending)) ?? 0
        won = (try? c.decode(Bool.self, forKey: .won)) ?? false
    }
}

/// Textos (logica pura, probada en InvoiceGoalsTests).
enum InvoiceGoalsText {
    static func facturas(_ n: Int) -> String { n == 1 ? "1 factura" : "\(n) facturas" }

    static func progress(_ goal: InvoiceGoal) -> String {
        if goal.confirmed >= goal.goal { return "¡Llegaste a \(facturas(goal.goal)) este mes!" }
        return "Llevas \(goal.confirmed) de \(facturas(goal.goal)) este mes"
    }

    static func detail(_ goal: InvoiceGoal) -> String {
        let pending = goal.pending > 0 ? " · \(goal.pending) por confirmar" : ""
        if goal.earned, let coupon = goal.coupon {
            return "Ganaste \(coupon)\(goal.merchant.map { " en \($0)" } ?? ""): está en Mis canjes."
        }
        if goal.confirmed >= goal.goal {
            return goal.coupon != nil ? "Tu cupón llega mañana con un aviso.\(pending)" : "¡Bien hecho! Sigue sumando cashback.\(pending)"
        }
        let missing = goal.goal - goal.confirmed
        if let coupon = goal.coupon {
            return "Te faltan \(facturas(missing)) para ganar \(coupon)\(goal.merchant.map { " en \($0)" } ?? "")\(pending)"
        }
        return "Cada factura suma cashback\(pending)"
    }

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

enum InvoiceGoalsRepository {
    static func fetchGoal() async -> InvoiceGoal? {
        try? await SupabaseManager.shared.client.rpc("my_invoice_goal").execute().value
    }

    static func fetchChallenges() async -> [MerchantChallenge] {
        (try? await SupabaseManager.shared.client.rpc("my_merchant_challenges").execute().value) ?? []
    }
}

// MARK: - Vistas

/// Tarjeta de Hoy: "Llevas 8 de 15 facturas este mes" + escanear.
struct InvoiceGoalCard: View {
    let goal: InvoiceGoal
    var onScan: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(MonAviBrand.primary.opacity(0.18), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: InvoiceGoalsText.fraction(confirmed: goal.confirmed, of: goal.goal))
                    .stroke(MonAviBrand.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("🧾").font(.system(size: 18))
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text(InvoiceGoalsText.progress(goal))
                    .font(.subheadline.weight(.semibold))
                Text(InvoiceGoalsText.detail(goal))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button(action: onScan) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(MonAviBrand.primary, in: Circle())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Escanear factura")
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

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
                ProgressView(value: InvoiceGoalsText.fraction(confirmed: challenge.won ? challenge.required : challenge.confirmed, of: challenge.required))
                    .tint(MonAviBrand.primary)
                HStack {
                    Text(InvoiceGoalsText.challengeProgress(challenge))
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
