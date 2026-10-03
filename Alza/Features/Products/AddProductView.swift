import SwiftUI

/// La calculadora "precio costo -> precio de venta" que pidio David para
/// comercios: pones cuanto te cuesta y que margen quieres ganar, y Amadai
/// calcula el precio de venta en vivo.
struct AddProductView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: ProductsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var unit = ""
    @State private var costPriceText = ""
    @State private var marginPercentText = "30"
    @State private var isSaving = false

    private var costPrice: Decimal { Decimal(string: costPriceText.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    private var marginPercent: Decimal { Decimal(string: marginPercentText.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    private var salePrice: Decimal { PriceCalculator.salePrice(costPrice: costPrice, marginPercent: marginPercent) }
    private var profit: Decimal { salePrice - costPrice }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && costPrice >= 0 && marginPercent >= 0 && marginPercent < 100
    }

    var body: some View {
        Form {
            Section("Producto o servicio") {
                TextField("Nombre", text: $name)
                TextField("Unidad (opcional, ej. caja, hora)", text: $unit)
            }

            Section("Calculadora de precio") {
                HStack {
                    Text("Precio costo")
                    Spacer()
                    TextField("0.00", text: $costPriceText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }

                HStack {
                    Text("Margen deseado")
                    Spacer()
                    TextField("30", text: $marginPercentText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    Text("%")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Resultado") {
                LabeledContent("Precio de venta") {
                    Text(salePrice, format: .currency(code: "USD"))
                        .font(.title3.bold())
                        .foregroundStyle(.green)
                }
                LabeledContent("Ganancia por unidad", value: profit.formatted(.currency(code: "USD")))
            }
        }
        .navigationTitle("Nuevo producto")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    guard let userId = appState.currentUserId else { return }
                    isSaving = true
                    Task {
                        defer { isSaving = false }
                        _ = try? await viewModel.add(
                            NewCatalogProduct(
                                userId: userId,
                                name: name,
                                unit: unit.isEmpty ? nil : unit,
                                costPrice: costPrice,
                                marginPercent: marginPercent,
                                salePrice: salePrice
                            )
                        )
                        dismiss()
                    }
                } label: {
                    if isSaving { ProgressView() } else { Text("Guardar") }
                }
                .disabled(!isValid || isSaving)
            }
        }
    }
}
