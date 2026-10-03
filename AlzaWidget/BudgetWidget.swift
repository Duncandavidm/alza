import WidgetKit
import SwiftUI

struct BudgetEntry: TimelineEntry {
    let date: Date
    let snapshot: BudgetWidgetSnapshot?
}

/// El widget no habla con Supabase ni toca el Keychain — solo lee el
/// snapshot que la app principal dejo en el App Group compartido
/// (BudgetsViewModel.publishWidgetSnapshot). Se refresca de inmediato
/// cuando la app escribe uno nuevo (WidgetCenter.reloadAllTimelines) y,
/// por si acaso, tambien cada hora.
struct BudgetTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> BudgetEntry {
        BudgetEntry(date: Date(), snapshot: BudgetTimelineProvider.previewSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (BudgetEntry) -> Void) {
        if context.isPreview {
            completion(BudgetEntry(date: Date(), snapshot: BudgetTimelineProvider.previewSnapshot))
        } else {
            completion(BudgetEntry(date: Date(), snapshot: BudgetWidgetSnapshot.load()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BudgetEntry>) -> Void) {
        let entry = BudgetEntry(date: Date(), snapshot: BudgetWidgetSnapshot.load())
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    static let previewSnapshot = BudgetWidgetSnapshot(
        items: [
            .init(category: "Comida", emoji: "🍔", colorHex: "#00A585", spent: 180, limitAmount: 250, ratio: 0.72),
            .init(category: "Transporte", emoji: "🚗", colorHex: "#F4A07A", spent: 95, limitAmount: 80, ratio: 1.19),
        ],
        updatedAt: Date()
    )
}

struct BudgetWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BudgetEntry

    private var brandColor: Color { Color(hex: "#00A585") ?? .green }
    private var alertColor: Color { Color(hex: "#B5453A") ?? .red }

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.items.isEmpty {
            content(for: snapshot)
        } else {
            emptyState
        }
    }

    @ViewBuilder
    private func content(for snapshot: BudgetWidgetSnapshot) -> some View {
        let itemsToShow = Array(snapshot.items.prefix(family == .systemSmall ? 1 : 4))
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(brandColor)
                Text("Presupuestos")
                    .font(.caption.weight(.bold))
            }

            ForEach(itemsToShow) { item in
                row(for: item)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
    }

    private func row(for item: BudgetWidgetSnapshot.Item) -> some View {
        let color = Color(hex: item.colorHex) ?? .gray
        let isOver = item.ratio >= 1
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("\(item.emoji) \(item.category)")
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text("\(Int(item.ratio * 100))%")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isOver ? alertColor : .secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.2))
                    Capsule()
                        .fill(isOver ? alertColor : color)
                        .frame(width: geo.size.width * min(item.ratio, 1))
                }
            }
            .frame(height: 6)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.bar.fill")
                .foregroundStyle(.secondary)
            Text("Abre Amadai y crea un presupuesto")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(14)
    }
}

struct BudgetWidget: Widget {
    let kind = "BudgetWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BudgetTimelineProvider()) { entry in
            BudgetWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Presupuestos")
        .description("Ve de un vistazo cuanto llevas gastado en cada categoria.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
