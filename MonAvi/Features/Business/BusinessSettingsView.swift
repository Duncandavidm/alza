import SwiftUI
import PhotosUI

/// "Mi negocio": lo que el usuario configura una vez y despues se usa
/// para pintar todas sus facturas, remisiones y recibos de pago con su
/// propia marca (logo, color, tipografia) en vez de un diseño generico.
struct BusinessSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = BusinessSettingsViewModel()
    @State private var logoItem: PhotosPickerItem?

    var body: some View {
        Form {
            Section("Logo") {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        logoPreview

                        PhotosPicker(selection: $logoItem, matching: .images) {
                            if viewModel.isUploadingLogo {
                                ProgressView()
                            } else {
                                Text(viewModel.logoPath == nil ? "Subir logo" : "Cambiar logo")
                            }
                        }
                        .disabled(viewModel.isUploadingLogo)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            }

            Section("Datos del negocio") {
                TextField("Nombre del negocio", text: $viewModel.businessName)
                TextField("NIT / identificacion fiscal", text: $viewModel.taxId)
                TextField("Direccion", text: $viewModel.address)
                TextField("Telefono", text: $viewModel.phone)
                    .keyboardType(.phonePad)
            }

            Section("Marca") {
                ColorPicker("Color de marca", selection: $viewModel.brandColor, supportsOpacity: false)

                Picker("Tipografia", selection: $viewModel.brandFont) {
                    ForEach(BrandFont.allCases) { font in
                        Text(font.displayName)
                            .font(.system(.body, design: font.design))
                            .tag(font)
                    }
                }
            }

            Section {
                brandPreview
            } header: {
                Text("Asi se va a ver en tus facturas")
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Mi negocio")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    guard let userId = appState.currentUserId else { return }
                    Task { await viewModel.save(userId: userId) }
                } label: {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Text("Guardar")
                    }
                }
                .disabled(viewModel.isSaving)
            }
        }
        .task {
            guard let userId = appState.currentUserId else { return }
            await viewModel.load(userId: userId)
        }
        .onChange(of: logoItem) { _, newItem in
            guard let newItem, let userId = appState.currentUserId else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    await viewModel.uploadLogo(userId: userId, imageData: data)
                }
            }
        }
    }

    @ViewBuilder
    private var logoPreview: some View {
        if let url = viewModel.logoURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else {
                    ProgressView()
                }
            }
            .frame(width: 88, height: 88)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
                .frame(width: 88, height: 88)
                .overlay(Image(systemName: "building.2.fill").foregroundStyle(.secondary))
        }
    }

    private var brandPreview: some View {
        HStack(spacing: 12) {
            logoThumb
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.businessName.isEmpty ? "Tu negocio" : viewModel.businessName)
                    .font(.system(.headline, design: viewModel.brandFont.design, weight: .bold))
                Text("Factura #0001")
                    .font(.system(.caption, design: viewModel.brandFont.design))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(viewModel.brandColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(viewModel.brandColor, lineWidth: 1.5))
    }

    @ViewBuilder
    private var logoThumb: some View {
        if let url = viewModel.logoURL {
            AsyncImage(url: url) { phase in
                (phase.image ?? Image(systemName: "building.2.fill"))
                    .resizable()
                    .scaledToFit()
            }
            .frame(width: 32, height: 32)
        } else {
            Circle().fill(viewModel.brandColor).frame(width: 10, height: 10)
        }
    }
}
