import SwiftUI

/// Mejora #2: ingreso ultra-rapido. Solo pregunta "¿cuanto?" y "¿que fue?" —
/// el tipo de movimiento esta ahi para diferenciarlo (mejora #3) pero es un
/// toque opcional, no un formulario. Sin categoria obligatoria.
struct QuickAddView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: DayJournalViewModel
    /// true cuando se abre desde el boton grande de microfono del
    /// dashboard — empieza a escuchar de una vez, sin que el usuario tenga
    /// que tocar el boton de voz otra vez adentro.
    var autoStartVoice: Bool = false
    /// Si no es nil, esta hoja edita este movimiento en vez de crear uno
    /// nuevo — mismo formulario, precargado (patron ya usado en
    /// AddSavingsGoalView). La cuenta no se puede cambiar aqui a proposito
    /// (ver TransactionsRepository.update); para eso hay que borrar y
    /// anotar de nuevo.
    var existingTransaction: FinanceTransaction? = nil
    @StateObject private var voiceRecognizer = VoiceTransactionRecognizer()
    @StateObject private var budgetsViewModel = BudgetsViewModel()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var descriptionFocused: Bool
    @State private var showingCategoryPicker = false

    @State private var movementType: MovementType = .gasto
    @State private var amountText = ""
    @State private var description = ""
    /// Opcional a proposito — la idea de quick-add es rapidez, asi que la
    /// categoria sigue sin ser obligatoria. Si la marcas, de una vez ves
    /// cuanto presupuesto te queda en esa categoria.
    @State private var category: TransactionCategory?
    @State private var sortedCategories: [TransactionCategory] = TransactionCategory.allCases
    @State private var isSaving = false
    @State private var showingSavingAnimation = false
    @State private var errorMessage: String?
    @State private var showingAdvice = false
    @State private var adviceText = ""
    @State private var adviceItems: [PaymentAdviceItem] = []

    private var enteredMagnitude: Decimal {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    MovementTypePicker(selection: $movementType)
                        .padding(.top, 8)

                    amountDisplay

                    VStack(alignment: .leading, spacing: 6) {
                        Text("¿Qué fue?")
                            .font(.headline)
                        TextField("ej. Compra de harina", text: $description)
                            .font(.title3)
                            .focused($descriptionFocused)
                            .submitLabel(.done)
                            .onSubmit { descriptionFocused = false }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.secondarySystemBackground))
                            )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Categoría")
                            .font(.headline)
                        categoryChips
                    }

                    budgetHint

                    if existingTransaction == nil {
                        voiceButton
                    }

                    if viewModel.defaultAccountId == nil {
                        Text("Necesitas una cuenta para guardar movimientos — crea una en Ajustes > Cuentas.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red).font(.footnote)
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(existingTransaction == nil ? "Anotar movimiento" : "Editar movimiento")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    // El teclado propio se esconde mientras se escribe la
                    // descripcion, para no apilarlo con el del sistema.
                    if !descriptionFocused {
                        AmountKeypad(
                            text: $amountText,
                            isInflow: movementType.isInflow,
                            onToggleSign: toggleSign
                        )
                    }
                    saveButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .sheet(isPresented: $showingCategoryPicker) {
                CategoryPickerSheet(selection: $category, categories: sortedCategories)
            }
            .onAppear {
                if let existingTransaction {
                    loadExistingTransaction(existingTransaction)
                } else if autoStartVoice {
                    Task { await handleMicTap() }
                }
            }
            .task { await refreshBudgets() }
            .task { await refreshSortedCategories() }
            .overlay {
                if showingSavingAnimation {
                    MovementSavingOverlay(
                        movementType: movementType,
                        itemEmoji: movementType.emoji,
                        description: description,
                        amount: enteredMagnitude
                    )
                }
            }
            .sheet(isPresented: $showingAdvice, onDismiss: { dismiss() }) {
                if let userId = appState.currentUserId {
                    PaymentAdviceView(advice: adviceText, items: adviceItems, userId: userId)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            Text(existingTransaction == nil ? "Guardar" : "Guardar cambios")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
        }
        .buttonStyle(.borderedProminent)
        .tint(movementType.tintColor)
        .disabled(enteredMagnitude <= 0 || isSaving || viewModel.defaultAccountId == nil)
    }

    /// El monto en grande, con el signo del tipo de movimiento — se llena
    /// con el teclado propio de abajo.
    private var amountDisplay: some View {
        VStack(spacing: 4) {
            Text("¿Cuánto?")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(movementType.isInflow ? "+" : "−")
                    .foregroundStyle(movementType.tintColor)
                Text("$")
                    .foregroundStyle(.secondary)
                Text(amountText.isEmpty ? "0" : amountText)
                    .foregroundStyle(amountText.isEmpty ? Color.secondary : Color.primary)
                    .contentTransition(.numericText())
            }
            .font(.system(size: 52, weight: .bold, design: MonAviBrand.fontDesign))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .animation(.snappy, value: amountText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Monto: \(amountText.isEmpty ? "0" : amountText) dólares")
    }

    /// +/− del teclado: cambia entre gasto e ingreso.
    private func toggleSign() {
        movementType = movementType.isInflow ? .gasto : .ingreso
    }

    /// Alternativa al llenado manual: dictar el movimiento en voz alta y
    /// que Claude lo interprete (monto, descripcion, tipo). Inspirado en el
    /// reconocimiento de voz de MonAi.
    private var voiceButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task { await handleMicTap() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: voiceRecognizer.isRecording ? "waveform" : "mic.fill")
                        .foregroundStyle(voiceRecognizer.isRecording ? .red : .accentColor)
                    Text(micLabel)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    if voiceRecognizer.isProcessing {
                        ProgressView()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(voiceRecognizer.isRecording ? Color.red.opacity(0.12) : Color(.secondarySystemBackground))
                )
            }
            .buttonStyle(.plain)
            .disabled(voiceRecognizer.isProcessing)

            if voiceRecognizer.isRecording && !voiceRecognizer.liveTranscript.isEmpty {
                Text(voiceRecognizer.liveTranscript)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let voiceError = voiceRecognizer.errorMessage {
                Text(voiceError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chipCategories) { option in
                    Button {
                        category = (category == option) ? nil : option
                    } label: {
                        Text("\(option.emoji) \(option.rawValue)")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(
                                    category == option
                                        ? MonAviBrand.primary
                                        : Color(.secondarySystemBackground)
                                )
                            )
                            .foregroundStyle(category == option ? .white : .primary)
                    }
                }

                Button {
                    showingCategoryPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text("Todas")
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().strokeBorder(MonAviBrand.primary, lineWidth: 1.5))
                    .foregroundStyle(MonAviBrand.primary)
                }
                .accessibilityLabel("Ver todas las categorías")
            }
        }
    }

    /// Las 6 que mas usa el usuario, y la elegida si no esta entre ellas.
    private var chipCategories: [TransactionCategory] {
        var chips = Array(sortedCategories.prefix(6))
        if let category, !chips.contains(category) {
            chips.insert(category, at: 0)
        }
        return chips
    }

    /// "Ve el presupuesto restante al agregar gastos" tambien en el camino
    /// rapido, si el usuario decidio marcar una categoria.
    private var matchingBudgetProgress: BudgetProgress? {
        guard let category else { return nil }
        return budgetsViewModel.progresses.first { $0.budget.category == category.rawValue }
    }

    @ViewBuilder
    private var budgetHint: some View {
        if movementType == .gasto, let progress = matchingBudgetProgress {
            let remaining = progress.budget.limitAmount - progress.spent - enteredMagnitude
            HStack(spacing: 6) {
                Image(systemName: remaining >= 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(remaining >= 0 ? MonAviBrand.primary : MonAviBrand.alert)
                if remaining >= 0 {
                    Text("Te quedarian \(remaining, format: .currency(code: "USD")).")
                } else {
                    Text("Te pasarias por \(abs(remaining), format: .currency(code: "USD")).")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func refreshBudgets() async {
        guard let userId = appState.currentUserId else { return }
        await budgetsViewModel.refresh(userId: userId)
    }

    private func refreshSortedCategories() async {
        guard let userId = appState.currentUserId else { return }
        sortedCategories = await CategoryUsageService.sortedCategories(userId: userId)
    }

    private var micLabel: String {
        if voiceRecognizer.isProcessing { return "Entendiendo lo que dijiste..." }
        if voiceRecognizer.isRecording { return "Escuchando... toca para terminar" }
        return "O dilo en voz alta"
    }

    private func handleMicTap() async {
        if let parsed = await voiceRecognizer.toggleRecording() {
            movementType = parsed.movementType
            amountText = parsed.amount == 0 ? "" : String(format: "%.2f", parsed.amount)
            description = parsed.description
        }
    }

    private func loadExistingTransaction(_ transaction: FinanceTransaction) {
        movementType = transaction.movementType
        amountText = NSDecimalNumber(decimal: abs(transaction.amount)).stringValue
        description = transaction.description ?? ""
        category = transaction.category.flatMap(TransactionCategory.init(rawValue:))
    }

    private func save() async {
        guard
            let magnitude = Decimal(string: amountText.replacingOccurrences(of: ",", with: "."))
        else { return }

        if let existingTransaction {
            await saveEdit(to: existingTransaction, magnitude: magnitude)
            return
        }

        guard
            let userId = appState.currentUserId,
            let accountId = viewModel.defaultAccountId
        else { return }

        isSaving = true
        showingSavingAnimation = true
        defer { isSaving = false }

        do {
            async let saved: Void = viewModel.quickAdd(
                userId: userId,
                accountId: accountId,
                magnitude: magnitude,
                description: description,
                movementType: movementType,
                category: category?.rawValue
            )
            async let minDelay: Void = Task.sleep(nanoseconds: MovementSavingOverlay.minDisplayNanoseconds(for: movementType))
            _ = try await (saved, minDelay)

            if movementType == .ingreso, let advice = try? await PaymentAdviceService.fetch(userId: userId, incomeAmount: magnitude),
               advice.hasAdvice {
                adviceText = advice.advice ?? ""
                adviceItems = advice.items ?? []
                NotificationManager.sendPaymentPriorityNotification(items: adviceItems)
                showingAdvice = true
                return
            }

            dismiss()
        } catch {
            showingSavingAnimation = false
            errorMessage = error.localizedDescription
        }
    }

    private func saveEdit(to transaction: FinanceTransaction, magnitude: Decimal) async {
        isSaving = true
        defer { isSaving = false }

        do {
            try await viewModel.updateTransaction(
                transaction,
                magnitude: magnitude,
                movementType: movementType,
                category: category?.rawValue,
                description: description.isEmpty ? nil : description
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
