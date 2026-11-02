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

    var body: some View {
        let _ = game.revision
        ScrollView {
            VStack(spacing: 16) {
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
