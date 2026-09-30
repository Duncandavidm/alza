import Foundation

@MainActor
final class DataPortabilityViewModel: ObservableObject {
    @Published private(set) var isExporting = false
    @Published private(set) var isImporting = false
    @Published private(set) var exportURL: URL?
    @Published var errorMessage: String?
    @Published var importSummary: String?

    func export(userId: UUID) async {
        isExporting = true
        defer { isExporting = false }

        do {
            async let transactionsTask = TransactionsRepository.shared.fetchAll(userId: userId)

            let recurringViewModel = RecurringTransactionsViewModel()
            await recurringViewModel.refresh(userId: userId)

            let csv = CSVTransactions.export(
                transactions: try await transactionsTask,
                recurring: recurringViewModel.items
            )

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("alza-export-\(Int(Date().timeIntervalSince1970)).csv")
            try csv.write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
        } catch {
            errorMessage = "No se pudo exportar: \(error.localizedDescription)"
        }
    }

    func importCSV(from url: URL, userId: UUID, accountId: UUID) async {
        isImporting = true
        defer { isImporting = false }

        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "No se pudo leer el archivo."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let rows = CSVTransactions.parse(text)
            let recurringViewModel = RecurringTransactionsViewModel()

            var importedTransactions = 0
            var importedRecurring = 0

            for row in rows {
                if row.isRecurring {
                    try await recurringViewModel.add(
                        NewRecurringTransaction(
                            userId: userId,
                            accountId: accountId,
                            name: row.name,
                            amount: abs(row.amount),
                            movementType: row.movementType,
                            category: row.category,
                            dayOfMonth: row.dayOfMonth ?? 1
                        )
                    )
                    importedRecurring += 1
                } else {
                    try await TransactionsRepository.shared.add(
                        NewTransaction(
                            userId: userId,
                            accountId: accountId,
                            amount: row.amount,
                            movementType: row.movementType,
                            category: row.category,
                            description: row.name.isEmpty ? nil : row.name,
                            tags: row.tags,
                            occurredAt: row.occurredAt ?? Date()
                        )
                    )
                    importedTransactions += 1
                }
            }

            importSummary = "Se importaron \(importedTransactions) movimientos y \(importedRecurring) recurrentes."
        } catch {
            errorMessage = "No se pudo importar: \(error.localizedDescription)"
        }
    }
}
