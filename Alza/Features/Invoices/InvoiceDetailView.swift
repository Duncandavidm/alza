import SwiftUI
import UIKit

struct InvoiceDetailView: View {
    @EnvironmentObject private var appState: AppState
    let invoice: Invoice
    @ObservedObject var invoicesViewModel: InvoicesViewModel

    @State private var business: BusinessSettings?
    @State private var items: [InvoiceItem] = []
    @State private var logoImage: Image?
    @State private var isLoading = true

    @State private var shareFile: ShareFile?
    @State private var isMarkingPaid = false
    @State private var showingReceiptAnimation = false
    @State private var pendingReceipt: PaymentReceipt?
    @State private var completedReceipt: PaymentReceipt?
    @State private var errorMessage: String?

    private var currentInvoice: Invoice {
        invoicesViewModel.invoices.first { $0.id == invoice.id } ?? invoice
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if isLoading {
                    ProgressView().padding(.top, 60)
                } else if let business {
                    InvoiceDocumentView(business: business, invoice: currentInvoice, items: items, logoImage: logoImage)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(radius: 8, y: 4)
                        .padding(.horizontal)

                    actions
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(currentInvoice.number ?? currentInvoice.docType.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(item: $shareFile) { file in
            ActivityShareSheet(items: [file.url])
        }
        .overlay {
            if showingReceiptAnimation {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    ReceiptStampView(
                        description: "\(currentInvoice.docType.displayName) \(currentInvoice.number ?? "")",
                        amount: currentInvoice.total,
                        message: "Pago de \(currentInvoice.customerName) registrado."
                    )
                    .onTapGesture { finishPaidAnimation() }
                }
                .task {
                    try? await Task.sleep(for: .seconds(2.2))
                    finishPaidAnimation()
                }
            }
        }
        .sheet(item: $completedReceipt) { receipt in
            if let business {
                NavigationStack {
                    PaymentReceiptView(business: business, invoice: currentInvoice, receipt: receipt, logoImage: logoImage)
                }
            }
        }
        .alert("Algo salio mal", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if currentInvoice.status == .emitida {
                Button {
                    Task { await invoicesViewModel.markDelivered(currentInvoice) }
                } label: {
                    Label("Marcar entregada", systemImage: "shippingbox.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if currentInvoice.status != .pagada && currentInvoice.status != .anulada {
                Button {
                    markPaid()
                } label: {
                    if isMarkingPaid {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label("Marcar pagada", systemImage: "checkmark.seal.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isMarkingPaid)
            }

            Button {
                guard let business else { return }
                shareFile = ShareFileRenderer.renderPNG(
                    InvoiceDocumentView(business: business, invoice: currentInvoice, items: items, logoImage: logoImage)
                ).map(ShareFile.init)
            } label: {
                Label("Compartir", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal)
    }

    private func load() async {
        guard let userId = appState.currentUserId else { return }
        isLoading = true
        defer { isLoading = false }

        async let businessTask = try? BusinessSettingsService.fetch(userId: userId)
        async let itemsTask = try? invoicesViewModel.fetchItems(invoiceId: invoice.id)

        business = await businessTask
        items = await itemsTask ?? []

        if let path = business?.logoPath, let url = LogoUploadService.publicURL(forPath: path) {
            logoImage = await Self.loadImage(from: url)
        }
    }

    private static func loadImage(from url: URL) async -> Image? {
        guard let (data, _) = try? await URLSession.shared.data(from: url), let uiImage = UIImage(data: data) else {
            return nil
        }
        return Image(uiImage: uiImage)
    }

    private func markPaid() {
        guard let userId = appState.currentUserId else { return }
        isMarkingPaid = true
        Task {
            do {
                let receipt = try await invoicesViewModel.markPaid(currentInvoice, userId: userId)
                completedReceipt = nil
                showingReceiptAnimation = true
                pendingReceipt = receipt
            } catch {
                errorMessage = "No se pudo marcar como pagada: \(error.localizedDescription)"
            }
            isMarkingPaid = false
        }
    }

    private func finishPaidAnimation() {
        showingReceiptAnimation = false
        completedReceipt = pendingReceipt
        pendingReceipt = nil
    }
}
