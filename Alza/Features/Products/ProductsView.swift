import SwiftUI

struct ProductsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = ProductsViewModel()
    @State private var showingAdd = false

    var body: some View {
        List {
            if viewModel.products.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "Sin productos todavia",
                    systemImage: "tag",
                    description: Text("Agrega tus productos o servicios con su precio costo y calcula el precio de venta.")
                )
            }

            ForEach(viewModel.products) { product in
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.name).font(.headline)
                    HStack(spacing: 12) {
                        Text("Costo: \(product.costPrice, format: .currency(code: "USD"))")
                        Text("Margen: \(product.marginPercent, format: .number.precision(.fractionLength(0)))%")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text("Venta: \(product.salePrice, format: .currency(code: "USD"))")
                        .font(.subheadline.bold())
                        .foregroundStyle(.green)
                }
                .padding(.vertical, 4)
            }
            .onDelete { offsets in
                for index in offsets {
                    let product = viewModel.products[index]
                    Task { await viewModel.delete(product) }
                }
            }
        }
        .navigationTitle("Catalogo y precios")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack {
                AddProductView(viewModel: viewModel)
            }
        }
        .task {
            guard let userId = appState.currentUserId else { return }
            await viewModel.refresh(userId: userId)
        }
        .alert("Algo salio mal", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
