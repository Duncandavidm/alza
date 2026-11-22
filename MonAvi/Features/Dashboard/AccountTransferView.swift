import SwiftUI
import Supabase

/// Pasar dinero de una cuenta propia a otra (ej. el ahorro que se liberó a
/// la cuenta principal). Con "Pasar todo", la cuenta de origen queda en $0.
/// No cuenta como gasto ni como ingreso.
struct AccountTransferView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    var sourceAccountId: UUID? = nil
    /// Se llama al terminar (para recargar la pantalla que la abrió).
    var onDone: (() -> Void)? = nil

    @State private var accounts: [Account] = []
    @State private var fromId: UUID?
    @State private var toId: UUID?
    @State private var amountText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var source: Account? { accounts.first { $0.id == fromId } }
    private var destination: Account? { accounts.first { $0.id == toId } }
    private var amount: Decimal { RecurringAmountParser.parse(amountText) ?? 0 }
    private var sources: [Account] { accounts.filter { !$0.type.isLiability } }
    private var destinations: [Account] { accounts.filter { $0.id != fromId } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Desde", selection: $fromId) {
                        ForEach(sources) { account in
                            Text("\(account.name) · \(account.balance.formatted(.currency(code: account.currency)))")
                                .tag(Optional(account.id))
                        }
                    }
                    Picker("Hacia", selection: $toId) {
                        ForEach(destinations) { account in
                            Text(account.type == .creditCard ? "\(account.name) (abono a la tarjeta)" : account.name)
                                .tag(Optional(account.id))
                        }
                    }
                    if let source, SavingsAvailability.isLocked(source), let label = SavingsAvailability.label(source.availableOn) {
                        Text("Ojo: marcaste que este dinero está bloqueado hasta el \(label).")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    AmountField(placeholder: "¿Cuánto pasas?", text: $amountText)
                    if let source, source.balance > 0 {
                        Button("Pasar todo (\(source.balance.formatted(.currency(code: source.currency))))") {
                            amountText = NSDecimalNumber(decimal: source.balance).stringValue
                        }
                    }
                } footer: {
                    if let source, let destination, amount > 0 {
                        let left = source.balance - amount
                        Text(left <= 0
                             ? "\(source.name) queda en $0 y \(destination.name) sube \(amount.formatted(.currency(code: "USD")))."
                             : "\(source.name) queda en \(left.formatted(.currency(code: "USD"))) y \(destination.name) sube \(amount.formatted(.currency(code: "USD"))).")
                    } else {
                        Text("Es dinero tuyo que cambia de cuenta: no cuenta como gasto ni como ingreso.")
                    }
                }

                if let source, amount > source.balance {
                    Text("Es más de lo que tiene \(source.name).")
                        .foregroundStyle(MonAviBrand.alert)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(MonAviBrand.alert)
                }
            }
            .navigationTitle("Pasar a otra cuenta")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pasar") { Task { await save() } }
                        .disabled(isSaving || amount <= 0 || source == nil || destination == nil || amount > (source?.balance ?? 0))
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        guard let userId = appState.currentUserId else { return }
        accounts = (try? await SupabaseManager.shared.client
            .from("accounts")
            .select()
            .eq("user_id", value: userId)
            .order("created_at", ascending: true)
            .execute()
            .value) ?? []
        fromId = fromId ?? sources.first { $0.id == sourceAccountId }?.id ?? sources.first { $0.type.isReserve }?.id ?? sources.first?.id
        // Destino por defecto: la cuenta principal (la primera que no es
        // ahorro ni tarjeta).
        toId = toId ?? accounts.first { $0.id != fromId && !$0.type.isReserve && !$0.type.isLiability }?.id
            ?? destinations.first?.id
        if amountText.isEmpty, let source, SavingsAvailability.isDue(source) {
            amountText = NSDecimalNumber(decimal: source.balance).stringValue
        }
    }

    private func save() async {
        guard let userId = appState.currentUserId, let source, let destination else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await AccountTransfers.transfer(amount: amount, from: source, to: destination, userId: userId)
            NotificationCenter.default.post(name: .recurringLoggedFromNotification, object: nil)
            onDone?()
            dismiss()
        } catch {
            errorMessage = "No se pudo hacer la transferencia: \(error.localizedDescription)"
        }
    }
}

/// Ficha de una cuenta (Ajustes > Cuentas): saldo, fecha en que el dinero
/// queda libre (plazo fijo, ahorro navideño) y "Pasar a otra cuenta".
struct AccountDetailView: View {
    @EnvironmentObject private var appState: AppState
    let account: Account
    var onChange: (() -> Void)? = nil

    @State private var isLocked = false
    @State private var availableOn = SavingsAvailability.suggestedDate()
    @State private var isSaving = false
    @State private var message: String?
    @State private var showingTransfer = false
    /// Saldo mostrado (cambia al ajustarlo sin esperar a recargar Hoy).
    @State private var shownAmount: Decimal?
    @State private var isEditingBalance = false
    @State private var balanceText = ""
    @State private var balanceMessage: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Tipo", value: account.type.displayName)
                LabeledContent(account.type == .creditCard ? "Debes" : "Saldo", value: (shownAmount ?? account.displayAmount).formatted(.currency(code: account.currency)))
                if isEditingBalance {
                    AmountField(placeholder: account.type == .creditCard ? "Lo que debes hoy" : "Saldo de hoy", text: $balanceText)
                    Button(isSaving ? "Guardando…" : "Guardar saldo") { Task { await saveBalance() } }
                        .disabled(isSaving || RecurringAmountParser.parse(balanceText) == nil)
                } else {
                    Button {
                        balanceText = DgiInvoiceLookupLogic.amountText(for: shownAmount ?? account.displayAmount)
                        balanceMessage = nil
                        isEditingBalance = true
                    } label: {
                        Label("Ajustar saldo", systemImage: "pencil")
                    }
                }
                if let balanceMessage {
                    Text(balanceMessage).font(.footnote).foregroundStyle(.secondary)
                }
            } footer: {
                Text(account.type == .creditCard
                     ? "Escribe lo que debes según tu banco. No se anota como gasto ni como pago."
                     : "Escribe el saldo que ves en tu banco. No se anota como gasto ni como ingreso.")
            }

            if !account.type.isLiability {
                Section {
                    Toggle("El dinero está bloqueado hasta una fecha", isOn: $isLocked)
                    if isLocked {
                        DatePicker("Disponible desde", selection: $availableOn, displayedComponents: .date)
                    }
                    Button(isSaving ? "Guardando…" : "Guardar") { Task { await saveAvailability() } }
                        .disabled(isSaving)
                    if let message {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("¿Cuándo está disponible?")
                } footer: {
                    Text("Para plazos fijos o ahorros que se liberan en una fecha (ej. diciembre). Ese día te preguntamos si ya está disponible y te ayudamos a pasarlo a otra cuenta. Si no tiene bloqueo, el dinero siempre está disponible.")
                }

                Section {
                    Button {
                        showingTransfer = true
                    } label: {
                        Label("Pasar a otra cuenta", systemImage: "arrow.left.arrow.right")
                    }
                    .disabled(account.balance <= 0)
                }
            }
        }
        .navigationTitle(account.name)
        .onAppear {
            if let date = SavingsAvailability.date(from: account.availableOn) {
                isLocked = true
                availableOn = date
            }
        }
        .sheet(isPresented: $showingTransfer) {
            AccountTransferView(sourceAccountId: account.id) { onChange?() }
        }
    }

    private func saveBalance() async {
        guard let entered = RecurringAmountParser.parse(balanceText) else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await AccountBalanceAdjustment.save(entered: entered, account: account)
            shownAmount = account.type == .creditCard ? abs(entered) : entered
            isEditingBalance = false
            balanceMessage = "Listo: saldo actualizado."
            onChange?()
        } catch {
            balanceMessage = "No se pudo guardar: \(error.localizedDescription)"
        }
    }

    private func saveAvailability() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await AccountTransfers.setAvailableOn(isLocked ? availableOn : nil, accountId: account.id)
            if isLocked, let label = SavingsAvailability.label(SavingsAvailability.string(from: availableOn)) {
                message = "Listo: el \(label) te preguntamos si ya está disponible."
            } else {
                message = "Listo: sin bloqueo, el dinero siempre está disponible."
            }
            onChange?()
        } catch {
            message = "No se pudo guardar: \(error.localizedDescription)"
        }
    }
}
