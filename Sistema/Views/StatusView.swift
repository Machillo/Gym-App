import SwiftData
import SwiftUI

/// Modos de la pantalla de registro de sesión.
enum SessionLogMode: Identifiable {
    case planned(routineID: UUID?, itineraryID: UUID, day: Date)
    case free
    case punishment
    case edit(WorkoutSession)
    case classLog

    var id: String {
        switch self {
        case .planned: return "planned"
        case .free: return "free"
        case .punishment: return "punishment"
        case let .edit(session): return "edit-\(session.id)"
        case .classLog: return "classLog"
        }
    }
}

@MainActor
struct StatusView: View {
    @Environment(GameService.self) private var game
    @Query private var players: [Player]
    @Query(sort: \SystemLogEntry.date, order: .reverse) private var logs: [SystemLogEntry]
    @State private var logMode: SessionLogMode?

    var body: some View {
        let _ = game.revision
        ScrollView {
            VStack(spacing: 16) {
                if let player = players.first {
                    statusWindow(player)
                    alerts(player)
                    HunterStateCard()
                    missionCard
                    ActivityTodayCard()
                    statsPanel(player)
                    recentLog
                }
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Estado")
        .toolbarBackground(Theme.background, for: .navigationBar)
        .sheet(item: $logMode) { mode in
            NavigationStack { SessionLogView(mode: mode) }
        }
    }

    // MARK: - Ventana principal

    private func statusWindow(_ player: Player) -> some View {
        let progress = player.progress
        let position = progress.position
        let bar = progress.levelProgress
        let status = player.status(now: game.now)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                Text(position.rank.letter)
                    .font(Theme.display(64, weight: .black))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 76, height: 84)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.accent))
                    .accessibilityLabel("Rango \(position.rank.letter)")
                VStack(alignment: .leading, spacing: 4) {
                    Text(player.name).font(.title3.bold())
                    Text(position.title)
                        .font(Theme.mono(13))
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityIdentifier("status.position")
                    Label(status.label, systemImage: statusSymbol(status))
                        .font(.caption.bold())
                        .foregroundStyle(statusColor(status))
                    NavigationLink {
                        ProfileView()
                    } label: {
                        Label(player.profileTitle ?? "Ver mi perfil", systemImage: "person.text.rectangle")
                            .font(.caption.bold())
                    }
                    .accessibilityIdentifier("status.profile")
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                XPBar(current: bar.current, needed: bar.needed)
                HStack {
                    Text(bar.needed > 0 ? "\(bar.current) / \(bar.needed) XP" : "Nivel máximo")
                    Spacer()
                    Text("XP total: \(player.totalXP)")
                        .accessibilityIdentifier("status.totalXP")
                }
                .font(Theme.mono(12))
                .foregroundStyle(Theme.secondaryText)
                if progress.isCapped {
                    Text("Topado en el nivel \(progress.capLevel). Superá la prueba de ascenso. Desborde retenido: \(progress.overflowXP) XP.")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                }
            }
            HStack {
                Label("Racha: \(player.currentStreak)", systemImage: "flame.fill")
                Spacer()
                Text("Máxima: \(player.maxStreak)")
            }
            .font(Theme.mono(13, weight: .semibold))
            .foregroundStyle(Theme.warning)
        }
        .systemPanel(tint: status == .penaltyZone ? Theme.danger : Theme.accent)
    }

    // MARK: - Alertas

    @ViewBuilder
    private func alerts(_ player: Player) -> some View {
        if let mission = player.ledger.openMission {
            VStack(alignment: .leading, spacing: 8) {
                PanelHeader(title: "Zona de penalización", symbol: "exclamationmark.triangle.fill", tint: Theme.danger)
                Text(PunishmentMission.title).font(.headline)
                Text(PunishmentMission.detail).font(.subheadline).foregroundStyle(Theme.secondaryText)
                Text("Vence: \(mission.deadline.formatted(date: .abbreviated, time: .shortened))")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.danger)
                Button {
                    logMode = .punishment
                } label: {
                    Label("Registrar misión de castigo", systemImage: "bolt.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.primaryAction)
                .tint(Theme.danger)
            }
            .systemPanel(tint: Theme.danger)
        }
        if let injury = player.activeInjury(now: game.now) {
            VStack(alignment: .leading, spacing: 6) {
                PanelHeader(title: "Modo lesión/enfermo", symbol: "cross.case.fill")
                Text("Motivo: \(injury.reason)")
                Text("Hasta: \(injury.end.formatted(date: .abbreviated, time: .omitted)). Penalizaciones y racha congeladas.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            .systemPanel(tint: Theme.warning)
        }
        if let expiry = game.appExpiry, expiry > game.now, expiry.timeIntervalSince(game.now) < 3 * 86_400 {
            VStack(alignment: .leading, spacing: 6) {
                PanelHeader(title: "La app está por vencer", symbol: "clock.badge.exclamationmark")
                Text("Vence el \(expiry.formatted(date: .abbreviated, time: .shortened)). Conectá el iPhone a la Mac para reinstalar; tus datos no se pierden.")
                    .font(.subheadline)
            }
            .systemPanel(tint: Theme.warning)
        }
        if game.itineraryExpired() {
            VStack(alignment: .leading, spacing: 8) {
                PanelHeader(title: "Itinerario vencido", symbol: "calendar.badge.exclamationmark")
                Text(SystemMessages.itineraryExpired).font(.subheadline)
                NavigationLink("Cargar nuevo itinerario") { ItineraryEditorView(itinerary: nil) }
                    .buttonStyle(.primaryAction)
            }
            .systemPanel(tint: Theme.warning)
        }
    }

    // MARK: - Misión de hoy

    @ViewBuilder
    private var missionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelHeader(title: "Misión de hoy", symbol: "target")
            if let mission = game.todayMission() {
                Text(mission.routine?.name ?? "Rutina no encontrada").font(.title3.bold())
                if let routine = mission.routine {
                    ForEach(routine.blocks) { block in
                        Label(block.summary, systemImage: block.kind.symbol)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                if let done = mission.completedSession {
                    Label("Cumplida: \(Format.percent(done.compliance)) · +\(done.xpAwarded) XP", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(done.compliance >= 0.5 ? Theme.success : Theme.warning)
                        .accessibilityIdentifier("status.missionDone")
                } else {
                    Button {
                        logMode = .planned(routineID: mission.routine?.id, itineraryID: mission.itinerary.id, day: mission.day)
                    } label: {
                        Label("Registrar sesión", systemImage: "square.and.pencil").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primaryAction)
                    .accessibilityIdentifier("status.logMission")
                }
            } else if game.activeItinerary() != nil {
                Text("Día de descanso. Recuperarse también es parte del plan.")
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text("No hay itinerario activo.").foregroundStyle(Theme.secondaryText)
            }
            let pending = game.pendingMissions()
            if !pending.isEmpty {
                Divider()
                Text("Días pendientes").font(.subheadline.bold())
                ForEach(pending, id: \.day) { item in
                    Button {
                        logMode = .planned(routineID: item.routine?.id, itineraryID: item.itinerary.id, day: item.day)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.day.formatted(.dateTime.weekday(.wide).day().month().locale(Locale(identifier: "es_CR"))))
                                .font(.subheadline.bold())
                            Text(item.routine?.name ?? "Rutina no encontrada").font(.caption)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.secondaryAction)
                    .accessibilityIdentifier("status.logPending")
                }
                Text("Registrarlo tarde suma XP y queda en tu historial, pero no borra una falta ya cobrada.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Button {
                logMode = .classLog
            } label: {
                Label("Clase, sparring o pelea", systemImage: "figure.boxing").frame(maxWidth: .infinity)
            }
            .buttonStyle(.secondaryAction)
            .accessibilityIdentifier("status.logClass")
            Button {
                logMode = .free
            } label: {
                Label("Registrar sesión libre", systemImage: "plus.circle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.secondaryAction)
            .accessibilityIdentifier("status.logFree")
        }
        .systemPanel()
    }

    // MARK: - Stats

    private func statsPanel(_ player: Player) -> some View {
        let stats = player.stats
        let top = max(StatKind.allCases.map { stats[$0] }.max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 10) {
            PanelHeader(title: "Atributos", symbol: "chart.bar.fill")
            ForEach(StatKind.allCases) { kind in
                HStack {
                    Text(kind.short).font(Theme.mono(13, weight: .bold)).frame(width: 40, alignment: .leading)
                    XPBar(current: Int(stats[kind] * 10), needed: Int(top * 10), tint: Theme.accent)
                    Text(String(format: "%.1f", stats[kind]))
                        .font(Theme.mono(13))
                        .frame(width: 52, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(kind.name): \(String(format: "%.1f", stats[kind]))")
            }
        }
        .systemPanel()
    }

    private var recentLog: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelHeader(title: "Bitácora del Sistema", symbol: "text.alignleft")
            ForEach(logs.prefix(5)) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.message).font(.footnote)
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            NavigationLink("Ver todo") { SystemLogView() }
                .font(.footnote)
        }
        .systemPanel()
    }

    private func statusColor(_ status: PlayerStatus) -> Color {
        switch status {
        case .normal: return Theme.success
        case .penaltyZone: return Theme.danger
        case .injured: return Theme.warning
        }
    }

    private func statusSymbol(_ status: PlayerStatus) -> String {
        switch status {
        case .normal: return "checkmark.shield.fill"
        case .penaltyZone: return "exclamationmark.octagon.fill"
        case .injured: return "cross.case.fill"
        }
    }
}

struct SystemLogView: View {
    @Query(sort: \SystemLogEntry.date, order: .reverse) private var logs: [SystemLogEntry]

    var body: some View {
        List(logs) { entry in
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.message)
                HStack {
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    Spacer()
                    if entry.xpDelta != 0 {
                        Text(entry.xpDelta > 0 ? "+\(entry.xpDelta) XP" : "\(entry.xpDelta) XP")
                            .foregroundStyle(entry.xpDelta > 0 ? Theme.success : Theme.danger)
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            }
            .listRowBackground(Theme.panel)
        }
        .systemBackground()
        .navigationTitle("Bitácora")
    }
}
