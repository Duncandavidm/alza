import SwiftUI

/// El estudio financiero inicial: pasos cortos que arman el panorama
/// completo del usuario (datos personales, ingresos fijos/variables,
/// cuentas fijas, suscripciones, deudas, ahorros, tolerancia al riesgo y
/// metas) para que el resto de MonAvi pueda aconsejar desde el primer dia,
/// inspirado en el detalle del prompt original de la version web.
struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = OnboardingViewModel()
    @State private var step = 0
    /// Idioma de la app (1.1.0), elegible desde la primera pantalla.
    @State private var language = AppLanguage.current
    @State private var languageChanged = false

    private let totalSteps = 16

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
                    case 13: budgetsStep
                    case 14: shortcutsStep
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
            .alert("Algo salió mal", isPresented: .constant(viewModel.errorMessage != nil)) {
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
            Picker(selection: $language) {
                ForEach(AppLanguage.allCases) { option in
                    Text(verbatim: option.nativeName).tag(option)
                }
            } label: {
                Text(verbatim: "Idioma · Language")
            }
            .pickerStyle(.segmented)
            .onChange(of: language) { _, newValue in
                guard newValue != AppLanguage.current else { languageChanged = false; return }
                AppLanguage.choose(newValue)
                Task { await appState.saveLanguagePreference(newValue) }
                languageChanged = true
            }
        } footer: {
            if languageChanged {
                Text(verbatim: language == .english
                    ? "Close MonAvi and open it again to continue in English."
                    : "Cierra MonAvi y vuelve a abrirla para continuar en español.")
            }
        }

        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("¡Bienvenido a MonAvi!")
                    .font(.title2.bold())
                Text("Antes de empezar, hagamos un repaso corto de tus finanzas. Con esto MonAvi te puede dar consejos de verdad, no genericos.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }

        Section("¿Cómo te llamas?") {
            TextField("Tu nombre", text: $viewModel.fullName)
        }

        if appState.offersCountryChoice {
            Section {
                CountryPicker(selection: $viewModel.country)
            } header: {
                Text("Elige tu país")
            } footer: {
                Text("Tus montos se mostrarán en \(viewModel.country.currencyName). El país y la moneda quedan fijos en tu cuenta.")
            }
            .onAppear { appState.applyCountry(viewModel.country) }
            .onChange(of: viewModel.country) { _, newValue in
                appState.applyCountry(newValue)
            }
        }
    }

    @ViewBuilder
    private var accountStep: some View {
        Section("Tu cuenta principal") {
            Text("¿De dónde sale y entra la mayoría de tu dinero? (banco, efectivo...)")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("ej. Cuenta de banco, Efectivo", text: $viewModel.accountName)
        }

        Section {
            AmountField(placeholder: L("¿Cuánto tienes hoy ahí?"), text: $viewModel.accountBalanceText)
        } header: {
            Text("¿Cuánto tienes hoy en esa cuenta?")
        } footer: {
            Text("Mira tu app del banco o cuenta tu efectivo. Así tu saldo en MonAvi empieza igual al real, no en $0. Lo puedes ajustar después.")
        }
    }

    private var fixedIncomeStep: some View {
        Section("¿Tienes un salario u otro ingreso fijo?") {
            Toggle("Si, tengo un ingreso fijo", isOn: $viewModel.hasFixedIncome)
            if viewModel.hasFixedIncome {
                Text("¿Cada cuánto te pagan?")
                    .font(.subheadline)
                Picker("¿Cada cuánto te pagan?", selection: $viewModel.fixedIncomeFrequency) {
                    ForEach(PayFrequency.allCases) { frequency in
                        Text(frequency.displayName).tag(frequency)
                    }
                }
                .pickerStyle(.segmented)

                AmountField(placeholder: viewModel.fixedIncomeFrequency.amountPlaceholder, text: $viewModel.fixedIncomeAmountText)

                switch viewModel.fixedIncomeFrequency {
                case .monthly:
                    DayOfMonthField(label: L("Día de pago"), day: $viewModel.fixedIncomeDay)
                case .biweekly:
                    DayOfMonthField(label: "Primera quincena", day: $viewModel.fixedIncomeDay)
                    DayOfMonthField(label: "Segunda quincena", day: $viewModel.fixedIncomeSecondDay)
                    Text("Si el mes tiene menos días, contamos el último día del mes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .weekly:
                    Picker("Día de pago", selection: $viewModel.fixedIncomeWeekday) {
                        ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { weekday in
                            Text(RecurringTransaction.weekdayName(weekday).capitalized).tag(weekday)
                        }
                    }
                case .daily:
                    Text("Te preguntaremos cada día en Hoy si ya lo recibiste, sin enviarte notificaciones.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var variableIncomeStep: some View {
        Section("¿Tienes otros ingresos que varían?") {
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
            Text("Marca las que apliquen, cambia el nombre si no coincide, y pon cuánto pagas. Si te falta alguna, agrégala abajo.")
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
                        DayOfMonthField(label: L("Día aproximado"), day: $bill.dayOfMonth)
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
        Section("¿Qué suscripciones tienes?") {
            Text("Netflix, Spotify, gimnasio, software — lo que pagues seguido.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach($viewModel.subscriptions) { $item in
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Nombre (ej. Netflix)", text: $item.name)
                    AmountField(placeholder: "Monto mensual", text: $item.amountText)
                    DayOfMonthField(label: L("Día de cobro"), day: $item.dayOfMonth)
                }
                .padding(.vertical, 2)
            }
            .onDelete { viewModel.subscriptions.remove(atOffsets: $0) }

            Button {
                viewModel.subscriptions.append(CustomFixedItemDraft())
            } label: {
                Label("Agregar suscripción", systemImage: "plus.circle")
            }
        }
    }

    private var otherFixedItemsStep: some View {
        Section("¿Otras cuentas fijas cada mes?") {
            Text("Colegio o matricula de tus hijos, mesada que das, préstamos — lo que se repita mes a mes.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach($viewModel.otherFixedItems) { $item in
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Nombre (ej. Colegio)", text: $item.name)
                    AmountField(placeholder: "Monto mensual", text: $item.amountText)
                    DayOfMonthField(label: L("Día de pago"), day: $item.dayOfMonth)
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

            Picker("Género", selection: $viewModel.gender) {
                Text("Sin especificar").tag(ProfileGender?.none)
                ForEach(ProfileGender.allCases) { gender in
                    Text(gender.displayName).tag(Optional(gender))
                }
            }

            TextField("Cuántos dependen de ti (hijos, etc.)", text: $viewModel.dependentsCountText)
                .keyboardType(.numberPad)

            TextField("A qué te dedicas (ej. dueño de un negocio, empleado...)", text: $viewModel.occupation, axis: .vertical)
                .lineLimit(2...4)
        }
    }

    private var debtsStep: some View {
        Section("¿Tienes deudas activas?") {
            Text("Tarjetas de crédito, préstamos, sobregiros — con esto MonAvi te puede avisar cuál pagar primero según la tasa de interés y si está en mora.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach($viewModel.debts) { $debt in
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Acreedor (ej. Tarjeta de crédito)", text: $debt.creditor)
                    LabeledField(label: L("¿Cuánto debes hoy?")) {
                        AmountField(placeholder: "Saldo actual", text: $debt.balanceText)
                    }
                    LabeledField(label: L("Cupo total (si es tarjeta)")) {
                        AmountField(placeholder: "ej. 3000", text: $debt.creditLimitText)
                    }
                    if let use = DebtDraftMath.utilization(debt) {
                        Text(L("Usas el %@ de tu cupo%@", FinancialSnapshot.percent(use), use > 0.3 ? L(" — lo ideal es menos del 30%") : ""))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(use > 0.3 ? .orange : MonAviBrand.primary)
                    }
                    LabeledField(label: L("Día de pago de cada mes (opcional)")) {
                        TextField("ej. 15", text: $debt.paymentDayText)
                            .keyboardType(.numberPad)
                    }
                    LabeledField(label: L("Tasa de interés (opcional)")) {
                        HStack {
                            PercentField(placeholder: debt.interestPeriod == .annual ? "ej. 24" : "ej. 2", text: $debt.interestRateText)
                            Picker("", selection: $debt.interestPeriod) {
                                ForEach(InterestPeriod.allCases) { period in
                                    Text(period.label).tag(period)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 170)
                        }
                    }
                    LabeledField(label: L("Pago mínimo (opcional)")) {
                        AmountField(placeholder: "ej. 60", text: $debt.minimumPaymentText)
                    }
                    Toggle("Está en mora / atrasada", isOn: $debt.isOverdue)
                }
                .padding(.vertical, 2)
            }
            .onDelete { viewModel.debts.remove(atOffsets: $0) }

            Button {
                viewModel.debts.append(DebtDraft(creditor: viewModel.debts.isEmpty ? L("Tarjeta de crédito") : ""))
            } label: {
                Label("Agregar deuda", systemImage: "plus.circle")
            }
        }
    }

    @ViewBuilder
    private var budgetsStep: some View {
        Section {
            Text("Ponle un límite al mes a lo que más gastas. En Hoy verás cuánto llevas en cada uno, justo debajo del total del día.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if viewModel.snapshot.freeMoney > 0 {
                Text("Después de tus pagos fijos te quedan unos \(FinancialSnapshot.money(viewModel.snapshot.freeMoney)) libres al mes.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MonAviBrand.primary)
            }
            ForEach($viewModel.budgets) { $budget in
                HStack(spacing: 8) {
                    Text(budget.emoji)
                    TextField("Nombre de la categoría", text: $budget.name)
                        .textInputAutocapitalization(.sentences)
                    AmountField(placeholder: L("Sin límite"), text: $budget.limitText)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 140)
                }
            }
            .onDelete { viewModel.budgets.remove(atOffsets: $0) }

            Menu {
                ForEach(BudgetDraft.addable.filter { category in
                    !viewModel.budgets.contains { $0.trimmedName == category.rawValue }
                }) { category in
                    Button("\(category.emoji) \(category.rawValue)") {
                        viewModel.budgets.append(BudgetDraft(category: category))
                    }
                }
                Button("🏷️ Otra (escribe el nombre)") {
                    viewModel.budgets.append(BudgetDraft())
                }
            } label: {
                Label("Agregar categoría", systemImage: "plus.circle")
            }
        } header: {
            Text("¿Quieres agregar presupuestos?")
        } footer: {
            Text("Es opcional: deja vacío lo que no quieras limitar. Toca un nombre para cambiarlo o desliza para quitarlo. Puedes agregar o cambiar presupuestos cuando quieras en la pestaña Presupuestos.")
        }
    }

    /// «Registra sin esfuerzo»: muestra los atajos que ya tiene MonAvi
    /// (Centro de control, doble toque atrás, widgets y avisos del banco).
    /// Solo informa; se configuran después en Ajustes > Automatizaciones.
    private var shortcutsStep: some View {
        Section {
            ControlCenterShowcase()
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            Label("Botones en el Centro de control: «Anotar gasto» y «Escanear factura».", systemImage: "switch.2")
            Label("Toca dos veces atrás del iPhone y dilo con tu voz, aun con la pantalla bloqueada.", systemImage: "hand.tap.fill")
            Label("Widgets «Tu día» y «Escanear factura» en la pantalla de inicio y la bloqueada.", systemImage: "apps.iphone")
            Label("Los avisos de tu banco y tus pagos con Apple Pay quedan listos para confirmar.", systemImage: "bell.badge.fill")
        } header: {
            Text("Registra sin esfuerzo")
        } footer: {
            Text("Configúralos cuando quieras en Ajustes > Automatizaciones.")
        }
        .font(.subheadline)
    }

    private var savingsStep: some View {
        Section("¿Tienes ahorros o inversiones actuales?") {
            Toggle("Si, tengo algo ahorrado", isOn: $viewModel.hasSavings)
            if viewModel.hasSavings {
                AmountField(placeholder: L("¿Cuánto tienes ahorrado/invertido?"), text: $viewModel.savingsAmountText)
                TextField("¿Dónde lo tienes? (ej. Ahorros Banco General)", text: $viewModel.savingsNote)
                Toggle("Está bloqueado hasta una fecha", isOn: $viewModel.savingsLocked)
                if viewModel.savingsLocked {
                    DatePicker("Disponible desde", selection: $viewModel.savingsAvailableOn, displayedComponents: .date)
                    Text("Plazo fijo, ahorro navideño… Ese día te preguntamos si ya está disponible. Si no tiene bloqueo, el dinero siempre está disponible.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Lo verás como una cuenta más en Hoy y en Ajustes > Cuentas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var riskToleranceStep: some View {
        Section("¿Qué tanto riesgo te sientes cómodo tomando al invertir?") {
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

    /// Ultimo paso: "Tu foto financiera" con todo lo que contesto y el plan
    /// para mejorar, antes de crear la cuenta y los pagos fijos.
    @ViewBuilder
    private var summaryStep: some View {
        FinancialSnapshotSections(snapshot: viewModel.snapshot, name: viewModel.fullName.trimmingCharacters(in: .whitespaces))

        Section {
            Text(L("Al tocar Empezar creamos tu cuenta \"%@\"%@, y anotamos tus pagos fijos para recordártelos%@.",
                   viewModel.accountName,
                   viewModel.hasSavings ? L(" y tu cuenta de ahorros") : "",
                   viewModel.budgets.contains { (OnboardingViewModel.amount($0.limitText) ?? 0) > 0 } ? L(", además de tus presupuestos del mes") : ""))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func finish() async {
        guard let userId = appState.currentUserId else { return }
        let success = await viewModel.finish(userId: userId)
        // 1.1.0: ya no se pide escanear la primera factura al terminar; la
        // persona recién empieza y todavía no ha gastado ni anotado ingresos.
        if success {
            appState.markOnboardingCompleted()
        }
    }
}
