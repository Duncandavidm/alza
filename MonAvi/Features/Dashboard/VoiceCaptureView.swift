import SwiftUI

/// "Registrar con voz" a pantalla completa, para Siri / Tocar atrás
/// (RecordByVoiceIntent) y "Probar ahora" en VoiceBackTapGuideView.
///
/// A diferencia de la voz dentro de QuickAddView (que solo pre-llena el
/// formulario para revisarlo), aqui se escucha, se interpreta y se GUARDA
/// de una vez, en la cuenta por defecto (la primera por created_at, igual
/// que AddMonAviExpenseIntent). Despues se muestra lo que se anoto con
/// "Deshacer" (lo borra) y "Editar" (abre QuickAddView para ese movimiento).
struct VoiceCaptureView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recognizer = VoiceTransactionRecognizer()
    /// Se reusa para cargar las cuentas, guardar, editar (QuickAddView lo
    /// pide) y deshacer, igual que en Hoy.
    @StateObject private var viewModel = DayJournalViewModel()

    private enum Phase: Equatable {
        case listening
        case saving
        case saved(FinanceTransaction)
        case noAccount
        case failed(String)
    }

    @State private var phase: Phase = .listening
    @State private var silenceTask: Task<Void, Never>?
    @State private var accountsLoaded = false
    @State private var editingTransaction: FinanceTransaction?
    @State private var isUndoing = false
    @State private var undoError: String?
    @State private var pulse = false

    /// Tras este silencio (sin palabras nuevas) se corta y se interpreta
    /// solo, como en QuickAddView.scheduleAutoStop.
    private static let silenceNanoseconds: UInt64 = 2_000_000_000

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                switch phase {
                case .listening, .saving:
                    listeningContent
                case .saved(let transaction):
                    savedContent(transaction)
                case .noAccount:
                    noAccountContent
                case .failed(let message):
                    failedContent(message)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)

            if !isSaved {
                Button {
                    close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color(.secondarySystemBackground)))
                }
                .padding(.trailing, 20)
                .padding(.top, 8)
                .accessibilityLabel("Cerrar")
                .disabled(phase == .saving)
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .animation(.easeInOut(duration: 0.25), value: phase)
        .sensoryFeedback(.success, trigger: isSaved) { _, saved in saved }
        .task { await loadAccounts() }
        .task { await startListening() }
        .onAppear { pulse = true }
        .onDisappear {
            silenceTask?.cancel()
            silenceTask = nil
            recognizer.cancel()
        }
        .onChange(of: recognizer.liveTranscript) { _, transcript in
            scheduleAutoStop(after: transcript)
        }
        .onChange(of: recognizer.endOfSpeechCount) { _, _ in
            // Termino de hablar: se corta, se interpreta y se guarda solo.
            Task { await finish() }
        }
        .sheet(item: $editingTransaction, onDismiss: refreshSavedTransaction) { transaction in
            QuickAddView(viewModel: viewModel, existingTransaction: transaction)
        }
    }

    private var isSaved: Bool {
        if case .saved = phase { return true }
        return false
    }

    // MARK: - Escuchando

    private var isBusy: Bool { recognizer.isProcessing || phase == .saving }

    private var listeningTitle: String {
        if phase == .saving { return "Anotando…" }
        if recognizer.isProcessing { return "Entendiendo lo que dijiste…" }
        if recognizer.isRecording { return recognizer.liveTranscript.isEmpty ? "Te escucho…" : "Sigue, te escucho…" }
        return "Preparando el micrófono…"
    }

    private var listeningContent: some View {
        VStack(spacing: 24) {
            Spacer()

            micCircle

            VStack(spacing: 10) {
                Text(listeningTitle)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                if !recognizer.liveTranscript.isEmpty {
                    Text("“\(recognizer.liveTranscript)”")
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                        .lineLimit(4)
                        .animation(.default, value: recognizer.liveTranscript)
                } else {
                    Text("Di algo como «Gasté 12 dólares en almuerzo» o «Me pagaron 500 de salario».")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 28)

            Spacer()

            VStack(spacing: 12) {
                if recognizer.isRecording {
                    Button {
                        Task { await finish() }
                    } label: {
                        Text("Listo")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MonAviBrand.primary)
                    .disabled(recognizer.liveTranscript.isEmpty)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private var micCircle: some View {
        ZStack {
            Circle()
                .fill(MonAviBrand.primary.opacity(0.15))
                .frame(width: 180, height: 180)
                .scaleEffect(recognizer.isRecording && pulse ? 1.12 : 0.92)
                .animation(
                    recognizer.isRecording
                        ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                        : .default,
                    value: pulse && recognizer.isRecording
                )

            Circle()
                .fill(MonAviBrand.primary)
                .frame(width: 110, height: 110)

            if isBusy {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            } else {
                Image(systemName: recognizer.isRecording ? "waveform" : "mic.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.variableColor.iterative, isActive: recognizer.isRecording)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Anotado

    private func savedContent(_ transaction: FinanceTransaction) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 110, weight: .semibold))
                .foregroundStyle(transaction.movementType.tintColor)
                .symbolEffect(.bounce, value: transaction.id)
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text(summary(for: transaction))
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                if let category = transaction.category.flatMap(TransactionCategory.init(rawValue:)) {
                    Text("\(category.emoji) \(category.rawValue)")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(.secondarySystemBackground)))
                }

                if let undoError {
                    Text(undoError)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(MonAviBrand.alert)
                }
            }
            .padding(.horizontal, 28)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    close()
                } label: {
                    Text("Listo")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(MonAviBrand.primary)
                .disabled(isUndoing)

                HStack(spacing: 12) {
                    Button {
                        Task { await undo(transaction) }
                    } label: {
                        Group {
                            if isUndoing {
                                ProgressView()
                            } else {
                                Label("Deshacer", systemImage: "arrow.uturn.backward")
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(MonAviBrand.alert)

                    Button {
                        editingTransaction = transaction
                    } label: {
                        Label("Editar", systemImage: "pencil")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(MonAviBrand.primary)
                }
                .disabled(isUndoing)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    /// "Anotado: Almuerzo · $12.00 (gasto)"
    private func summary(for transaction: FinanceTransaction) -> String {
        let rawDescription = (transaction.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let description: String
        if rawDescription.isEmpty {
            description = transaction.movementType.displayName
        } else {
            description = rawDescription.prefix(1).uppercased() + String(rawDescription.dropFirst())
        }
        let amount = abs(transaction.amount).formatted(.currency(code: "USD"))
        return "Anotado: \(description) · \(amount) (\(transaction.movementType.displayName.lowercased()))"
    }

    // MARK: - Sin cuenta / error

    private var noAccountContent: some View {
        messageScreen(
            icon: "creditcard.trianglebadge.exclamationmark",
            iconColor: MonAviBrand.alert,
            title: "Primero crea una cuenta",
            message: "Necesitas una cuenta para guardar movimientos. Créala en Ajustes > Cuentas y vuelve a intentarlo.",
            primaryTitle: "Entendido",
            primaryIcon: nil,
            primaryAction: close
        )
    }

    private func failedContent(_ message: String) -> some View {
        messageScreen(
            icon: "mic.slash.fill",
            iconColor: MonAviBrand.alert,
            title: "No te entendí",
            message: message,
            primaryTitle: "Intentar de nuevo",
            primaryIcon: "mic.fill",
            primaryAction: { Task { await startListening() } }
        )
    }

    private func messageScreen(
        icon: String,
        iconColor: Color,
        title: String,
        message: String,
        primaryTitle: String,
        primaryIcon: String?,
        primaryAction: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(iconColor)
                    .frame(width: 110, height: 110)
                Image(systemName: icon)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)

            Spacer()

            Button(action: primaryAction) {
                Group {
                    if let primaryIcon {
                        Label(primaryTitle, systemImage: primaryIcon)
                    } else {
                        Text(primaryTitle)
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(MonAviBrand.primary)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Logica

    private func loadAccounts() async {
        guard let userId = appState.currentUserId else { return }
        viewModel.errorMessage = nil
        await viewModel.refresh(userId: userId)
        // Si la carga fallo (red), no se concluye "no tiene cuentas": se
        // reintenta al momento de guardar.
        accountsLoaded = viewModel.errorMessage == nil
        if accountsLoaded, viewModel.accounts.isEmpty {
            silenceTask?.cancel()
            recognizer.cancel()
            phase = .noAccount
        }
    }

    private func startListening() async {
        guard phase != .noAccount else { return }
        undoError = nil
        phase = .listening
        guard !recognizer.isRecording else { return }
        _ = await recognizer.toggleRecording()
        // Ya se pudo haber detectado que no hay cuenta mientras se pedian
        // los permisos: no dejar el microfono abierto.
        if phase == .noAccount {
            recognizer.cancel()
            return
        }
        if !recognizer.isRecording, let error = recognizer.errorMessage {
            phase = .failed(error)
        }
    }

    /// Cada palabra nueva reinicia la cuenta: tras ~2 s sin hablar, se
    /// corta y se interpreta solo.
    private func scheduleAutoStop(after transcript: String) {
        guard phase == .listening, recognizer.isRecording, !transcript.isEmpty else { return }
        silenceTask?.cancel()
        silenceTask = Task {
            try? await Task.sleep(nanoseconds: Self.silenceNanoseconds)
            guard !Task.isCancelled else { return }
            await finish()
        }
    }

    private func finish() async {
        silenceTask?.cancel()
        silenceTask = nil
        guard phase == .listening, recognizer.isRecording else { return }

        guard let parsed = await recognizer.toggleRecording()?.normalizedForQuickAdd() else {
            phase = .failed(recognizer.errorMessage ?? VoiceRecognitionError.parseFailed.errorDescription ?? "")
            return
        }
        await save(parsed)
    }

    private func save(_ rawParsed: ParsedVoiceTransaction) async {
        // pago_proveedor / transferencia → gasto + Proveedores / Transferencias.
        let parsed = rawParsed.normalizedForQuickAdd()
        guard parsed.amount > 0 else {
            phase = .failed("No escuché el monto. Intenta de nuevo, por ejemplo: «gasté 12 dólares en almuerzo».")
            return
        }
        guard let userId = appState.currentUserId else {
            phase = .failed("Tu sesión se cerró. Entra de nuevo a MonAvi e inténtalo otra vez.")
            return
        }

        phase = .saving

        if !accountsLoaded {
            await loadAccounts()
            guard accountsLoaded else {
                phase = .failed("No se pudieron cargar tus cuentas. Revisa tu conexión a internet e intenta de nuevo.")
                return
            }
        }
        // Misma cuenta por defecto que AddMonAviExpenseIntent: la primera
        // por created_at (viewModel.accounts viene ordenado asi).
        guard let accountId = viewModel.accounts.first?.id else {
            phase = .noAccount
            return
        }

        let description = parsed.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = parsed.category.flatMap(TransactionCategory.init(rawValue:))
            ?? (parsed.movementType.isInflow ? nil : MerchantCategoryGuesser.category(for: description))

        do {
            try await viewModel.quickAdd(
                userId: userId,
                accountId: accountId,
                magnitude: Decimal(parsed.amount),
                description: description,
                movementType: parsed.movementType,
                category: category?.rawValue
            )
            // quickAdd agrega el movimiento recien creado al inicio del dia
            // (la lista va de lo mas nuevo a lo mas viejo).
            guard let created = viewModel.todayTransactions.first else {
                close()
                return
            }
            if created.movementType == .ingreso {
                CelebrationFeedback.playIncome()
            }
            phase = .saved(created)
        } catch {
            phase = .failed("No se pudo guardar el movimiento: \(error.localizedDescription)")
        }
    }

    private func undo(_ transaction: FinanceTransaction) async {
        isUndoing = true
        undoError = nil
        defer { isUndoing = false }
        do {
            try await viewModel.deleteTransaction(transaction)
            close()
        } catch {
            undoError = "No se pudo deshacer: \(error.localizedDescription)"
        }
    }

    /// Despues de "Editar", mostrar los datos corregidos.
    private func refreshSavedTransaction() {
        guard case .saved(let current) = phase,
              let updated = viewModel.todayTransactions.first(where: { $0.id == current.id })
        else { return }
        phase = .saved(updated)
    }

    private func close() {
        silenceTask?.cancel()
        silenceTask = nil
        recognizer.cancel()
        dismiss()
    }
}
