import SwiftUI

struct InvoicesView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = InvoicesViewModel()
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            List {
                if viewModel.invoices.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView(
                        "Sin facturas todavia",
                        systemImage: "doc.text",
                        description: Text("Crea una factura, remision o cuenta por cobrar para tus clientes.")
                    )
                }

                ForEach(viewModel.invoices) { invoice in
                    NavigationLink {
                        InvoiceDetailView(invoice: invoice, invoicesViewModel: viewModel)
                    } label: {
                        InvoiceRow(invoice: invoice)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        let invoice = viewModel.invoices[index]
                        Task { await viewModel.delete(invoice) }
                    }
                }
            }
            .navigationTitle("Facturas")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink {
                        BusinessSettingsView()
                    } label: {
                        Image(systemName: "building.2.fill")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                NavigationStack {
                    AddInvoiceView(viewModel: viewModel)
                }
            }
            .task {
                guard let userId = appState.currentUserId else { return }
                await viewModel.refresh(userId: userId)
            }
            .refreshable {
                guard let userId = appState.currentUserId else { return }
                await viewModel.refresh(userId: userId)
            }
            .alert("Algo salio mal", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
}

private struct InvoiceRow: View {
    let invoice: Invoice

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(invoice.number ?? invoice.docType.displayName)
                    .font(.headline)
                Spacer()
                Text(invoice.total, format: .currency(code: "USD"))
                    .font(.headline)
            }

            HStack {
                Text(invoice.customerName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                statusBadge
            }

            if let countdown = invoice.dueCountdownLabel {
                Text(countdown)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(invoice.isOverdue ? .red : .orange)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusBadge: some View {
        Text(invoice.status.displayName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColor.opacity(0.15), in: Capsule())
            .foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        switch invoice.status {
        case .emitida: return .blue
        case .entregada: return .orange
        case .pagada: return .green
        case .anulada: return .gray
        }
    }
}
