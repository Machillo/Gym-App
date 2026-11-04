import SwiftData
import SwiftUI

/// Aro de avance de un reto.
struct ChallengeRing: View {
    var fraction: Double
    var complete: Bool
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            Circle().stroke(Theme.accent.opacity(0.2), lineWidth: size / 8)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(complete ? Theme.success : Theme.glow, style: StrokeStyle(lineWidth: size / 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if complete {
                Image(systemName: "checkmark").font(.system(size: size / 3, weight: .bold)).foregroundStyle(Theme.success)
            } else {
                Text(Format.percent(fraction)).font(Theme.mono(size / 5, weight: .bold))
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(complete ? "Cumplido" : Format.percent(fraction))
    }
}

struct ChallengeRow: View {
    let challenge: Challenge

    var body: some View {
        HStack(spacing: 14) {
            ChallengeRing(fraction: challenge.fraction, complete: challenge.isComplete)
            VStack(alignment: .leading, spacing: 2) {
                Text(challenge.title).font(.headline)
                Text(challenge.detail).font(.caption).foregroundStyle(Theme.secondaryText)
                Text("\(Int(challenge.current)) / \(Int(challenge.target))")
                    .font(Theme.mono(12, weight: .semibold))
                    .foregroundStyle(Theme.glow)
            }
        }
    }
}

@MainActor
struct ChallengesView: View {
    @Environment(GameService.self) private var game
    @Query private var players: [Player]
    @Query(sort: \ChallengeAward.date, order: .reverse) private var awards: [ChallengeAward]

    var body: some View {
        let _ = game.revision
        List {
            if let player = players.first {
                let input = game.challengeInput(player: player)
                let earned = Set(awards.map(\.key))
                Section("Esta semana") {
                    ForEach(ChallengeEngine.weekly(input)) { ChallengeRow(challenge: $0) }
                }
                .listRowBackground(Theme.panel)
                Section("Este mes") {
                    ForEach(ChallengeEngine.monthly(input)) { ChallengeRow(challenge: $0) }
                }
                .listRowBackground(Theme.panel)
                Section("Logros por conseguir") {
                    ForEach(ChallengeEngine.milestones(input).filter { !earned.contains($0.key) }) { ChallengeRow(challenge: $0) }
                }
                .listRowBackground(Theme.panel)
            }
            if !awards.isEmpty {
                Section("Ganados") {
                    ForEach(awards, id: \.key) { award in
                        HStack(spacing: 12) {
                            Image(systemName: "medal.fill").foregroundStyle(Theme.warning)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(award.title).font(.headline)
                                Text("\(award.detail) · \(award.date.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                }
                .listRowBackground(Theme.panel)
            }
        }
        .systemBackground()
        .navigationTitle("Retos")
    }
}
