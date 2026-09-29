import SwiftUI

struct InsightsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = InsightsViewModel()

    var body: some View {
        NavigationStack {
            List {
                if viewModel.insights.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView(
                        "Sin insights todavia",
                        systemImage: "sparkles",
                        description: Text("Genera insights de IA a partir de tus cuentas y movimientos.")
                    )
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
}
