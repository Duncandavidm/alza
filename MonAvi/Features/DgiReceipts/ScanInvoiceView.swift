import SwiftUI
import PhotosUI

/// Hoja principal de "Facturas que suman": camara en vivo (lo normal) o,
/// si la factura llego como captura de pantalla, una foto de la galeria.
/// Ambas desembocan en `ScanReviewView`.
struct ScanInvoiceView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: DgiReceiptsViewModel
    let accounts: [Account]
    @Environment(\.dismiss) private var dismiss

    @State private var isProcessing = false
    @State private var progressText = "Validando..."
    @State private var invalidMessage: String?
    @State private var draft: ScanDraft?
    @State private var galleryItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                cameraSection
                    .overlay(alignment: .bottom) { photoButton }

                if let invalidMessage {
                    Text(invalidMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                if isProcessing {
                    ProgressView(progressText)
                        .padding(.bottom, 8)
                }
            }
            .navigationTitle("Escanear factura")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .sheet(item: $draft) { scanDraft in
                ScanReviewView(
                    viewModel: viewModel,
                    accounts: accounts,
                    onSaved: { dismiss() },
                    draft: scanDraft
                )
            }
        }
    }

    private var cameraSection: some View {
        DgiQRScannerView(
            onScan: { raw in handleScan(raw) },
            onError: { message in invalidMessage = message }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    /// Para facturas que llegaron como captura (correo, WhatsApp).
    private var photoButton: some View {
        PhotosPicker(selection: $galleryItem, matching: .images) {
            Label("Desde una foto", systemImage: "photo.on.rectangle")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .foregroundStyle(.white)
        }
        .padding(.bottom, 28)
        .onChange(of: galleryItem) { _, newItem in
            Task { await handleGalleryPick(newItem) }
        }
    }

    private func handleScan(_ raw: String) {
        guard !isProcessing else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        Task {
            guard let userId = appState.currentUserId else { return }
            isProcessing = true
            progressText = "Validando..."
            invalidMessage = nil
            defer { isProcessing = false }

            switch await viewModel.processScan(raw: trimmed, userId: userId) {
            case .invalid(let message):
                invalidMessage = message
            case .ready(let scanDraft):
                // Intenta leer la factura completa (monto, comercio,
                // productos); si no se puede, sigue el flujo manual.
                progressText = "Leyendo tu factura…"
                draft = await viewModel.lookupInvoice(for: scanDraft)
            }
        }
    }

    private func handleGalleryPick(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        guard let payload = GalleryQRScanner.scan(imageData: data) else {
            invalidMessage = "No se encontró un código QR en esa foto."
            return
        }
        handleScan(payload)
    }
}
