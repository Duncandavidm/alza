import SwiftUI

/// Ultimo paso del onboarding (1.0.5): escanear la primera factura. Va
/// despues de crear las cuentas (el gasto de la factura necesita una) y
/// antes de entrar a la app. "Más tarde" sigue sin escanear.
struct FirstInvoiceView: View {
    var onDone: () -> Void

    @State private var isScanning = false
    @State private var didScan = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(MonAviBrand.primary)
                .padding(28)
                .background(MonAviBrand.primary.opacity(0.12), in: Circle())

            VStack(spacing: 10) {
                Text(didScan ? "¡Primera factura lista!" : "Escanea tu primera factura")
                    .font(.system(.title2, design: MonAviBrand.fontDesign).bold())
                    .multilineTextAlignment(.center)
                Text(didScan
                     ? "Cada factura que escanees suma cashback para usar en comercios aliados."
                     : "¿Tienes a mano una factura de hoy? Escanea su código QR: el gasto se anota solo y ganas cashback para usar en comercios aliados.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)

            VStack(alignment: .leading, spacing: 12) {
                tip("🧾", "Pide factura fiscal en cada compra.")
                tip("📱", "Escanea el QR, o compártela a MonAvi si te llegó por correo o WhatsApp.")
                tip("💸", "Tu cashback se suma cuando la factura se confirma.")
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                if didScan {
                    Button { onDone() } label: {
                        Text("Empezar").font(.headline).frame(maxWidth: .infinity).frame(height: 52)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button { isScanning = true } label: {
                        Label("Escanear ahora", systemImage: "camera.fill")
                            .font(.headline).frame(maxWidth: .infinity).frame(height: 52)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Más tarde") { onDone() }
                        .font(.subheadline)
                }
            }
            .tint(MonAviBrand.primary)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .invoiceScanner(isPresented: $isScanning) {
            didScan = await hasAnyReceipt()
        }
    }

    private func tip(_ emoji: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(emoji)
            Text(text).font(.subheadline)
        }
    }

    private func hasAnyReceipt() async -> Bool {
        guard let userId = try? await SupabaseManager.shared.client.auth.session.user.id else { return false }
        struct Row: Decodable { let id: UUID }
        let rows: [Row] = (try? await SupabaseManager.shared.client
            .from("dgi_receipts")
            .select("id")
            .eq("user_id", value: userId)
            .limit(1)
            .execute()
            .value) ?? []
        return !rows.isEmpty
    }
}
