import SwiftUI

/// Pantalla de escucha a pantalla completa para anotar por voz: se abre
/// escuchando de una vez, muestra lo que va entendiendo y corta sola al
/// dejar de hablar (ver QuickAddView.scheduleAutoStop). Al terminar, el
/// formulario queda lleno para revisarlo y guardar.
struct VoiceListeningView: View {
    @ObservedObject var recognizer: VoiceTransactionRecognizer
    let onFinish: () -> Void
    let onRetry: () -> Void
    let onType: () -> Void

    @State private var pulse = false

    private var hasError: Bool {
        recognizer.errorMessage != nil && !recognizer.isRecording && !recognizer.isProcessing
    }

    private var title: String {
        if recognizer.isProcessing { return "Entendiendo lo que dijiste…" }
        if recognizer.isRecording { return recognizer.liveTranscript.isEmpty ? "Te escucho…" : "Sigue, te escucho…" }
        if hasError { return "No te entendí" }
        return "Preparando el micrófono…"
    }

    var body: some View {
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
                    Text("Di algo como «Gasté 12 dólares en el súper» o «Me pagaron 500 de un cliente».")
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
