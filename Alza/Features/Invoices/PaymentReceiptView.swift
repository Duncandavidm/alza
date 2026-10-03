import SwiftUI

/// Se muestra justo despues de la animacion de impresora/sello PAGADO al
/// marcar una factura como pagada. El recibo queda guardado
/// (payment_receipts) y se puede volver a compartir desde aqui por el
/// medio que el cliente prefiera.
struct PaymentReceiptView: View {
    let business: BusinessSettings
    let invoice: Invoice
    let receipt: PaymentReceipt
    let logoImage: Image?

    @Environment(\.dismiss) private var dismiss
    @State private var shareFile: ShareFile?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ReceiptDocumentView(business: business, invoice: invoice, receipt: receipt, logoImage: logoImage)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: 8, y: 4)
                    .padding(.horizontal)

                Button {
                    shareFile = ShareFileRenderer.renderPNG(
                        ReceiptDocumentView(business: business, invoice: invoice, receipt: receipt, logoImage: logoImage)
                    ).map(ShareFile.init)
                } label: {
                    Label("Compartir recibo", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Recibo de pago")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Listo") { dismiss() }
            }
        }
        .sheet(item: $shareFile) { file in
            ActivityShareSheet(items: [file.url])
        }
    }
}

struct ReceiptDocumentView: View {
    let business: BusinessSettings
    let invoice: Invoice
    let receipt: PaymentReceipt
    let logoImage: Image?

    private var font: Font.Design { business.brandFont.design }

    var body: some View {
        VStack(spacing: 14) {
            if let logoImage {
                logoImage
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Text(business.businessName?.isEmpty == false ? business.businessName! : "Mi negocio")
                .font(.system(.title3, design: font, weight: .bold))
                .foregroundStyle(.black)

            Text("RECIBO DE PAGO")
                .font(.system(.caption, design: font, weight: .bold))
                .foregroundStyle(business.brandColor)

            Divider()

            VStack(spacing: 6) {
                row("Recibo", receipt.receiptNumber)
                row("Fecha", receipt.paidAt.formatted(date: .abbreviated, time: .shortened))
                row("Cliente", invoice.customerName)
                row("Referencia", "\(invoice.docType.displayName) \(invoice.number ?? "")")
            }

            Divider()

            VStack(spacing: 2) {
                Text("MONTO PAGADO")
                    .font(.system(.caption2, design: font, weight: .bold))
                    .foregroundStyle(.gray)
                Text(receipt.amount, format: .currency(code: "USD"))
                    .font(.system(.largeTitle, design: font, weight: .black))
                    .foregroundStyle(.green)
            }

            Text("Generado con Amadai")
                .font(.system(.caption2, design: font))
                .foregroundStyle(.gray)
        }
        .padding(24)
        .frame(width: 320)
        .background(Color.white)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(.footnote, design: font))
                .foregroundStyle(.gray)
            Spacer()
            Text(value)
                .font(.system(.footnote, design: font, weight: .medium))
                .foregroundStyle(.black)
        }
    }
}
