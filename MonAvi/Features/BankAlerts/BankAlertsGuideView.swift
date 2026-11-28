import SwiftUI

/// Ajustes > Automatizaciones > "Tus movimientos del banco": como armar la
/// automatizacion de Atajos (Notificación, Mensaje o Correo) que llama a
/// DetectBankMovementIntent, y un campo para probar con un aviso de ejemplo.
struct BankAlertsGuideView: View {
    private enum Trigger: String, CaseIterable, Identifiable {
        case notification = "Notificación"
        case sms = "SMS"
        case email = "Correo"
        var id: String { rawValue }
    }

    @State private var trigger: Trigger = .notification
    @State private var sampleText = "Compra por B/.12.40 en CAFE LA ESQUINA con tarjeta terminada en 4021"
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(MonAviBrand.primary)
                    Text("Tus movimientos del banco, solos")
                        .font(.system(.title2, design: MonAviBrand.fontDesign, weight: .bold))
                    Text("Cuando llega el aviso de tu banco o de Yappy, MonAvi lo detecta y te pregunta si quieres registrarlo. Nada se guarda sin que lo confirmes.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("Cómo funciona") {
                Label("Llega la notificación, el SMS o el correo de tu banco", systemImage: "1.circle.fill")
                Label("MonAvi lee el monto y el comercio en tu teléfono", systemImage: "2.circle.fill")
                Label("Te avisa «Pago detectado» o «Ingreso detectado»: tocas Registrar, Revisar o Descartar", systemImage: "3.circle.fill")
            }
            .font(.subheadline)

            Section {
                Picker("Aviso", selection: $trigger) {
                    ForEach(Trigger.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                }
                .pickerStyle(.segmented)
                ForEach(Array(steps(for: trigger).enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(MonAviBrand.primary))
                        Text(.init(step))
                            .font(.subheadline)
                    }
                    .padding(.vertical, 2)
                }
                Button {
                    if let url = URL(string: "shortcuts://") { UIApplication.shared.open(url) }
                } label: {
                    Label("Abrir Atajos", systemImage: "arrow.up.forward.app.fill")
                }
            } header: {
                Text("Armar la automatización (una sola vez)")
            } footer: {
                Text(footer(for: trigger))
            }

            Section {
                TextField("Pega aquí un aviso de tu banco", text: $sampleText, axis: .vertical)
                    .lineLimit(2...5)
                    .font(.footnote)
                Button {
                    Task { await test() }
                } label: {
                    Label(isTesting ? "Probando…" : "Probar con este aviso", systemImage: "play.circle.fill")
                }
                .disabled(isTesting || sampleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let testResult {
                    Text(testResult)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Pruébalo")
            } footer: {
                Text("Te llega la notificación «Pago detectado» y el movimiento queda en Hoy por confirmar. Si no lo quieres, descártalo.")
            }

            Section {
                Label("El texto del aviso se lee en tu teléfono y no se guarda: solo el movimiento que confirmes.", systemImage: "lock.fill")
                Label("Los códigos de seguridad, las compras rechazadas y las promociones se ignoran siempre.", systemImage: "hand.raised.fill")
                Label("Si el mismo movimiento llega dos veces (notificación y SMS), se cuenta una sola vez.", systemImage: "square.on.square")
                Label("A veces iOS no ejecuta la automatización con todas las notificaciones. Si falta un movimiento, anótalo a mano.", systemImage: "info.circle.fill")
            } header: {
                Text("Bueno saber")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .navigationTitle("Movimientos del banco")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func steps(for trigger: Trigger) -> [String] {
        let common = [
            L("Marca **Ejecutar inmediatamente** y apaga **Notificar al ejecutar**. Toca **Siguiente**."),
            L("Toca **Nueva automatización en blanco**, busca **MonAvi** y elige **Detectar movimiento del banco**."),
            L("En **Aviso**, elige la variable **Entrada del atajo**. Si quieres, escribe el nombre del banco en **App o banco**. Toca **Listo**."),
        ]
        switch trigger {
        case .notification:
            return [
                L("Abre **Atajos**, ve a **Automatización** y toca **+**."),
                L("Elige **Notificación** y escoge la app de tu banco o **Yappy**."),
                L("Opcional: filtra por palabras como **compra**, **pagaste** o **recibiste**."),
            ] + common
        case .sms:
            return [
                L("Abre **Atajos**, ve a **Automatización** y toca **+**."),
                L("Elige **Mensaje**. En **Remitente**, escoge el número o contacto de tu banco (o usa **El mensaje contiene** «compra»)."),
            ] + common
        case .email:
            return [
                L("Abre **Atajos**, ve a **Automatización** y toca **+**."),
                L("Elige **Correo**. En **Remitente**, escribe el correo de avisos de tu banco."),
            ] + common
        }
    }

    private func footer(for trigger: Trigger) -> String {
        switch trigger {
        case .notification:
            return L("Necesitas la versión más reciente de iOS. Si no ves «Notificación» en la lista, actualiza tu teléfono o usa SMS o correo.")
        case .sms:
            return L("Funciona con los bancos que te mandan un SMS por cada compra o transferencia. El SMS tiene que llegar a la app Mensajes.")
        case .email:
            return L("Funciona con la app Mail de Apple. Activa en tu banca en línea los avisos por correo de cada movimiento.")
        }
    }

    @MainActor
    private func test() async {
        isTesting = true
        defer { isTesting = false }
        guard BankAlertParser.parse(sampleText) != nil else {
            testResult = L("No encontramos un movimiento en ese texto. El aviso tiene que traer el monto con su moneda (B/., $ o USD) y decir si fue una compra, un pago o un dinero recibido.")
            return
        }
        if await DetectedMovementActions.detect(text: sampleText, source: "Prueba") != nil {
            testResult = L("¡Listo! Te llegó «Pago detectado» y quedó en Hoy por confirmar.")
        } else {
            testResult = L("Ya tienes uno igual por confirmar en Hoy (el mismo monto hace pocos minutos).")
        }
    }
}
