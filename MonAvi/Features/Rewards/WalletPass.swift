import PassKit
import SwiftUI
import UIKit

/// "Agregar a Apple Wallet": el codigo del cupon como pase de Wallet (QR,
/// comercio, vencimiento y aviso al pasar cerca del local). El pase lo
/// arma y firma la funcion wallet-pass; si el certificado de Apple Wallet
/// todavia no esta configurado en el servidor, el boton no aparece.
@MainActor
enum WalletPassService {
    enum PassError: LocalizedError {
        case server(String)
        var errorDescription: String? {
            switch self {
            case .server(let message): return message
            }
        }
    }

    private static var cachedEnabled: Bool?

    static func isEnabled() async -> Bool {
        if let cachedEnabled { return cachedEnabled }
        guard PKAddPassesViewController.canAddPasses() else { return false }
        struct Check: Decodable { let enabled: Bool }
        guard let data = try? await call(body: ["check": true]),
              let check = try? JSONDecoder().decode(Check.self, from: data) else { return false }
        cachedEnabled = check.enabled
        return check.enabled
    }

    static func pass(for redemptionId: UUID) async throws -> PKPass {
        let data = try await call(body: ["redemption_id": redemptionId.uuidString.lowercased()])
        return try PKPass(data: data)
    }

    private static func call(body: [String: Any]) async throws -> Data {
        let session = try await SupabaseManager.shared.client.auth.session
        var request = URLRequest(url: Config.supabaseURL.appendingPathComponent("functions/v1/wallet-pass"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            struct Failure: Decodable { let error: String }
            let message = (try? JSONDecoder().decode(Failure.self, from: data))?.error
            throw PassError.server(message ?? "No se pudo crear el pase. Inténtalo de nuevo.")
        }
        return data
    }
}

/// Boton oficial de Apple ("Agregar a Apple Wallet").
struct AddToWalletButton: UIViewRepresentable {
    var action: () -> Void

    func makeUIView(context: Context) -> PKAddPassButton {
        let button = PKAddPassButton(addPassButtonStyle: .black)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: PKAddPassButton, context: Context) {
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}

/// Hoja nativa para agregar el pase.
struct AddPassSheet: UIViewControllerRepresentable {
    let pass: PKPass

    func makeUIViewController(context: Context) -> UIViewController {
        PKAddPassesViewController(pass: pass) ?? UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

/// Seccion para RedemptionCodeView: solo si el pase se puede crear y el
/// codigo sigue vigente.
struct WalletPassSection: View {
    let redemption: RewardRedemption

    @State private var isEnabled = false
    @State private var isLoading = false
    @State private var pass: PKPass?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isEnabled && redemption.status == .emitido && redemption.expiresAt > Date() {
                VStack(spacing: 8) {
                    if isLoading {
                        ProgressView("Preparando tu pase…")
                    } else {
                        AddToWalletButton { Task { await load() } }
                            .frame(height: 48)
                        Text("Tenlo a mano en caja, y Wallet te lo recuerda al pasar cerca del local.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .task { isEnabled = await WalletPassService.isEnabled() }
        .sheet(item: Binding(get: { pass.map(IdentifiedPass.init) }, set: { if $0 == nil { pass = nil } })) { item in
            AddPassSheet(pass: item.pass)
                .ignoresSafeArea()
        }
    }

    private struct IdentifiedPass: Identifiable {
        let pass: PKPass
        var id: String { pass.serialNumber }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            pass = try await WalletPassService.pass(for: redemption.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
