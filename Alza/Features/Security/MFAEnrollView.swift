import SwiftUI

/// Activar verificacion en 2 pasos: muestra el QR (y el secreto como
/// respaldo) para escanear con una app de autenticacion (Google
/// Authenticator, Authy, 1Password...), y pide el codigo de 6 digitos
/// para confirmar que de verdad quedo enlazada antes de darla por activa.
struct MFAEnrollView: View {
    @Environment(\.dismiss) private var dismiss
    let onEnrolled: () -> Void

    @State private var enrollment: MFAService.EnrollResult?
    @State private var code = ""
    @State private var isLoading = true
    @State private var isVerifying = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if isLoading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                } else if let enrollment {
                    Section {
                        VStack(spacing: 12) {
                            if let qrImage = QRCodeGenerator.image(from: enrollment.uri) {
                                qrImage
                                    .interpolation(.none)
                                    .resizable()
                                    .frame(width: 200, height: 200)
                            }
                            Text("Escanea este codigo con Google Authenticator, Authy, 1Password o la app de autenticacion que prefieras.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }

                    Section("¿No puedes escanear?") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Escribe este codigo a mano en tu app:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(enrollment.secret)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }

                    Section("Confirma el codigo") {
                        TextField("Codigo de 6 digitos", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                    }

                    if let errorMessage {
                        Section {
                            Text(errorMessage).foregroundStyle(AlzaBrand.alert).font(.footnote)
                        }
                    }
                }
            }
            .navigationTitle("Verificacion en 2 pasos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await confirm() }
                    } label: {
                        if isVerifying { ProgressView() } else { Text("Activar") }
                    }
                    .disabled(enrollment == nil || code.count != 6 || isVerifying)
                }
            }
            .task { await startEnrollment() }
        }
    }

    private func startEnrollment() async {
        isLoading = true
        defer { isLoading = false }
        do {
            enrollment = try await MFAService.enrollTOTP()
        } catch {
            errorMessage = "No se pudo iniciar el enrolamiento: \(error.localizedDescription)"
        }
    }

    private func confirm() async {
        guard let enrollment else { return }
        isVerifying = true
        defer { isVerifying = false }
        do {
            try await MFAService.verify(factorId: enrollment.factorId, code: code)
            onEnrolled()
            dismiss()
        } catch {
            errorMessage = "Codigo incorrecto o expirado. Intenta de nuevo."
        }
    }
}
