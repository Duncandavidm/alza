import Foundation

/// Distingue una pregunta dicha por voz ("¿cuánto gasté en súper este
/// mes?") de un movimiento para anotar ("gasté 12 en almuerzo"). Las
/// preguntas se responden con ask-finances (la misma IA de "Pregúntale a
/// tu dinero" en Análisis); los movimientos siguen el camino de siempre.
enum VoiceQuestionDetector {
    /// Inicios tipicos de una pregunta sobre sus finanzas (sin tildes).
    private static let questionStarts: [String] = [
        "cuanto", "cuanta", "cuantos", "cuantas",
        "cual", "cuales",
        "como voy", "como estoy", "como van", "como va", "como me fue", "como ando",
        "en que", "que tanto", "que porcentaje", "que categoria", "que dia", "que mes",
        "dime", "muestrame", "ensename", "quiero saber", "resumeme", "dame un resumen",
        "me alcanza", "puedo gastar", "me queda", "me quedan",
    ]

    /// Inicios que tambien pueden ser un movimiento ("que me pagaron 500"):
    /// cuentan como pregunta solo si no se entiende como movimiento.
    private static let weakStarts: [String] = ["que", "donde", "cuando"]

    /// Muletillas que pueden ir antes de la pregunta.
    private static let leadingFillers: [String] = ["oye", "monavi", "y", "a", "ver", "bueno", "oka", "ok", "okay", "este"]

    static func isQuestion(_ transcript: String) -> Bool {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // El dictado de Apple a veces ya pone los signos.
        if trimmed.contains("?") || trimmed.contains("¿") { return true }

        var words = SimpleVoiceParser.fold(trimmed)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        while let first = words.first, leadingFillers.contains(first), words.count > 1 {
            words.removeFirst()
        }
        let text = words.joined(separator: " ")
        let starts = { (start: String) in text == start || text.hasPrefix(start + " ") }
        if questionStarts.contains(where: starts) { return true }
        if weakStarts.contains(where: starts) { return SimpleVoiceParser.parse(trimmed) == nil }
        return false
    }
}

/// Lo que respondio MonAvi a una pregunta por voz.
struct VoiceAnswer: Equatable {
    let question: String
    let answer: String
}
