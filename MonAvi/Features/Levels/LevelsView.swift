import SwiftUI

/// "Nivel e insignias": la experiencia que da cuidar tus finanzas. No se
/// canjea por nada — es para motivarte (ver HabitEngine para las reglas).
struct LevelsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = LevelsViewModel()

    private let badgeColumns = [GridItem(.adaptive(minimum: 100), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let progress = viewModel.progress {
                    levelCard(progress)
                    disclaimer
                    badgesSection(progress)
                    sourcesSection(progress)
                    savingsSection(progress)
                    rulesSection
                } else if viewModel.isLoading {
                    ProgressView().padding(.top, 60)
                } else if let errorMessage = viewModel.errorMessage {
                    ContentUnavailableView(
                        "No se pudo cargar",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Nivel e insignias")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    // MARK: - Nivel

    private func levelCard(_ progress: HabitEngine.Progress) -> some View {
        let level = progress.level

        return VStack(spacing: 14) {
            Text(level.emoji)
                .font(.system(size: 56))
                .accessibilityHidden(true)

            VStack(spacing: 2) {
                Text("Nivel \(level.number)")
                    .font(.subheadline.weight(.semibold))
                    .opacity(0.8)
                Text(level.name)
                    .font(.system(size: 30, weight: .bold, design: MonAviBrand.fontDesign))
            }

            VStack(spacing: 6) {
                ProgressView(value: level.progress(xp: progress.totalXP))
                    .tint(MonAviBrand.accentOnDark)
                HStack {
                    Text("\(progress.totalXP) XP")
                    Spacer()
                    if let next = level.nextLevelXP {
                        Text("Faltan \(next - progress.totalXP) XP para el nivel \(level.number + 1)")
                    } else {
                        Text("¡Nivel máximo!")
                    }
                }
                .font(.caption.weight(.medium))
                .opacity(0.85)
            }

            HStack(spacing: 0) {
                stat(value: "\(progress.currentStreak)", label: progress.currentStreak == 1 ? "día seguido 🔥" : "días seguidos 🔥")
                Divider().frame(height: 32).overlay(MonAviBrand.onDarkSurface.opacity(0.3))
                stat(value: "\(progress.earnedBadges.count)/\(progress.badges.count)", label: "insignias")
                Divider().frame(height: 32).overlay(MonAviBrand.onDarkSurface.opacity(0.3))
                stat(value: "\(progress.xpThisMonth)/\(HabitEngine.Rules.monthlyXPCap)", label: "XP este mes")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .foregroundStyle(MonAviBrand.onDarkSurface)
        .background(MonAviBrand.headerGradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .opacity(0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private var disclaimer: some View {
        Label {
            Text("Los niveles e insignias son para motivarte: no se canjean por dinero ni premios. Los puntos canjeables vienen solo de facturas verificadas por la DGI.")
        } icon: {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(MonAviBrand.primary)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(cardBackground)
    }

    // MARK: - Insignias

    private func badgesSection(_ progress: HabitEngine.Progress) -> some View {
        section(title: "Insignias") {
            LazyVGrid(columns: badgeColumns, spacing: 12) {
                ForEach(progress.badges) { badge in
                    badgeCell(badge)
                }
            }
        }
    }

    private func badgeCell(_ badge: HabitBadge) -> some View {
        VStack(spacing: 6) {
            Text(badge.emoji)
                .font(.system(size: 34))
                .grayscale(badge.isEarned ? 0 : 1)
                .opacity(badge.isEarned ? 1 : 0.4)
                .frame(width: 60, height: 60)
                .background(
                    Circle().fill(badge.isEarned ? MonAviBrand.primary.opacity(0.15) : Color(.tertiarySystemFill))
                )
                .overlay(
                    Circle().strokeBorder(badge.isEarned ? MonAviBrand.primary : Color.clear, lineWidth: 2)
                )

            Text(badge.title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            if badge.isEarned {
                Text("¡Ganada!")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(MonAviBrand.primary)
            } else {
                ProgressView(value: badge.progress)
                    .tint(MonAviBrand.primary)
                Text("\(min(badge.current, badge.target))/\(badge.target)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(badge.title). \(badge.detail) \(badge.isEarned ? "Ganada" : "Progreso \(min(badge.current, badge.target)) de \(badge.target)")")
    }

    // MARK: - Como se gana XP

    private func sourcesSection(_ progress: HabitEngine.Progress) -> some View {
        section(title: "Cómo ganas experiencia") {
            VStack(spacing: 0) {
                ForEach(HabitEngine.XPSource.allCases) { source in
                    HStack(alignment: .top, spacing: 12) {
                        Text(source.emoji)
                            .font(.title3)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.title)
                                .font(.subheadline.weight(.semibold))
                            Text(source.rule)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text("\(progress.xpBySource[source] ?? 0) XP")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(MonAviBrand.primary)
                    }
                    .padding(.vertical, 10)

                    if source != HabitEngine.XPSource.allCases.last {
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - Ahorro

    private func savingsSection(_ progress: HabitEngine.Progress) -> some View {
        section(title: "Tus aportes de ahorro") {
            VStack(alignment: .leading, spacing: 0) {
                if progress.contributionReviews.isEmpty {
                    Text("Todavía no tienes aportes. Crea una meta y aparta algo cada semana: cada aporte que se quede 30 días sin retirarse suma a tu nivel.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    ForEach(progress.contributionReviews.prefix(10)) { review in
                        contributionRow(review)
                        if review.id != progress.contributionReviews.prefix(10).last?.id {
                            Divider()
                        }
                    }
                }

                NavigationLink {
                    SavingsGoalsView()
                } label: {
                    Label("Ir a mis metas de ahorro", systemImage: "chevron.right")
                        .labelStyle(TrailingIconLabelStyle())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MonAviBrand.primary)
                        .padding(.top, 10)
                }
            }
        }
    }

    private func contributionRow(_ review: HabitEngine.ContributionReview) -> some View {
        let goal = viewModel.goalsById[review.contribution.goalId]
        let (text, icon, color) = statusInfo(review.status)

        return HStack(spacing: 12) {
            Text(goal?.emoji ?? "🎯")
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(goal?.name ?? "Meta eliminada")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Label(text, systemImage: icon)
                    .font(.caption)
                    .foregroundStyle(color)
            }
            Spacer(minLength: 8)
            Text(review.contribution.amount, format: .currency(code: "USD"))
                .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func statusInfo(_ status: HabitEngine.ContributionStatus) -> (String, String, Color) {
        switch status {
        case .matured:
            return ("Maduró: cuenta para tu nivel", "checkmark.seal.fill", MonAviBrand.primary)
        case .maturing(let date):
            return ("Madura el \(date.formatted(.dateTime.day().month(.abbreviated)))", "hourglass", Color.secondary)
        case .broken:
            return ("No cuenta: retiraste antes de 30 días", "xmark.circle", MonAviBrand.alert)
        case .unbacked:
            return ("No cuenta: no cuadra con tus ingresos y gastos de ese mes", "exclamationmark.circle", MonAviBrand.alert)
        }
    }

    private var rulesSection: some View {
        section(title: "Para que tu ahorro cuente") {
            VStack(alignment: .leading, spacing: 8) {
                ruleRow("Se premia la constancia, no el monto: apartar $5 cada semana vale lo mismo que apartar $500.")
                ruleRow("Lo que ahorras en un mes tiene que caber en lo que registraste ese mes (ingresos menos gastos). Anota tus ingresos.")
                ruleRow("Un aporte cuenta cuando pasan 30 días sin retirar dinero de esa meta.")
                ruleRow("Los días anotados se cuentan el día que anotas, no la fecha que le pones al movimiento.")
                ruleRow("Puedes ganar hasta \(HabitEngine.Rules.monthlyXPCap) XP por mes.")
            }
        }
    }

    private func ruleRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(MonAviBrand.primary)
                .font(.footnote)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Utilidades

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
    }

    private func refresh() async {
        guard let userId = appState.currentUserId else { return }
        await viewModel.refresh(userId: userId)
    }
}

/// "Texto  >" con el icono a la derecha.
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}
