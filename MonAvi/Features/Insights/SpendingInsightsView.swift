import SwiftUI
import Charts

struct SpendingInsightsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = SpendingInsightsViewModel()

    var body: some View {
        List {
            Section {
                Picker("Periodo", selection: $viewModel.period) {
                    ForEach(SpendingPeriod.allCases) { period in
                        Text(period.displayName).tag(period)
                    }
                }
                .pickerStyle(.segmented)
            }

            if viewModel.categorySpends.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "Sin gastos en este periodo",
                    systemImage: "chart.pie",
                    description: Text("Cuando registres gastos, aquí verás en qué se te va el dinero.")
                )
            } else {
                Section {
                    Chart(viewModel.categorySpends) { item in
                        SectorMark(
                            angle: .value("Total", NSDecimalNumber(decimal: item.total).doubleValue),
                            innerRadius: .ratio(0.6),
                            angularInset: 1.5
                        )
                        .foregroundStyle(by: .value("Categoría", item.category))
                        .cornerRadius(4)
                    }
                    .frame(height: 220)
                    .chartLegend(position: .bottom, spacing: 12)
                } header: {
                    Text("Total gastado: \(viewModel.totalSpend, format: .currency(code: "USD"))")
                }

                Section("Top 3 categorías") {
                    ForEach(viewModel.topCategories) { item in
                        categoryRow(item)
                    }
                }

                Section("Todas las categorías") {
                    ForEach(viewModel.categorySpends) { item in
                        categoryRow(item)
                    }
                }
            }
        }
        .navigationTitle("Gastos por categoría")
        .task {
            guard let userId = appState.currentUserId else { return }
            await viewModel.refresh(userId: userId)
        }
        .refreshable {
            guard let userId = appState.currentUserId else { return }
            await viewModel.refresh(userId: userId)
        }
        .alert("Algo salió mal", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func categoryRow(_ item: CategorySpend) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.category).font(.subheadline.weight(.medium))
                if let percent = viewModel.percent(of: item) {
                    Text("\(percent, format: .number.precision(.fractionLength(0)))% del total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(item.total, format: .currency(code: "USD")).font(.subheadline.weight(.semibold))
                if let delta = item.deltaPercent {
                    Text("\(delta >= 0 ? "+" : "")\(delta, format: .number.precision(.fractionLength(0)))% vs anterior")
                        .font(.caption2)
                        .foregroundStyle(delta >= 0 ? .red : .green)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
