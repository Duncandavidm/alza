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

/// Dia del mes (1-31): se escribe directo con el teclado numerico, en una
/// cajita a la derecha. Antes tenia botones +/- y habia que tocarlos uno
/// por uno (del 1 al 25 eran 24 toques). En meses mas cortos, 29/30/31
/// cuentan como el ultimo dia del mes.
struct DayOfMonthField: View {
    let label: String
    @Binding var day: Int
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            HStack(spacing: 4) {
                Text("Día")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField("15", text: $text)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.body.weight(.semibold))
                    .focused($focused)
                    .frame(width: 44)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemFill)))
            .onTapGesture { focused = true }
        }
        .onAppear { text = String(day) }
        .onChange(of: text) { _, newValue in
            let digits = String(newValue.filter(\.isNumber).prefix(2))
            if digits != newValue { text = digits; return }
            if let value = Int(digits), value > 0 { day = min(value, 31) }
        }
        .onChange(of: focused) { _, isFocused in
            // Al salir: si quedo vacio o fuera de rango, se muestra el dia valido.
            if !isFocused { text = String(day) }
        }
        .onChange(of: day) { _, newValue in
            if !focused { text = String(newValue) }
        }
    }
}

/// Etiqueta chica arriba de un campo: el placeholder solo se cortaba
/// ("Interés /mes (op...") cuando habia dos campos en la misma fila.
struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
        }
    }
}

enum DebtDraftMath {
    static func utilization(_ debt: DebtDraft) -> Double? {
        guard let balance = OnboardingViewModel.amount(debt.balanceText), balance > 0,
              let limit = OnboardingViewModel.amount(debt.creditLimitText), limit > 0 else { return nil }
        return NSDecimalNumber(decimal: balance / limit).doubleValue
    }
}
