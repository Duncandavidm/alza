import Foundation
import Speech
import AVFoundation
import Supabase

/// Resultado de parse-voice-transaction: los campos con los que se
/// pre-llena el formulario de "Anotar movimiento" para que el usuario los
/// revise (no se guarda automaticamente).
struct ParsedVoiceTransaction: Decodable {
    let amount: Double
    let description: String
    let movementType: MovementType
    let category: String?
}

enum VoiceRecognitionError: LocalizedError {
    case permissionDenied
    case recognizerUnavailable
    case emptyTranscript
    case parseFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Necesitamos permiso de micrófono y reconocimiento de voz. Actívalos en Ajustes > MonAvi."
        case .recognizerUnavailable:
            return "El reconocimiento de voz no está disponible ahora mismo. Revisa tu conexión a internet e intenta de nuevo."
        case .emptyTranscript:
            return "No se escuchó nada. Intenta de nuevo."
        case .parseFailed:
            return "No se pudo entender el movimiento. Intenta decirlo de otra forma, con el monto."
        }
    }
}

/// Graba, transcribe (on-device cuando es posible) y le pide a Claude que
/// interprete un movimiento dicho en voz alta. Inspirado en el ingreso por
/// voz de MonAi.
@MainActor
final class VoiceTransactionRecognizer: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isProcessing = false
    @Published private(set) var liveTranscript = ""
    @Published var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = VoiceTransactionRecognizer.makeSpanishRecognizer()

    /// "es-419" no siempre existe como reconocedor (en el simulador casi
    /// nunca): se usa el español del dispositivo si esta soportado, y si
    /// no, el primero disponible de una lista de variantes cercanas.
    private nonisolated static func makeSpanishRecognizer() -> SFSpeechRecognizer? {
        let normalize = { (id: String) in id.replacingOccurrences(of: "_", with: "-").lowercased() }
        let supported = Set(SFSpeechRecognizer.supportedLocales().map { normalize($0.identifier) })

        var candidates: [String] = []
        if Locale.current.language.languageCode?.identifier == "es" {
            candidates.append(Locale.current.identifier)
        }
        candidates += ["es-PA", "es-419", "es-MX", "es-US", "es-CO", "es-ES"]

        for identifier in candidates where supported.contains(normalize(identifier)) {
            if let recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier)) {
                return recognizer
            }
        }
        return SFSpeechRecognizer(locale: Locale(identifier: "es-MX"))
    }
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private let supabase = SupabaseManager.shared.client

    func toggleRecording() async -> ParsedVoiceTransaction? {
        if isRecording {
            return await stopAndParse()
        } else {
            await start()
            return nil
        }
    }

    /// Deja de grabar sin interpretar nada (el usuario prefirio escribir
    /// o cerro la hoja).
    func cancel() {
        guard isRecording else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecording = false
        liveTranscript = ""
    }

    private func start() async {
        errorMessage = nil
        liveTranscript = ""

        let speechStatus = await requestSpeechAuthorization()
        guard speechStatus == .authorized else {
            errorMessage = VoiceRecognitionError.permissionDenied.errorDescription
            return
        }

        let micGranted = await requestMicrophonePermission()
        guard micGranted else {
            errorMessage = VoiceRecognitionError.permissionDenied.errorDescription
            return
        }

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = VoiceRecognitionError.recognizerUnavailable.errorDescription
            return
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "No se pudo activar el micrófono."
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // En un iPhone real se prefiere transcribir en el dispositivo
        // (privacidad). En el simulador no hay modelo local, asi que se usa
        // el servidor de Apple.
        #if !targetEnvironment(simulator)
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        #endif
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            errorMessage = "No se pudo empezar a grabar."
            return
        }

        isRecording = true

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let self, let result else { return }
            Task { @MainActor in
                self.liveTranscript = result.bestTranscription.formattedString
            }
        }
    }

    private func stopAndParse() async -> ParsedVoiceTransaction? {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        isRecording = false
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        let transcript = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            errorMessage = VoiceRecognitionError.emptyTranscript.errorDescription
            return nil
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            struct Payload: Encodable { let transcript: String }
            let parsed: ParsedVoiceTransaction = try await supabase.functions.invoke(
                "parse-voice-transaction",
                options: FunctionInvokeOptions(body: Payload(transcript: transcript))
            )
            return parsed
        } catch {
            errorMessage = VoiceRecognitionError.parseFailed.errorDescription
            return nil
        }
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
