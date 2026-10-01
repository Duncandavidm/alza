import Foundation
import Supabase

@MainActor
final class ProductsViewModel: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let supabase = SupabaseManager.shared.client

    func refresh(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        do {
            products = try await supabase
                .from("products")
                .select()
                .eq("user_id", value: userId)
                .order("name", ascending: true)
                .execute()
                .value
        } catch {
            errorMessage = "No se pudo cargar tu catalogo: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func add(_ new: NewProduct) async throws -> Product {
        let created: Product = try await supabase
            .from("products")
            .insert(new)
            .select()
            .single()
            .execute()
            .value
        products.append(created)
        products.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return created
    }

    func delete(_ product: Product) async {
        do {
            try await supabase.from("products").delete().eq("id", value: product.id).execute()
            products.removeAll { $0.id == product.id }
        } catch {
            errorMessage = "No se pudo borrar: \(error.localizedDescription)"
        }
    }
}
