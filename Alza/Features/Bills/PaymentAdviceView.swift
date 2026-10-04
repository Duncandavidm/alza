import SwiftUI

/// El pop-up del diferenciador de Avi: aparece justo despues de registrar
/// un ingreso, si hay cuentas por pagar o recurrentes vencidas, con un
/// plan de pago priorizado por IA y un boton para pagar cada una ahi mismo.
struct PaymentAdviceView: View {
    let advice: String
    @State var items: [PaymentAdviceItem]
    let userId: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var payingId: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Text("💡").font(.title2)
                        Text(advice)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }

                Section("En que orden pagar") {
                    ForEach(items) { item in
                        row(item)
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.caption)
                }
            }
            .navigationTitle("Consejo de Avi")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ item: PaymentAdviceItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(item.rank)")
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body.weight(.medium))
                Text(item.dueInfo).font(.caption).foregroundStyle(.secondary)
                Text(item.reason).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(Decimal(item.amount), format: .currency(code: "USD"))
                    .fontWeight(.semibold)

                Button {
                    Task { await markPaid(item) }
                } label: {
                    if payingId == item.id {
                        ProgressView()
                    } else {
                        Text("Pagar")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(payingId != nil)
            }
        }
        .padding(.vertical, 4)
    }

    private func markPaid(_ item: PaymentAdviceItem) async {
        payingId = item.id
        defer { payingId = nil }
        do {
            try await PaymentAdviceActions.markPaid(item: item, userId: userId)
            items.removeAll { $0.id == item.id }
        } catch {
            errorMessage = "No se pudo registrar el pago: \(error.localizedDescription)"
        }
    }
}
