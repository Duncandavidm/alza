import SwiftUI

/// «Tus compras»: los productos de tus facturas con su precio, para ver en
/// que comercio te salio mas barato lo que compras seguido. Los datos son
/// los renglones de las facturas ya leidas (my_purchases, 0083).
struct Purchase: Decodable, Equatable, Identifiable {
    let id = UUID()
    let description: String
    let merchant: String
    let quantity: Double?
    let unitPrice: Double?
    let total: Double?
    let boughtAt: Date?

    enum CodingKeys: String, CodingKey {
        case description, merchant, quantity, total
        case unitPrice = "unit_price"
        case boughtAt = "bought_at"
    }

    init(description: String, merchant: String, quantity: Double? = 1, unitPrice: Double?, total: Double? = nil, boughtAt: Date? = nil) {
        self.description = description
        self.merchant = merchant
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.total = total
        self.boughtAt = boughtAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        description = (try? c.decode(String.self, forKey: .description)) ?? ""
        merchant = (try? c.decode(String.self, forKey: .merchant)) ?? ""
        quantity = try? c.decodeIfPresent(Double.self, forKey: .quantity)
        unitPrice = try? c.decodeIfPresent(Double.self, forKey: .unitPrice)
        total = try? c.decodeIfPresent(Double.self, forKey: .total)
        boughtAt = (try? c.decodeIfPresent(String.self, forKey: .boughtAt)).flatMap(InvoiceGoalsText.date(fromTimestamp:))
    }

    static func == (lhs: Purchase, rhs: Purchase) -> Bool {
        lhs.description == rhs.description && lhs.merchant == rhs.merchant
            && lhs.unitPrice == rhs.unitPrice && lhs.boughtAt == rhs.boughtAt
    }
}

/// Un producto y lo que pagaste por el en cada comercio.
struct ProductPrices: Identifiable, Equatable {
    struct Offer: Identifiable, Equatable {
        let merchant: String
        /// Precio de la compra mas reciente en ese comercio.
        let lastPrice: Double
        let lowestPrice: Double
        let lastDate: Date?
        let purchases: Int
        var id: String { merchant }
    }

    let key: String
    let name: String
    /// De mas barato a mas caro (por el ultimo precio).
    let offers: [Offer]
    let purchases: Int
    let lastDate: Date?
    var id: String { key }

    var cheapest: Offer? { offers.first }
    /// Cuanto ahorras comprandolo donde sale mas barato vs. donde mas caro.
    var savingsPerUnit: Double {
        guard let low = offers.first?.lastPrice, let high = offers.last?.lastPrice else { return 0 }
        return max(high - low, 0)
    }
}

enum PurchaseComparison {
    /// "LECHE  Entera 1L*" -> "leche entera 1l": sin tildes, mayusculas ni
    /// signos, para juntar el mismo producto escrito un poco distinto.
    static func normalized(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
        let cleaned = folded.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }

    static func group(_ purchases: [Purchase]) -> [ProductPrices] {
        var byKey: [String: [Purchase]] = [:]
        for purchase in purchases {
            guard let price = purchase.unitPrice, price > 0 else { continue }
            let key = normalized(purchase.description)
            guard !key.isEmpty else { continue }
            byKey[key, default: []].append(purchase)
        }
        let groups: [ProductPrices] = byKey.map { key, items in
            let sorted = items.sorted { ($0.boughtAt ?? .distantPast) > ($1.boughtAt ?? .distantPast) }
            var offers: [ProductPrices.Offer] = []
            for (merchant, merchantItems) in Dictionary(grouping: sorted, by: { $0.merchant }) {
                let prices = merchantItems.compactMap(\.unitPrice)
                offers.append(.init(
                    merchant: merchant,
                    lastPrice: merchantItems.first?.unitPrice ?? 0,
                    lowestPrice: prices.min() ?? 0,
                    lastDate: merchantItems.first?.boughtAt,
                    purchases: merchantItems.count
                ))
            }
            offers.sort { $0.lastPrice == $1.lastPrice ? $0.merchant < $1.merchant : $0.lastPrice < $1.lastPrice }
            return ProductPrices(
                key: key,
                name: sorted.first?.description.trimmingCharacters(in: .whitespaces) ?? key,
                offers: offers,
                purchases: items.count,
                lastDate: sorted.first?.boughtAt
            )
        }
        // Primero lo que se compara en varios comercios, luego lo mas comprado.
        return groups.sorted {
            if ($0.offers.count > 1) != ($1.offers.count > 1) { return $0.offers.count > 1 }
            if $0.purchases != $1.purchases { return $0.purchases > $1.purchases }
            return $0.name < $1.name
        }
    }

    static func price(_ value: Double) -> String {
        InvoiceMonthSummaryText.money(value)
    }

    static func summary(_ product: ProductPrices) -> String {
        guard let cheapest = product.cheapest else { return "" }
        if product.offers.count > 1 {
            return "Más barato en \(cheapest.merchant): \(price(cheapest.lastPrice))"
        }
        return "\(price(cheapest.lastPrice)) en \(cheapest.merchant)"
    }
}

struct PurchasesView: View {
    @State private var products: [ProductPrices] = []
    @State private var hasLoaded = false
    @State private var query = ""

    private var filtered: [ProductPrices] {
        let needle = PurchaseComparison.normalized(query)
        guard !needle.isEmpty else { return products }
        return products.filter { $0.key.contains(needle) }
    }

    var body: some View {
        List {
            if !hasLoaded {
                ProgressView().frame(maxWidth: .infinity)
            } else if products.isEmpty {
                ContentUnavailableView(
                    "Todavía no hay productos",
                    systemImage: "cart",
                    description: Text("Cuando escanees facturas, aquí verás lo que compraste y cuánto pagaste en cada comercio.")
                )
            } else {
                Section {
                    ForEach(filtered) { product in
                        NavigationLink {
                            ProductPricesDetail(product: product)
                        } label: {
                            row(product)
                        }
                    }
                } footer: {
                    Text("Precios por unidad de tus facturas de los últimos 6 meses.")
                }
            }
        }
        .navigationTitle("Tus compras")
        .searchable(text: $query, prompt: "Busca un producto, ej. leche")
        .task { await load() }
        .refreshable { await load() }
    }

    private func row(_ product: ProductPrices) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(product.name.capitalized)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text(PurchaseComparison.summary(product))
                .font(.caption)
                .foregroundStyle(product.offers.count > 1 ? MonAviBrand.primary : .secondary)
            if product.offers.count > 1 && product.savingsPerUnit > 0 {
                Text("Ahorras \(PurchaseComparison.price(product.savingsPerUnit)) por unidad frente a \(product.offers.last?.merchant ?? "")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func load() async {
        defer { hasLoaded = true }
        let purchases: [Purchase] = (try? await SupabaseManager.shared.client
            .rpc("my_purchases")
            .execute()
            .value) ?? []
        products = PurchaseComparison.group(purchases)
    }
}

private struct ProductPricesDetail: View {
    let product: ProductPrices

    var body: some View {
        List {
            Section("Dónde lo compraste") {
                ForEach(product.offers) { offer in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(offer.merchant)
                            Text(detail(offer))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(PurchaseComparison.price(offer.lastPrice))
                            .fontWeight(offer == product.cheapest && product.offers.count > 1 ? .bold : .regular)
                            .foregroundStyle(offer == product.cheapest && product.offers.count > 1 ? MonAviBrand.primary : .primary)
                    }
                }
            }
        }
        .navigationTitle(product.name.capitalized)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detail(_ offer: ProductPrices.Offer) -> String {
        var parts: [String] = [offer.purchases == 1 ? "1 compra" : "\(offer.purchases) compras"]
        if offer.lowestPrice < offer.lastPrice {
            parts.append("lo más bajo: \(PurchaseComparison.price(offer.lowestPrice))")
        }
        if let date = offer.lastDate {
            parts.append("última: \(date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: .monavi)))")
        }
        return parts.joined(separator: " · ")
    }
}
