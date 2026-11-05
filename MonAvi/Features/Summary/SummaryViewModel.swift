import Foundation

@MainActor
final class SummaryViewModel: ObservableObject {
    @Published var kind: SummaryKind = .expenses { didSet { recompute() } }
    /// Al cambiar de periodo se vuelve al actual (offset 0).
    @Published var period: SummaryPeriod = .month { didSet { offset = 0 } }
    @Published var offset = 0 { didSet { recompute() } }
    /// nil = todas las cuentas.
    @Published var accountId: UUID? = nil { didSet { recompute() } }

    @Published private(set) var snapshot: SummarySnapshot?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private var allTransactions: [FinanceTransaction] = []

    var canGoForward: Bool { offset < 0 }

    func refresh(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        do {
            allTransactions = try await TransactionsRepository.shared.fetchAll(userId: userId)
            recompute()
        } catch {
            errorMessage = "No se pudo cargar tu resumen: \(error.localizedDescription)"
        }
    }

    func goBack() { offset -= 1 }

    func goForward() {
        guard canGoForward else { return }
        offset += 1
    }

    private func recompute() {
        snapshot = SummaryCalculator().snapshot(
            transactions: allTransactions,
            kind: kind,
            period: period,
            offset: offset,
            accountId: accountId
        )
    }
}
