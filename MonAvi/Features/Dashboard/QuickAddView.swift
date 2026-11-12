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
    /// Pantalla de escucha a pantalla completa (al tocar el microfono):
    /// tapa el formulario y el teclado hasta que hay un resultado.
    @State private var isVoiceMode = false
    /// Corta la grabacion sola tras un silencio, sin tener que tocar nada.
    @State private var silenceTask: Task<Void, Never>?

    @State private var movementType: MovementType = .gasto
    @State private var amountText = ""
    @State private var description = ""
    /// Opcional a proposito — la idea de quick-add es rapidez, asi que la
    /// categoria sigue sin ser obligatoria. Si la marcas, de una vez ves
    /// cuanto presupuesto te queda en esa categoria.
    @State private var category: CategoryChoice?
    /// true si el usuario toco una categoria a mano (o vino de la voz o del
    /// movimiento que se edita): entonces la sugerencia automatica por la
    /// descripcion ya no la pisa.
    @State private var userPickedCategory = false
    /// Espera ~0.4 s sin escribir antes de sugerir categoria.
    @State private var suggestionTask: Task<Void, Never>?
    @ObservedObject private var userCategories = UserCategoriesStore.shared
    /// Lo que el usuario suele anotar (ultimos ~300 movimientos): la mejor
    /// señal para sugerir categoria. Se carga una vez al abrir.
    @State private var historyLearner = CategoryHistoryLearner(entries: [])
    @State private var historyLoaded = false
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
                // Compacto a proposito: tipo (una fila) + monto arriba,
                // siempre visibles sobre el panel de abajo (categorias,
                // "¿Qué fue?", teclado y Guardar). Cuentas en un iPhone Pro
                // de 852 pt: barra ~100, tipo ~44, monto ~82, panel ~424
                // (con el indicador de inicio) — sobra espacio.
                VStack(spacing: 12) {
                    MovementTypePicker(selection: $movementType, types: MovementType.quickAddTypes, compact: true)
                        .padding(.top, 4)

                    amountDisplay

                    budgetHint


                    if viewModel.defaultAccountId == nil {
                        Text("Necesitas una cuenta para guardar movimientos — crea una en Ajustes > Cuentas.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red).font(.footnote)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(existingTransaction == nil ? "Anotar movimiento" : "Editar movimiento")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    // Categorias y "¿Qué fue?" van pegados al teclado:
                    // siempre a la vista (tambien con el teclado del
                    // sistema arriba), sin tener que hacer scroll.
                    categoryChips
                    descriptionField

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
                .padding(.top, 8)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity)
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .sheet(isPresented: $showingCategoryPicker) {
                CategoryPickerSheet(selection: builtInSelection, categories: sortedCategories)
            }
            .onAppear {
                if let existingTransaction {
                    loadExistingTransaction(existingTransaction)
                } else if autoStartVoice {
                    Task { await startVoice() }
                }
            }
            .onDisappear {
                cancelVoice()
                suggestionTask?.cancel()
            }
            .onChange(of: description) { _, _ in
                scheduleCategorySuggestion()
            }
            .onChange(of: movementType) { _, _ in
                scheduleCategorySuggestion(delayNanoseconds: 0)
            }
            .onChange(of: voiceRecognizer.liveTranscript) { _, transcript in
                scheduleAutoStop(after: transcript)
            }
            .onChange(of: voiceRecognizer.endOfSpeechCount) { _, _ in
                // Termino de hablar: se corta y se interpreta solo.
                guard isVoiceMode, voiceRecognizer.isRecording else { return }
                Task { await finishVoice() }
            }
            .overlay {
                if isVoiceMode {
                    VoiceListeningView(
                        recognizer: voiceRecognizer,
                        onFinish: { Task { await finishVoice() } },
                        onRetry: { Task { await startVoice() } },
                        onType: cancelVoice
                    )
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isVoiceMode)
            .task { await refreshBudgets() }
            .task { await refreshSortedCategories() }
            .task { await userCategories.refresh() }
            .task { await loadCategoryHistory() }
            .overlay {
                if showingSavingAnimation {
                    MovementSavingOverlay(
                        movementType: movementType,
                        itemEmoji: category?.emoji ?? movementType.emoji,
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
                .frame(height: 48)
        }
        .buttonStyle(.borderedProminent)
        .tint(movementType.tintColor)
        .disabled(enteredMagnitude <= 0 || isSaving || viewModel.defaultAccountId == nil)
    }

    /// El monto en grande, con el signo del tipo de movimiento — se llena
    /// con el teclado propio de abajo.
    private var descriptionField: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil")
                .foregroundStyle(.secondary)
            TextField("¿Qué fue? ej. Almuerzo", text: $description)
                .font(.body)
                .focused($descriptionFocused)
                .submitLabel(.done)
                .onSubmit { descriptionFocused = false }
            if descriptionFocused {
                Button("Listo") { descriptionFocused = false }
                    .font(.subheadline.weight(.semibold))
            } else if existingTransaction == nil {
                // Dictar el movimiento completo (monto, que fue y categoria).
                Button {
                    Task { await startVoice() }
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(MonAviBrand.primary))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dictar movimiento")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .frame(minHeight: 46)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
        .contentShape(Rectangle())
        .onTapGesture { descriptionFocused = true }
    }

    private var amountDisplay: some View {
        VStack(spacing: 2) {
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
    /// Fila compacta de categorias, en el panel de abajo junto a "¿Qué
    /// fue?". Se desplaza sola hasta la elegida (o la sugerida).
    private var categoryChips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chipChoices) { option in
                        let isSelected = category?.id == option.id
                        Button {
                            selectCategory(isSelected ? nil : option)
                        } label: {
                            Text("\(option.emoji) \(option.title)")
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule().fill(
                                        isSelected
                                            ? MonAviBrand.primary
                                            : Color(.secondarySystemBackground)
                                    )
                                )
                                .foregroundStyle(isSelected ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                        .id(option.id)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ver todas las categorías")
                }
                .padding(.vertical, 1)
            }
            .onChange(of: category?.id) { _, newId in
                guard let newId else { return }
                withAnimation(.snappy) {
                    proxy.scrollTo(newId, anchor: .center)
                }
            }
        }
        .accessibilityLabel("Categoría")
    }

    /// Fijas relevantes al tipo de movimiento (para ingresos, las de
    /// ingreso primero; para gastos, las que mas usa), luego las propias
    /// del usuario, y la elegida al inicio si no esta entre ellas.
    private var chipChoices: [CategoryChoice] {
        let builtIns: [TransactionCategory]
        if movementType.isInflow {
            builtIns = [.income, .gifts, .savings, .other]
        } else {
            builtIns = Array(sortedCategories.filter { $0 != .income }.prefix(8))
        }

        var chips = builtIns.map { CategoryChoice.builtIn($0) }
        for custom in userCategories.applicable(isInflow: movementType.isInflow) {
            let choice = CategoryChoice(custom)
            if !chips.contains(where: { $0.id == choice.id }) {
                chips.append(choice)
            }
        }
        if let category, !chips.contains(where: { $0.id == category.id }) {
            chips.insert(category, at: 0)
        }
        return chips
    }

    /// Puente para la hoja "Todas" (solo categorias fijas).
    private var builtInSelection: Binding<TransactionCategory?> {
        Binding(
            get: { category?.builtIn },
            set: { newValue in selectCategory(newValue.map { CategoryChoice.builtIn($0) }) }
        )
    }

    /// Eleccion manual: desde aqui la sugerencia automatica ya no la cambia.
    private func selectCategory(_ choice: CategoryChoice?) {
        category = choice
        userPickedCategory = choice != nil
    }

    /// Sugiere categoria por lo escrito en "¿Qué fue?", tras una pausa al
    /// escribir. Solo si el usuario no eligio una a mano.
    private func scheduleCategorySuggestion(delayNanoseconds: UInt64 = 400_000_000) {
        suggestionTask?.cancel()
        guard !userPickedCategory else { return }
        let text = description
        let isInflow = movementType.isInflow
        suggestionTask = Task { @MainActor in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled, !userPickedCategory else { return }
            withAnimation(.snappy) {
                category = suggestedCategory(for: text, isInflow: isInflow)
            }
        }
    }

    /// En orden: 1) lo que el usuario suele usar para esa descripcion o
    /// primera palabra (historial), 2) una categoria propia cuyo nombre
    /// aparezca en el texto, 3) las palabras clave de las fijas, y 4) (dentro
    /// del mismo CategoryKeywordGuesser) el adivinador de comercios.
    private func suggestedCategory(for text: String, isInflow: Bool) -> CategoryChoice? {
        if let stored = historyLearner.category(for: text, isInflow: isInflow),
           let choice = CategoryChoice(stored: stored),
           isStillAvailable(choice) {
            return choice
        }
        let padded = CategoryKeywordGuesser.normalizedPadded(text)
        for custom in userCategories.applicable(isInflow: isInflow) {
            let name = CategoryKeywordGuesser.normalizedPadded(custom.name).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, padded.contains(" \(name)") {
                return CategoryChoice(custom)
            }
        }
        return CategoryKeywordGuesser.category(for: text, isInflow: isInflow).map { CategoryChoice.builtIn($0) }
    }

    /// Una categoria propia que el usuario ya borro no se vuelve a sugerir.
    private func isStillAvailable(_ choice: CategoryChoice) -> Bool {
        guard case .custom(let name, _) = choice else { return true }
        let key = CategoryKeywordGuesser.normalizedPadded(name)
        return userCategories.categories.contains {
            CategoryKeywordGuesser.normalizedPadded($0.name) == key
        }
    }

    /// Carga una sola vez los ultimos movimientos para aprender de ellos.
    private func loadCategoryHistory() async {
        guard !historyLoaded, let userId = appState.currentUserId else { return }
        historyLoaded = true
        let recent = (try? await TransactionsRepository.shared.fetchRecent(userId: userId, limit: 300)) ?? []
        historyLearner = CategoryHistoryLearner(transactions: recent)
        // Si ya habia texto escrito (o dictado), re-sugerir con el historial.
        if !description.isEmpty {
            scheduleCategorySuggestion(delayNanoseconds: 0)
        }
    }

    /// "Ve el presupuesto restante al agregar gastos" tambien en el camino
    /// rapido, si el usuario decidio marcar una categoria.
    private var matchingBudgetProgress: BudgetProgress? {
        guard let category = category?.builtIn else { return nil }
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

    // MARK: - Voz

    private func startVoice() async {
        descriptionFocused = false
        isVoiceMode = true
        guard !voiceRecognizer.isRecording else { return }
        _ = await voiceRecognizer.toggleRecording()
    }

    /// Termina de escuchar y pre-llena el formulario con lo que entendio
    /// Claude. Si falla, la pantalla de escucha muestra el error y deja
    /// reintentar o escribir.
    private func finishVoice() async {
        silenceTask?.cancel()
        silenceTask = nil
        guard voiceRecognizer.isRecording else { return }
        guard let parsed = await voiceRecognizer.toggleRecording()?.normalizedForQuickAdd() else { return }

        movementType = parsed.movementType
        if parsed.amount > 0 {
            let isWhole = parsed.amount.rounded() == parsed.amount
            amountText = String(format: isWhole ? "%.0f" : "%.2f", parsed.amount)
        } else {
            amountText = ""
        }
        description = parsed.description
        if let parsedCategory = parsed.category.flatMap(TransactionCategory.init(rawValue:)) {
            category = .builtIn(parsedCategory)
            userPickedCategory = true
        }
        isVoiceMode = false
    }

    private func cancelVoice() {
        silenceTask?.cancel()
        silenceTask = nil
        voiceRecognizer.cancel()
        isVoiceMode = false
    }

    /// Cada palabra nueva reinicia la cuenta: tras 1.8 s sin hablar, se
    /// corta y se interpreta solo.
    private func scheduleAutoStop(after transcript: String) {
        guard isVoiceMode, voiceRecognizer.isRecording, !transcript.isEmpty else { return }
        silenceTask?.cancel()
        silenceTask = Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            await finishVoice()
        }
    }

    private func loadExistingTransaction(_ transaction: FinanceTransaction) {
        // "Pago a proveedor" / "Transferencia" (datos viejos) se cargan como
        // gasto con categoria Proveedores / Transferencias, y asi se guardan.
        let mapping = transaction.movementType.quickAddMapping
        movementType = mapping.movementType
        amountText = NSDecimalNumber(decimal: abs(transaction.amount)).stringValue
        description = transaction.description ?? ""
        // Una categoria propia (o ya borrada) se carga como propia, no se
        // pierde por no ser una de las fijas.
        category = mapping.category.map { CategoryChoice.builtIn($0) } ?? CategoryChoice(stored: transaction.category)
        userPickedCategory = category != nil
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
        // Que el teclado no tape el recibo / carrito de la animacion.
        descriptionFocused = false
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
        suggestionTask?.cancel()
        showingSavingAnimation = true
        defer { isSaving = false }

        do {
            async let saved: Void = viewModel.quickAdd(
                userId: userId,
                accountId: accountId,
                magnitude: magnitude,
                description: description,
                movementType: movementType,
                category: category?.storedValue
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
                category: category?.storedValue,
                description: description.isEmpty ? nil : description
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
