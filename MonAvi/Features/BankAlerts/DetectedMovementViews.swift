import SwiftUI

/// Hoy: "Movimientos detectados · por confirmar" con los avisos del banco
/// que llegaron por Atajos. Cada uno se registra (con la cuenta y la
/// categoria sugeridas), se revisa o se descarta. No sale si no hay nada.
struct DetectedMovementsCard: View {
    @ObservedObject var store: DetectedMovementStore
    let onReview: (DetectedMovement) -> Void
    let onQuickRegister: (DetectedMovement) -> Void

    var body: some View {
        if !store.pending.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge.fill")
                        .foregroundStyle(MonAviBrand.primary)
                    Text(store.pending.count == 1 ? L("1 movimiento por confirmar") : L("%@ movimientos por confirmar", "\(store.pending.count)"))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
                ForEach(store.pending.prefix(3)) { movement in
                    row(movement)
                }
                if store.pending.count > 3 {
                    Text("Y \(store.pending.count - 3) más: tócalos para revisarlos uno por uno.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(MonAviBrand.primary.opacity(0.10)))
        }
    }

    private func row(_ movement: DetectedMovement) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                onReview(movement)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Text(movement.isIncome ? "💰" : "💳")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(movement.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(subtitle(movement))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if movement.possibleDuplicate {
                            Label("Parece que ya lo anotaste", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                    Text(movement.amountText)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(movement.isIncome ? MonAviBrand.primary : .primary)
                }
            }
            .buttonStyle(.plain)
            HStack(spacing: 8) {
                Button("Registrar") { onQuickRegister(movement) }
                    .buttonStyle(.borderedProminent)
                    .tint(MonAviBrand.primary)
                Button("Revisar") { onReview(movement) }
                    .buttonStyle(.bordered)
                Spacer()
                Button(role: .destructive) {
                    DetectedMovementActions.dismiss(idString: movement.id.uuidString)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Descartar")
            }
            .font(.footnote.weight(.semibold))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
    }

    private func subtitle(_ movement: DetectedMovement) -> String {
        var parts: [String] = []
        if let source = movement.source { parts.append(source) }
        if let last4 = movement.last4 { parts.append("•\(last4)") }
        parts.append(movement.detectedAt.formatted(date: .abbreviated, time: .shortened))
        return parts.joined(separator: " · ")
    }
}

/// Revisar un movimiento detectado antes de guardarlo: tipo, monto,
/// descripcion, categoria y cuenta (la tarjeta se recuerda para la proxima).
struct DetectedMovementReviewView: View {
    let movement: DetectedMovement
    let accounts: [Account]
    let userId: UUID?
    /// Presupuestos del mes, para mostrar el "Límite de gasto".
    var progresses: [BudgetProgress] = []
    /// "1 de 2" cuando hay varios por confirmar.
    var position: Int? = nil
    var total: Int? = nil
    var onDone: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var isIncome: Bool
    @State private var amountText: String
    @State private var descriptionText: String
    @State private var category: TransactionCategory?
    @State private var accountId: UUID?
    @State private var rememberCard = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didPrefill = false

    init(
        movement: DetectedMovement,
        accounts: [Account],
        userId: UUID?,
        progresses: [BudgetProgress] = [],
        position: Int? = nil,
        total: Int? = nil,
        onDone: @escaping () -> Void = {}
    ) {
        self.movement = movement
        self.accounts = accounts
        self.userId = userId
        self.progresses = progresses
        self.position = position
        self.total = total
        self.onDone = onDone
        _isIncome = State(initialValue: movement.isIncome)
        _amountText = State(initialValue: "\(abs(movement.amount))")
        _descriptionText = State(initialValue: movement.counterpart ?? "")
    }

    private var amount: Decimal? {
        let value: Decimal?
        if AppCountry.current == .colombia {
            value = AppCountry.parseAmount(amountText)
        } else {
            let normalized = amountText.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." }
            value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
        }
        guard let value, value > 0 else { return nil }
        return value
    }

    private var categories: [TransactionCategory] {
        isIncome ? [.income, .gifts, .transfers, .other] : TransactionCategory.allCases.filter { $0 != .income }
    }

    var body: some View {
        NavigationStack {
            Form {
                if movement.possibleDuplicate {
                    Section {
                        Label("Ya tienes un movimiento igual de hace pocos minutos. Revisa que no lo estés anotando dos veces.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                Section {
                    Picker("Tipo", selection: $isIncome) {
                        Text("Gasto").tag(false)
                        Text("Ingreso").tag(true)
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Text("Monto")
                        Spacer()
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.body.weight(.semibold))
                    }
                    TextField(isIncome ? L("¿De quién?") : L("¿Dónde? (ej. Café La Esquina)"), text: $descriptionText)
                    if !isIncome, let amount, amount <= 10 {
                        Label("Gasto hormiga: pequeño, pero suma cada mes", systemImage: "ant.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(isIncome ? L("Ingreso detectado") : L("Pago detectado"))
                } footer: {
                    Text(footerText)
                }

                Section("Categoría") {
                    Picker("Categoría", selection: $category) {
                        Text("Sin categoría").tag(TransactionCategory?.none)
                        ForEach(categories) { item in
                            Text("\(item.emoji) \(item.rawValue)").tag(TransactionCategory?.some(item))
                        }
                    }
                }

                budgetSection

                Section("Cuenta") {
                    if accounts.isEmpty {
                        Text("Crea una cuenta en MonAvi para registrar este movimiento.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Cuenta", selection: $accountId) {
                            ForEach(accounts) { account in
                                Text(account.name).tag(UUID?.some(account.id))
                            }
                        }
                        if let last4 = movement.last4 {
                            Toggle("Usar siempre esta cuenta para •\(last4)", isOn: $rememberCard)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red).font(.footnote)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        DetectedMovementActions.dismiss(idString: movement.id.uuidString)
                        onDone()
                        dismiss()
                    } label: {
                        Text("Descartar, no es un movimiento mío")
                    }
                }
            }
            .navigationTitle(queueTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isIncome ? L("Agregar ingreso") : L("Agregar gasto")) { Task { await save() } }
                        .disabled(isSaving || amount == nil || accountId == nil || userId == nil)
                }
            }
            .onAppear {
                // Sugerencias: categoria por el comercio y la cuenta de esa tarjeta.
                guard !didPrefill else { return }
                didPrefill = true
                category = DetectedMovementActions.suggestedCategory(for: movement)
                accountId = DetectedMovementActions.suggestedAccountId(for: movement, accounts: accounts)
            }
            .onChange(of: isIncome) { _, income in
                if let current = category, !categories.contains(current) { category = income ? .income : nil }
            }
        }
    }

    private var queueTitle: String {
        if let position, let total, total > 1 { return L("Por confirmar · %@ de %@", "\(position)", "\(total)") }
        return L("Por confirmar")
    }

    /// "Límite de gasto": como queda el presupuesto del mes de esa
    /// categoria si se agrega este gasto.
    @ViewBuilder
    private var budgetSection: some View {
        if !isIncome, let category,
           let progress = progresses.first(where: { $0.budget.category == category.rawValue }),
           progress.budget.limitAmount > 0 {
            let projected = progress.spent + (amount ?? 0)
            let limit = progress.budget.limitAmount
            let ratio = NSDecimalNumber(decimal: projected / limit).doubleValue
            Section("Límite de gasto") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(category.emoji) \(category.displayName)")
                        Spacer()
                        Text("\(projected.formatted(.appCurrency)) de \(limit.formatted(.appCurrency))")
                            .font(.subheadline.weight(.semibold))
                    }
                    ProgressView(value: min(max(ratio, 0), 1))
                        .tint(ratio >= 1 ? MonAviBrand.alert : (ratio >= 0.8 ? Color.orange : MonAviBrand.primary))
                    Text(ratio >= 1
                         ? L("Con este gasto pasas tu presupuesto del mes.")
                         : L("Con este gasto llegas al %@%% de tu presupuesto del mes.", "\(Int((ratio * 100).rounded()))"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var footerText: String {
        var parts = [L("Leído de un aviso")]
        if let source = movement.source { parts[0] += L(" de %@", "\(source)") }
        parts.append(movement.detectedAt.formatted(date: .abbreviated, time: .shortened))
        return parts.joined(separator: " · ") + L(". Nada se guarda hasta que toques Registrar.")
    }

    private func save() async {
        guard let userId, let accountId, let amount else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await DetectedMovementActions.register(
                movement,
                userId: userId,
                accountId: accountId,
                amount: amount,
                isIncome: isIncome,
                category: category,
                description: descriptionText,
                rememberCard: rememberCard
            )
            onDone()
            dismiss()
        } catch {
            errorMessage = L("No se pudo registrar. Revisa tu conexión e inténtalo de nuevo.")
        }
    }
}
