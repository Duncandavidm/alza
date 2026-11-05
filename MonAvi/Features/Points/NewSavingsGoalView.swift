import SwiftUI

/// Meta del mes ACTUAL (UTC) para una inscripcion ya existente — el
/// estado (cumplida/no cumplida) lo decide unicamente el reporte del
/// banco via reconcile-savings-reports, nunca el cliente.
struct NewSavingsGoalView: View {
    let enrollment: SponsoredSavingsEnrollment
    var onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var targetAmountText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let repository = CardPointsRepository.shared

    private var targetAmount: Decimal {
        Decimal(string: targetAmountText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AmountField(placeholder: "Saldo promedio objetivo", text: $targetAmountText)
                } header: {
                    Text("Meta de este mes")
                } footer: {
                    Text("El banco reporta tu saldo PROMEDIO del mes al terminar el periodo — no cuenta un deposito de un solo dia.")
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Nueva meta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }
                        .disabled(targetAmount <= 0 || isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.createSavingsGoal(
                NewSponsoredSavingsGoal(
                    enrollmentId: enrollment.id,
                    periodMonth: SavingsPeriod.currentMonthString,
                    targetAmount: targetAmount
                )
            )
            onCreated()
            dismiss()
        } catch {
            errorMessage = "No se pudo guardar la meta: \(error.localizedDescription)"
        }
    }
}

/// Mismo criterio de "mes" en UTC que usa el servidor (ver
/// reconcile-savings-reports) — para que la meta que crea el cliente
/// quede en el mismo periodo que el banco va a reportar. Produce el
/// mismo formato String "yyyy-MM-dd" (SavingsGoalDateFormat) que toda
/// columna `date`, para comparar por igualdad de texto en vez de volver
/// a parsear fechas.
enum SavingsPeriod {
    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    static var currentMonthString: String {
        let monthStart = utcCalendar.dateInterval(of: .month, for: Date())?.start ?? Date()
        return SavingsGoalDateFormat.string(from: monthStart)
    }
}

/// Para mostrar "noviembre 2026" a partir de un `periodMonthDate`: fija
/// el timeZone a UTC (igual que SavingsGoalDateFormat) para que el mes
/// no se desplace un dia hacia atras en una zona con offset negativo
/// como Panama (medianoche UTC del dia 1 seria todavia el mes anterior
/// en hora local si se formatea sin fijar la zona).
enum MonthYearFormat {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date).capitalized
    }
}
