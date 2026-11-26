import SwiftUI

struct InsightsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = InsightsViewModel()
    @State private var question = ""
    @FocusState private var questionFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        FinancialPlanView()
                    } label: {
                        Label("Tu plan en 7 pasos", systemImage: "map.fill")
                    }
                    NavigationLink {
                        FinancialHealthView()
                    } label: {
                        Label("Tu salud financiera", systemImage: "heart.text.square.fill")
                    }
                    NavigationLink {
                        SpendingInsightsView()
                    } label: {
                        Label("Gastos por categoría", systemImage: "chart.pie.fill")
                    }
                }

                Section("Pregunta lo que sea") {
                    HStack(spacing: 8) {
                        TextField("ej. ¿Cuánto gasté en comida este mes?", text: $question)
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
                        .accessibilityLabel("Enviar pregunta")
                        .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isAsking)
                    }

                    if viewModel.isAsking {
                        MonAviCatLoader(message: "Pensando tu respuesta…", size: 170)
                            .padding(.vertical, 8)
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

                Section("Análisis") {
                    if viewModel.isGenerating {
                        MonAviCatLoader(message: "Analizando tus cuentas y movimientos…", size: 200)
                            .padding(.vertical, 12)
                    } else if viewModel.insights.isEmpty && !viewModel.isLoading {
                        Text("Genera un análisis con IA de tus cuentas y movimientos.")
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
            .navigationTitle("Análisis")
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
            .alert("Algo salió mal", isPresented: .constant(viewModel.errorMessage != nil)) {
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
