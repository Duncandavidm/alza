import Foundation

/// Compara el nombre de comercio que llega de Wallet/Atajos ("SUPER 99
/// VIA ESPAÑA") con los nombres de los comercios aliados ("Super 99"),
/// sin importar mayusculas ni tildes. Logica pura (testeable).
enum PartnerMerchantMatcher {
    /// Nombres de comercio mas cortos que esto no se comparan — evita que
    /// un aliado "Rey" calce con cualquier cosa que contenga "rey".
    static let minimumLength = 3

    static func normalized(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "es_PA"))
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// El nombre del primer aliado cuyo nombre aparece dentro del comercio
    /// pagado (o viceversa). Prefiere el nombre mas largo (mas especifico).
    static func match(merchant: String, partnerNames: [String]) -> String? {
        let paid = normalized(merchant)
        guard paid.count >= minimumLength else { return nil }

        return partnerNames
            .sorted { $0.count > $1.count }
            .first { name in
                let partner = normalized(name)
                guard partner.count >= minimumLength else { return false }
                return paid.contains(partner) || partner.contains(paid)
            }
    }
}
