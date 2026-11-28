import SwiftUI

/// Resumen del mes de facturas: cuantas escaneaste, cuanto gastaste con
/// factura, el cashback que ganaste y en que comercios. Se comparte como
/// imagen ("Este mes gané $8.40 de cashback con mis facturas") con el
/// codigo de invitacion, para que los amigos se unan.
struct InvoiceMonthSummary: Decodable, Equatable {
    struct MerchantLine: Decodable, Equatable, Identifiable {
        let name: String
        let receipts: Int
        let amount: Double
        var id: String { name }
    }

    let month: String
    let receipts: Int
    let spent: Double
    let cashbackCents: Int
    let merchantCount: Int
    let merchants: [MerchantLine]

    enum CodingKeys: String, CodingKey {
        case month, receipts, spent, merchants
        case cashbackCents = "cashback_cents"
        case merchantCount = "merchant_count"
    }

    init(month: String, receipts: Int, spent: Double, cashbackCents: Int, merchantCount: Int, merchants: [MerchantLine] = []) {
        self.month = month
        self.receipts = receipts
        self.spent = spent
        self.cashbackCents = cashbackCents
        self.merchantCount = merchantCount
        self.merchants = merchants
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        month = (try? c.decode(String.self, forKey: .month)) ?? ""
        receipts = (try? c.decode(Int.self, forKey: .receipts)) ?? 0
        spent = (try? c.decode(Double.self, forKey: .spent)) ?? 0
        cashbackCents = (try? c.decode(Int.self, forKey: .cashbackCents)) ?? 0
        merchantCount = (try? c.decode(Int.self, forKey: .merchantCount)) ?? 0
        merchants = (try? c.decode([MerchantLine].self, forKey: .merchants)) ?? []
    }
}

/// Textos del resumen (logica pura, probada en InvoiceMonthSummaryTests).
enum InvoiceMonthSummaryText {
    static let monthNames = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
                             "agosto", "septiembre", "octubre", "noviembre", "diciembre"]

    /// "2026-11" -> "noviembre".
    static func monthName(_ month: String) -> String {
        let parts = month.split(separator: "-")
        guard parts.count == 2, let number = Int(parts[1]), (1...12).contains(number) else { return "este mes" }
        return monthNames[number - 1]
    }

    static func money(cents: Int) -> String {
        String(format: "$%.2f", Double(cents) / 100)
    }

    static func money(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale(identifier: "en_US")
        return "$" + (formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount))
    }

    /// "Este mes" o "En octubre".
    static func when(_ month: String, isCurrent: Bool) -> String {
        isCurrent ? L("Este mes") : L("En %@", "\(monthName(month))")
    }

    /// Titular de la tarjeta para compartir.
    static func headline(_ summary: InvoiceMonthSummary, isCurrent: Bool) -> String {
        let when = when(summary.month, isCurrent: isCurrent)
        if summary.cashbackCents > 0 {
            return L("%@ gané %@ de cashback con mis facturas", "\(when)", "\(money(cents: summary.cashbackCents))")
        }
        let facturas = summary.receipts == 1 ? L("1 factura") : L("%@ facturas", "\(summary.receipts)")
        return L("%@ escaneé %@ con MonAvi", "\(when)", "\(facturas)")
    }

    static func shareText(_ summary: InvoiceMonthSummary, isCurrent: Bool, code: String?) -> String {
        var text = headline(summary, isCurrent: isCurrent) + " 💸"
        if let code, !code.isEmpty {
            text += L("\nÚnete a MonAvi con mi código %@ y gana cashback tú también: %@", "\(code)", "\(Config.appStoreURL.absoluteString)")
        } else {
            text += L("\nDescarga MonAvi y gana cashback con tus facturas: %@", "\(Config.appStoreURL.absoluteString)")
        }
        return text
    }

    /// Meses para elegir: el actual y los 5 anteriores ("2026-11", ...).
    static func recentMonths(from date: Date = Date(), count: Int = 6, calendar: Calendar = .current) -> [String] {
        (0..<count).compactMap { offset in
            guard let day = calendar.date(byAdding: .month, value: -offset, to: date) else { return nil }
            let parts = calendar.dateComponents([.year, .month], from: day)
            guard let year = parts.year, let month = parts.month else { return nil }
            return String(format: "%04d-%02d", year, month)
        }
    }
}

struct InvoiceMonthSummaryView: View {
    @State private var months = InvoiceMonthSummaryText.recentMonths()
    @State private var selectedMonth = InvoiceMonthSummaryText.recentMonths().first ?? ""
    @State private var summary: InvoiceMonthSummary?
    @State private var isLoading = false
    @State private var referralCode: String?
    @State private var shareItems: ShareItems?

    private struct ShareItems: Identifiable {
        let id = UUID()
        let items: [Any]
    }

    private var isCurrent: Bool { selectedMonth == months.first }

    var body: some View {
        List {
            Section {
                Picker("Mes", selection: $selectedMonth) {
                    ForEach(months, id: \.self) { month in
                        Text(InvoiceMonthSummaryText.monthName(month).capitalized).tag(month)
                    }
                }
            }

            if let summary {
                Section {
                    InvoiceShareCard(summary: summary, isCurrent: isCurrent, code: referralCode)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section("Tu mes con factura") {
                    LabeledContent("Facturas escaneadas", value: "\(summary.receipts)")
                    LabeledContent("Gastaste con factura", value: InvoiceMonthSummaryText.money(summary.spent))
                    LabeledContent("Cashback ganado", value: InvoiceMonthSummaryText.money(cents: summary.cashbackCents))
                    LabeledContent("Comercios", value: "\(summary.merchantCount)")
                }

                if !summary.merchants.isEmpty {
                    Section("Donde más compraste") {
                        ForEach(summary.merchants) { line in
                            LabeledContent {
                                Text(InvoiceMonthSummaryText.money(line.amount))
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.name)
                                    Text(line.receipts == 1 ? "1 factura" : "\(line.receipts) facturas")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    NavigationLink {
                        PurchasesView()
                    } label: {
                        Label("Tus compras: dónde sale más barato", systemImage: "cart")
                    }
                }

                Section {
                    Button {
                        share(summary)
                    } label: {
                        Label("Compartir en redes", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(summary.receipts == 0)
                } footer: {
                    Text(referralCode == nil
                         ? L("Se comparte como imagen con el enlace de descarga.")
                         : L("Se comparte como imagen con tu código de invitación: si tus amigos se unen con él, los dos ganan cashback."))
                }
            } else if isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                ContentUnavailableView("Sin datos", systemImage: "doc.text.magnifyingglass", description: Text("No pudimos cargar el resumen. Desliza hacia abajo para reintentar."))
            }
        }
        .navigationTitle("Resumen del mes")
        .task { await loadCode() }
        .task(id: selectedMonth) { await load() }
        .refreshable { await load() }
        .sheet(item: $shareItems) { share in
            ActivityShareSheet(items: share.items)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        struct Params: Encodable { let p_month: String }
        let fetched: InvoiceMonthSummary? = try? await SupabaseManager.shared.client
            .rpc("my_invoice_month_summary", params: Params(p_month: selectedMonth + "-01"))
            .execute()
            .value
        summary = fetched
    }

    private func loadCode() async {
        referralCode = try? await ReferralRepository.shared.fetchSummary().code
    }

    private func share(_ summary: InvoiceMonthSummary) {
        let card = InvoiceShareCard(summary: summary, isCurrent: isCurrent, code: referralCode, forExport: true)
        var items: [Any] = [InvoiceMonthSummaryText.shareText(summary, isCurrent: isCurrent, code: referralCode)]
        if let url = ShareFileRenderer.renderPNG(card, scale: 3) { items.insert(url, at: 0) }
        shareItems = ShareItems(items: items)
    }
}

/// La imagen para compartir (360x450 pt -> 1080x1350 px, formato de feed).
struct InvoiceShareCard: View {
    let summary: InvoiceMonthSummary
    let isCurrent: Bool
    let code: String?
    var forExport = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "leaf.fill")
                Text("MonAvi").font(.system(size: 20, weight: .bold, design: MonAviBrand.fontDesign))
                Spacer()
                Text(InvoiceMonthSummaryText.monthName(summary.month).capitalized)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.18), in: Capsule())
            }

            Spacer(minLength: 0)

            Text(InvoiceMonthSummaryText.headline(summary, isCurrent: isCurrent))
                .font(.system(size: forExport ? 30 : 26, weight: .heavy, design: MonAviBrand.fontDesign))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                stat("\(summary.receipts)", summary.receipts == 1 ? "factura" : "facturas")
                stat(InvoiceMonthSummaryText.money(cents: summary.cashbackCents), "cashback")
                stat("\(summary.merchantCount)", summary.merchantCount == 1 ? "comercio" : "comercios")
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                if let code, !code.isEmpty {
                    Text("Únete con mi código")
                        .font(.system(size: 13, weight: .medium))
                        .opacity(0.85)
                    Text(code)
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .tracking(4)
                } else {
                    Text("Pide factura y gana cashback")
                        .font(.system(size: 15, weight: .semibold))
                }
                Text("Descárgala en el App Store")
                    .font(.system(size: 12, weight: .medium))
                    .opacity(0.8)
            }
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(width: forExport ? 360 : nil, height: forExport ? 450 : 330)
        .frame(maxWidth: forExport ? nil : .infinity)
        .background(
            LinearGradient(
                colors: [Color(red: 0.0, green: 0.65, blue: 0.52), Color(red: 0.02, green: 0.20, blue: 0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: forExport ? 0 : 24, style: .continuous))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 20, weight: .bold, design: MonAviBrand.fontDesign))
            Text(label).font(.system(size: 12, weight: .medium)).opacity(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
