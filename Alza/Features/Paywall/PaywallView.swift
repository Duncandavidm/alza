import SwiftUI

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
                        .font(.system(.subheadline, design: AlzaBrand.fontDesign))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .animation(.easeInOut(duration: 0.2), value: audience)
                        .id(audience)
                        .transition(.opacity)

                    pricingCard

                    Text("Menos de lo que cuesta un ☕ cafe a la semana.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    ctaButton

                    confirmationNote

                    if let error = subscriptionStore.purchaseError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(AlzaBrand.alert)
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
                    .foregroundStyle(AlzaBrand.primary)
            )
            .font(.system(.largeTitle, design: AlzaBrand.fontDesign, weight: .heavy))
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
                        .font(.system(.subheadline, design: AlzaBrand.fontDesign, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if audience == option {
                                Capsule().fill(AlzaBrand.primary)
                            }
                        }
                        .foregroundStyle(audience == option ? .white : .primary)
                }
                .pressable()
            }
        }
        .padding(4)
        .background(Capsule().fill(Color(.secondarySystemBackground)))
    }

    @ViewBuilder
    private var pricingCard: some View {
        if let product = subscriptionStore.product {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Mensual")
                        .font(.system(.headline, design: AlzaBrand.fontDesign, weight: .bold))
                    Spacer()
                    if let duration = subscriptionStore.freeTrialDurationText {
                        Text("\(duration) gratis")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(AlzaBrand.primary))
                            .foregroundStyle(.white)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(product.displayPrice)
                        .font(.system(size: 36, weight: .bold, design: AlzaBrand.fontDesign))
                    Text("/ mes")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(AlzaBrand.primary, lineWidth: 2)
                    )
            )
        } else if subscriptionStore.isLoadingProduct {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemBackground))
                .frame(height: 96)
                .overlay(ProgressView())
        } else {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemBackground))
                .frame(height: 96)
                .overlay(
                    Text("No se pudo cargar el precio")
                        .foregroundStyle(AlzaBrand.alert)
                )
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
                        .font(.system(.headline, design: AlzaBrand.fontDesign, weight: .bold))
                    Spacer()
                    Text("\(duration) gratis")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.white.opacity(0.22)))
                } else {
                    Text("Suscribirme")
                        .font(.system(.headline, design: AlzaBrand.fontDesign, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(height: 58)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 18).fill(AlzaBrand.headerGradient))
        }
        .pressable()
        .disabled(subscriptionStore.product == nil)
    }

    @ViewBuilder
    private var confirmationNote: some View {
        if let price = subscriptionStore.product?.displayPrice,
           subscriptionStore.freeTrialDurationText != nil {
            VStack(spacing: 4) {
                Label("Hoy no pagas nada.", systemImage: "checkmark.seal.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AlzaBrand.primary)
                Text("Se renueva automaticamente a \(price) / mes despues de la prueba. Cancela cuando quieras.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
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
                    Text("Cerrar sesion")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .disabled(isSigningOut)
        }
    }
}
