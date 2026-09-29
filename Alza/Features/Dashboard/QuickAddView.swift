import SwiftUI

/// Mejora #2: ingreso ultra-rapido. Solo pregunta "¿cuanto?" y "¿que fue?" —
/// el tipo de movimiento esta ahi para diferenciarlo (mejora #3) pero es un
/// toque opcional, no un formulario. Sin categoria obligatoria.
struct QuickAddView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: DayJournalViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var amountFieldFocused: Bool

    @State private var movementType: MovementType = .gasto
    @State private var amountText = ""
    @State private var description = ""
    @State private var isSaving = false
    @State private var showingCartAnimation = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                MovementTypePicker(selection: $movementType)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 6) {
                    Text("¿Cuanto?")
                        .font(.headline)
                    HStack {
                        Text("$")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField("0", text: $amountText)
                            .font(.system(size: 40, weight: .bold))
                            .keyboardType(.decimalPad)
                            .focused($amountFieldFocused)
                    }
                    Divider()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("¿Que fue?")
                        .font(.headline)
                    TextField("ej. Compra de harina", text: $description)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.footnote)
                }

                Spacer()

                Button {
                    Task { await save() }
                } label: {
                    Text("Guardar")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(movementType.tintColor)
                .disabled(amountText.isEmpty || isSaving || viewModel.defaultAccountId == nil)
            }
            .padding(20)
            .navigationTitle("Anotar movimiento")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .onAppear { amountFieldFocused = true }
            .overlay {
                if showingCartAnimation {
                    Color(.systemBackground).opacity(0.85).ignoresSafeArea()
                    CartLoadingView(
                        itemEmoji: movementType.emoji,
                        message: "Anotando tu \(movementType.displayName.lowercased())..."
                    )
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        guard
            let userId = appState.currentUserId,
            let accountId = viewModel.defaultAccountId,
            let magnitude = Decimal(string: amountText.replacingOccurrences(of: ",", with: "."))
        else { return }

        isSaving = true
        showingCartAnimation = true
        defer { isSaving = false }

        do {
            async let saved: Void = viewModel.quickAdd(
                userId: userId,
                accountId: accountId,
                magnitude: magnitude,
                description: description,
                movementType: movementType
            )
            async let minDelay: Void = Task.sleep(nanoseconds: 1_200_000_000)
            _ = try await (saved, minDelay)
            dismiss()
        } catch {
            showingCartAnimation = false
            errorMessage = error.localizedDescription
        }
    }
}
