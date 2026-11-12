import SwiftUI

/// Ajustes > Categorías: las fijas de MonAvi (solo lectura) y las propias
/// del usuario, con su emoji. Las propias se pueden crear, editar y borrar;
/// los movimientos guardan el nombre como texto, asi que al borrar una
/// categoria los movimientos que ya la usan no cambian.
struct CategoriesView: View {
    @ObservedObject private var store = UserCategoriesStore.shared
    @State private var isAdding = false
    @State private var editingCategory: UserCategory?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                if store.categories.isEmpty {
                    Text("Crea categorías a tu medida, con el emoji que quieras. Aparecen al anotar un movimiento.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(store.categories) { category in
                    Button {
                        editingCategory = category
                    } label: {
                        HStack(spacing: 12) {
                            CategoryIcon(emoji: category.emoji, color: MonAviBrand.primary, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.name)
                                    .foregroundStyle(Color.primary)
                                Text(category.kind.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "pencil")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .onDelete { indexSet in
                    Task { await delete(at: indexSet) }
                }

                Button {
                    isAdding = true
                } label: {
                    Label("Nueva categoría", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Mis categorías")
            } footer: {
                if !store.categories.isEmpty {
                    Text("Desliza para borrar. Tus movimientos conservan el nombre de la categoría.")
                }
            }

            Section("Categorías de MonAvi") {
                ForEach(TransactionCategory.allCases) { category in
                    HStack(spacing: 12) {
                        CategoryIcon(category: category, size: 36)
                        Text(category.rawValue)
                        Spacer()
                        if category == .income {
                            Text("Ingreso")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Categorías")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAdding = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Nueva categoría")
            }
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .sheet(isPresented: $isAdding) {
            UserCategoryEditorView(existing: nil)
        }
        .sheet(item: $editingCategory) { category in
            UserCategoryEditorView(existing: category)
        }
        .alert("Algo salió mal", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func delete(at indexSet: IndexSet) async {
        let targets = indexSet.map { store.categories[$0] }
        for category in targets {
            do {
                try await UserCategoriesRepository.shared.delete(category)
                store.remove(category)
            } catch {
                errorMessage = "No se pudo borrar la categoría: \(error.localizedDescription)"
            }
        }
    }
}

/// Hoja para crear o editar una categoria propia: nombre, tipo y emoji.
struct UserCategoryEditorView: View {
    let existing: UserCategory?

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: UserCategoryKind = .gasto
    @State private var emoji = "🏷️"
    @State private var customEmojiText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    static let suggestedEmojis: [String] = [
        "🍔", "🍕", "☕️", "🛒", "🚗", "⛽️", "🏠", "💡", "📱", "💊",
        "👕", "🎬", "🎮", "📚", "🐶", "🎁", "✈️", "🏋️", "💇‍♀️", "👶",
        "🍺", "🎵", "💻", "🧾", "💳", "🏦", "💰", "📈", "🛠️", "🧹",
        "🌱", "⚽️", "🎨", "🚌", "🏥", "🍼", "🧴", "🪴", "🛍️", "🏷️",
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 8)

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && trimmedName.count <= 30 && !emoji.isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Text(emoji)
                            .font(.system(size: 34))
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(MonAviBrand.primary.opacity(0.16)))
                        TextField("Nombre, ej. Gimnasio", text: $name)
                            .font(.title3)
                            .textInputAutocapitalization(.sentences)
                            .onChange(of: name) { _, newValue in
                                if newValue.count > 30 { name = String(newValue.prefix(30)) }
                            }
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("\(trimmedName.count)/30")
                }

                Section("Tipo") {
                    Picker("Tipo", selection: $kind) {
                        ForEach(UserCategoryKind.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(Self.suggestedEmojis, id: \.self) { option in
                            Button {
                                emoji = option
                                customEmojiText = ""
                            } label: {
                                Text(option)
                                    .font(.system(size: 26))
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(emoji == option ? MonAviBrand.primary.opacity(0.22) : Color.clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(emoji == option ? MonAviBrand.primary : Color.clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(emoji == option ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)

                    TextField("O escribe cualquier emoji", text: $customEmojiText)
                        .onChange(of: customEmojiText) { _, newValue in
                            applyCustomEmoji(newValue)
                        }
                } header: {
                    Text("Emoji")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(existing == nil ? "Nueva categoría" : "Editar categoría")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if let existing {
                    name = existing.name
                    kind = existing.kind
                    emoji = existing.emoji
                }
            }
        }
        .presentationDetents([.large])
    }

    /// Se queda solo con el primer caracter (grafema) si es un emoji.
    private func applyCustomEmoji(_ text: String) {
        guard let first = text.first else { return }
        let firstString = String(first)
        if Self.isEmoji(first) {
            emoji = firstString
            if text != firstString { customEmojiText = firstString }
        } else {
            customEmojiText = ""
        }
    }

    static func isEmoji(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        guard let first = scalars.first else { return false }
        return first.properties.isEmojiPresentation
            || (first.properties.isEmoji && scalars.count > 1)
    }

    private func save() async {
        guard canSave else { return }
        let duplicateBuiltIn = TransactionCategory.allCases.contains {
            $0.rawValue.compare(trimmedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        if duplicateBuiltIn {
            errorMessage = "Ya existe una categoría de MonAvi con ese nombre."
            return
        }

        isSaving = true
        defer { isSaving = false }
        do {
            let saved: UserCategory
            if let existing {
                saved = try await UserCategoriesRepository.shared.update(existing, name: trimmedName, emoji: emoji, kind: kind)
            } else {
                saved = try await UserCategoriesRepository.shared.add(name: trimmedName, emoji: emoji, kind: kind)
            }
            UserCategoriesStore.shared.upsert(saved)
            dismiss()
        } catch {
            let text = String(describing: error)
            if text.contains("23505") || text.localizedCaseInsensitiveContains("duplicate") {
                errorMessage = "Ya tienes una categoría con ese nombre."
            } else {
                errorMessage = "No se pudo guardar: \(error.localizedDescription)"
            }
        }
    }
}
