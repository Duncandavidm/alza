import SwiftUI
import StoreKit

private enum PaywallAudience: String, CaseIterable, Identifiable, Equatable {
    case personal = "Personal"
    case negocio = "Negocio"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .personal:
            return "Dashboard financiero completo, metas y consejos de IA para tus finanzas personales."
        case .negocio:
            return "Factura, controla cuentas por cobrar y recibe insights de IA para tu negocio."
        }
    }
}

struct PaywallView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var subscriptionStore: SubscriptionStore
    @State private var isSigningOut = false
    @State private var audience: PaywallAudience = .personal
    @State private var appeared = false
    /// Hoja de App Store para canjear un codigo de oferta de suscripcion.
    @State private var isRedeemingOfferCode = false

    private static let topChips = [
        MarqueeChip(icon: "💬", text: "Pregunta lo que sea sobre tu dinero"),
        MarqueeChip(icon: "🔔", text: "Alertas antes de que venza una cuenta"),
        MarqueeChip(icon: "📈", text: "Prioriza qué deuda pagar primero"),
        MarqueeChip(icon: "🧾", text: "Factura a tus clientes desde la app"),
    ]

    private static let bottomChips = [
        MarqueeChip(icon: "♾️", text: "Transacciones y cuentas ilimitadas"),
        MarqueeChip(icon: "🤖", text: "Insights de IA sobre tus gastos"),
        MarqueeChip(icon: "🎙️", text: "Anota gastos con tu voz"),
        MarqueeChip(icon: "📊", text: "Reportes de tu negocio al día"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                    .padding(.top, 24)

                VStack(spacing: 10) {
                    MarqueeRow(chips: Self.topChips)
                    MarqueeRow(chips: Self.bottomChips, reversed: true)
                }

                VStack(spacing: 20) {
                    audienceToggle

                    Text(audience.description)
                        .font(.system(.subheadline, design: MonAviBrand.fontDesign))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .animation(.easeInOut(duration: 0.2), value: audience)
                        .id(audience)
                        .transition(.opacity)

                    pricingCard

                    Text("Menos de lo que cuesta un ☕ café a la semana.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    ctaButton

                    confirmationNote

                    if let error = subscriptionStore.purchaseError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(MonAviBrand.alert)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)

                footer
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                appeared = true
            }
        }
        .task {
            await subscriptionStore.loadProduct()
        }
        .offerCodeRedemption(isPresented: $isRedeemingOfferCode) { _ in
            Task {
                await subscriptionStore.syncCurrentEntitlements()
                await appState.refreshSubscriptionStatus()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            EmbeddedLogo.monAviMark
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)

            (
                Text("Hazte ")
                    .foregroundStyle(.primary)
                + Text("Pro")
                    .foregroundStyle(MonAviBrand.primary)
            )
            .font(.system(.largeTitle, design: MonAviBrand.fontDesign, weight: .heavy))
        }
    }

    private var audienceToggle: some View {
        HStack(spacing: 4) {
            ForEach(PaywallAudience.allCases) { option in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        audience = option
                    }
                } label: {
                    Text(option.rawValue)
                        .font(.system(.subheadline, design: MonAviBrand.fontDesign, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(audience == option ? MonAviBrand.primary : .clear)
                        )
                        .foregroundStyle(audience == option ? .white : .primary)
                }
                .buttonStyle(.plain)
                .pressable()
            }
        }
        .padding(4)
        .background(Capsule().fill(Color(.secondarySystemBackground)))
    }

    @ViewBuilder
    private var pricingCard: some View {
        let annual = subscriptionStore.product(for: .annual)
        let monthly = subscriptionStore.product(for: .monthly)

        if annual != nil || monthly != nil {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    if let annual {
                        planOption(plan: .annual, product: annual, badge: "Mejor precio")
                    }
                    if let monthly {
                        planOption(plan: .monthly, product: monthly, badge: nil)
                    }
                }

                commitmentCaption
            }
        } else if subscriptionStore.isLoadingProduct {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemBackground))
                .frame(height: 140)
                .overlay(ProgressView())
        } else {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemBackground))
                .frame(height: 140)
                .overlay(
                    Text("No se pudo cargar el precio")
                        .foregroundStyle(MonAviBrand.alert)
                )
        }
    }

    /// Una de las dos tarjetas de plan ("12 meses" / "Mensual") — tocarla
    /// selecciona ese plan, el resaltado con borde de marca indica cual
    /// esta elegido. El precio del anual se muestra como equivalente
    /// mensual (total / 12) para que se compare directo con el mensual,
    /// con el total real aparte en `commitmentCaption`.
    private func planOption(plan: SubscriptionPlan, product: Product, badge: String?) -> some View {
        let isSelected = subscriptionStore.selectedPlan == plan
        let priceText = subscriptionStore.monthlyEquivalentPrice(for: product) ?? product.displayPrice

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                subscriptionStore.selectPlan(plan)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(badge ?? " ")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(badge == nil ? .clear : MonAviBrand.primary)
                    )
                    .foregroundStyle(.white)
                    .opacity(badge == nil ? 0 : 1)

                Text(plan == .annual ? "12 meses" : "Mensual")
                    .font(.system(.subheadline, design: MonAviBrand.fontDesign, weight: .semibold))
                    .foregroundStyle(.primary)

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(priceText)
                        .font(.system(size: 24, weight: .bold, design: MonAviBrand.fontDesign))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("/ mes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(isSelected ? MonAviBrand.primary : .clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
        .pressable()
    }

    @ViewBuilder
    private var commitmentCaption: some View {
        if let product = subscriptionStore.selectedProduct {
            Group {
                if subscriptionStore.selectedPlan == .annual {
                    Text("Cobro anual — compromiso de 12 meses, \(product.displayPrice) en total")
                } else {
                    Text("Cobro mensual, cancela cuando quieras")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
    }

    private var ctaButton: some View {
        Button {
            guard let userId = appState.currentUserId else { return }
            Task { await subscriptionStore.purchase(appAccountToken: userId) }
        } label: {
            HStack {
                if let duration = subscriptionStore.freeTrialDurationText {
                    Text("Empieza por USD 0.00")
                        .font(.system(.headline, design: MonAviBrand.fontDesign, weight: .bold))
                    Spacer()
                    Text("\(duration) gratis")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.white.opacity(0.22)))
                } else {
                    Text("Suscribirme")
                        .font(.system(.headline, design: MonAviBrand.fontDesign, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(height: 58)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 18).fill(MonAviBrand.headerGradient))
        }
        .pressable()
        .disabled(subscriptionStore.selectedProduct == nil)
    }

    @ViewBuilder
    private var confirmationNote: some View {
        if let price = subscriptionStore.selectedProduct?.displayPrice,
           subscriptionStore.freeTrialDurationText != nil {
            let cadence = subscriptionStore.selectedPlan == .annual ? "al año" : "al mes"
            VStack(spacing: 4) {
                Label("Hoy no pagas nada.", systemImage: "checkmark.seal.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MonAviBrand.primary)
                Text("Se renueva automáticamente a \(price) \(cadence) después de la prueba. Cancela cuando quieras.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                Link("Privacidad", destination: Config.privacyPolicyURL)
                Link("Términos", destination: Config.termsOfUseURL)
                if let url = URL(string: "mailto:\(Config.supportEmail)") {
                    Link("Contacto", destination: url)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .minimumScaleFactor(0.7)
            .lineLimit(1)
            .frame(maxWidth: .infinity)

            HStack(spacing: 20) {
                Button("Restaurar compras") {
                    Task {
                        await subscriptionStore.restore()
                        await appState.refreshSubscriptionStatus()
                    }
                }

                Button("Canjear código") {
                    isRedeemingOfferCode = true
                }
            }
            .font(.footnote)

            Button {
                Task {
                    isSigningOut = true
                    await appState.signOut()
                    isSigningOut = false
                }
            } label: {
                if isSigningOut {
                    ProgressView()
                } else {
                    Label("Cerrar sesión", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .disabled(isSigningOut)
        }
    }
}

