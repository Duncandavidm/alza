import SwiftUI

/// Lista completa de categorias con su icono y color, con buscador — se
/// abre desde "Todas" en Anotar movimiento.
struct CategoryPickerSheet: View {
    @Binding var selection: TransactionCategory?
    /// Ya ordenadas por uso (las que mas usa el usuario primero).
    let categories: [TransactionCategory]
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [TransactionCategory] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return categories }
        return categories.filter {
            $0.rawValue.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if selection != nil {
                    Button("Sin categoría") {
                        selection = nil
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }

                ForEach(filtered) { category in
                    Button {
                        selection = category
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            CategoryIcon(category: category, size: 36)
                            Text(category.rawValue)
                                .foregroundStyle(Color.primary)
                            Spacer()
                            if selection == category {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(MonAviBrand.primary)
                            }
                        }
                    }
                    .accessibilityAddTraits(selection == category ? .isSelected : [])
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "Buscar categoría")
            .navigationTitle("Categoría")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
