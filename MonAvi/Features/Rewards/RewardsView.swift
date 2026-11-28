import SwiftUI
import UIKit

/// "Canjea tus premios": catalogo de productos de comercios aliados. Cada
/// comercio canjea en una moneda: cashback (centavos, de facturas DGI) o
/// puntos (por buenos habitos). El usuario toca "Canjear", confirma, y la
/// RPC `redeem_reward` descuenta de la moneda correcta y genera el codigo
/// que muestra en caja.
struct RewardsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openURL) private var openURL
    @StateObject private var viewModel = RewardsViewModel()

    /// "Descuentos" (gratis por ser de MonAvi, 0067), "Premios" (catalogo
    /// con cashback o puntos) o "Comercios" (donde canjear).
    enum Mode: String, CaseIterable, Identifiable {
        case benefits = "Descuentos"
        case rewards = "Premios"
        case merchants = "Comercios"
        var id: String { rawValue }
    }

    @State private var mode: Mode
    /// Si viene de "Ver premios" de un comercio, solo muestra los suyos.
    @State private var merchantFilter: UUID?

    /// Pestañas visibles: "Premios" ya no tiene pestaña propia (mostraba
    /// lo mismo que "Comercios"); los premios con cashback se ven desde
    /// cada comercio con "Ver premios" (modo .rewards con merchantFilter).
    static let pickerModes: [Mode] = [.benefits, .merchants]

    init(initialMode: Mode = .merchants) {
        _mode = State(initialValue: initialMode)
    }

    @State private var pendingItem: RewardItem?
    @State private var isConfirming = false
    @State private var isRedeeming = false
    @State private var presentedRedemption: RewardRedemption?
    @State private var redeemErrorMessage: String?
    /// Producto cuyo canje pidio verificar el correo; se reintenta solo al
    /// cerrar EmailVerificationSheet si se verifico.
    @State private var itemAwaitingVerification: RewardItem?
    @State private var isVerifyingEmail = false
    @State private var didVerifyEmail = false
    /// Descuento que se va a usar (dialogo de confirmacion) y el que pidio
    /// verificar el correo.
    @State private var pendingBenefit: RewardItem?
    @State private var isConfirmingBenefit = false
    @State private var benefitAwaitingVerification: RewardItem?
    @State private var isScanningInvoice = false
    /// "Como llegar" de un comercio con sucursales: se elige el local.
    @State private var directionsChoices: [DirectionsOption] = []
    @State private var isChoosingBranch = false
    /// Codigo recien generado: se abre con la celebracion de billetes.
    @State private var celebrateRedemptionId: UUID?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                balanceHeader
                if appState.isInFreeTrial {
                    TrialLockedBanner()
                }
                referralBanner
                Picker("Ver", selection: pickerSelection) {
                    ForEach(Self.pickerModes) { (option: Mode) in
                        Text(L(option.rawValue)).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                if let merchantFilter, mode != .merchants {
                    merchantFilterChip(merchantFilter)
                } else if chipCategories.count > 1 {
                    categoryChips
                }
                content
                    .trialLocked(appState.isInFreeTrial)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(navigationTitle)
        .onChange(of: mode) { _, _ in
            // Cada pestaña tiene sus propias categorias.
            if let selected = viewModel.selectedCategory, !chipCategories.contains(selected) {
                viewModel.selectedCategory = nil
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .refreshable { await refresh() }
        .task { await refresh() }
        .overlay { redeemingOverlay }
        .confirmationDialog(
            confirmationTitle,
            isPresented: $isConfirming,
            titleVisibility: .visible,
            presenting: pendingItem
        ) { (item: RewardItem) in
            Button(item.isUnlockable ? L("Desbloquear por %@", item.formattedCost) : L("Canjear por %@", item.formattedCost)) {
                Task { await redeem(item) }
            }
            Button("Cancelar", role: .cancel) {}
        }
        .confirmationDialog(
            pendingBenefit.map(BenefitsMath.confirmationTitle(for:)) ?? L("¿Usar este descuento?"),
            isPresented: $isConfirmingBenefit,
            titleVisibility: .visible,
            presenting: pendingBenefit
        ) { (item: RewardItem) in
            Button("Generar mi código") {
                Task { await useBenefit(item) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("Úsalo en caja antes de pagar: el código dura 15 minutos. Pide tu factura fiscal para ganar cashback también.")
        }
        .sheet(item: $presentedRedemption, onDismiss: {
            celebrateRedemptionId = nil
            Task { await viewModel.refreshBenefits() }
        }) { (redemption: RewardRedemption) in
            RedemptionCodeView(redemption: redemption, celebrate: redemption.id == celebrateRedemptionId)
        }
        .confirmationDialog("¿A qué sucursal vas?", isPresented: $isChoosingBranch, titleVisibility: .visible) {
            ForEach(directionsChoices) { (option: DirectionsOption) in
                Button(option.subtitle.map { "\(option.title) — \($0)" } ?? option.title) {
                    openURL(option.url)
                }
            }
            Button("Cancelar", role: .cancel) {}
        }
        .invoiceScanner(isPresented: $isScanningInvoice) {
            await viewModel.refreshBenefits()
        }
        .sheet(isPresented: $isVerifyingEmail, onDismiss: retryAfterEmailVerification) {
            EmailVerificationSheet {
                didVerifyEmail = true
            }
        }
        .alert("No se pudo canjear", isPresented: isShowingRedeemError) {
            Button("OK", role: .cancel) { redeemErrorMessage = nil }
        } message: {
            Text(redeemErrorMessage ?? "")
        }
    }

    /// Los premios de un comercio se muestran bajo la pestaña "Comercios".
    private var pickerSelection: Binding<Mode> {
        Binding(
            get: { mode == .rewards ? .merchants : mode },
            set: { newValue in
                merchantFilter = nil
                mode = newValue
            }
        )
    }

    // MARK: - Secciones

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
                MyRedemptionsView()
            } label: {
                Label("Mis cupones y canjes", systemImage: "ticket.fill")
            }
        }
    }

    private var balanceHeader: some View {
        RewardBalancesHeader(balance: viewModel.balance)
    }

    /// Atajo a "Invita amigos" (mismo ReferralView que en Mi perfil).
    private var referralBanner: some View {
        NavigationLink {
            ReferralView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "gift.fill")
                    .font(.title3)
                    .foregroundStyle(MonAviBrand.primary)
                Text("Invita amigos y gana cashback")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    /// Categorias de la pestaña actual (las crea el panel en /categorias y
    /// cada comercio tiene la suya): de los descuentos o de los premios.
    private var chipCategories: [String] {
        let names: [String]
        switch mode {
        case .benefits: names = RewardsMath.categories(of: benefitItems + viewModel.items)
        case .rewards: names = viewModel.categories
        case .merchants: names = RewardsMath.categories(of: viewModel.items + benefitItems)
        }
        return RewardsMath.orderedCategories(names, info: viewModel.categoryInfo)
    }

    private var benefitItems: [RewardItem] { viewModel.benefits.benefits.map(\.item) }

    /// Descuentos del comercio o de la categoria elegida (o todos).
    private var visibleBenefits: [BenefitEntry] {
        var entries = viewModel.benefits.benefits
        if let merchantFilter {
            entries = entries.filter { $0.item.merchantId == merchantFilter }
        } else if let category = viewModel.selectedCategory {
            let allowed = Set(RewardsMath.filter(entries.map(\.item), category: category).map(\.id))
            entries = entries.filter { allowed.contains($0.id) }
        }
        return entries
    }

    /// Comercios con premios o descuentos, de la categoria elegida.
    private var merchantSummaries: [PartnerMerchantSummary] {
        let all = PartnerMerchantSummary.group(viewModel.items, benefits: benefitItems)
        guard let category = viewModel.selectedCategory else { return all }
        return all.filter { $0.category?.trimmingCharacters(in: .whitespacesAndNewlines) == category }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(title: L("Todos"), category: nil)
                ForEach(chipCategories, id: \.self) { (category: String) in
                    categoryChip(title: RewardsMath.categoryTitle(category, info: viewModel.categoryInfo), category: category)
                }
            }
        }
    }

    private func categoryChip(title: String, category: String?) -> some View {
        let isSelected = viewModel.selectedCategory == category
        return Button {
            withAnimation(.snappy) {
                viewModel.selectedCategory = category
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? MonAviBrand.primary : Color(.secondarySystemGroupedBackground), in: Capsule())
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private var navigationTitle: String {
        switch mode {
        case .benefits: return L("Descuentos para ti")
        case .rewards: return L("Canjea tus premios")
        case .merchants: return L("Dónde canjear")
        }
    }

    // MARK: - Descuentos de aliados

    @ViewBuilder
    private var benefitsContent: some View {
        let response = viewModel.benefits
        if !viewModel.hasLoaded && response.benefits.isEmpty {
            ProgressView("Cargando descuentos…")
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else {
            if !response.unlocked && !response.benefits.isEmpty {
                BenefitsUnlockCard(bestDiscount: BenefitsMath.bestPercentText(response.benefits)) {
                    isScanningInvoice = true
                }
            }
            if response.benefits.isEmpty {
                ContentUnavailableView(
                    "Pronto habrá descuentos",
                    systemImage: "percent",
                    description: Text("Aquí verás los descuentos que te dan los comercios aliados por ser de MonAvi.")
                )
                .padding(.top, 12)
            } else if merchantFilter == nil && viewModel.selectedCategory == nil {
                marketplace(unlocked: response.unlocked)
            } else {
                ForEach(visibleBenefits) { (entry: BenefitEntry) in
                    BenefitCard(
                        entry: entry,
                        state: BenefitsMath.state(of: entry, unlocked: response.unlocked),
                        isWorking: isRedeeming,
                        onDirections: { openDirections(for: entry.item) },
                        onPrimary: { primaryAction(for: entry, unlocked: response.unlocked) }
                    )
                }
                if merchantFilter == nil, let category = viewModel.selectedCategory {
                    ForEach(RewardsMath.filter(viewModel.items, category: category)) { (item: RewardItem) in
                        RewardItemCard(
                            item: item,
                            balance: viewModel.spendableBalance(for: item),
                            isRedeeming: isRedeeming,
                            onDirections: { openDirections(for: item) },
                            onRedeem: { askToRedeem(item) }
                        )
                    }
                }
            }
            AskForInvoiceTip()
        }
    }

    // MARK: - Vitrina (Descuentos > Todos)

    /// Fila de comercios arriba y una fila por categoria con sus beneficios
    /// (gratis y con cashback), como una vitrina.
    @ViewBuilder
    private func marketplace(unlocked: Bool) -> some View {
        let stores = PartnerMerchantSummary.group(viewModel.items, benefits: benefitItems)
        if !stores.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                marketplaceHeader(L("Comercios"), actionTitle: L("Ver todos")) {
                    withAnimation(.snappy) { mode = .merchants }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(stores) { (store: PartnerMerchantSummary) in
                            Button {
                                withAnimation(.snappy) {
                                    merchantFilter = store.id
                                    mode = store.items.isEmpty ? .benefits : .rewards
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    MerchantLogoView(urlString: store.merchant?.logoUrl, name: store.name, size: 62)
                                    Text(store.name)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                }
                                .frame(width: 78)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }

        let allItems = benefitItems + viewModel.items
        let categories = RewardsMath.orderedCategories(RewardsMath.categories(of: allItems), info: viewModel.categoryInfo)
        ForEach(categories, id: \.self) { (category: String) in
            marketplaceRow(
                title: RewardsMath.categoryTitle(category, info: viewModel.categoryInfo),
                entries: viewModel.benefits.benefits.filter { RewardsMath.filter([$0.item], category: category).count == 1 },
                items: RewardsMath.filter(viewModel.items, category: category),
                unlocked: unlocked,
                seeAll: { withAnimation(.snappy) { viewModel.selectedCategory = category } }
            )
        }
        let known = Set(categories)
        let uncategorized: (RewardItem) -> Bool = { item in
            let category = item.merchant?.category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !known.contains(category)
        }
        marketplaceRow(
            title: L("Más beneficios"),
            entries: viewModel.benefits.benefits.filter { uncategorized($0.item) },
            items: viewModel.items.filter(uncategorized),
            unlocked: unlocked,
            seeAll: nil
        )
    }

    @ViewBuilder
    private func marketplaceRow(
        title: String,
        entries: [BenefitEntry],
        items: [RewardItem],
        unlocked: Bool,
        seeAll: (() -> Void)?
    ) -> some View {
        if !entries.isEmpty || !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                marketplaceHeader(title, actionTitle: seeAll == nil ? nil : "Ver todo", action: seeAll ?? {})
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(entries) { (entry: BenefitEntry) in
                            benefitTile(entry, unlocked: unlocked)
                        }
                        ForEach(items) { (item: RewardItem) in
                            cashbackTile(item)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func marketplaceHeader(_ title: String, actionTitle: String?, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.system(.headline, design: MonAviBrand.fontDesign, weight: .bold))
            Spacer()
            if let actionTitle {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .tint(MonAviBrand.primary)
            }
        }
    }

    /// Descuento o bono gratis por ser de MonAvi.
    private func benefitTile(_ entry: BenefitEntry, unlocked: Bool) -> some View {
        let state = BenefitsMath.state(of: entry, unlocked: unlocked)
        let button: (title: String, enabled: Bool) = {
            switch state {
            case .locked: return ("Desbloquear", true)
            case .available: return ("Usar", true)
            case .active: return (L("Ver código"), true)
            case .cooldown: return ("Disponible pronto", false)
            case .usedUp: return (L("Ya lo usaste"), false)
            }
        }()
        return MarketplaceOfferTile(
            photoUrl: entry.item.photoUrl,
            placeholderSymbol: entry.item.kind.placeholderSymbol,
            merchantName: entry.item.merchantName,
            title: entry.item.name,
            costText: "Gratis",
            buttonTitle: button.title,
            buttonEnabled: button.enabled && !isRedeeming,
            progress: nil,
            action: { primaryAction(for: entry, unlocked: unlocked) }
        )
    }

    /// Descuento, bono o producto que se desbloquea con cashback.
    private func cashbackTile(_ item: RewardItem) -> some View {
        let balance = viewModel.spendableBalance(for: item)
        let affordable = RewardsMath.canAfford(cost: item.pointsCost, balance: balance)
        return MarketplaceOfferTile(
            photoUrl: item.photoUrl,
            placeholderSymbol: item.kind.placeholderSymbol,
            merchantName: item.merchantName,
            title: item.name,
            costText: item.formattedCost,
            buttonTitle: affordable ? (item.isUnlockable ? L("Desbloquear") : L("Canjear")) : L("Ver"),
            buttonEnabled: !isRedeeming,
            progress: affordable ? nil : (balance: balance, cost: item.pointsCost, currency: item.currency),
            action: {
                if affordable {
                    askToRedeem(item)
                } else {
                    withAnimation(.snappy) {
                        merchantFilter = item.merchantId
                        mode = .rewards
                    }
                }
            }
        )
    }

    private func primaryAction(for entry: BenefitEntry, unlocked: Bool) {
        switch BenefitsMath.state(of: entry, unlocked: unlocked) {
        case .locked:
            isScanningInvoice = true
        case .active(let redemption):
            presentedRedemption = redemption
        case .available:
            pendingBenefit = entry.item
            isConfirmingBenefit = true
        case .cooldown, .usedUp:
            break
        }
    }

    private func useBenefit(_ item: RewardItem) async {
        guard !isRedeeming else { return }
        isRedeeming = true
        do {
            let redemption = try await RewardsRepository.shared.useBenefit(item: item)
            isRedeeming = false
            pendingBenefit = nil
            celebrateRedemptionId = redemption.id
            presentedRedemption = redemption
        } catch let error where RewardsRepository.requiresEmailVerification(error) {
            isRedeeming = false
            benefitAwaitingVerification = item
            didVerifyEmail = false
            isVerifyingEmail = true
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            isRedeeming = false
            redeemErrorMessage = RewardsRepository.userMessage(for: error)
        }
        await viewModel.refreshBenefits()
    }

    // MARK: - Contenido

    @ViewBuilder
    private var content: some View {
        if mode == .benefits {
            benefitsContent
        } else if mode == .merchants && !merchantSummaries.isEmpty {
            merchantsList
        } else if !viewModel.hasLoaded && viewModel.items.isEmpty {
            ProgressView("Cargando comercios…")
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
            errorState(errorMessage)
        } else if viewModel.items.isEmpty {
            emptyState
        } else if mode == .merchants {
            merchantsList
        } else if visibleItems.isEmpty {
            emptyState
        } else {
            itemsList
        }
    }

    private var visibleItems: [RewardItem] {
        if let merchantFilter {
            return viewModel.items.filter { $0.merchantId == merchantFilter }
        }
        return viewModel.filteredItems
    }

    private var merchantsList: some View {
        ForEach(merchantSummaries) { (summary: PartnerMerchantSummary) in
            let sample = summary.items.first ?? summary.benefits[0]
            PartnerMerchantRow(
                summary: summary,
                balance: viewModel.spendableBalance(for: sample),
                onDirections: { openDirections(for: sample) },
                onShowRewards: {
                    withAnimation(.snappy) {
                        merchantFilter = summary.id
                        // Solo descuentos: se abre la pestaña de descuentos.
                        mode = summary.items.isEmpty ? .benefits : .rewards
                    }
                }
            )
        }
    }

    private func merchantFilterChip(_ merchantId: UUID) -> some View {
        let name = (viewModel.items + benefitItems).first { $0.merchantId == merchantId }?.merchantName ?? "Comercio"
        return Button {
            withAnimation(.snappy) {
                merchantFilter = nil
                // Los premios de un comercio se abren desde "Comercios":
                // al quitar el filtro se vuelve a la lista de comercios.
                if mode == .rewards { mode = .merchants }
            }
        } label: {
            Label("\(name)  ✕", systemImage: "storefront")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(MonAviBrand.primary, in: Capsule())
                .foregroundStyle(Color.white)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Quitar filtro de \(name)")
    }

    private var itemsList: some View {
        ForEach(visibleItems) { (item: RewardItem) in
            RewardItemCard(
                item: item,
                balance: viewModel.spendableBalance(for: item),
                isRedeeming: isRedeeming,
                onDirections: { openDirections(for: item) },
                onRedeem: { askToRedeem(item) }
            )
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if viewModel.items.isEmpty {
            ContentUnavailableView(
                "Pronto habrá comercios aliados",
                systemImage: "gift",
                description: Text("Pronto verás aquí los comercios aliados donde canjear tu cashback.")
            )
            .padding(.top, 24)
        } else {
            ContentUnavailableView(
                "Nada en esta categoría",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Prueba con otra categoría o toca \"Todos\".")
            )
            .padding(.top, 24)
        }
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Algo salió mal", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Reintentar") {
                Task { await refresh() }
            }
            .buttonStyle(.borderedProminent)
            .tint(MonAviBrand.primary)
        }
        .padding(.top, 24)
    }

    @ViewBuilder
    private var redeemingOverlay: some View {
        if isRedeeming {
            ZStack {
                Color.black.opacity(0.15).ignoresSafeArea()
                ProgressView(pendingItem?.isUnlockable == true ? "Desbloqueando…" : "Canjeando…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    // MARK: - Acciones

    private var confirmationTitle: String {
        guard let item = pendingItem else { return L("¿Canjear este producto?") }
        if item.isUnlockable {
            return L("¿Desbloquear %@ en %@ por %@ de cashback? Lo usas en caja en los próximos %@ días.", "\(item.name)", "\(item.merchantName)", "\(item.formattedCost)", "\(item.unlockValidDays ?? 7)")
        }
        return RewardsMath.confirmationTitle(
            itemName: item.name,
            merchantName: item.merchantName,
            cost: item.pointsCost,
            currency: item.currency
        )
    }

    private var isShowingRedeemError: Binding<Bool> {
        Binding(
            get: { redeemErrorMessage != nil },
            set: { newValue in
                if !newValue { redeemErrorMessage = nil }
            }
        )
    }

    private func askToRedeem(_ item: RewardItem) {
        pendingItem = item
        isConfirming = true
    }

    private func openDirections(for item: RewardItem) {
        let options = RewardsMath.directionsOptions(for: item.merchant)
        if options.count > 1 {
            directionsChoices = options
            isChoosingBranch = true
            return
        }
        let url = options.first?.url
            ?? RewardsMath.directionsURL(name: item.merchantName, address: nil, mapsUrl: nil)
        if let url {
            openURL(url)
        }
    }

    private func redeem(_ item: RewardItem) async {
        guard !isRedeeming else { return }
        isRedeeming = true
        do {
            let redemption = try await RewardsRepository.shared.redeem(item: item)
            isRedeeming = false
            pendingItem = nil
            celebrateRedemptionId = redemption.id
            presentedRedemption = redemption
        } catch let error where RewardsRepository.requiresEmailVerification(error) {
            // Primer canje con el correo sin verificar: pedir el codigo y,
            // al verificar, reintentar este mismo canje.
            isRedeeming = false
            itemAwaitingVerification = item
            didVerifyEmail = false
            isVerifyingEmail = true
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            isRedeeming = false
            redeemErrorMessage = RewardsRepository.userMessage(for: error)
        }
        if let userId = appState.currentUserId {
            if redeemErrorMessage != nil || item.maxRedemptions != nil {
                // "Se agotó" o un canje con cupo: se recarga el catalogo
                // para que desaparezca o se actualice su "Quedan N".
                await viewModel.refresh(userId: userId)
            } else {
                await viewModel.refreshBalance(userId: userId)
            }
        }
    }

    /// Al cerrar EmailVerificationSheet: si se verifico, reintenta el canje
    /// pendiente (despues de cerrar la hoja, para poder presentar el
    /// codigo del canje sin chocar con la animacion de cierre).
    private func retryAfterEmailVerification() {
        let item = itemAwaitingVerification
        let benefit = benefitAwaitingVerification
        let verified = didVerifyEmail
        itemAwaitingVerification = nil
        benefitAwaitingVerification = nil
        didVerifyEmail = false
        guard verified else { return }
        if let item {
            Task { await redeem(item) }
        } else if let benefit {
            Task { await useBenefit(benefit) }
        }
    }

    private func refresh() async {
        guard let userId = appState.currentUserId else { return }
        await viewModel.refresh(userId: userId)
    }
}

/// Tarjeta chica de la vitrina: foto, comercio, nombre, costo ("Gratis" o
/// "$1.00"), barra de "te faltan" y boton.
struct MarketplaceOfferTile: View {
    let photoUrl: String?
    let placeholderSymbol: String
    let merchantName: String
    let title: String
    let costText: String
    let buttonTitle: String
    let buttonEnabled: Bool
    let progress: (balance: Int, cost: Int, currency: RewardCurrency)?
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RewardPhotoView(urlString: photoUrl, cornerRadius: 14, placeholderSymbol: placeholderSymbol)
            Text(merchantName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2, reservesSpace: true)
            Text(costText)
                .font(.caption.weight(.bold))
                .foregroundStyle(MonAviBrand.primaryDark)
            if let progress {
                RewardProgressBar(balance: progress.balance, cost: progress.cost, currency: progress.currency, compact: true)
            }
            Spacer(minLength: 0)
            Button(action: action) {
                Text(buttonTitle)
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(MonAviBrand.primary)
            .disabled(!buttonEnabled)
        }
        .frame(width: 168)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}
