import SwiftUI

/// "Buzon" de sugerencias: el cliente escribe que le gustaria ver en Avi,
/// se guarda en Supabase y queda aqui mismo como historial de lo que ya
/// mando. David lo revisa directo en el dashboard de Supabase.
struct FeedbackView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = FeedbackViewModel()
    @State private var draft = ""
    @State private var isSending = false
    @FocusState private var isDraftFocused: Bool

    var body: some View {
        List {
            Section {
                TextField("¿Que te gustaria ver en Avi?", text: $draft, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($isDraftFocused)

                Button {
                    Task { await send() }
                } label: {
                    if isSending {
                        ProgressView()
                    } else {
                        Text("Enviar sugerencia")
                    }
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            } footer: {
                Text("Leemos cada sugerencia — nos ayuda a decidir que construir despues.")
            }

            if !viewModel.suggestions.isEmpty {
                Section("Tus sugerencias enviadas") {
                    ForEach(viewModel.suggestions) { suggestion in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(suggestion.message)
                            Text(suggestion.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { indexSet in
                        Task { await delete(at: indexSet) }
                    }
                }
            }
        }
        .navigationTitle("Sugerencias")
        .task { await refresh() }
        .refreshable { await refresh() }
        .alert("Algo salio mal", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func refresh() async {
        guard let userId = appState.currentUserId else { return }
        await viewModel.refresh(userId: userId)
    }

    private func send() async {
        guard let userId = appState.currentUserId else { return }
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }

        isSending = true
        defer { isSending = false }

        do {
            try await viewModel.submit(NewFeedbackSuggestion(userId: userId, message: message))
            draft = ""
            isDraftFocused = false
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func delete(at indexSet: IndexSet) async {
        for index in indexSet {
            try? await viewModel.delete(viewModel.suggestions[index])
        }
    }
}
