import SwiftUI
import PhotosUI
import UIKit

/// Hoja principal de "Facturas que suman": camara en vivo (lo normal) o,
/// si la factura llego como captura de pantalla, una foto de la galeria.
/// Ambas desembocan en `ScanReviewView`.
///
/// Escaneo seguido: al guardar una factura la camara queda abierta para la
/// siguiente (con el conteo arriba) hasta que el usuario toca "Listo".
/// Con `linkTo` (la factura de un gasto recien anotado) se cierra al
/// guardar esa una.
struct ScanInvoiceView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: DgiReceiptsViewModel
    let accounts: [Account]
    var linkTo: FinanceTransaction? = nil
    /// Una factura que llego por "Compartir → MonAvi" (PDF o imagen): se
    /// lee al abrir, sin pasar por la camara.
    var initialPayload: String? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var savedCount = 0
    /// QR ya guardados en esta sesion de camara: si la misma factura sigue
    /// frente a la camara despues de guardarla, no se vuelve a abrir.
    @State private var savedPayloads: Set<String> = []
    @State private var pendingPayload: String?
    @State private var didHandleInitialPayload = false

    @State private var isProcessing = false
    @State private var progressText = "Validando..."
    @State private var invalidMessage: String?
    @State private var draft: ScanDraft?
    @State private var galleryItem: PhotosPickerItem?

    /// La factura llego como archivo (PDF o imagen compartida): no hace
    /// falta la camara, solo esperar la lectura con el gato.
    private var isFromFile: Bool { initialPayload != nil }

    var body: some View {
        NavigationStack {
            Group {
                if isFromFile {
                    fileSection
                } else {
                    VStack(spacing: 0) {
                        cameraSection
                            .overlay(alignment: .bottom) { photoButton }
                            .overlay(alignment: .top) { savedBanner }

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
                }
            }
            .navigationTitle(isFromFile ? "Tu factura" : "Escanear factura")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(savedCount > 0 ? "Listo" : "Cancelar") { dismiss() }
                }
            }
            .sheet(item: $draft, onDismiss: {
                // Factura compartida: si cierra la revision sin guardar, no
                // hay camara detras a la que volver.
                if isFromFile { dismiss() }
            }) { scanDraft in
                ScanReviewView(
                    viewModel: viewModel,
                    accounts: accounts,
                    onSaved: { handleSaved() },
                    draft: scanDraft
                )
            }
            .task {
                guard let initialPayload, !didHandleInitialPayload else { return }
                didHandleInitialPayload = true
                handleScan(initialPayload)
            }
        }
    }

    /// Factura compartida: el gato juega mientras se lee; si falla, el
    /// motivo y un boton para cerrar.
    private var fileSection: some View {
        VStack(spacing: 20) {
            Spacer()
            if let invalidMessage, !isProcessing {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundStyle(MonAviBrand.primary)
                Text(invalidMessage)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("Cerrar") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(MonAviBrand.primary)
            } else {
                MonAviCatLoader(message: isProcessing ? progressText : "Abriendo tu factura…")
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private var cameraSection: some View {
        DgiQRScannerView(
            onScan: { raw in handleScan(raw) },
            onError: { message in invalidMessage = message }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    @ViewBuilder
    private var savedBanner: some View {
        if savedCount > 0 {
            Label(
                savedCount == 1
                    ? "1 factura guardada · escanea la siguiente"
                    : "\(savedCount) facturas guardadas · escanea la siguiente",
                systemImage: "checkmark.circle.fill"
            )
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(MonAviBrand.primary, in: Capsule())
            .foregroundStyle(.white)
            .padding(.top, 16)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func handleSaved() {
        if let pendingPayload { savedPayloads.insert(pendingPayload) }
        pendingPayload = nil
        if linkTo != nil || initialPayload != nil {
            dismiss()
            return
        }
        withAnimation { savedCount += 1 }
        invalidMessage = nil
        UINotificationFeedbackGenerator().notificationOccurred(.success)
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
        guard !isProcessing, draft == nil else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !savedPayloads.contains(trimmed) else {
            invalidMessage = "Esa factura ya la guardaste. Apunta a la siguiente."
            return
        }

        Task {
            guard let userId = appState.currentUserId else { return }
            isProcessing = true
            progressText = isFromFile ? "Revisando tu factura…" : "Validando..."
            invalidMessage = nil
            defer { isProcessing = false }

            switch await viewModel.processScan(raw: trimmed, userId: userId) {
            case .invalid(let message):
                invalidMessage = message
            case .ready(let scanDraft):
                // Intenta leer la factura completa (monto, comercio,
                // productos); si no se puede, sigue el flujo manual.
                progressText = "Leyendo tu factura…"
                var enriched = await viewModel.lookupInvoice(for: scanDraft)
                if let linkTo {
                    enriched.linkedTransaction = linkTo
                    enriched.splitByCategory = false
                }
                pendingPayload = trimmed
                draft = enriched
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
