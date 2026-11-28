import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// «Verifica tus ingresos» (1.1.0). Para el cashback, los ingresos anotados
/// cuentan hasta el tope sin verificar (US$3,000 al mes en Panamá). Quien
/// gana más sube un documento; el equipo lo revisa y desde entonces cuenta
/// el monto aprobado por 6 meses. El documento se borra al revisarlo.
struct IncomeVerificationView: View {
    @EnvironmentObject private var appState: AppState
    @State private var status: IncomeStatus?
    @State private var kind: IncomeDocumentKind = .talonario
    @State private var consent = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isImportingPDF = false
    @State private var fileData: Data?
    @State private var fileIsPDF = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var didSend = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Verifica tus ingresos")
                        .font(.title3.bold())
                    Text("Tu cashback se respalda con lo que ganas. Sin verificar, cuentan hasta \(capText) al mes. Si ganas más, sube un documento y, al aprobarlo, cuenta tu ingreso completo durante 6 meses.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if let status {
                Section("Tu estado") {
                    if status.isVerified, let verified = status.verifiedIncome {
                        Label("Ingreso verificado: \(verified.formatted(.appCurrency)) al mes", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(MonAviBrand.primary)
                        if let until = status.verifiedUntil {
                            Text("Vigente hasta \(until)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else if status.hasPendingRequest || didSend {
                        Label("Tu documento está en revisión. Te avisaremos.", systemImage: "hourglass")
                    } else if status.requestStatus == "rechazada" {
                        Label("No pudimos verificar tu último documento.", systemImage: "xmark.circle")
                            .foregroundStyle(MonAviBrand.alert)
                        if let note = status.requestNote {
                            Text(note).font(.footnote).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Ingresos anotados en los últimos 30 días: \(status.income30d.formatted(.appCurrency))")
                    }
                    if status.inReview {
                        Label("Tu cashback está en revisión: lo nuevo queda pendiente hasta que terminemos.", systemImage: "shield.lefthalf.filled")
                            .font(.footnote)
                    }
                }
            }

            if !(status?.hasPendingRequest ?? false) && !didSend {
                Section("Documento") {
                    Picker("Tipo", selection: $kind) {
                        ForEach(IncomeDocumentKind.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Elegir foto", systemImage: "photo")
                    }
                    Button {
                        isImportingPDF = true
                    } label: {
                        Label("Elegir PDF", systemImage: "doc")
                    }
                    if fileData != nil {
                        Label(fileIsPDF ? L("PDF listo para enviar") : L("Foto lista para enviar"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(MonAviBrand.primary)
                    }
                }

                Section {
                    Toggle(isOn: $consent) {
                        Text("Acepto que MonAvi revise este documento solo para verificar mis ingresos. Se borra al terminar la revisión.")
                            .font(.footnote)
                    }
                    Button {
                        Task { await send() }
                    } label: {
                        HStack {
                            if isSending { ProgressView() }
                            Text("Enviar para revisión")
                                .bold()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(fileData == nil || !consent || isSending)
                } footer: {
                    Text("Asegúrate de que se vean tu nombre y el monto. Solo el equipo de MonAvi lo ve.")
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(MonAviBrand.alert)
                }
            }
        }
        .navigationTitle("Verificar ingresos")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .onChange(of: photoItem) { _, item in
            Task { await loadPhoto(item) }
        }
        .fileImporter(isPresented: $isImportingPDF, allowedContentTypes: [.pdf]) { result in
            loadPDF(result)
        }
    }

    private var capText: String {
        (status?.cap ?? 3000).formatted(.appCurrency)
    }

    private func refresh() async {
        status = try? await IncomeVerificationService.status()
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        // JPEG liviano (también convierte HEIC): suficiente para leer el documento.
        let maxSide: CGFloat = 2200
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        fileData = resized.jpegData(compressionQuality: 0.8)
        fileIsPDF = false
    }

    private func loadPDF(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        guard data.count <= 10 * 1024 * 1024 else {
            errorMessage = L("El PDF pesa más de 10 MB. Prueba con una foto o un PDF más liviano.")
            return
        }
        fileData = data
        fileIsPDF = true
    }

    private func send() async {
        guard let userId = appState.currentUserId, let fileData else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            try await IncomeVerificationService.submit(userId: userId, data: fileData, isPDF: fileIsPDF, kind: kind)
            didSend = true
            self.fileData = nil
            await refresh()
        } catch {
            errorMessage = L("No se pudo enviar el documento. Revisa tu conexión e intenta de nuevo.")
        }
    }
}
