import SwiftUI

/// El "papel" de la factura/remision/cuenta por cobrar, pintado con la
/// marca del negocio (logo, color, tipografia). Misma vista para la
/// vista previa en pantalla y para lo que se exporta a imagen al
/// compartir, asi el cliente ve exactamente lo que recibe.
struct InvoiceDocumentView: View {
    let business: BusinessSettings
    let invoice: Invoice
    let items: [InvoiceItem]
    /// Precargado fuera de esta vista (AsyncImage no es confiable dentro
    /// de un ImageRenderer, que renderiza fuera de pantalla).
    let logoImage: Image?

    private var font: Font.Design { business.brandFont.design }
    private var businessName: String {
        let name = business.businessName ?? ""
        return name.isEmpty ? "Mi negocio" : name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Divider()
            customerBlock
            itemsTable
            totalsBlock

            if let notes = invoice.notes, !notes.isEmpty {
                Text(notes)
                    .font(.system(.footnote, design: font))
                    .foregroundStyle(.secondary)
            }

            footer
        }
        .padding(24)
        .frame(width: 380)
        .background(Color.white)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            if let logoImage {
                logoImage
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(businessName)
                    .font(.system(.title3, design: font, weight: .bold))
                    .foregroundStyle(.black)
                if let taxId = business.taxId, !taxId.isEmpty {
                    Text(taxId).font(.system(.caption, design: font)).foregroundStyle(.gray)
                }
                if let address = business.address, !address.isEmpty {
                    Text(address).font(.system(.caption, design: font)).foregroundStyle(.gray)
                }
                if let phone = business.phone, !phone.isEmpty {
                    Text(phone).font(.system(.caption, design: font)).foregroundStyle(.gray)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(invoice.docType.displayName.uppercased())
                    .font(.system(.subheadline, design: font, weight: .black))
                    .foregroundStyle(business.brandColor)
                if let number = invoice.number {
                    Text(number)
                        .font(.system(.subheadline, design: font, weight: .bold))
                        .foregroundStyle(.black)
                }
                Text(invoice.issueDateValue.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(.caption, design: font))
                    .foregroundStyle(.gray)
            }
        }
    }

    private var customerBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("CLIENTE")
                .font(.system(.caption2, design: font, weight: .bold))
                .foregroundStyle(business.brandColor)
            Text(invoice.customerName)
                .font(.system(.body, design: font, weight: .semibold))
                .foregroundStyle(.black)
            if let contact = invoice.customerContact, !contact.isEmpty {
                Text(contact).font(.system(.caption, design: font)).foregroundStyle(.gray)
            }
            if let due = invoice.dueDateValue {
                Text("Vence: \(due.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(.caption, design: font))
                    .foregroundStyle(.gray)
            }
        }
    }

    private var itemsTable: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Descripcion").font(.system(.caption, design: font, weight: .bold))
                Spacer()
                Text("Cant.").font(.system(.caption, design: font, weight: .bold)).frame(width: 36)
                Text("Total").font(.system(.caption, design: font, weight: .bold)).frame(width: 64, alignment: .trailing)
            }
            .foregroundStyle(.gray)

            Divider()

            ForEach(items) { item in
                HStack(alignment: .top) {
                    Text(item.description)
                        .font(.system(.footnote, design: font))
                        .foregroundStyle(.black)
                    Spacer()
                    Text(item.quantity, format: .number)
                        .font(.system(.footnote, design: font))
                        .frame(width: 36)
                        .foregroundStyle(.black)
                    Text(item.lineTotal, format: .currency(code: "USD"))
                        .font(.system(.footnote, design: font))
                        .frame(width: 64, alignment: .trailing)
                        .foregroundStyle(.black)
                }
            }
        }
    }

    private var totalsBlock: some View {
        HStack {
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("TOTAL")
                    .font(.system(.caption, design: font, weight: .bold))
                    .foregroundStyle(.gray)
                Text(invoice.total, format: .currency(code: "USD"))
                    .font(.system(.title2, design: font, weight: .black))
                    .foregroundStyle(business.brandColor)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Text("Generado con Avi")
                .font(.system(.caption2, design: font))
                .foregroundStyle(.gray)
            Spacer()
        }
        .padding(.top, 6)
    }
}
