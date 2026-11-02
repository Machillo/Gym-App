import SwiftData
import SwiftUI

struct TrialsView: View {
    @Environment(GameService.self) private var game
    @Query private var players: [Player]
    @Query(sort: \AscensionTrial.targetRankRaw) private var trials: [AscensionTrial]

    var body: some View {
        let _ = game.revision
        ScrollView {
            VStack(spacing: 16) {
                if let player = players.first {
                    current(player)
                    ForEach(trials) { trial in
                        trialCard(trial, player: player)
                    }
                }
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Pruebas de ascenso")
    }

    private func current(_ player: Player) -> some View {
        let progress = player.progress
        return VStack(alignment: .leading, spacing: 8) {
            PanelHeader(title: "Estado de ascenso", symbol: "shield.lefthalf.filled")
            Text(progress.position.title).font(Theme.mono(14, weight: .semibold))
            Text(availabilityText(progress.trialAvailability(now: game.now)))
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            Text("Las pruebas se superan solas cuando registrás la sesión que completa el último requisito.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .systemPanel()
    }

    private func trialCard(_ trial: AscensionTrial, player: Player) -> some View {
        let isNext = trial.target == player.progress.unlockedRank.next
        let statuses = isNext ? AscensionEngine.evaluate(target: trial.target, metrics: game.trialMetrics(player: player)) : []
        let tint: Color = trial.state == .passed ? Theme.success : (trial.state == .available ? Theme.glow : Theme.secondaryText)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Prueba de rango \(trial.target.letter)").font(.headline)
                Spacer()
                Text(trial.state.label.uppercased())
                    .font(Theme.mono(11, weight: .bold))
                    .foregroundStyle(tint)
            }
            Text("Tiempo mínimo en el rango anterior: \(trial.target.minMonthsInPreviousRank) mes(es)")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            if isNext {
                ForEach(statuses) { status in
                    HStack(alignment: .top) {
                        Image(systemName: status.met ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(status.met ? Theme.success : Theme.secondaryText)
                        VStack(alignment: .leading) {
                            Text(status.requirement.description).font(.subheadline)
                            Text(status.progress).font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
            } else {
                ForEach(AscensionEngine.requirements(for: trial.target), id: \.self) { req in
                    Text("• \(req.description)").font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
            if let passed = trial.passedAt {
                Text("Superada el \(passed.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(Theme.success)
            }
        }
        .systemPanel(tint: tint)
        .opacity(trial.state == .locked && !isNext ? 0.6 : 1)
    }

    private func availabilityText(_ availability: TrialAvailability) -> String {
        switch availability {
        case let .needsLevel(level):
            return "Alcanzá el nivel \(level) para habilitar la siguiente prueba."
        case let .needsTime(date):
            return "Tiempo mínimo en el rango: disponible desde el \(date.formatted(date: .abbreviated, time: .omitted))."
        case let .available(rank):
            return "Prueba de rango \(rank.letter) disponible. Cumplí los requisitos."
        case .maxed:
            return "Rango máximo alcanzado."
        }
    }
}
