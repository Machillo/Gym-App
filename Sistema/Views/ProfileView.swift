import SwiftData
import SwiftUI

/// Quién sos hoy y en qué te vas convirtiendo.
@MainActor
struct ProfileView: View {
    @Environment(GameService.self) private var game
    @Query private var players: [Player]
    @Query(sort: \SystemLogEntry.date, order: .reverse) private var logs: [SystemLogEntry]
    @Query(sort: \BodyEntry.date) private var bodyEntries: [BodyEntry]

    var body: some View {
        let _ = game.revision
        ScrollView {
            if let player = players.first {
                let profile = game.profile(player: player)
                VStack(spacing: 16) {
                    identity(profile, player: player)
                    if profile.totalMinutes > 0 { style(profile) }
                    if !profile.disciplines.isEmpty { disciplines(profile) }
                    next(player)
                    bodyPanel
                    evolution
                }
                .padding()
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Perfil")
    }

    private func identity(_ profile: FighterProfile, player: Player) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelHeader(title: "Hoy sos", symbol: "person.text.rectangle")
            Text(profile.title ?? "\(profile.tier) por definir")
                .font(.title2.bold())
                .accessibilityIdentifier("profile.title")
            Text(profile.title == nil
                 ? "Tu estilo sale de lo que registrés. Con tu primera sesión aparece."
                 : "El nivel sale de tu rango y el estilo, de tus últimas \(FighterProfile.windowDays / 7) semanas. Si cambiás lo que entrenás, cambia tu perfil.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            if let strongest = profile.strongest, let weakest = profile.weakest, strongest != weakest {
                Divider()
                Label("Tu fuerte: \(strongest.name)", systemImage: "arrow.up.circle.fill").foregroundStyle(Theme.success)
                Label("Por mejorar: \(weakest.name)", systemImage: "arrow.down.circle.fill").foregroundStyle(Theme.warning)
            }
        }
        .systemPanel()
    }

    private func style(_ profile: FighterProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelHeader(title: "Tu estilo", symbol: "chart.pie.fill")
            share("Pelea", profile.fightMinutes, of: profile.totalMinutes)
            share("Fuerza", profile.strengthMinutes, of: profile.totalMinutes)
            share("Acondicionamiento", profile.conditioningMinutes, of: profile.totalMinutes)
        }
        .systemPanel()
    }

    private func share(_ label: String, _ minutes: Double, of total: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text(Format.percent(total > 0 ? minutes / total : 0)).font(Theme.mono(13, weight: .bold))
            }
            XPBar(current: Int(minutes), needed: max(Int(total), 1), tint: Theme.accent)
        }
    }

    private func disciplines(_ profile: FighterProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelHeader(title: "Clases", symbol: "figure.boxing")
            ForEach(profile.disciplines) { item in
                HStack {
                    Text(item.discipline.name)
                    Spacer()
                    Text("\(Format.count(item.classes, "clase")) · \(Format.minutes(item.minutes))")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .systemPanel()
    }

    @ViewBuilder
    private func next(_ player: Player) -> some View {
        let rank = player.position.rank
        if let target = Rank(rawValue: rank.rawValue + 1) {
            VStack(alignment: .leading, spacing: 8) {
                PanelHeader(title: "Siguiente evolución", symbol: "arrow.up.forward.circle")
                Text("\(FighterProfile.tier(for: target)) · Rango \(target.letter)").font(.headline)
                ForEach(AscensionEngine.requirements(for: target), id: \.self) { requirement in
                    Label(requirement.description, systemImage: "circle")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .systemPanel()
        }
    }

    private var bodyPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelHeader(title: "Tu cuerpo", symbol: "figure.stand")
            if let weight = bodyEntries.last(where: { $0.weightKg != nil }) {
                Text("Peso: \(Format.weight(weight.weightKg ?? 0, unit: weight.weightUnit))")
            }
            if let fat = bodyEntries.last(where: { $0.bodyFatPercent != nil })?.bodyFatPercent {
                Text("Grasa: \(BodyMetric.bodyFat.text(fat, weightUnit: .kg))")
            }
            NavigationLink(bodyEntries.isEmpty ? "Registrar peso y medidas" : "Ver todo") { BodyView() }
                .font(.footnote)
        }
        .systemPanel()
    }

    private var evolution: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelHeader(title: "Tu evolución", symbol: "point.topleft.down.to.point.bottomright.curvepath")
            let history = logs.filter { $0.kind == .profile }
            if history.isEmpty { Text("Todavía sin cambios.").foregroundStyle(Theme.secondaryText) }
            ForEach(history) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.message).font(.footnote)
                    Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .systemPanel()
    }
}
