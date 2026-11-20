import SwiftUI

/// "Conecta tus pagos con Wallet": paso a paso para armar una
/// automatizacion personal en la app Atajos (disparador "Transacción" de
/// Wallet, iOS 17+) que llama a `AddMonAviExpenseIntent`. No hay
/// integracion con Visa/Mastercard: el bono por pagar con tarjeta en un
/// comercio aliado se valida con la factura DGI escaneada (que dice la
/// forma de pago), asi nadie puede inventar compras.
///
/// Reemplaza la entrada a LinkedCardsView (vincular tarjeta a mano), que
/// dependia de un feed de procesadores de tarjeta que no se va a usar.
struct WalletAutomationGuideView: View {
    private struct Step: Identifiable {
        let id: Int
        let text: String
    }

    private let steps: [Step] = [
        Step(id: 1, text: "Abre la app **Atajos** y toca **Automatización**."),
        Step(id: 2, text: "Toca **Nueva automatización** (o el botón **+**)."),
        Step(id: 3, text: "Elige **Transacción** (Wallet)."),
        Step(id: 4, text: "Elige las tarjetas de Wallet con las que pagas."),
        Step(id: 5, text: "Marca **Ejecutar inmediatamente** y toca **Siguiente**."),
        Step(id: 6, text: "Toca **Nueva automatización en blanco**, busca **MonAvi** y elige la acción **Anotar un gasto en MonAvi**."),
        Step(id: 7, text: "En **Monto**, elige la variable **Cantidad** (o Monto) de la transacción; en **Comercio**, elige **Comercio**. Si quieres, elige también la cuenta."),
        Step(id: 8, text: "Toca **Listo**. ¡Ya está!")
    ]

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "wallet.pass.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(MonAviBrand.primary)
                    Text("Conecta tus pagos con Wallet")
                        .font(.system(.title2, design: MonAviBrand.fontDesign, weight: .bold))
                    Text("Así cada pago con tarjeta se anota solo en MonAvi, sin abrir la app.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section {
                ForEach(steps) { step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(step.id)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(MonAviBrand.primary))
                        Text(LocalizedStringKey(step.text))
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }

                if let url = URL(string: "shortcuts://") {
                    Link(destination: url) {
                        Label("Abrir Atajos", systemImage: "square.2.layers.3d.fill")
                    }
                }
            } header: {
                Text("Paso a paso")
            } footer: {
                Text("Necesitas iOS 17 o más y tus tarjetas en Wallet.")
            }

            Section {
                benefit(
                    icon: "creditcard.fill",
                    text: "Si pagas con tarjeta en un comercio aliado y escaneas la factura, ganas tu cashback más el bono extra del comercio."
                )
                benefit(
                    icon: "checkmark.seal.fill",
                    text: "Tu factura es la prueba del pago: dice el comercio, el monto y que pagaste con tarjeta. Así nadie puede inventar compras."
                )
                benefit(
                    icon: "bell.badge.fill",
                    text: "Cuando pagues en un comercio aliado, te avisamos para que no se te olvide escanear la factura."
                )
            } header: {
                Text("Pagar con tarjeta en comercios aliados")
            } footer: {
                Text("MonAvi no se conecta a tu banco ni a Visa o Mastercard: solo recibe el monto y el comercio que Atajos le pasa.")
            }
        }
        .navigationTitle("Pagos con Wallet")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func benefit(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(MonAviBrand.primary)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}
