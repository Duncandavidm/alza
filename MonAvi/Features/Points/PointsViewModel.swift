import Foundation

/// Compartido por las pantallas de puntos (hub, tarjetas, ofertas) — un
/// solo lugar que lee el ledger unico (points_balances) y los datos de
/// tarjeta en comercios aliados.
@MainActor
final class PointsViewModel: ObservableObject {
    @Published private(set) var balance = PointsBalance.zero
    @Published private(set) var linkedCards: [LinkedCard] = []
    @Published private(set) var offers: [PartnerOffer] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let repository = CardPointsRepository.shared

    var activeCards: [LinkedCard] {
        linkedCards.filter { $0.status == .active }
    }

    func refresh(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        async let balanceTask = repository.fetchBalance(userId: userId)
        async let cardsTask: [LinkedCard] = (try? await repository.fetchLinkedCards(userId: userId)) ?? []
        async let offersTask: [PartnerOffer] = (try? await repository.fetchActiveOffers()) ?? []

        balance = await balanceTask
        linkedCards = await cardsTask
        offers = await offersTask
    }

    func addCard(userId: UUID, brand: CardBrand, last4: String, alias: String) async throws {
        let created = try await repository.addLinkedCard(
            NewLinkedCard(userId: userId, brand: brand, last4: last4, alias: alias, accountId: nil)
        )
        linkedCards.append(created)
    }

    func setStatus(_ card: LinkedCard, to status: LinkedCardStatus) async {
        do {
            try await repository.updateStatus(card, to: status)
            if let index = linkedCards.firstIndex(where: { $0.id == card.id }) {
                if status == .removed {
                    linkedCards.remove(at: index)
                } else {
                    linkedCards[index].status = status
                }
            }
        } catch {
            errorMessage = "No se pudo actualizar la tarjeta: \(error.localizedDescription)"
        }
    }
}
