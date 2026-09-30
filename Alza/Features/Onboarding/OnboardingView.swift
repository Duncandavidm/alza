import SwiftUI

/// El estudio financiero inicial: 8 pasos cortos que arman el panorama
/// completo del usuario (datos, ingresos fijos/variables, cuentas fijas,
/// suscripciones, otras cuentas) para que el resto de Alza pueda aconsejar
/// desde el primer dia.
struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = OnboardingViewModel()
    @State private var step = 0

    private let totalSteps = 8

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: Double(totalSteps))
                    .padding(.horizontal)
                    .padding(.top, 8)

                Form {
                    switch step {
                    case 0: welcomeStep
                    case 1: accountStep
                    case 2: fixedIncomeStep
                    case 3: variableIncomeStep
                    case 4: commonBillsStep
                    case 5: subscriptionsStep
                    case 6: otherFixedItemsStep
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

    private var welcomeStep: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("¡Bienvenido a Alza!")
                    .font(.title2.bold())
                Text("Antes de empezar, hagamos un repaso corto de tus finanzas. Con esto Alza te puede dar consejos de verdad, no genericos.")
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
                TextField("¿Cuanto? (por mes)", text: $viewModel.fixedIncomeAmountText)
                    .keyboardType(.decimalPad)
                Stepper("Dia de pago: \(viewModel.fixedIncomeDay)", value: $viewModel.fixedIncomeDay, in: 1...28)
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
            Text("Marca las que apliquen y pon cuanto pagas.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach($viewModel.commonBills) { $bill in
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(bill.name, isOn: $bill.isEnabled)
                    if bill.isEnabled {
                        TextField("Monto mensual", text: $bill.amountText)
                            .keyboardType(.decimalPad)
                        Stepper("Dia aproximado: \(bill.dayOfMonth)", value: $bill.dayOfMonth, in: 1...28)
                    }
                }
                .padding(.vertical, 2)
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
                    TextField("Monto mensual", text: $item.amountText)
                        .keyboardType(.decimalPad)
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
                    TextField("Monto mensual", text: $item.amountText)
                        .keyboardType(.decimalPad)
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
