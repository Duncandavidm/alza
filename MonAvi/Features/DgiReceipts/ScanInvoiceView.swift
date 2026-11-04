import SwiftUI
import PhotosUI

/// Hoja principal de "Facturas que suman": camara en vivo, pegar el
/// link/CUFE a mano, o elegir una foto de la galeria — las tres formas
/// que pidio el modulo, todas desembocan en `ScanReviewView`.
struct ScanInvoiceView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: DgiReceiptsViewModel
    let accounts: [Account]
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable, Identifiable {
        case camera = "Camara"
        case manual = "Pegar codigo"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .camera
    @State private var manualText = ""
    @State private var isProcessing = false
    @State private var invalidMessage: String?
    @State private var draft: ScanDraft?
    @State private var galleryItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Modo", selection: $mode) {
                    ForEach(Mode.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                switch mode {
                case .camera:
                    cameraSection
                case .manual:
                    manualSection
                }

                if let invalidMessage {
                    Text(invalidMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                if isProcessing {
                    ProgressView("Validando...")
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
                    draft: scanDraft,
                    onSaved: { dismiss() }
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

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pega el link completo del codigo QR, o solo el CUFE de 66 caracteres.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            TextField("https://dgi-fep.mef.gob.pa/...", text: $manualText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            Button {
                handleScan(manualText)
            } label: {
                Text("Procesar").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(manualText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)

            Divider().padding(.vertical, 4)

            PhotosPicker(selection: $galleryItem, matching: .images) {
                Label("Elegir una foto de la galeria", systemImage: "photo.on.rectangle")
            }
            .onChange(of: galleryItem) { _, newItem in
                Task { await handleGalleryPick(newItem) }
            }

            Spacer()
        }
        .padding()
    }

    private func handleScan(_ raw: String) {
        guard !isProcessing else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        Task {
            guard let userId = appState.currentUserId else { return }
            isProcessing = true
            invalidMessage = nil
            defer { isProcessing = false }

            switch await viewModel.processScan(raw: trimmed, userId: userId) {
            case .invalid(let message):
                invalidMessage = message
            case .ready(let scanDraft):
                draft = scanDraft
            }
        }
    }

    private func handleGalleryPick(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        guard let payload = GalleryQRScanner.scan(imageData: data) else {
            invalidMessage = "No se encontro un codigo QR en esa foto."
            return
        }
        handleScan(payload)
    }
}
