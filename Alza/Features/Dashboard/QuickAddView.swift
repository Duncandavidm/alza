import SwiftUI

/// Mejora #2: ingreso ultra-rapido. Solo pregunta "¿cuanto?" y "¿que fue?" —
/// el tipo de movimiento esta ahi para diferenciarlo (mejora #3) pero es un
/// toque opcional, no un formulario. Sin categoria obligatoria.
struct QuickAddView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: DayJournalViewModel
    @StateObject private var voiceRecognizer = VoiceTransactionRecognizer()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var amountFieldFocused: Bool

    @State private var movementType: MovementType = .gasto
    @State private var amountText = ""
    @State private var description = ""
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
            VStack(spacing: 20) {
                MovementTypePicker(selection: $movementType)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 6) {
                    Text("¿Cuanto?")
                        .font(.headline)
                    HStack {
                        Text("$")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField("0", text: $amountText)
                            .font(.system(size: 40, weight: .bold))
                            .keyboardType(.decimalPad)
                            .focused($amountFieldFocused)
                    }
                    Divider()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("¿Que fue?")
                        .font(.headline)
                    TextField("ej. Compra de harina", text: $description)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                }

                voiceButton

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.footnote)
                }

                Spacer()

                Button {
                    Task { await save() }
                } label: {
                    Text("Guardar")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(movementType.tintColor)
                .disabled(amountText.isEmpty || isSaving || viewModel.defaultAccountId == nil)
            }
            .padding(20)
            .navigationTitle("Anotar movimiento")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .onAppear { amountFieldFocused = true }
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
        .presentationDetents([.medium, .large])
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
            amountFieldFocused = false
        }
    }

    private func save() async {
        guard
            let userId = appState.currentUserId,
            let accountId = viewModel.defaultAccountId,
            let magnitude = Decimal(string: amountText.replacingOccurrences(of: ",", with: "."))
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
                movementType: movementType
            )
            async let minDelay: Void = Task.sleep(nanoseconds: MovementSavingOverlay.minDisplayNanoseconds(for: movementType))
            _ = try await (saved, minDelay)

            if movementType == .ingreso, let advice = try? await PaymentAdviceService.fetch(userId: userId, incomeAmount: magnitude),
               advice.hasAdvice {
                adviceText = advice.advice ?? ""
                adviceItems = advice.items ?? []
                showingAdvice = true
                return
            }

            dismiss()
        } catch {
            showingSavingAnimation = false
            errorMessage = error.localizedDescription
        }
    }
}
