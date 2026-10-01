import SwiftUI

/// Campo de monto con el signo de $ siempre visible a la izquierda, para que
/// quede claro de un vistazo que ahi se escribe dinero (antes era un
/// TextField pelado con solo un placeholder gris, facil de pasar por alto).
struct AmountField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 4) {
            Text("$")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad)
        }
    }
}

/// Igual que AmountField pero con % a la derecha — para tasas de interes.
struct PercentField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 4) {
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad)
            Text("%")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

/// Dia del mes (1-28) que se puede escribir directo o ajustar con +/-.
/// Antes era solo un Stepper — habia que tocar + o - uno por uno para
/// llegar, por ejemplo, del 1 al 25.
struct DayOfMonthField: View {
    let label: String
    @Binding var day: Int

    private var clampedBinding: Binding<Int> {
        Binding(
            get: { day },
            set: { day = min(max($0, 1), 28) }
        )
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("Dia", value: clampedBinding, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 36)
            Stepper("", value: clampedBinding, in: 1...28)
                .labelsHidden()
        }
    }
}
