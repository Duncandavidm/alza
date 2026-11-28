import SwiftUI

/// Ilustración de los botones de MonAvi en el Centro de control (dibujada
/// con SwiftUI, sin imágenes). La usan el paso «Registra sin esfuerzo» del
/// registro y la guía de Ajustes.
struct ControlCenterShowcase: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                tile(symbol: "plus.circle.fill", title: L("Anotar gasto"), highlighted: true)
                tile(symbol: "qrcode.viewfinder", title: "Escanear factura", highlighted: true)
            }
            HStack(spacing: 12) {
                ForEach(["wifi", "flashlight.on.fill", "camera.fill", "calculator"], id: \.self) { symbol in
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(.white.opacity(0.14)))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.1)], startPoint: .top, endPoint: .bottom))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Centro de control con los botones Anotar gasto y Escanear factura de MonAvi")
    }

    private func tile(symbol: String, title: String, highlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
            Text(title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(highlighted ? AnyShapeStyle(MonAviBrand.headerGradient) : AnyShapeStyle(.white.opacity(0.14)))
        )
    }
}

/// Ajustes > Automatizaciones > «Botones del Centro de control»: cómo
/// agregar «Anotar gasto» y «Escanear factura» (iOS 18 o posterior). Mismo
/// estilo que VoiceBackTapGuideView.
struct ControlCenterGuideView: View {
    private let steps: [String] = [
        L("Desliza hacia abajo desde la esquina superior derecha de la pantalla para abrir el **Centro de control**."),
        L("Toca **+** arriba a la izquierda y luego **Agregar un control**."),
        L("Busca **MonAvi** y elige **Anotar gasto** o **Escanear factura** (puedes agregar los dos)."),
        L("¡Listo! Desde cualquier pantalla, incluso la bloqueada, toca el botón y MonAvi se abre listo."),
    ]

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    ControlCenterShowcase()
                    Text("Registra sin esfuerzo")
                        .font(.system(.title2, design: MonAviBrand.fontDesign, weight: .bold))
                    Text("Agrega los botones de MonAvi al Centro de control y anota un gasto o escanea una factura en segundos, sin buscar la app.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(MonAviBrand.primary))
                        Text(LocalizedStringKey(step))
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Cómo agregarlos")
            } footer: {
                Text("Necesita iOS 18 o posterior. También puedes ponerlos en la pantalla bloqueada: mantén presionada la pantalla bloqueada > Personalizar y cambia los botones de abajo.")
            }
        }
        .navigationTitle("Centro de control")
        .navigationBarTitleDisplayMode(.inline)
    }
}
