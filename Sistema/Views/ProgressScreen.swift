import Charts
import SwiftData
import SwiftUI

@MainActor
struct ProgressScreen: View {
    @Environment(GameService.self) private var game
    @Query(sort: \SystemLogEntry.date) private var logs: [SystemLogEntry]
    @Query(sort: \PenaltyEvent.date, order: .reverse) private var penalties: [PenaltyEvent]
    @Query(sort: \Itinerary.startDate, order: .reverse) private var itineraries: [Itinerary]
    @Query private var sessions: [WorkoutSession]
    @Query private var players: [Player]
    @Query private var exerciseLogs: [ExerciseLog]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query(sort: \BodyEntry.date) private var bodyEntries: [BodyEntry]

    var body: some View {
        let _ = game.revision
        ScrollView {
            VStack(spacing: 16) {
                weeklySummary
                challenges
                bodyPanel
                exerciseProgress
                xpChart
                complianceByItinerary
                rankTimeline
                penaltyLog
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Progreso")
    }

    private func summary(weekOf date: Date) -> WeeklySummary {
        WeeklySummary.make(weekOf: date, sessions: sessions.filter { !$0.isPunishment }.map(\.digest),
                           volumes: exerciseLogs.map { ($0.date, $0.volume) }, records: exerciseLogs.compactMap(\.markRecord))
    }

    private var weeklySummary: some View {
        let current = summary(weekOf: game.now)
        let previous = summary(weekOf: SistemaCalendar.addDays(-7, to: game.now))
        return VStack(alignment: .leading, spacing: 8) {
            PanelHeader(title: "Esta semana", symbol: "calendar")
            summaryRow("Sesiones", "\(current.sessions)", previous: "\(previous.sessions)")
            summaryRow("Tiempo", Format.minutes(current.minutes), previous: Format.minutes(previous.minutes))
            summaryRow("Peso levantado", volumeText(current.volumeKg), previous: volumeText(previous.volumeKg))
            summaryRow("Clases", "\(current.classes)", previous: "\(previous.classes)")
            summaryRow("Marcas nuevas", "\(current.records)", previous: "\(previous.records)")
        }
        .systemPanel()
    }

    private func summaryRow(_ label: String, _ value: String, previous: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(value).font(Theme.mono(14, weight: .bold)).foregroundStyle(Theme.glow)
                Text("antes: \(previous)").font(.caption2).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func volumeText(_ kg: Double) -> String {
        "\(Int(kg.rounded())) kg"
    }

    private var challenges: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelHeader(title: "Retos", symbol: "trophy.fill")
            if let player = players.first {
                let active = ChallengeEngine.active(game.challengeInput(player: player))
                HStack(spacing: 12) {
                    ForEach(active.prefix(4)) { challenge in
                        VStack(spacing: 4) {
                            ChallengeRing(fraction: challenge.fraction, complete: challenge.isComplete, size: 56)
                            Text(challenge.title)
                                .font(.caption2)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            NavigationLink("Ver todos los retos") { ChallengesView() }
                .font(.footnote)
                .accessibilityIdentifier("progress.challenges")
        }
        .systemPanel()
    }

    private var bodyPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelHeader(title: "Cuerpo", symbol: "figure.stand")
            let snapshots = bodyEntries.map(\.snapshot)
            let unit = bodyEntries.last(where: { $0.weightKg != nil })?.weightUnit ?? .kg
            ForEach([BodyMetric.weight, .bodyFat, .measure(.waist), .measure(.armRight)]) { metric in
                if let trend = BodyTrend.make(metric, entries: snapshots) {
                    HStack {
                        Text(metric.name)
                        Spacer()
                        Text(metric.text(trend.current, weightUnit: unit)).font(Theme.mono(14, weight: .bold)).foregroundStyle(Theme.glow)
                    }
                }
            }
            NavigationLink(bodyEntries.isEmpty ? "Registrar peso, grasa y medidas" : "Ver todo") { BodyView() }
                .font(.footnote)
                .accessibilityIdentifier("progress.body")
        }
        .systemPanel()
    }

    /// Los ejercicios entrenados más recientemente, con su gráfico.
    private var exerciseProgress: some View {
        let latest = Dictionary(grouping: exerciseLogs.filter { $0.exerciseID != nil && $0.weight > 0 }, by: \.exerciseID)
            .compactMapValues { $0.map(\.date).max() }
        let recent = exercises.filter { latest[$0.id] != nil }
            .sorted { (latest[$0.id] ?? .distantPast) > (latest[$1.id] ?? .distantPast) }
            .prefix(6)
        return VStack(alignment: .leading, spacing: 10) {
            PanelHeader(title: "Tus ejercicios", symbol: "dumbbell.fill")
            if recent.isEmpty {
                Text("Registrá pesos en tus sesiones para ver cómo progresa cada ejercicio.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(Array(recent)) { exercise in
                NavigationLink { ExerciseDetailView(exercise: exercise) } label: {
                    HStack {
                        Text(exercise.name).foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                    }
                    .padding(.vertical, 4)
                }
            }
            NavigationLink("Ver todos") { ExercisesView() }
                .font(.footnote)
        }
        .systemPanel()
    }

    private var xpChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelHeader(title: "XP en el tiempo", symbol: "chart.line.uptrend.xyaxis")
            if logs.isEmpty {
                Text("Sin datos todavía.").foregroundStyle(Theme.secondaryText)
            } else {
                Chart(logs) { entry in
                    LineMark(x: .value("Fecha", entry.date), y: .value("XP", entry.totalXPAfter))
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(Theme.glow)
                }
                .frame(height: 200)
            }
        }
        .systemPanel()
    }

    private var complianceByItinerary: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelHeader(title: "Cumplimiento por itinerario", symbol: "percent")
            ForEach(itineraries) { itinerary in
                let value = compliance(for: itinerary)
                HStack {
                    Text(itinerary.name)
                    Spacer()
                    Text(value.map(Format.percent) ?? "—")
                        .font(Theme.mono(14, weight: .bold))
                        .foregroundStyle((value ?? 1) < 0.5 ? Theme.danger : Theme.glow)
                }
            }
            if itineraries.isEmpty { Text("Sin itinerarios.").foregroundStyle(Theme.secondaryText) }
        }
        .systemPanel()
    }

    private var rankTimeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelHeader(title: "Línea de rangos", symbol: "flag.checkered")
            let milestones = logs.filter { $0.kind == .rank || $0.kind == .trial }
            if milestones.isEmpty {
                Text("Rango E desde el inicio. Seguí entrenando.").foregroundStyle(Theme.secondaryText)
            }
            ForEach(milestones) { entry in
                HStack(alignment: .top) {
                    Circle().fill(Theme.glow).frame(width: 8, height: 8).padding(.top, 6)
                    VStack(alignment: .leading) {
                        Text(entry.message).font(.footnote)
                        Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
        }
        .systemPanel()
    }

    private var penaltyLog: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelHeader(title: "Bitácora de penalizaciones", symbol: "exclamationmark.triangle")
            if penalties.isEmpty {
                Text("Sin penalizaciones. Así se hace.").foregroundStyle(Theme.secondaryText)
            }
            ForEach(penalties) { event in
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.reason.label).font(.subheadline.bold())
                    Text(penaltyDetail(event))
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                }
            }
        }
        .systemPanel(tint: penalties.isEmpty ? Theme.accent : Theme.danger)
    }

    private func penaltyDetail(_ event: PenaltyEvent) -> String {
        var parts = [event.date.formatted(date: .abbreviated, time: .omitted), "−\(event.xpLost) XP"]
        if event.levelsLost > 0 { parts.append("−\(event.levelsLost) nivel(es)") }
        if event.rankLost { parts.append("rango perdido") }
        return parts.joined(separator: " · ")
    }

    /// Promedio de los días planeados ya cerrados (sin sesión = 0 %).
    private func compliance(for itinerary: Itinerary) -> Double? {
        guard let player = game.player() else { return nil }
        let yesterday = SistemaCalendar.addDays(-1, to: SistemaCalendar.startOfDay(game.now))
        let end = min(itinerary.endDate, yesterday)
        guard end >= itinerary.startDate else { return nil }
        let snapshot = itinerary.snapshot
        var bestByDay: [Date: Double] = [:]
        for s in sessions where !s.isPunishment && s.itineraryID == itinerary.id {
            if let day = s.plannedDay { bestByDay[day] = max(bestByDay[day] ?? 0, s.compliance) }
        }
        var total = 0.0
        var count = 0
        var day = itinerary.startDate
        let injuries = player.injuries
        while day <= end {
            if snapshot.isPlannedWeekday(day) && !injuries.contains(where: { $0.contains(day) }) {
                total += bestByDay[day] ?? 0
                count += 1
            }
            day = SistemaCalendar.addDays(1, to: day)
        }
        return count > 0 ? total / Double(count) : nil
    }
}
