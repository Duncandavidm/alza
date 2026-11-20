import SwiftUI

/// "Registra con doble toque": paso a paso para que tocar dos veces la
/// parte de atrás del iPhone (Tocar atrás, en Accesibilidad) abra MonAvi
/// escuchando, via un atajo que corre `RecordByVoiceIntent`. Mismo estilo
/// que WalletAutomationGuideView.
struct VoiceBackTapGuideView: View {
    private struct Step: Identifiable {
        let id: Int
        let text: String
        var note: String? = nil
    }

    private let steps: [Step] = [
        Step(
            id: 1,
            text: "Abre la app **Atajos**, toca **+**, busca **MonAvi** y elige **Registrar gasto o ingreso con voz**. Guarda el atajo con el nombre **MonAvi voz**.",
            note: "Las acciones de MonAvi también aparecen solas en Atajos, en la sección de apps."
        ),
        Step(
            id: 2,
            text: "Ve a **Ajustes > Accesibilidad > Tocar > Tocar atrás > Doble toque** y elige **MonAvi voz**."
        ),
        Step(
            id: 3,
            text: "¡Listo! Toca dos veces la parte de atrás del iPhone (sobre la manzana), di por ejemplo «gasté 12 dólares en almuerzo» o «me pagaron 500 de salario» y MonAvi lo anota."
        )
    ]

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(MonAviBrand.primary)
                    Text("Registra con doble toque")
                        .font(.system(.title2, design: MonAviBrand.fontDesign, weight: .bold))
                    Text("Toca dos veces la parte de atrás de tu iPhone, di tu gasto o ingreso y MonAvi lo anota solo. Sin buscar la app ni escribir nada.")
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
                        VStack(alignment: .leading, spacing: 4) {
                            Text(LocalizedStringKey(step.text))
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                            if let note = step.note {
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                if let url = URL(string: "shortcuts://") {
                    Link(destination: url) {
                        Label("Abrir Atajos", systemImage: "square.2.layers.3d.fill")
                    }
                }

                Button {
                    NotificationRouter.shared.requestVoiceCapture()
                } label: {
                    Label("Probar ahora", systemImage: "mic.fill")
                }
            } header: {
                Text("Paso a paso")
            } footer: {
                Text("Tocar atrás necesita un iPhone 8 o más nuevo.")
            }

            Section {
                benefit(
                    icon: "waveform",
                    text: "También funciona con Siri: di «Oye Siri, anota en MonAvi»."
                )
                benefit(
                    icon: "checkmark.circle.fill",
                    text: "MonAvi lo guarda en tu cuenta principal y te muestra lo que anotó, con **Deshacer** y **Editar** por si algo salió mal."
                )
            } header: {
                Text("Bueno saber")
            }
        }
        .navigationTitle("Doble toque")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func benefit(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(MonAviBrand.primary)
                .frame(width: 24)
            Text(LocalizedStringKey(text))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}
