import Foundation

/// Estado de "Puntos y cashback": el catalogo, los dos saldos canjeables
/// (cashback en centavos y puntos por habitos) y el filtro de categoria.
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

    /// Cashback canjeable, en centavos.
    var cashbackCents: Int { balance.confirmedPoints }

    /// Puntos por habitos canjeables.
    var habitPoints: Int { balance.habitPoints }

    /// Saldo que aplica a un producto segun la moneda de su comercio.
    func spendableBalance(for item: RewardItem) -> Int {
        balance.spendable(in: item.currency)
    }

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

