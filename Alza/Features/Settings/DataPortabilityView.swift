import SwiftUI
import UniformTypeIdentifiers

/// Exportar/importar CSV (inspirado en MonAi 1.10: "las transacciones
/// recurrentes ahora se incluyen en la exportacion e importacion de CSV").
struct DataPortabilityView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = DataPortabilityViewModel()
    @StateObject private var accountsViewModel = DashboardViewModel()

    @State private var isPickingFile = false
    @State private var pendingImportURL: URL?
    @State private var showingImportConfirm = false
    @State private var selectedAccountId: UUID?

    var body: some View {
        List {
            Section("Exportar") {
                Text("Descarga todos tus movimientos y recurrentes en un CSV.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    Task { await export() }
                } label: {
                    if viewModel.isExporting {
                        ProgressView()
                    } else {
                        Label("Exportar CSV", systemImage: "square.and.arrow.up")
                    }
                }
                .disabled(viewModel.isExporting)

                if let url = viewModel.exportURL {
                    ShareLink(item: url) {
                        Label("Compartir \(url.lastPathComponent)", systemImage: "square.and.arrow.up.circle")
                    }
                }
            }

            Section("Importar") {
                Text("Elige un CSV exportado de Avi para agregar esos movimientos a una cuenta.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    isPickingFile = true
                } label: {
                    Label("Elegir archivo CSV", systemImage: "square.and.arrow.down")
                }
                .disabled(viewModel.isImporting)

                if viewModel.isImporting {
                    ProgressView("Importando...")
                }

                if let summary = viewModel.importSummary {
                    Text(summary).font(.footnote).foregroundStyle(.green)
                }
            }
        }
        .navigationTitle("Exportar / Importar")
        .task { await refreshAccounts() }
        .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            switch result {
            case .success(let url):
                pendingImportURL = url
                showingImportConfirm = true
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showingImportConfirm) {
            if let url = pendingImportURL {
                ImportConfirmSheet(
                    url: url,
                    accounts: accountsViewModel.accounts,
                    selectedAccountId: $selectedAccountId
                ) { accountId in
                    Task {
                        guard let userId = appState.currentUserId else { return }
                        await viewModel.importCSV(from: url, userId: userId, accountId: accountId)
                        showingImportConfirm = false
                    }
                }
            }
        }
        .alert("Algo salio mal", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func export() async {
        guard let userId = appState.currentUserId else { return }
        await viewModel.export(userId: userId)
    }

    private func refreshAccounts() async {
        guard let userId = appState.currentUserId else { return }
        await accountsViewModel.refresh(userId: userId)
        selectedAccountId = selectedAccountId ?? accountsViewModel.accounts.first?.id
    }
}

private struct ImportConfirmSheet: View {
    let url: URL
    let accounts: [Account]
    @Binding var selectedAccountId: UUID?
    let onConfirm: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Text("Se va a importar \(url.lastPathComponent) a esta cuenta:")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Picker("Cuenta", selection: $selectedAccountId) {
                    ForEach(accounts) { account in
                        Text(account.name).tag(Optional(account.id))
                    }
                }
            }
            .navigationTitle("Importar CSV")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importar") {
                        if let accountId = selectedAccountId {
                            onConfirm(accountId)
                            dismiss()
                        }
                    }
                    .disabled(selectedAccountId == nil)
                }
            }
        }
    }
}
