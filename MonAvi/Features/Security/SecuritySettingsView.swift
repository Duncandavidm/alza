import SwiftUI

/// Ajustes > Seguridad: desbloqueo con Face ID / Touch ID.
struct SecuritySettingsView: View {
    @ObservedObject private var lock = BiometricLock.shared
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var isAvailable: Bool { BiometricLock.availableKind != .none }

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(
                    get: { lock.isEnabled },
                    set: { newValue in
                        Task {
                            isSaving = true
                            errorMessage = nil
                            let ok = await lock.setEnabled(newValue)
                            isSaving = false
                            if !ok { errorMessage = "No se pudo verificar tu identidad. Intenta de nuevo." }
                        }
                    }
                )) {
                    Label("Desbloquear con \(BiometricLock.methodName)", systemImage: BiometricLock.systemImage)
                }
                .tint(MonAviBrand.primary)
                .disabled(!isAvailable || isSaving)
            } header: {
                Text("Acceso rápido y seguro")
            } footer: {
                if isAvailable {
                    Text("Al abrir MonAvi, o al volver después de 30 segundos, te pide \(BiometricLock.methodName). Si no funciona, puedes usar el código de tu iPhone. Mientras cambias de app, tu información queda oculta.")
                } else {
                    Text("Configura Face ID, Touch ID o un código en los Ajustes de tu iPhone para usar esta opción.")
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(MonAviBrand.alert).font(.footnote)
                }
            }
        }
        .navigationTitle("Seguridad")
    }
}
