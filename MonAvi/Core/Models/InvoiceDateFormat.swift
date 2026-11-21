import Foundation

/// Mismo patron que `BillDateFormat`: las columnas `date` de Postgres se
/// manejan como String "yyyy-MM-dd" de punta a punta, sin depender de como
/// el decoder de supabase-swift interprete una fecha sin hora.
enum InvoiceDateFormat {
    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from string: String?) -> Date? {
        guard let string else { return nil }
        return formatter.date(from: string)
    }
}
