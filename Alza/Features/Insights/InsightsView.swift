import SwiftUI

struct InsightsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = InsightsViewModel()
    @State private var question = ""
    @FocusState private var questionFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section("Pregunta lo que sea") {
                    HStack(spacing: 8) {
                        TextField("ej. ¿Cuanto gaste en comida este mes?", text: $question)
                            .focused($questionFocused)
                            .onSubmit { Task { await ask() } }

                        Button {
                            Task { await ask() }
                        } label: {
                            if viewModel.isAsking {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title2)
                            }
                        }
                        .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isAsking)
                    }

                    if let answer = viewModel.lastAnswer {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(answer)
                                .font(.subheadline)
                            Button("Cerrar") { viewModel.clearAnswer() }
                                .font(.caption)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Insights") {
                    if viewModel.insights.isEmpty && !viewModel.isLoading {
                        Text("Genera insights de IA a partir de tus cuentas y movimientos.")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(viewModel.insights) { insight in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(insight.title).font(.headline)
                            Text(insight.body).font(.subheadline).foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button("Descartar", role: .destructive) {
                                Task { await viewModel.dismiss(insight) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Insights")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await generate() }
                    } label: {
                        if viewModel.isGenerating {
                            ProgressView()
                        } else {
                            Label("Generar", systemImage: "wand.and.stars")
                        }
                    }
                    .disabled(viewModel.isGenerating)
                }
            }
            .refreshable { await refresh() }
            .task { await refresh() }
            .alert("Algo salio mal", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private func refresh() async {
        guard let userId = appState.currentUserId else { return }
        await viewModel.refresh(userId: userId)
    }

    private func generate() async {
        guard let userId = appState.currentUserId else { return }
        await viewModel.generateInsights(userId: userId)
    }

    private func ask() async {
        guard let userId = appState.currentUserId else { return }
        questionFocused = false
        let asked = question
        question = ""
        await viewModel.ask(userId: userId, question: asked)
    }
}
