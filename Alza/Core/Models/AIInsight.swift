import Foundation

enum InsightKind: String, Codable {
    case general
    case spending
    case saving
    case alert
}

struct AIInsight: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    let kind: InsightKind
    let title: String
    let body: String
    var dismissed: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case kind
        case title
        case body
        case dismissed
        case createdAt = "created_at"
    }
}
