import Foundation

/// Estado de "Canjea tus puntos": el catalogo, el saldo canjeable y el
/// filtro de categoria.
@MainActor
final class RewardsViewModel: ObservableObject {
    @Published private(set) var items: [RewardItem] = []
    @Published private(set) var balance = PointsBalance.zero
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published var errorMessage: String?
    @Published var selectedCategory: String?

    private let repository = RewardsRepository.shared

    var categories: [String] { RewardsMath.categories(of: items) }

    var filteredItems: [RewardItem] {
        RewardsMath.filter(items, category: selectedCategory)
    }

    var redeemablePoints: Int { balance.confirmedPoints }

    func refresh(userId: UUID) async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }

        async let balanceTask: PointsBalance = CardPointsRepository.shared.fetchBalance(userId: userId)
        do {
            let fetched = try await repository.fetchItems()
            items = fetched
            errorMessage = nil
            if let selectedCategory, !categories.contains(selectedCategory) {
                self.selectedCategory = nil
            }
        } catch {
            errorMessage = "No pudimos cargar los comercios aliados. Desliza hacia abajo para intentar de nuevo."
        }
        balance = await balanceTask
    }

    func refreshBalance(userId: UUID) async {
        balance = await CardPointsRepository.shared.fetchBalance(userId: userId)
    }
}
