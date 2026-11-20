import SwiftUI

/// Consentimiento del estudio de mercado anonimo (Ley 81 de 2019 de
/// Panama). Se muestra sola una vez (al abrir "Puntos y cashback"
/// si aun no hay decision) y se puede cambiar en Ajustes > Privacidad.
/// Ambos botones guardan una decision (acepto / no acepto).
struct MarketStudyConsentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    var onDecided: (Bool) -> Void = { _ in }

    @State private var isSaving = false
    @State private var errorMessage: String?
    /// Segunda decision, aparte: promociones y regalos ('ofertas').
    /// Empieza apagada; se guarda junto con la del estudio.
    @State private var wantsOffers = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("🛒").font(.system(size: 56))

                    Text("Tus compras, anónimas")
                        .font(.system(.title2, design: MonAviBrand.fontDesign, weight: .bold))

                    item(
                        icon: "doc.text.magnifyingglass",
                        title: "Qué usamos",
                        text: "Tus facturas verificadas: comercio, productos, monto, medio de pago, fecha y hora. También tu edad y género, si nos los diste."
                    )
                    item(
                        icon: "person.3.fill",
                        title: "Cómo lo usamos",
                        text: "Solo en estudios agregados y anónimos de al menos 5 personas. Nunca tu nombre, tu correo ni tus compras individuales. Los comercios y marcas ven tendencias, no personas."
                    )
                    item(
                        icon: "gift.fill",
                        title: "Qué ganas",
                        text: "Ayudas a que haya más premios y campañas de marcas en MonAvi."
                    )
                    item(
                        icon: "arrow.uturn.backward.circle.fill",
                        title: "Tú decides",
                        text: "Puedes cambiar de opinión cuando quieras en Ajustes > Privacidad."
                    )

                    offersCard

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    VStack(spacing: 10) {
                        Button {
                            Task { await decide(true) }
                        } label: {
                            Text("Acepto participar")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button {
                            Task { await decide(false) }
                        } label: {
                            Text("Ahora no")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    .disabled(isSaving)
                    .padding(.top, 6)

                    Link("Ver política de privacidad", destination: Config.privacyPolicyURL)
                        .font(.footnote)
                        .frame(maxWidth: .infinity)
                }
                .padding(20)
            }
            .navigationTitle("Estudio de mercado")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if isSaving { ProgressView() }
            }
            .toolbar {
                // Solo si fallo el guardado: para no dejar a nadie atrapado
                // sin red. Sin decision, se puede elegir luego en Ajustes.
                if errorMessage != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cerrar") { dismiss() }
                    }
                }
            }
        }
        // Hay que elegir una de las dos opciones: ambas quedan registradas.
        .interactiveDismissDisabled()
    }

    /// Decision separada del estudio: recibir promociones y regalos.
    private var offersCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $wantsOffers) {
                Label("Recibir promociones y regalos", systemImage: "gift.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .tint(MonAviBrand.primary)
            Text(PrivacySettingsSection.offersFooter)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func item(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(MonAviBrand.primary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @MainActor
    private func decide(_ granted: Bool) async {
        guard let userId = appState.currentUserId else {
            dismiss()
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            // Dos decisiones independientes, ambas quedan registradas.
            try await ConsentRepository.shared.record(userId: userId, purpose: .estudioMercado, granted: granted)
            try await ConsentRepository.shared.record(userId: userId, purpose: .ofertas, granted: wantsOffers)
            onDecided(granted)
            dismiss()
        } catch {
            errorMessage = "No se pudo guardar tu decisión. Revisa tu conexión e intenta de nuevo."
        }
    }
}

/// Recuerda en el telefono que ya se mostro el consentimiento (por
/// usuario), para no volver a mostrarlo solo aunque falle la red.
enum MarketStudyConsentPrompt {
    private static func key(_ userId: UUID) -> String { "marketStudyConsentPrompted-\(userId.uuidString)" }

    static func wasShown(userId: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: key(userId))
    }

    static func markShown(userId: UUID) {
        UserDefaults.standard.set(true, forKey: key(userId))
    }

    /// true solo si nunca se mostro y el servidor confirma que no hay
    /// decision (un error de red no cuenta como "sin decision").
    @MainActor
    static func shouldShow(userId: UUID) async -> Bool {
        guard !wasShown(userId: userId) else { return false }
        do {
            let decision = try await ConsentRepository.shared.current(userId: userId, purpose: .estudioMercado)
            if decision != nil {
                // Ya decidio (quizas en otro telefono): no volver a mostrar.
                markShown(userId: userId)
                return false
            }
            return true
        } catch {
            return false
        }
    }
}

/// Ajustes > Privacidad: los interruptores del estudio de mercado y de
/// promociones y regalos (cada cambio guarda una fila nueva) y la
/// politica de privacidad.
struct PrivacySettingsSection: View {
    static let offersFooter = "Te avisaremos de ofertas de comercios y marcas, y podrás recibir regalos como cashback o productos gratis. Puedes desactivarlo cuando quieras."

    var body: some View {
        Section {
            ConsentToggleRow(
                title: "Participar en el estudio de mercado anónimo",
                purpose: .estudioMercado
            )

            Link(destination: Config.privacyPolicyURL) {
                Label("Ver política de privacidad", systemImage: "hand.raised.fill")
            }
            .foregroundStyle(.primary)
        } header: {
            Text("Privacidad")
        } footer: {
            Text("Usamos tus facturas verificadas solo en estudios agregados y anónimos de al menos 5 personas. Nunca tu nombre, correo ni compras individuales: los comercios y marcas ven tendencias, no personas.")
        }

        Section {
            ConsentToggleRow(
                title: "Recibir promociones y regalos",
                purpose: .ofertas
            )
        } footer: {
            Text(Self.offersFooter)
        }

        Section {
            ConsentToggleRow(
                title: "Usar funciones con IA",
                purpose: .ia
            )
        } footer: {
            Text(Self.aiFooter)
        }
    }

    static let aiFooter = "Las preguntas, el análisis y las notas por voz usan Claude, la IA de Anthropic. Solo se envían los datos necesarios para responder y no se usan para entrenar modelos. Si lo desactivas, no se envía nada."
}

/// Un interruptor de consentimiento: lee la ultima decision y guarda una
/// fila nueva en cada cambio (si falla, vuelve al valor anterior).
private struct ConsentToggleRow: View {
    let title: String
    let purpose: ConsentPurpose

    @EnvironmentObject private var appState: AppState
    @State private var granted = false
    @State private var isLoaded = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Toggle(title, isOn: binding)
            .disabled(!isLoaded || isSaving)
            .task { await load() }

        if let errorMessage {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { granted },
            set: { newValue in
                guard newValue != granted else { return }
                Task { await save(newValue) }
            }
        )
    }

    @MainActor
    private func load() async {
        guard let userId = appState.currentUserId else { return }
        do {
            let decision = try await ConsentRepository.shared.current(userId: userId, purpose: purpose)
            granted = decision?.granted ?? false
            isLoaded = true
            errorMessage = nil
        } catch {
            isLoaded = false
            errorMessage = "No se pudo cargar tu preferencia. Intenta más tarde."
        }
    }

    @MainActor
    private func save(_ newValue: Bool) async {
        guard let userId = appState.currentUserId else { return }
        let previous = granted
        granted = newValue
        isSaving = true
        defer { isSaving = false }
        do {
            try await ConsentRepository.shared.record(userId: userId, purpose: purpose, granted: newValue)
            if purpose == .estudioMercado {
                MarketStudyConsentPrompt.markShown(userId: userId)
            }
            if purpose == .ia {
                AIConsentCenter.shared.setCached(newValue, userId: userId)
            }
            errorMessage = nil
        } catch {
            granted = previous
            errorMessage = "No se pudo guardar el cambio. Revisa tu conexión."
        }
    }
}
