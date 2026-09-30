import Foundation

/// Exportar/importar movimientos y recurrentes como un solo CSV (inspirado
/// en "las transacciones recurrentes ahora se incluyen en la exportacion e
/// importacion de CSV" de MonAi).
enum CSVTransactions {
    static let header = ["tipo", "fecha", "dia_del_mes", "nombre", "categoria", "tipo_movimiento", "monto", "etiquetas"]

    static func export(transactions: [FinanceTransaction], recurring: [RecurringTransaction]) -> String {
        let formatter = ISO8601DateFormatter()
        var lines = [CSV.row(header)]

        for transaction in transactions {
            lines.append(CSV.row([
                "movimiento",
                formatter.string(from: transaction.occurredAt),
                "",
                transaction.description ?? "",
                transaction.category ?? "",
                transaction.movementType.rawValue,
                "\(transaction.amount)",
                transaction.tags.joined(separator: "|"),
            ]))
        }

        for item in recurring {
            lines.append(CSV.row([
                "recurrente",
                "",
                "\(item.dayOfMonth)",
                item.name,
                item.category ?? "",
                item.movementType.rawValue,
                "\(item.amount)",
                "",
            ]))
        }

        return lines.joined()
    }

    struct ImportedRow {
        let isRecurring: Bool
        let occurredAt: Date?
        let dayOfMonth: Int?
        let name: String
        let category: String?
        let movementType: MovementType
        /// Monto tal cual viene en el CSV: signado para movimientos,
        /// magnitud positiva para recurrentes.
        let amount: Decimal
        let tags: [String]
    }

    static func parse(_ csvText: String) -> [ImportedRow] {
        let lines = csvText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        guard lines.count > 1 else { return [] }

        let formatter = ISO8601DateFormatter()
        var rows: [ImportedRow] = []

        for line in lines.dropFirst() {
            let fields = CSV.parseLine(line)
            guard fields.count >= 8 else { continue }

            rows.append(
                ImportedRow(
                    isRecurring: fields[0] == "recurrente",
                    occurredAt: fields[1].isEmpty ? nil : formatter.date(from: fields[1]),
                    dayOfMonth: Int(fields[2]),
                    name: fields[3],
                    category: fields[4].isEmpty ? nil : fields[4],
                    movementType: MovementType(rawValue: fields[5]) ?? .gasto,
                    amount: Decimal(string: fields[6]) ?? 0,
                    tags: fields[7].isEmpty ? [] : fields[7].split(separator: "|").map(String.init)
                )
            )
        }
        return rows
    }
}
