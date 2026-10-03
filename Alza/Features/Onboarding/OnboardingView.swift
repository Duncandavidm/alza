import SwiftUI

/// El estudio financiero inicial: pasos cortos que arman el panorama
/// completo del usuario (datos personales, ingresos fijos/variables,
/// cuentas fijas, suscripciones, deudas, ahorros, tolerancia al riesgo y
/// metas) para que el resto de Amadai pueda aconsejar desde el primer dia,
/// inspirado en el detalle del prompt original de la version web.
struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = OnboardingViewModel()
    @State private var step = 0

    private let totalSteps = 14

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: Double(totalSteps))
                    .padding(.horizontal)
                    .padding(.top, 8)

                Form {
                    switch step {
                    case 0: welcomeStep
                    case 1: personalInfoStep
                    case 2: accountStep
                    case 3: fixedIncomeStep
                    case 4: variableIncomeStep
                    case 5: commonBillsStep
                    case 6: subscriptionsStep
                    case 7: otherFixedItemsStep
                    case 8: debtsStep
                    case 9: savingsStep
                    case 10: riskToleranceStep
                    case 11: shortTermGoalsStep
                    case 12: longTermGoalsStep
                    default: summaryStep
                    }
                }
            }
            .navigationTitle("Conozcamonos")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if step > 0 {
                        Button("Atras") { step -= 1 }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if step < totalSteps - 1 {
                        Button("Siguiente") { step += 1 }
                    } else {
                        Button {
                            Task { await finish() }
                        } label: {
                            if viewModel.isSaving {
                                ProgressView()
                            } else {
                                Text("Empezar")
                            }
                        }
                        .disabled(viewModel.isSaving)
                    }
                }
            }
            .alert("Algo salio mal", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Pasos

    @ViewBuilder
    private var welcomeStep: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("¡Bienvenido a Amadai!")
                    .font(.title2.bold())
                Text("Antes de empezar, hagamos un repaso corto de tus finanzas. Con esto Amadai te puede dar consejos de verdad, no genericos.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }

        Section("¿Como te llamas?") {
            TextField("Tu nombre", text: $viewModel.fullName)
        }
    }

    private var accountStep: some View {
        Section("Tu cuenta principal") {
            Text("¿De donde sale y entra la mayoria de tu dinero? (banco, efectivo...)")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("ej. Cuenta de banco, Efectivo", text: $viewModel.accountName)
        }
    }

    private var fixedIncomeStep: some View {
        Section("¿Tienes un salario u otro ingreso fijo?") {
            Toggle("Si, tengo un ingreso fijo", isOn: $viewModel.hasFixedIncome)
            if viewModel.hasFixedIncome {
                AmountField(placeholder: "¿Cuanto? (por mes)", text: $viewModel.fixedIncomeAmountText)
                DayOfMonthField(label: "Dia de pago", day: $viewModel.fixedIncomeDay)
            }
        }
    }

    private var variableIncomeStep: some View {
        Section("¿Tienes otros ingresos que varian?") {
            Text("Ventas, trabajos independientes, comisiones — cosas que no son siempre el mismo monto.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Si, tengo ingresos variables", isOn: $viewModel.hasVariableIncome)
            if viewModel.hasVariableIncome {
                TextField("Cuentame un poco (opcional)", text: $viewModel.variableIncomeNotes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
    }

    private var commonBillsStep: some View {
        Section("¿Cuales de estas pagas cada mes?") {
            Text("Marca las que apliquen, cambia el nombre si no coincide, y pon cuanto pagas. Si te falta alguna, agregala abajo.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach($viewModel.commonBills) { $bill in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField("Nombre", text: $bill.name)
                        Spacer()
                        Toggle("", isOn: $bill.isEnabled)
                            .labelsHidden()
                    }
                    if bill.isEnabled {
                        AmountField(placeholder: "Monto mensual", text: $bill.amountText)
                        DayOfMonthField(label: "Dia aproximado", day: $bill.dayOfMonth)
                    }
                }
                .padding(.vertical, 2)
            }
            .onDelete { viewModel.commonBills.remove(atOffsets: $0) }

            Button {
                viewModel.commonBills.append(
                    CommonBillDraft(name: "", category: .other, isEnabled: true)
                )
            } label: {
                Label("Agregar otra cuenta", systemImage: "plus.circle")
            }
        }
    }

    private var subscriptionsStep: some View {
        Section("¿Que suscripciones tienes?") {
            Text("Netflix, Spotify, gimnasio, software — lo que pagues seguido.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach($viewModel.subscriptions) { $item in
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Nombre (ej. Netflix)", text: $item.name)
                    AmountField(placeholder: "Monto mensual", text: $item.amountText)
                }
                .padding(.vertical, 2)
            }
            .onDelete { viewModel.subscriptions.remove(atOffsets: $0) }

            Button {
                viewModel.subscriptions.append(CustomFixedItemDraft())
            } label: {
                Label("Agregar suscripcion", systemImage: "plus.circle")
            }
        }
    }

    private var otherFixedItemsStep: some View {
        Section("¿Otras cuentas fijas cada mes?") {
            Text("Colegio o matricula de tus hijos, mesada que das, prestamos — lo que se repita mes a mes.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach($viewModel.otherFixedItems) { $item in
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Nombre (ej. Colegio)", text: $item.name)
                    AmountField(placeholder: "Monto mensual", text: $item.amountText)
                }
                .padding(.vertical, 2)
            }
            .onDelete { viewModel.otherFixedItems.remove(atOffsets: $0) }

            Button {
                viewModel.otherFixedItems.append(CustomFixedItemDraft())
            } label: {
                Label("Agregar cuenta fija", systemImage: "plus.circle")
            }
        }
    }

    private var personalInfoStep: some View {
        Section("Tu panorama personal") {
            Text("Esto nos ayuda a dar consejos acordes a tu etapa de vida, no genericos.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Edad", text: $viewModel.ageText)
                .keyboardType(.numberPad)

            Picker("Estado civil", selection: $viewModel.maritalStatus) {
                Text("Prefiero no decir").tag(MaritalStatus?.none)
                ForEach(MaritalStatus.allCases) { status in
                    Text(status.displayName).tag(Optional(status))
                }
            }

            TextField("Cuantos dependen de ti (hijos, etc.)", text: $viewModel.dependentsCountText)
                .keyboardType(.numberPad)

            TextField("A que te dedicas (ej. dueño de un negocio, empleado...)", text: $viewModel.occupation, axis: .vertical)
                .lineLimit(2...4)
        }
    }

    private var debtsStep: some View {
        Section("¿Tienes deudas activas?") {
            Text("Tarjetas de credito, prestamos, sobregiros — con esto Amadai te puede avisar cual pagar primero segun la tasa de interes y si esta en mora.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach($viewModel.debts) { $debt in
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Acreedor (ej. Tarjeta de credito)", text: $debt.creditor)
                    AmountField(placeholder: "Saldo actual", text: $debt.balanceText)
                    HStack {
                        PercentField(placeholder: "Interes /mes (opcional)", text: $debt.interestRateText)
                        AmountField(placeholder: "Pago minimo (opcional)", text: $debt.minimumPaymentText)
                    }
                    Toggle("Esta en mora / atrasada", isOn: $debt.isOverdue)
                }
                .padding(.vertical, 2)
            }
            .onDelete { viewModel.debts.remove(atOffsets: $0) }

            Button {
                viewModel.debts.append(DebtDraft())
            } label: {
                Label("Agregar deuda", systemImage: "plus.circle")
            }
        }
    }

    private var savingsStep: some View {
        Section("¿Tienes ahorros o inversiones actuales?") {
            Toggle("Si, tengo algo ahorrado", isOn: $viewModel.hasSavings)
            if viewModel.hasSavings {
                AmountField(placeholder: "¿Cuanto tienes ahorrado/invertido?", text: $viewModel.savingsAmountText)
                TextField("Nota (ej. meta banco, disponible en diciembre)", text: $viewModel.savingsNote, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
    }

    private var riskToleranceStep: some View {
        Section("¿Que tanto riesgo te sientes comodo tomando al invertir?") {
            Picker("Tolerancia al riesgo", selection: $viewModel.riskTolerance) {
                Text("Prefiero no decir").tag(RiskTolerance?.none)
                ForEach(RiskTolerance.allCases) { tolerance in
                    Text(tolerance.displayName).tag(Optional(tolerance))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    private var shortTermGoalsStep: some View {
        Section("Tus metas a corto plazo (1 año)") {
            Text("Ej. crear un fondo de emergencia, liquidar una deuda, organizar el presupuesto.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach($viewModel.shortTermGoals) { $goal in
                TextField("Una meta", text: $goal.text)
            }
            .onDelete { viewModel.shortTermGoals.remove(atOffsets: $0) }

            Button {
                viewModel.shortTermGoals.append(GoalDraft())
            } label: {
                Label("Agregar meta", systemImage: "plus.circle")
            }
        }
    }

    private var longTermGoalsStep: some View {
        Section("Tus metas a largo plazo (5+ años)") {
            Text("Ej. educacion de la familia, invertir en bienes raices, independencia financiera.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach($viewModel.longTermGoals) { $goal in
                TextField("Una meta", text: $goal.text)
            }
            .onDelete { viewModel.longTermGoals.remove(atOffsets: $0) }

            Button {
                viewModel.longTermGoals.append(GoalDraft())
            } label: {
                Label("Agregar meta", systemImage: "plus.circle")
            }
        }
    }

    private var summaryStep: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Listo, \(viewModel.fullName.isEmpty ? "eso es todo" : viewModel.fullName).")
                    .font(.title3.bold())
                Text("Vamos a crear tu cuenta \"\(viewModel.accountName)\" y anotar todo lo que marcaste como recurrente, para que ya lo veas reflejado desde hoy.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
    }

    private func finish() async {
        guard let userId = appState.currentUserId else { return }
        let success = await viewModel.finish(userId: userId)
        if success {
            appState.markOnboardingCompleted()
        }
    }
}
