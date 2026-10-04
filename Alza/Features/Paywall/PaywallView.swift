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

    private static let topChips = [
        MarqueeChip(icon: "💬", text: "Pregunta lo que sea sobre tu dinero"),
        MarqueeChip(icon: "🔔", text: "Alertas antes de que venza una cuenta"),
        MarqueeChip(icon: "📈", text: "Prioriza que deuda pagar primero"),
        MarqueeChip(icon: "🧾", text: "Factura a tus clientes desde la app"),
    ]

    private static let bottomChips = [
        MarqueeChip(icon: "♾️", text: "Transacciones y cuentas ilimitadas"),
        MarqueeChip(icon: "🤖", text: "Insights de IA sobre tus gastos"),
        MarqueeChip(icon: "🎙️", text: "Anota gastos con tu voz"),
        MarqueeChip(icon: "📊", text: "Reportes de tu negocio al dia"),
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
                        .font(.system(.subheadline, design: AviBrand.fontDesign))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .animation(.easeInOut(duration: 0.2), value: audience)
                        .id(audience)
                        .transition(.opacity)

                    tierToggle

                    pricingCard

                    Text("Menos de lo que cuesta un ☕ cafe a la semana.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    ctaButton

                    confirmationNote

                    if let error = subscriptionStore.purchaseError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(AviBrand.alert)
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
    }

    private var header: some View {
        VStack(spacing: 4) {
            EmbeddedLogo.alzaMark
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)

            (
                Text("Hazte ")
                    .foregroundStyle(.primary)
                + Text("Pro")
                    .foregroundStyle(AviBrand.primary)
            )
            .font(.system(.largeTitle, design: AviBrand.fontDesign, weight: .heavy))
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
                        .font(.system(.subheadline, design: AviBrand.fontDesign, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(audience == option ? AviBrand.primary : .clear)
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

    /// Individual / Familia — independiente del audienceToggle de arriba
    /// (ese es solo texto descriptivo). Familia es un producto propio mas
    /// caro (no Apple Family Sharing, ver Config.swift), por eso vive aqui
    /// junto a la eleccion de precio, no junto al toggle de audiencia.
    private var tierToggle: some View {
        HStack(spacing: 4) {
            ForEach(SubscriptionTier.allCases) { tier in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectTier(tier)
                    }
                } label: {
                    Text(tier == .individual ? "Individual" : "Familia")
                        .font(.system(.subheadline, design: AviBrand.fontDesign, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(subscriptionStore.selectedPlan.tier == tier ? AviBrand.primary : .clear)
                        )
                        .foregroundStyle(subscriptionStore.selectedPlan.tier == tier ? .white : .primary)
                }
                .buttonStyle(.plain)
                .pressable()
            }
        }
        .padding(4)
        .background(Capsule().fill(Color(.secondarySystemBackground)))
    }

    /// Cambia de tier conservando el ciclo (mensual/anual) elegido si ese
    /// producto ya cargo; si no, cae al otro ciclo del mismo tier que si
    /// haya cargado, para no dejar el tier nuevo sin nada que comprar.
    private func selectTier(_ tier: SubscriptionTier) {
        let billing = subscriptionStore.selectedPlan.billing
        if subscriptionStore.product(tier: tier, billing: billing) != nil {
            subscriptionStore.selectPlan(.plan(tier: tier, billing: billing))
        } else if let fallback = SubscriptionBilling.allCases.first(where: { subscriptionStore.product(tier: tier, billing: $0) != nil }) {
            subscriptionStore.selectPlan(.plan(tier: tier, billing: fallback))
        }
    }

    @ViewBuilder
    private var pricingCard: some View {
        let tier = subscriptionStore.selectedPlan.tier
        let annual = subscriptionStore.product(tier: tier, billing: .annual)
        let monthly = subscriptionStore.product(tier: tier, billing: .monthly)

        if annual != nil || monthly != nil {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    if let annual {
                        planOption(plan: .plan(tier: tier, billing: .annual), product: annual, badge: "Mejor precio")
                    }
                    if let monthly {
                        planOption(plan: .plan(tier: tier, billing: .monthly), product: monthly, badge: nil)
                    }
                }

                commitmentCaption

                // Solo el tier Familia anuncia compartir — el Individual no
                // usa Apple Family Sharing nativo a proposito (competiria
                // gratis con el plan Familia de pago, ver Config.swift).
                if tier == .familia {
                    Label("Invita hasta 5 personas con tu codigo (Ajustes > Mi familia)", systemImage: "person.3.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                        .foregroundStyle(AviBrand.alert)
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
                            .fill(badge == nil ? .clear : AviBrand.primary)
                    )
                    .foregroundStyle(.white)
                    .opacity(badge == nil ? 0 : 1)

                Text(plan.billing == .annual ? "12 meses" : "Mensual")
                    .font(.system(.subheadline, design: AviBrand.fontDesign, weight: .semibold))
                    .foregroundStyle(.primary)

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(priceText)
                        .font(.system(size: 24, weight: .bold, design: AviBrand.fontDesign))
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
                            .stroke(isSelected ? AviBrand.primary : .clear, lineWidth: 2)
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
                if subscriptionStore.selectedPlan.billing == .annual {
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
                        .font(.system(.headline, design: AviBrand.fontDesign, weight: .bold))
                    Spacer()
                    Text("\(duration) gratis")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.white.opacity(0.22)))
                } else {
                    Text("Suscribirme")
                        .font(.system(.headline, design: AviBrand.fontDesign, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(height: 58)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 18).fill(AviBrand.headerGradient))
        }
        .pressable()
        .disabled(subscriptionStore.selectedProduct == nil)
    }

    @ViewBuilder
    private var confirmationNote: some View {
        if let price = subscriptionStore.selectedProduct?.displayPrice,
           subscriptionStore.freeTrialDurationText != nil {
            let cadence = subscriptionStore.selectedPlan.billing == .annual ? "al año" : "al mes"
            VStack(spacing: 4) {
                Label("Hoy no pagas nada.", systemImage: "checkmark.seal.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AviBrand.primary)
                Text("Se renueva automaticamente a \(price) \(cadence) despues de la prueba. Cancela cuando quieras.")
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
                Link("Terminos", destination: Config.termsOfUseURL)
                if let url = URL(string: "mailto:\(Config.supportEmail)") {
                    Link("Contacto", destination: url)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .minimumScaleFactor(0.7)
            .lineLimit(1)
            .frame(maxWidth: .infinity)

            Button("Restaurar compras") {
                Task {
                    await subscriptionStore.restore()
                    await appState.refreshSubscriptionStatus()
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
                    Label("Cerrar sesion", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .disabled(isSigningOut)
        }
    }
}
