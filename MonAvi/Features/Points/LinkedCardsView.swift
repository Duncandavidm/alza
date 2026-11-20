import SwiftUI

/// "Mis tarjetas": agregar, pausar o eliminar una tarjeta vinculada para
/// ganar puntos en comercios aliados. Solo pide marca + ultimos 4 +
/// alias — nunca numero completo, CVV ni vencimiento.
struct LinkedCardsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: PointsViewModel
    @State private var isAdding = false

    var body: some View {
        List {
            if viewModel.linkedCards.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "Sin tarjetas vinculadas",
                    systemImage: "creditcard",
                    description: Text("Vincula una tarjeta para ganar cashback automáticamente cuando pagues en un comercio aliado.")
                )
            } else {
                ForEach(viewModel.linkedCards) { card in
                    cardRow(card)
                }
            }
        }
        .navigationTitle("Mis tarjetas")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    isAdding = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Agregar tarjeta")
            }
        }
        .sheet(isPresented: $isAdding) {
            AddLinkedCardView(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private func cardRow(_ card: LinkedCard) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(card.alias).font(.body)
                Text("\(card.brand.displayName) •••• \(card.last4)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if card.status == .paused {
                Text("Pausada")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await viewModel.setStatus(card, to: .removed) }
            } label: {
                Label("Eliminar", systemImage: "trash")
            }

            Button {
                Task { await viewModel.setStatus(card, to: card.status == .active ? .paused : .active) }
            } label: {
                Label(card.status == .active ? "Pausar" : "Reactivar", systemImage: card.status == .active ? "pause.fill" : "play.fill")
            }
            .tint(.orange)
        }
    }
}

private struct AddLinkedCardView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: PointsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var brand: CardBrand = .visa
    @State private var last4 = ""
    @State private var alias = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var hasConsented = false

    private var isValid: Bool {
        last4.count == 4 && last4.allSatisfy(\.isNumber) && !alias.trimmingCharacters(in: .whitespaces).isEmpty && hasConsented
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Marca", selection: $brand) {
                        ForEach(CardBrand.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }

                    TextField("Últimos 4 dígitos", text: $last4)
                        .keyboardType(.numberPad)
                        .onChange(of: last4) { _, newValue in
                            last4 = String(newValue.filter(\.isNumber).prefix(4))
                        }

                    TextField("Alias (ej. \"Visa del banco\")", text: $alias)
                } footer: {
                    Text("Nunca pedimos el número completo, el CVV ni la fecha de vencimiento — con esto basta para identificar tus compras.")
                }

                Section {
                    Toggle(isOn: $hasConsented) {
                        Text("Autorizo a MonAvi a identificar mis compras con esta tarjeta en comercios aliados para acreditarme cashback.")
                            .font(.footnote)
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Vincular tarjeta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }
                        .disabled(!isValid || isSaving)
                }
            }
        }
    }

    private func save() async {
        guard let userId = appState.currentUserId else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await viewModel.addCard(userId: userId, brand: brand, last4: last4, alias: alias.trimmingCharacters(in: .whitespaces))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
