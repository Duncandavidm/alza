import SwiftUI

/// Mejora #5: al "cerrar el dia", un resumen limpio con un mensaje simple —
/// como cuando el dueño terminaba de pasar el lapiz por su libreta.
struct DayCloseSummaryView: View {
    @Environment(\.dismiss) private var dismiss
    let summary: DaySummary

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Text(summary.mood.emoji)
                    .font(.system(size: 64))

                VStack(spacing: 4) {
                    Text(summary.mood.title)
                        .font(.largeTitle.bold())
                    Text(summary.mood.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)

                VStack(spacing: 12) {
                    summaryRow(label: "Vendiste / cobraste", value: summary.income, color: .green)
                    summaryRow(label: "Gastaste", value: -summary.expense, color: .red)
                    Divider()
                    summaryRow(
                        label: "Te quedo en el bolsillo",
                        value: summary.net,
                        color: summary.net >= 0 ? .green : .red,
                        emphasized: true
                    )
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
                .padding(.horizontal, 24)

                Spacer()

                Button("Listo") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .padding(.horizontal, 24)
            }
            .padding(.bottom, 20)
            .navigationTitle("Tu dia")
        }
    }

    @ViewBuilder
    private func summaryRow(label: String, value: Decimal, color: Color, emphasized: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(emphasized ? .headline : .subheadline)
            Spacer()
            Text(value, format: .currency(code: "USD"))
                .font(emphasized ? .title3.bold() : .subheadline.weight(.medium))
                .foregroundStyle(color)
        }
    }
}
