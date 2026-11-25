import AppIntents
import SwiftUI
import WidgetKit

struct DayEntry: TimelineEntry {
    let date: Date
    let snapshot: DayWidgetSnapshot?
    let hideAmounts: Bool
}

/// Widget "Tu día": gastado hoy y en el mes, lo que te queda, los ultimos
/// movimientos y los botones Voz / Agregar. Lee el snapshot que la app deja
/// en el App Group (DayWidgetUpdater); no habla con Supabase.
struct DayTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry {
        DayEntry(date: Date(), snapshot: Self.preview, hideAmounts: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        completion(DayEntry(
            date: Date(),
            snapshot: context.isPreview ? Self.preview : DayWidgetSnapshot.load(),
            hideAmounts: context.isPreview ? false : DayWidgetSnapshot.hideAmounts
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let entry = DayEntry(date: Date(), snapshot: DayWidgetSnapshot.load(), hideAmounts: DayWidgetSnapshot.hideAmounts)
        // Se vuelve a dibujar cada hora y a medianoche (para que "Hoy" empiece en $0).
        let calendar = Calendar.current
        let nextHour = calendar.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        let midnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        completion(Timeline(entries: [entry], policy: .after(min(nextHour, midnight))))
    }

    static let preview = DayWidgetSnapshot(
        todaySpent: 24.50, todayCount: 3, monthSpent: 612.40, monthLeft: 487.60,
        recent: [
            .init(id: "1", title: "Café La Esquina", emoji: "☕", amount: 4.50, isIncome: false),
            .init(id: "2", title: "Supermercado", emoji: "🛒", amount: 18.00, isIncome: false),
            .init(id: "3", title: "Salario", emoji: "💰", amount: 1100, isIncome: true),
            .init(id: "4", title: "Netflix", emoji: "📺", amount: 9.99, isIncome: false),
            .init(id: "5", title: "Gasolina", emoji: "🚗", amount: 30, isIncome: false),
        ],
        updatedAt: Date()
    )
}

struct DayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DayEntry

    private let brand = Color(hex: "#00A585") ?? .green
    private let alert = Color(hex: "#B5453A") ?? .red

    private var snapshot: DayWidgetSnapshot? { entry.snapshot }
    private var isToday: Bool { snapshot?.isFromToday(now: entry.date) ?? false }
    private var todaySpent: Double { isToday ? (snapshot?.todaySpent ?? 0) : 0 }
    private var todayCount: Int { isToday ? (snapshot?.todayCount ?? 0) : 0 }

    var body: some View {
        if snapshot == nil {
            empty
        } else {
            switch family {
            case .systemSmall: small
            case .systemLarge: large
            default: medium
            }
        }
    }

    // MARK: - Tamanos

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            header(showCount: false)
            Spacer(minLength: 0)
            stat("Hoy", money(todaySpent), big: true)
            if let left = snapshot?.monthLeft {
                stat("Te queda", money(left), color: left < 0 ? alert : brand)
            } else {
                stat("Mes", money(snapshot?.monthSpent ?? 0))
            }
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 10) {
            header(showCount: true)
            statsRow
            Spacer(minLength: 0)
            buttons
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            header(showCount: true)
            statsRow
            Text("Recientes")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 7) {
                ForEach(snapshot?.recent ?? []) { item in
                    HStack(spacing: 8) {
                        Text(item.emoji).font(.caption)
                        Text(item.title)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Spacer()
                        Text((item.isIncome ? "+" : "−") + money(item.amount))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(item.isIncome ? brand : .primary)
                    }
                }
                if (snapshot?.recent ?? []).isEmpty {
                    Text("Todavía no tienes movimientos este mes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
            buttons
        }
    }

    // MARK: - Piezas

    private func header(showCount: Bool) -> some View {
        HStack(spacing: 6) {
            Circle().fill(brand).frame(width: 8, height: 8)
            Text("MonAvi")
                .font(.caption.weight(.bold))
            Spacer()
            Button(intent: ToggleWidgetAmountsIntent()) {
                Image(systemName: entry.hideAmounts ? "eye.slash" : "eye")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            if showCount {
                Text(todayCount == 1 ? "1 mov." : "\(todayCount) mov.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statsRow: some View {
        HStack(alignment: .top, spacing: 0) {
            stat("Hoy", money(todaySpent))
            Divider().frame(height: 30).padding(.horizontal, 8)
            stat("Mes", money(snapshot?.monthSpent ?? 0))
            if let left = snapshot?.monthLeft {
                Divider().frame(height: 30).padding(.horizontal, 8)
                stat("Te queda", money(left), color: left < 0 ? alert : brand)
            }
        }
    }

    private func stat(_ label: String, _ value: String, big: Bool = false, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(big ? .title3.weight(.bold) : .subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Link(destination: URL(string: "monavi://voice")!) {
                Label("Voz", systemImage: "mic.fill")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(brand.opacity(0.15)))
                    .foregroundStyle(brand)
            }
            Link(destination: URL(string: "monavi://add")!) {
                Label("Agregar", systemImage: "plus")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(brand))
                    .foregroundStyle(.white)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundStyle(brand)
            Text("Abre MonAvi para ver tu día")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    /// Monto en la moneda de la cuenta (la app guarda el país en el App
    /// Group): Panamá "USD 52.30" como siempre, Colombia "$ 50.000".
    private func money(_ value: Double) -> String {
        if entry.hideAmounts { return "$•••" }
        let country = UserDefaults(suiteName: "group.app.monavi.shared")?.string(forKey: "monavi.country")
        if country == "CO" {
            return value.formatted(.currency(code: "COP").locale(Locale(identifier: "es_CO")).precision(.fractionLength(0)))
        }
        return value.formatted(.currency(code: "USD"))
    }
}

struct DayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: DayWidgetSnapshot.widgetKind, provider: DayTimelineProvider()) { entry in
            DayWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Tu día")
        .description("Tus gastos del día y del mes de un vistazo, con tus últimos movimientos.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
