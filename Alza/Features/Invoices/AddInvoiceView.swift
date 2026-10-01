import SwiftUI

struct AddInvoiceView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: InvoicesViewModel
    @Environment(\.dismiss) private var dismiss

    @StateObject private var accountsViewModel = DashboardViewModel()
    @StateObject private var productsViewModel = ProductsViewModel()

    @State private var docType: InvoiceDocType = .factura
    @State private var customerName = ""
    @State private var customerContact = ""
    @State private var selectedAccountId: UUID?
    @State private var issueDate = Date()
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var notes = ""
    @State private var items: [InvoiceItemDraft] = [InvoiceItemDraft()]
    @State private var showingProductPicker = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var subtotal: Decimal { items.reduce(0) { $0 + $1.lineTotal } }

    private var isValid: Bool {
        !customerName.trimmingCharacters(in: .whitespaces).isEmpty
            && selectedAccountId != nil
            && items.contains { !$0.description.trimmingCharacters(in: .whitespaces).isEmpty && $0.lineTotal > 0 }
    }

    var body: some View {
        Form {
            Section("Tipo de documento") {
                Picker("Tipo", selection: $docType) {
                    ForEach(InvoiceDocType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Cliente") {
                TextField("Nombre del cliente", text: $customerName)
                TextField("Telefono o correo (opcional)", text: $customerContact)
            }

            Section("Cuenta donde recibes el pago") {
                if accountsViewModel.accounts.isEmpty {
                    Text("Primero crea una cuenta en la pestaña Cuentas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Cuenta", selection: $selectedAccountId) {
                        Text("Selecciona").tag(UUID?.none)
                        ForEach(accountsViewModel.accounts) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }
                }
            }

            Section("Fechas") {
                DatePicker("Fecha de emision", selection: $issueDate, displayedComponents: .date)
                Toggle("Tiene fecha de vencimiento", isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker("Vence el", selection: $dueDate, in: issueDate..., displayedComponents: .date)
                }
            }

            Section("Items") {
                ForEach($items) { $item in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Descripcion", text: $item.description)
                        HStack {
                            TextField("Cantidad", text: $item.quantityText)
                                .keyboardType(.decimalPad)
                                .frame(width: 70)
                            TextField("Precio unitario", text: $item.unitPriceText)
                                .keyboardType(.decimalPad)
                            Spacer()
                            Text(item.lineTotal, format: .currency(code: "USD"))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onDelete { items.remove(atOffsets: $0) }

                Button {
                    items.append(InvoiceItemDraft())
                } label: {
                    Label("Agregar item", systemImage: "plus.circle")
                }

                Button {
                    showingProductPicker = true
                } label: {
                    Label("Agregar desde catalogo", systemImage: "tag")
                }
            }

            Section("Notas (opcional)") {
                TextField("Notas", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section {
                LabeledContent("Total") {
                    Text(subtotal, format: .currency(code: "USD"))
                        .font(.title3.bold())
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red).font(.footnote)
                }
            }
        }
        .navigationTitle("Nueva \(docType.displayName.lowercased())")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving { ProgressView() } else { Text("Guardar") }
                }
                .disabled(!isValid || isSaving)
            }
        }
        .sheet(isPresented: $showingProductPicker) {
            NavigationStack {
                ProductPickerView(viewModel: productsViewModel) { product in
                    var draft = InvoiceItemDraft()
                    draft.productId = product.id
                    draft.description = product.name
                    draft.unitPriceText = NSDecimalNumber(decimal: product.salePrice).stringValue
                    items.append(draft)
                }
            }
        }
        .task {
            guard let userId = appState.currentUserId else { return }
            await accountsViewModel.refresh(userId: userId)
            await productsViewModel.refresh(userId: userId)
            if selectedAccountId == nil {
                selectedAccountId = accountsViewModel.accounts.first?.id
            }
        }
    }

    private func save() async {
        guard let userId = appState.currentUserId, let accountId = selectedAccountId else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            try await viewModel.create(
                NewInvoice(
                    userId: userId,
                    accountId: accountId,
                    docType: docType,
                    number: nil,
                    customerName: customerName,
                    customerContact: customerContact.isEmpty ? nil : customerContact,
                    issueDate: InvoiceDateFormat.string(from: issueDate),
                    dueDate: hasDueDate ? InvoiceDateFormat.string(from: dueDate) : nil,
                    subtotal: subtotal,
                    total: subtotal,
                    notes: notes.isEmpty ? nil : notes
                ),
                items: items
            )
            dismiss()
        } catch {
            errorMessage = "No se pudo guardar: \(error.localizedDescription)"
        }
    }
}

private struct ProductPickerView: View {
    @ObservedObject var viewModel: ProductsViewModel
    @Environment(\.dismiss) private var dismiss
    let onPick: (CatalogProduct) -> Void

    var body: some View {
        List(viewModel.products) { product in
            Button {
                onPick(product)
                dismiss()
            } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text(product.name).foregroundStyle(.primary)
                        Text(product.salePrice, format: .currency(code: "USD"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .navigationTitle("Catalogo")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cerrar") { dismiss() }
            }
        }
        .overlay {
            if viewModel.products.isEmpty {
                ContentUnavailableView(
                    "Sin productos",
                    systemImage: "tag",
                    description: Text("Agrega productos desde Ajustes > Catalogo y precios.")
                )
            }
        }
    }
}
