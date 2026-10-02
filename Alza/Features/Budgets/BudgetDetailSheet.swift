import SwiftUI

/// Tocar una barra de presupuesto (en el dashboard o en la lista de
/// Presupuestos) abre esto: cambiar el color, el limite, o eliminarlo.
struct BudgetDetailSheet: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: BudgetsViewModel
    let progress: BudgetProgress
    @Environment(\.dismiss) private var dismiss

    @State private var selectedColor: Color
    @State private var limitText: String
    @State private var averageMonthly: Decimal?
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(viewModel: BudgetsViewModel, progress: BudgetProgress) {
        self.viewModel = viewModel
        self.progress = progress
        let fallbackIndex = viewModel.progresses.firstIndex { $0.id == progress.id } ?? 0
        _selectedColor = State(initialValue: BudgetColorPalette.color(for: progress.budget, index: fallbackIndex))
        _limitText = State(initialValue: NSDecimalNumber(decimal: progress.budget.limitAmount).stringValue)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text(categoryEmoji)
                        .font(.system(size: 44))
                        .frame(width: 84, height: 84)
                        .background(Circle().fill(selectedColor.opacity(0.18)))

                    Text(progress.budget.category)
                        .font(.system(.title3, design: AlzaBrand.fontDesign, weight: .bold))

                    if let averageMonthly {
                        Text("prom. \(BudgetCandyBar.compactAmount(averageMonthly)) / mes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Color del presupuesto")
                        .font(.subheadline.weight(.semibold))

                    HStack(spacing: 10) {
                        ForEach(Array(BudgetColorPalette.swatches.enumerated()), id: \.offset) { _, swatch in
                            Button {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                    selectedColor = swatch
                                }
                            } label: {
                                Circle()
                                    .fill(swatch)
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle()
                                            .stroke(.primary, lineWidth: selectedColor == swatch ? 2 : 0)
                                            .padding(-3)
                                    )
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Limite \(progress.budget.period.displayName.lowercased())")
                        .font(.subheadline.weight(.semibold))
                    AmountField(placeholder: "Limite", text: $limitText)
                        .font(.title2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(AlzaBrand.alert)
                }

                Spacer()

                Button(role: .destructive) {
                    Task { await delete() }
                } label: {
                    Text("Eliminar presupuesto")
                        .font(.system(.headline, design: AlzaBrand.fontDesign))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.bordered)
                .tint(AlzaBrand.alert)
                .pressable()
            }
            .padding(24)
            .navigationTitle(progress.budget.category)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Image(systemName: "checkmark")
                        }
                    }
                    .disabled(limitText.isEmpty || isSaving)
                }
            }
            .task { await loadAverage() }
        }
    }

    private var categoryEmoji: String {
        TransactionCategory(rawValue: progress.budget.category)?.emoji ?? "🛍️"
    }

    private func loadAverage() async {
        guard let userId = appState.currentUserId else { return }
        averageMonthly = try? await viewModel.averageMonthlySpent(for: progress.budget, userId: userId)
    }

    private func save() async {
        guard let limit = Decimal(string: limitText.replacingOccurrences(of: ",", with: ".")), limit > 0 else {
            errorMessage = "Pon un limite valido."
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await viewModel.updateBudget(progress.budget, limitAmount: limit, color: selectedColor.hexString)
            dismiss()
        } catch {
            errorMessage = "No se pudo guardar: \(error.localizedDescription)"
        }
    }

    private func delete() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await viewModel.deleteBudget(progress.budget)
            dismiss()
        } catch {
            errorMessage = "No se pudo eliminar: \(error.localizedDescription)"
        }
    }
}
