import Foundation

/// Ordena las categorias de movimiento segun que tanto las usa el usuario
/// (mas usadas primero), para que las vea de una vez en los selectores
/// rapidos sin tener que buscarlas entre las que casi no usa.
enum CategoryUsageService {
    static func sortedCategories(userId: UUID, recentLimit: Int = 200) async -> [TransactionCategory] {
        let recent = (try? await TransactionsRepository.shared.fetchRecent(userId: userId, limit: recentLimit)) ?? []
        var counts: [String: Int] = [:]
        for transaction in recent {
            guard let category = transaction.category else { continue }
            counts[category, default: 0] += 1
        }

        return TransactionCategory.allCases.enumerated()
            .sorted { lhs, rhs in
                let lhsCount = counts[lhs.element.rawValue] ?? 0
                let rhsCount = counts[rhs.element.rawValue] ?? 0
                if lhsCount != rhsCount { return lhsCount > rhsCount }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
