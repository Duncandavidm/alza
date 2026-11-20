import Foundation
import SwiftUI

/// Cache en memoria de las categorias propias del usuario: se carga al
/// iniciar sesion y cada vez que cambian en Ajustes > Categorías, para que
/// las listas y graficas muestren su emoji sin pedirlas a cada rato.
@MainActor
final class UserCategoriesStore: ObservableObject {
    static let shared = UserCategoriesStore()

    @Published private(set) var categories: [UserCategory] = []

    private init() {}

    func refresh() async {
        do {
            let fetched = try await UserCategoriesRepository.shared.fetchAll()
            set(fetched)
        } catch {
            // Sin conexion se queda con lo que ya tenia.
        }
    }

    func clear() {
        set([])
    }

    /// Las que aplican al tipo de movimiento (entrada o salida).
    func applicable(isInflow: Bool) -> [UserCategory] {
        categories.filter { $0.kind.applies(isInflow: isInflow) }
    }

    func set(_ list: [UserCategory]) {
        categories = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        CategoryDisplay.updateCache(categories)
    }

    func upsert(_ category: UserCategory) {
        var list = categories.filter { $0.id != category.id }
        list.append(category)
        set(list)
    }

    func remove(_ category: UserCategory) {
        set(categories.filter { $0.id != category.id })
    }
}

/// Emoji, nombre y color para cualquier texto guardado en
/// `transactions.category`: primero las categorias fijas
/// (TransactionCategory), luego las propias del usuario. Lee una copia
/// protegida con lock para poder usarse desde cualquier hilo.
enum CategoryDisplay {
    private static let lock = NSLock()
    private static var emojiByKey: [String: (name: String, emoji: String)] = [:]

    static func updateCache(_ categories: [UserCategory]) {
        var map: [String: (name: String, emoji: String)] = [:]
        for category in categories {
            map[key(category.name)] = (category.name, category.emoji)
        }
        lock.lock()
        emojiByKey = map
        lock.unlock()
    }

    private static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func custom(for raw: String?) -> (name: String, emoji: String)? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return emojiByKey[key(raw)]
    }

    /// nil si el texto no es una categoria conocida (fija ni propia).
    static func emoji(for raw: String?) -> String? {
        if let builtIn = TransactionCategory(rawValue: raw ?? "") { return builtIn.emoji }
        return custom(for: raw)?.emoji
    }

    /// El nombre a mostrar, o nil si no hay categoria.
    static func name(for raw: String?) -> String? {
        if let builtIn = TransactionCategory(rawValue: raw ?? "") { return builtIn.rawValue }
        if let custom = custom(for: raw) { return custom.name }
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Las propias van en el color de marca para distinguirlas del gris de
    /// "Sin categoría".
    static func color(for raw: String?) -> Color? {
        if let builtIn = TransactionCategory(rawValue: raw ?? "") { return builtIn.color }
        return custom(for: raw) != nil ? MonAviBrand.primary : nil
    }

    static func isCustom(_ raw: String?) -> Bool {
        TransactionCategory(rawValue: raw ?? "") == nil && custom(for: raw) != nil
    }
}

/// Lo elegido en Anotar movimiento: una categoria fija o una propia.
enum CategoryChoice: Hashable, Identifiable {
    case builtIn(TransactionCategory)
    case custom(name: String, emoji: String)

    var id: String { storedValue }

    /// Lo que se guarda en `transactions.category`.
    var storedValue: String {
        switch self {
        case .builtIn(let category): return category.rawValue
        case .custom(let name, _): return name
        }
    }

    var emoji: String {
        switch self {
        case .builtIn(let category): return category.emoji
        case .custom(_, let emoji): return emoji
        }
    }

    var title: String { storedValue }

    var builtIn: TransactionCategory? {
        if case .builtIn(let category) = self { return category }
        return nil
    }

    init(_ category: TransactionCategory) {
        self = .builtIn(category)
    }

    init(_ category: UserCategory) {
        self = .custom(name: category.name, emoji: category.emoji)
    }

    /// Desde el texto guardado: fija si coincide, propia si esta en la
    /// cache, y si no (una propia ya borrada) igual se conserva como propia.
    init?(stored raw: String?) {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        if let builtIn = TransactionCategory(rawValue: trimmed) {
            self = .builtIn(builtIn)
        } else {
            self = .custom(name: CategoryDisplay.name(for: trimmed) ?? trimmed,
                           emoji: CategoryDisplay.emoji(for: trimmed) ?? "🏷️")
        }
    }
}
