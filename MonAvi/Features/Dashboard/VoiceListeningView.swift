import SwiftUI

/// Pantalla de escucha a pantalla completa para anotar por voz: se abre
/// escuchando de una vez, muestra lo que va entendiendo y corta sola al
/// dejar de hablar (ver QuickAddView.scheduleAutoStop). Al terminar, el
/// formulario queda lleno para revisarlo y guardar. Si la persona hizo
/// una pregunta ("¿cuánto gasté en súper este mes?"), muestra la respuesta.
struct VoiceListeningView: View {
    @ObservedObject var recognizer: VoiceTransactionRecognizer
    let onFinish: () -> Void
    let onRetry: () -> Void
    let onType: () -> Void
    /// Cierra todo despues de leer una respuesta.
    var onClose: (() -> Void)?

    @State private var pulse = false

    private var hasError: Bool {
        recognizer.errorMessage != nil && !recognizer.isRecording && !recognizer.isProcessing
    }

    private var shownAnswer: VoiceAnswer? {
        recognizer.isRecording || recognizer.isProcessing ? nil : recognizer.answer
    }

    private var title: String {
        if recognizer.isAnswering { return L("Buscando la respuesta…") }
        if recognizer.isProcessing { return L("Entendiendo lo que dijiste…") }
        if recognizer.isRecording { return recognizer.liveTranscript.isEmpty ? L("Te escucho…") : L("Sigue, te escucho…") }
        if hasError { return L("No te entendí") }
        return L("Preparando el micrófono…")
    }

    var body: some View {
        if let shownAnswer {
            VoiceAnswerContent(
                answer: shownAnswer,
                onDone: onClose ?? onType,
                onAskAgain: onRetry,
                onType: onType
            )
        } else {
            listening
        }
    }

    private var listening: some View {
        VStack(spacing: 24) {
            Spacer()

            micCircle

            VStack(spacing: 10) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                if !recognizer.liveTranscript.isEmpty {
                    Text("“\(recognizer.liveTranscript)”")
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                        .lineLimit(4)
                        .animation(.default, value: recognizer.liveTranscript)
                } else if let error = recognizer.errorMessage, hasError {
                    Text(error)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(MonAviBrand.alert)
                } else {
                    Text("Di algo como «Gasté 12 dólares en el súper» o pregunta «¿Cuánto gasté en súper este mes?».")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 28)

            Spacer()

            VStack(spacing: 12) {
                if hasError {
                    Button(action: onRetry) {
                        Label("Intentar de nuevo", systemImage: "mic.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MonAviBrand.primary)
                } else if recognizer.isRecording {
                    Button(action: onFinish) {
                        Text("Listo")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MonAviBrand.primary)
                    .disabled(recognizer.liveTranscript.isEmpty)
                }

                Button("Prefiero escribirlo", action: onType)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MonAviBrand.primary)
                    .disabled(recognizer.isProcessing)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
        .onAppear { pulse = true }
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
                .fill(hasError ? MonAviBrand.alert : MonAviBrand.primary)
                .frame(width: 110, height: 110)

            if recognizer.isProcessing {
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
}

/// La respuesta a una pregunta por voz, con la pregunta arriba.
struct VoiceAnswerContent: View {
    let answer: VoiceAnswer
    let onDone: () -> Void
    let onAskAgain: () -> Void
    let onType: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(MonAviBrand.primary)
                    .frame(width: 110, height: 110)
                Image(systemName: "sparkles")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)

            VStack(spacing: 14) {
                Text("“\(answer.question)”")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                // Por voz la respuesta viene corta (1-2 oraciones).
                Text(answer.answer)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(10)
                    .minimumScaleFactor(0.7)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 28)

            Spacer()

            VStack(spacing: 12) {
                Button(action: onDone) {
                    Text("Listo")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(MonAviBrand.primary)

                HStack(spacing: 12) {
                    Button(action: onAskAgain) {
                        Label("Preguntar otra cosa", systemImage: "mic.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(MonAviBrand.primary)

                    Button(action: onType) {
                        Label("Anotar", systemImage: "square.and.pencil")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(MonAviBrand.primary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
    }
}
