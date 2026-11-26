import AppIntents
import SwiftUI
import WidgetKit

/// "Escanear factura" en la pantalla bloqueada (y de inicio): tocarlo abre
/// MonAvi directo en la camara (monavi://scan). No necesita datos.
struct InvoiceScanEntry: TimelineEntry {
    let date: Date
}

struct InvoiceScanProvider: TimelineProvider {
    func placeholder(in context: Context) -> InvoiceScanEntry { InvoiceScanEntry(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (InvoiceScanEntry) -> Void) {
        completion(InvoiceScanEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<InvoiceScanEntry>) -> Void) {
        completion(Timeline(entries: [InvoiceScanEntry(date: Date())], policy: .never))
    }
}

struct InvoiceScanWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(InvoiceScanRequest.url)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 24, weight: .semibold))
            }
            .containerBackground(for: .widget) { Color.clear }
            .accessibilityLabel("Escanear factura")
        case .accessoryInline:
            Label("Escanear factura", systemImage: "qrcode.viewfinder")
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 26, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Escanear factura")
                        .font(.headline)
                    Text("Gana cashback")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .containerBackground(for: .widget) { Color.clear }
        default:
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 34, weight: .semibold))
                Spacer(minLength: 0)
                Text("Escanear factura")
                    .font(.headline)
                Text("y gana cashback")
                    .font(.caption)
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(for: .widget) {
                LinearGradient(
                    colors: [Color(red: 0, green: 0.65, blue: 0.52), Color(red: 0.03, green: 0.35, blue: 0.28)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
}

struct InvoiceScanWidget: Widget {
    let kind = "MonAviInvoiceScan"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: InvoiceScanProvider()) { _ in
            InvoiceScanWidgetView()
        }
        .configurationDisplayName("Escanear factura")
        .description("Abre la cámara de MonAvi desde la pantalla bloqueada para escanear tu factura.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .systemSmall])
    }
}

/// Boton del Centro de control y de la pantalla bloqueada (iOS 18+).
@available(iOS 18.0, *)
struct InvoiceScanControl: ControlWidget {
    static let kind = "app.monavi.widget.invoice-scan"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenInvoiceScannerIntent()) {
                Label("Escanear factura", systemImage: "qrcode.viewfinder")
            }
        }
        .displayName("Escanear factura")
        .description("Abre MonAvi con la cámara lista para tu factura.")
    }
}

/// Botón "Anotar gasto" del Centro de control y de la pantalla bloqueada
/// (iOS 18+): abre MonAvi en Anotar movimiento.
@available(iOS 18.0, *)
struct QuickAddControl: ControlWidget {
    static let kind = "app.monavi.widget.quick-add"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenQuickAddIntent()) {
                Label("Anotar gasto", systemImage: "plus.circle.fill")
            }
        }
        .displayName("Anotar gasto")
        .description("Abre MonAvi listo para anotar un gasto.")
    }
}
