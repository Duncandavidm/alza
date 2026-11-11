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
    /// Sube cada vez que se detecta que la persona termino de hablar
    /// (silencio despues de haber dicho algo). Las pantallas lo observan
    /// con onChange para cortar e interpretar solas, sin tocar "Listo".
    @Published private(set) var endOfSpeechCount = 0

    // Deteccion de fin de habla: nivel del microfono + cambios del texto.
    private var lastVoiceAt = Date()
    private var lastTranscriptChangeAt = Date()
    private var recordingStartedAt = Date()
    private var noiseFloor: Float = -60
    private var calibrationSamples: [Float] = []
    private var endOfSpeechTask: Task<Void, Never>?
    /// Silencio (sin voz ni palabras nuevas) que se toma como "termino".
    private static let endOfSpeechSilence: TimeInterval = 1.3
    /// Si no dice nada en este tiempo, se corta (mensaje "No se escuchó nada").
    private static let noSpeechTimeout: TimeInterval = 7
    /// Tope de una grabacion.
    private static let maxDuration: TimeInterval = 20

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
        endOfSpeechTask?.cancel()
        endOfSpeechTask = nil
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
            request.append(buffer)
            let level = Self.decibels(of: buffer)
            Task { @MainActor in self?.noteAudioLevel(level) }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            errorMessage = "No se pudo empezar a grabar."
            return
        }

        isRecording = true
        let now = Date()
        recordingStartedAt = now
        lastVoiceAt = now
        lastTranscriptChangeAt = now
        noiseFloor = -60
        calibrationSamples = []

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let self, let result else { return }
            Task { @MainActor in
                let text = result.bestTranscription.formattedString
                if text != self.liveTranscript {
                    self.liveTranscript = text
                    self.lastTranscriptChangeAt = Date()
                }
                // Algunos reconocedores marcan el final solos tras una pausa.
                if result.isFinal, !text.isEmpty, self.isRecording {
                    self.signalEndOfSpeech()
                }
            }
        }

        startEndOfSpeechWatchdog()
    }

    // MARK: - Fin de habla automatico

    /// Nivel (dBFS) de un bloque de audio del microfono.
    private nonisolated static func decibels(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return -100 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<count {
            let sample = channel[index]
            sum += sample * sample
        }
        let rms = (sum / Float(count)).squareRoot()
        return rms > 0 ? 20 * log10(rms) : -100
    }

    /// Los primeros ~0.4 s miden el ruido del lugar; despues, todo lo que
    /// pase claramente por encima de ese ruido cuenta como voz.
    private func noteAudioLevel(_ level: Float) {
        guard isRecording else { return }
        if calibrationSamples.count < 16 {
            calibrationSamples.append(level)
            if calibrationSamples.count == 16 {
                let sorted = calibrationSamples.sorted()
                noiseFloor = sorted[sorted.count / 2]
            }
            return
        }
        let threshold = max(noiseFloor + 10, -50)
        if level > threshold {
            lastVoiceAt = Date()
        }
    }

    private func startEndOfSpeechWatchdog() {
        endOfSpeechTask?.cancel()
        endOfSpeechTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard let self, self.isRecording else { return }
                let now = Date()
                let hasWords = !self.liveTranscript.trimmingCharacters(in: .whitespaces).isEmpty
                let quietFor = now.timeIntervalSince(max(self.lastVoiceAt, self.lastTranscriptChangeAt))
                let elapsed = now.timeIntervalSince(self.recordingStartedAt)

                if hasWords && quietFor >= Self.endOfSpeechSilence {
                    self.signalEndOfSpeech()
                    return
                }
                if !hasWords && elapsed >= Self.noSpeechTimeout {
                    self.signalEndOfSpeech()
                    return
                }
                if elapsed >= Self.maxDuration {
                    self.signalEndOfSpeech()
                    return
                }
            }
        }
    }

    private func signalEndOfSpeech() {
        endOfSpeechTask?.cancel()
        endOfSpeechTask = nil
        endOfSpeechCount += 1
    }

    private func stopAndParse() async -> ParsedVoiceTransaction? {
        endOfSpeechTask?.cancel()
        endOfSpeechTask = nil
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
