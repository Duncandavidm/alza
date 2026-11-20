import SwiftUI
import UIKit

/// Estado de "Invita amigos": el resumen de la RPC `my_referral_summary`
/// y el envio de un codigo con `apply_referral_code`.
@MainActor
final class ReferralViewModel: ObservableObject {
    @Published private(set) var summary: ReferralSummary?
    @Published private(set) var isLoading = false
    @Published private(set) var isApplying = false
    @Published var loadErrorMessage: String?
    @Published var applyErrorMessage: String?
    @Published var didApplyCode = false
    @Published var codeInput = ""

    var canSubmitCode: Bool {
        ReferralRepository.normalized(codeInput).count == ReferralRepository.codeLength && !isApplying
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            summary = try await ReferralRepository.shared.fetchSummary()
            loadErrorMessage = nil
        } catch {
            if summary == nil {
                loadErrorMessage = "No se pudo cargar tu código. Revisa tu conexión e inténtalo de nuevo."
            }
        }
    }

    func applyCode() async {
        let code = ReferralRepository.normalized(codeInput)
        guard code.count == ReferralRepository.codeLength, !isApplying else { return }
        isApplying = true
        defer { isApplying = false }
        do {
            try await ReferralRepository.shared.apply(code: code)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            didApplyCode = true
            codeInput = ""
            summary = try? await ReferralRepository.shared.fetchSummary()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            applyErrorMessage = ReferralRepository.userMessage(for: error)
        }
    }
}

/// "Invita amigos": tu codigo para compartir, cuantos amigos se unieron
/// con el y, en tus primeros dias, el campo para usar el codigo de quien
/// te invito.
struct ReferralView: View {
    @StateObject private var viewModel = ReferralViewModel()
    @State private var didCopy = false
    @FocusState private var isCodeFieldFocused: Bool

    var body: some View {
        Group {
            if let summary = viewModel.summary {
                content(summary)
            } else if let message = viewModel.loadErrorMessage {
                ContentUnavailableView {
                    Label("Algo salió mal", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Reintentar") {
                        Task { await viewModel.load() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MonAviBrand.primary)
                }
            } else {
                ProgressView("Cargando tu código…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Invita amigos")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .alert("No se pudo usar el código", isPresented: isShowingApplyError) {
            Button("OK", role: .cancel) { viewModel.applyErrorMessage = nil }
        } message: {
            Text(viewModel.applyErrorMessage ?? "")
        }
        .alert("¡Listo!", isPresented: $viewModel.didApplyCode) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Ganarás 100 puntos cuando registres tu primera factura y se confirme.")
        }
    }

    private func content(_ summary: ReferralSummary) -> some View {
        List {
            codeSection(summary)
            statsSection(summary)
            howItWorksSection
            invitedBySection(summary)
        }
        .listStyle(.insetGrouped)
        .refreshable { await viewModel.load() }
    }

    // MARK: - Tu codigo

    private func codeSection(_ summary: ReferralSummary) -> some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(MonAviBrand.accentOnDark)

                Text("Invita amigos y gana 200 puntos")
                    .font(.system(.title3, design: MonAviBrand.fontDesign, weight: .bold))
                    .foregroundStyle(MonAviBrand.onDarkSurface)
                    .multilineTextAlignment(.center)

                VStack(spacing: 4) {
                    Text("Tu código")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MonAviBrand.onDarkSurface.opacity(0.75))
                    Text(summary.code)
                        .font(.system(size: 40, weight: .heavy, design: .monospaced))
                        .kerning(6)
                        .foregroundStyle(MonAviBrand.onDarkSurface)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .accessibilityLabel("Tu código: \(summary.code.map { String($0) }.joined(separator: " "))")
                }

                HStack(spacing: 12) {
                    Button {
                        copy(summary.code)
                    } label: {
                        Label(didCopy ? "Copiado" : "Copiar", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                            .font(.system(.subheadline, design: MonAviBrand.fontDesign, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(.white.opacity(0.18)))
                            .foregroundStyle(MonAviBrand.onDarkSurface)
                    }
                    .buttonStyle(.plain)
                    .pressable()

                    ShareLink(item: shareMessage(for: summary.code)) {
                        Label("Compartir", systemImage: "square.and.arrow.up")
                            .font(.system(.subheadline, design: MonAviBrand.fontDesign, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(MonAviBrand.primary))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .pressable()
                }
                .disabled(summary.code.isEmpty)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 16)
            .listRowInsets(EdgeInsets())
            .listRowBackground(MonAviBrand.headerGradient)
        }
    }

    private func shareMessage(for code: String) -> String {
        "Únete a MonAvi y gana 100 puntos con mi código \(code): \(Config.appStoreURL.absoluteString)"
    }

    private func copy(_ code: String) {
        guard !code.isEmpty else { return }
        UIPasteboard.general.string = code
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.snappy) { didCopy = true }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.snappy) { didCopy = false }
        }
    }

    // MARK: - Resultados

    private func statsSection(_ summary: ReferralSummary) -> some View {
        Section("Tus invitaciones") {
            LabeledContent("Invitados", value: "\(summary.invited)")
            LabeledContent("Premiados", value: "\(summary.rewarded)")
            LabeledContent("Pendientes", value: "\(summary.pending)")
            LabeledContent("Puntos ganados") {
                Text("\(summary.pointsEarned)")
                    .fontWeight(.semibold)
                    .foregroundStyle(MonAviBrand.primaryDark)
            }
        }
    }

    // MARK: - Como funciona

    private var howItWorksSection: some View {
        Section {
            ruleRow(icon: "square.and.arrow.up", text: "Comparte tu código con tus amigos.")
            ruleRow(icon: "person.badge.plus", text: "Tu amigo lo usa al unirse y gana 100 puntos.")
            ruleRow(icon: "star.fill", text: "Tú ganas 200 puntos por cada amigo.")
        } header: {
            Text("Cómo funciona")
        } footer: {
            Text("Los puntos llegan cuando tu amigo registra su primera factura y se confirma. Se premian hasta 10 invitaciones cada 30 días.")
        }
    }

    private func ruleRow(icon: String, text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(MonAviBrand.primary)
        }
    }

    // MARK: - ¿Te invito alguien?

    @ViewBuilder
    private func invitedBySection(_ summary: ReferralSummary) -> some View {
        if let appliedCode = summary.appliedCode, !appliedCode.isEmpty {
            Section("¿Te invitó alguien?") {
                Label {
                    Text("Usaste el código \(appliedCode)")
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(MonAviBrand.primary)
                }
            }
        } else if summary.canApplyCode {
            Section {
                TextField("Código de 6 caracteres", text: codeBinding)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .submitLabel(.done)
                    .focused($isCodeFieldFocused)
                    .onSubmit { submitCode() }

                Button {
                    submitCode()
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isApplying {
                            ProgressView()
                        } else {
                            Text("Usar código")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(!viewModel.canSubmitCode)
            } header: {
                Text("¿Te invitó alguien?")
            } footer: {
                Text("Escribe el código de quien te invitó y gana 100 puntos. Solo puedes usar un código, en tus primeros 7 días.")
            }
        }
    }

    /// Mayusculas y maximo 6 caracteres mientras escribe.
    private var codeBinding: Binding<String> {
        Binding(
            get: { viewModel.codeInput },
            set: { viewModel.codeInput = ReferralRepository.normalized($0) }
        )
    }

    private var isShowingApplyError: Binding<Bool> {
        Binding(
            get: { viewModel.applyErrorMessage != nil },
            set: { newValue in
                if !newValue { viewModel.applyErrorMessage = nil }
            }
        )
    }

    private func submitCode() {
        guard viewModel.canSubmitCode else { return }
        isCodeFieldFocused = false
        Task { await viewModel.applyCode() }
    }
}

#Preview {
    NavigationStack {
        ReferralView()
    }
}
