import Foundation
import Observation
import SwiftData

/// Anuncio animado del Sistema (subidas, bajadas, castigos).
struct Announcement: Identifiable, Equatable {
    let id = UUID()
    var headline: String
    var message: String
    var positive: Bool
}

/// Lo que toca hoy según el itinerario activo.
struct TodayMission {
    var itinerary: Itinerary
    var routine: Routine?
    var day: Date
    var completedSession: WorkoutSession?
}

/// Borrador de sesión que arma la pantalla de registro.
struct SessionDraft {
    var title: String
    var date: Date
    var results: [BlockResult]
    var rpe: Int = 7
    var notes: String = ""
    var durationMinutes: Double
    var routineID: UUID?
    var itineraryID: UUID?
    var plannedDay: Date?
    var isPunishment = false
}

struct SessionOutcome {
    var session: WorkoutSession
    var xp: Int
    var rawXP: Double
    var events: [ProgressEvent]
}

/// Orquesta el motor y la persistencia. Toda mutación del juego pasa por acá.
@MainActor
@Observable
final class GameService {
    let context: ModelContext
    let clock: DateProvider
    let notifications: NotificationScheduling

    var announcements: [Announcement] = []
    /// Se incrementa en cada cambio para que las vistas que leen del servicio se refresquen.
    private(set) var revision = 0

    init(context: ModelContext, clock: DateProvider, notifications: NotificationScheduling) {
        self.context = context
        self.clock = clock
        self.notifications = notifications
    }

    var now: Date { clock.now }

    /// Hasta cuántos días atrás se puede registrar una sesión planeada que quedó pendiente.
    private static let pendingLookbackDays = 7

    // MARK: - Lecturas

    func player() -> Player? {
        try? context.fetch(FetchDescriptor<Player>()).first
    }

    func itineraries() -> [Itinerary] {
        (try? context.fetch(FetchDescriptor<Itinerary>(sortBy: [SortDescriptor(\.startDate, order: .reverse)]))) ?? []
    }

    func activeItinerary() -> Itinerary? {
        itineraries().first { $0.isActive }
    }

    func routines() -> [Routine] {
        (try? context.fetch(FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.name)]))) ?? []
    }

    func routine(id: UUID?) -> Routine? {
        guard let id else { return nil }
        return routines().first { $0.id == id }
    }

    func exercises() -> [Exercise] {
        (try? context.fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name)]))) ?? []
    }

    func sessions() -> [WorkoutSession] {
        (try? context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date)]))) ?? []
    }

    func exerciseLogs() -> [ExerciseLog] {
        (try? context.fetch(FetchDescriptor<ExerciseLog>(sortBy: [SortDescriptor(\.date)]))) ?? []
    }

    func trials() -> [AscensionTrial] {
        (try? context.fetch(FetchDescriptor<AscensionTrial>(sortBy: [SortDescriptor(\.targetRankRaw)]))) ?? []
    }

    func todayMission() -> TodayMission? {
        let today = SistemaCalendar.startOfDay(now)
        guard let itinerary = activeItinerary(), itinerary.snapshot.covers(today),
              let plan = itinerary.dayPlan(for: today), !plan.isRest else { return nil }
        let done = sessions().last { !$0.isPunishment && $0.plannedDay == today }
        return TodayMission(itinerary: itinerary, routine: routine(id: plan.routineID), day: today, completedSession: done)
    }

    /// Días planeados recientes del itinerario activo que todavía no tienen sesión, del más viejo al más nuevo.
    func pendingMissions() -> [TodayMission] {
        guard let itinerary = activeItinerary(), let player = player() else { return [] }
        let today = SistemaCalendar.startOfDay(now)
        let logged = Set(sessions().filter { !$0.isPunishment }.compactMap(\.plannedDay).map(SistemaCalendar.startOfDay))
        return (1...Self.pendingLookbackDays).reversed().compactMap { offset in
            let day = SistemaCalendar.addDays(-offset, to: today)
            guard itinerary.snapshot.covers(day), !logged.contains(day),
                  !player.injuries.contains(where: { $0.contains(day) }),
                  let plan = itinerary.dayPlan(for: day), !plan.isRest else { return nil }
            return TodayMission(itinerary: itinerary, routine: routine(id: plan.routineID), day: day, completedSession: nil)
        }
    }

    /// El itinerario activo venció (o no hay ninguno vigente) y el Sistema exige uno nuevo.
    func itineraryExpired() -> Bool {
        let today = SistemaCalendar.startOfDay(now)
        let all = itineraries()
        guard !all.isEmpty else { return false }
        return !all.contains { $0.snapshot.covers(today) || $0.startDate > today }
    }

    // MARK: - Onboarding

    @discardableResult
    func createPlayer(name: String) -> Player {
        let player = Player(name: name.trimmingCharacters(in: .whitespacesAndNewlines), now: now)
        context.insert(player)
        seedCatalogIfNeeded()
        log(.info, SystemMessages.welcome, player: player)
        save()
        return player
    }

    func seedCatalogIfNeeded() {
        guard exercises().isEmpty else { return }
        for item in ExerciseCatalog.starter {
            context.insert(Exercise(name: item.name, aliases: item.aliases, category: item.category, stats: item.stats, now: now))
        }
    }

    // MARK: - Catálogo

    /// Busca por nombre/alias; si no existe, lo crea. Nunca duplica.
    @discardableResult
    func findOrCreateExercise(named name: String, category: ExerciseCategory = .fullBody, stats: [StatKind] = [.strength]) -> Exercise? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let all = exercises()
        if let match = ExerciseCatalog.match(trimmed, in: all.map(\.catalogEntry)) {
            return all.first { $0.id == match.id }
        }
        let exercise = Exercise(name: trimmed, category: category, stats: stats, now: now)
        context.insert(exercise)
        save()
        return exercise
    }

    /// Liga los ejercicios de los bloques al catálogo (crea los que falten).
    func linkExercises(_ blocks: [RoutineBlock]) -> [RoutineBlock] {
        blocks.map { block in
            var b = block
            switch b.kind {
            case .strength:
                if let ex = findOrCreateExercise(named: b.strength.exerciseName, stats: [.strength]) {
                    b.strength.exerciseID = ex.id
                    b.strength.exerciseName = ex.name
                }
            case .circuit:
                b.circuit.exercises = b.circuit.exercises.map { item in
                    var e = item
                    if let ex = findOrCreateExercise(named: e.exerciseName, stats: [.endurance]) {
                        e.exerciseID = ex.id
                        e.exerciseName = ex.name
                    }
                    return e
                }
            default:
                break
            }
            return b
        }
    }

    // MARK: - Rutinas e itinerarios

    @discardableResult
    func saveRoutine(_ routine: Routine?, name: String, blocks: [RoutineBlock]) -> Routine {
        let linked = linkExercises(blocks)
        let target: Routine
        if let routine {
            routine.name = name
            routine.blocks = linked
            target = routine
        } else {
            target = Routine(name: name, blocks: linked, now: now)
            context.insert(target)
        }
        save()
        return target
    }

    /// Crea una rutina por cada día de un programa del gimnasio.
    @discardableResult
    func saveProgram(name: String, changeDate: Date?, days: [ProgramDay]) -> [Routine] {
        let saved = days.enumerated().map { index, day -> Routine in
            let routine = Routine(name: day.name, blocks: linkExercises(day.blocks), now: now)
            routine.programName = name
            routine.programDay = index + 1
            routine.focus = day.focus
            routine.programChangeDate = changeDate
            context.insert(routine)
            return routine
        }
        save()
        return saved
    }

    func isRoutineInUse(_ routine: Routine) -> Bool {
        activeItinerary()?.plan.contains { $0.routineID == routine.id } ?? false
    }

    /// Las sesiones guardan su propia copia de lo prescrito: borrar la rutina no toca el historial.
    func deleteRoutine(_ routine: Routine) {
        guard !isRoutineInUse(routine) else { return }
        context.delete(routine)
        save()
    }

    @discardableResult
    func createItinerary(name: String, start: Date, end: Date, plan: [DayPlan]) -> Itinerary {
        for it in itineraries() { it.isActive = false }
        let itinerary = Itinerary(name: name, startDate: start, endDate: max(end, start), plan: plan, isActive: true, now: now)
        context.insert(itinerary)
        save()
        rescheduleNotifications()
        return itinerary
    }

    func updateItinerary(_ itinerary: Itinerary, name: String, start: Date, end: Date, plan: [DayPlan]) {
        itinerary.name = name
        itinerary.startDate = SistemaCalendar.startOfDay(start)
        itinerary.endDate = SistemaCalendar.startOfDay(max(end, start))
        itinerary.plan = plan
        save()
        rescheduleNotifications()
    }

    /// Pone un programa en lugar del itinerario activo, desde la misma fecha de inicio y hasta su fecha de cambio.
    /// Borra las rutinas del itinerario reemplazado; el historial no se toca porque cada sesión guarda su copia.
    func adoptProgram(named name: String) {
        let days = routines().filter { $0.programName == name }.sorted { ($0.programDay ?? 0) < ($1.programDay ?? 0) }
        let current = activeItinerary()
        guard !days.isEmpty, current?.name != name else { return }
        let start = current?.startDate ?? SistemaCalendar.startOfDay(now)
        let end = days.first?.programChangeDate ?? SistemaCalendar.addDays(56, to: start)
        let replaced = routines().filter { routine in
            routine.programName != name && current?.plan.contains { $0.routineID == routine.id } == true
        }
        if let current, !sessions().contains(where: { $0.itineraryID == current.id }) { context.delete(current) }
        let weekdays = ProgramSchedule.defaultWeekdays(dayCount: days.count)
        createItinerary(name: name, start: start, end: end,
                        plan: ProgramSchedule.plan(routineIDs: days.map(\.id), on: Set(weekdays)))
        replaced.forEach(deleteRoutine)
    }

    // MARK: - Evaluación diaria (penalizaciones)

    /// Se llama al abrir la app y al volver a primer plano.
    func evaluate() {
        guard let player = player() else { return }
        var progress = player.progress
        var ledger = player.ledger
        let snapshots = sessions().map(\.snapshot)
        let outcome = PenaltyEngine.evaluate(
            progress: &progress, ledger: &ledger,
            itineraries: itineraries().map(\.snapshot),
            sessions: snapshots, injuries: player.injuries, now: now
        )
        player.progress = progress
        player.ledger = ledger
        player.lastCalculatedAt = now

        for mission in outcome.completedMissions {
            log(.mission, SystemMessages.missionCompleted, player: player, date: mission.completedAt ?? now)
        }
        for record in outcome.penalties {
            context.insert(PenaltyEvent(record: record))
            log(.penalty, SystemMessages.penalty(record), xpDelta: -record.xpLost, player: player,
                date: SistemaCalendar.addDays(1, to: record.day).addingTimeInterval(-1))
        }
        if !outcome.newMissions.isEmpty {
            log(.mission, SystemMessages.missionAssigned, player: player)
        }
        if !outcome.penalties.isEmpty {
            let lost = outcome.penalties.reduce(0) { $0 + $1.xpLost }
            announcements.append(Announcement(headline: "PENALIZACIÓN",
                                              message: "\(outcome.penalties.count) falta(s) registradas. −\(lost) XP.",
                                              positive: false))
        }
        announce(outcome.progressEvents, player: player)
        try? context.save()
        refreshTrials(player: player)
        save()
        rescheduleNotifications()
    }

    // MARK: - Registro de sesión

    @discardableResult
    func logSession(_ draft: SessionDraft) -> SessionOutcome? {
        guard let player = player() else { return nil }
        let compliance = ComplianceEngine.sessionCompliance(draft.results)
        let blocks = draft.results.map(\.prescribed)
        let input = XPEngine.SessionInput(dominantKind: XPEngine.dominantKind(blocks), minutes: draft.durationMinutes,
                                          rpe: draft.rpe, compliance: compliance, startedAt: draft.date)
        let raw = XPEngine.rawXP(input)
        let existing = sessions()
        let day = SistemaCalendar.startOfDay(draft.date)
        let week = SistemaCalendar.startOfWeek(draft.date)
        let earnedToday = existing.filter { SistemaCalendar.startOfDay($0.date) == day }.reduce(0) { $0 + $1.xpAwarded }
        let earnedWeek = existing.filter { SistemaCalendar.startOfWeek($0.date) == week }.reduce(0) { $0 + $1.xpAwarded }
        let xp = XPEngine.cappedXP(raw: raw, earnedToday: earnedToday, earnedThisWeek: earnedWeek)

        let session = WorkoutSession(date: draft.date, title: draft.title, results: draft.results, rpe: draft.rpe,
                                     notes: draft.notes, durationMinutes: draft.durationMinutes,
                                     itineraryID: draft.itineraryID, plannedDay: draft.plannedDay,
                                     routineID: draft.routineID, isPunishment: draft.isPunishment)
        session.compliance = compliance
        session.xpAwarded = xp
        context.insert(session)
        recordExerciseLogs(for: session, results: draft.results)

        var progress = player.progress
        let events = progress.applyGain(xp, now: draft.date)
        player.progress = progress

        let catalogStats = Dictionary(uniqueKeysWithValues: exercises().map { ($0.id, $0.stats) })
        let gains = StatsEngine.gains(results: draft.results, compliance: compliance, planned: draft.plannedDay != nil,
                                      early: XPEngine.isEarly(draft.date), exerciseStats: catalogStats)
        var stats = player.stats
        for kind in StatKind.allCases { stats[kind] += gains[kind] }
        player.stats = stats

        log(.gain, SystemMessages.sessionLogged(xp: xp, compliance: compliance, capped: Double(xp) < raw.rounded()),
            xpDelta: xp, player: player, date: draft.date)

        if draft.isPunishment {
            var ledger = player.ledger
            var outcome = EvaluationOutcome()
            PenaltyEngine.resolveMissions(ledger: &ledger, sessions: (existing + [session]).map(\.snapshot), outcome: &outcome)
            player.ledger = ledger
            if !outcome.completedMissions.isEmpty {
                log(.mission, SystemMessages.missionCompleted, player: player)
                announcements.append(Announcement(headline: "CASTIGO CUMPLIDO", message: SystemMessages.missionCompleted, positive: true))
            }
        }

        announce(events, player: player)
        try? context.save()
        refreshTrials(player: player)
        save()
        rescheduleNotifications()
        Haptics.success()
        return SessionOutcome(session: session, xp: xp, rawXP: raw, events: events)
    }

    private func recordExerciseLogs(for session: WorkoutSession, results: [BlockResult]) {
        for result in results {
            let block = result.prescribed
            switch block.kind {
            case .strength:
                let key = markKey(id: block.strength.exerciseID, name: block.strength.exerciseName)
                for (index, set) in result.sets.enumerated() {
                    let improved = block.strength.weight > 0 && set.weight > block.strength.weight && set.reps >= block.strength.reps
                    context.insert(ExerciseLog(exerciseID: block.strength.exerciseID, markKey: key, sessionID: session.id,
                                               date: session.date, kind: .strength, setIndex: index, reps: set.reps,
                                               weight: set.weight, isImprovement: improved))
                }
            case .circuit:
                for (index, exercise) in block.circuit.exercises.enumerated() {
                    let actual = index < result.circuitActuals.count ? result.circuitActuals[index] : PerformedCircuitExercise()
                    guard result.rounds > 0 || (block.circuit.isAMRAP && (result.minutes ?? 0) > 0) else { continue }
                    context.insert(ExerciseLog(exerciseID: exercise.exerciseID,
                                               markKey: markKey(id: exercise.exerciseID, name: exercise.exerciseName),
                                               sessionID: session.id, date: session.date, kind: .circuit,
                                               setIndex: result.rounds, reps: actual.reps ?? 0, weight: actual.weight ?? 0,
                                               seconds: Double(actual.seconds ?? 0)))
                }
            case .cardio:
                guard (result.minutes ?? 0) > 0 || (result.distanceKm ?? 0) > 0 else { continue }
                context.insert(ExerciseLog(exerciseID: nil, markKey: "cardio:\(block.cardio.modality.rawValue)",
                                           sessionID: session.id, date: session.date, kind: .cardio, setIndex: 0,
                                           seconds: (result.minutes ?? 0) * 60, distanceKm: result.distanceKm ?? 0))
            case .classSession:
                guard (result.minutes ?? 0) > 0 else { continue }
                context.insert(ExerciseLog(exerciseID: nil, markKey: "class:\(block.klass.discipline.rawValue)",
                                           sessionID: session.id, date: session.date, kind: .classSession, setIndex: 0,
                                           seconds: (result.minutes ?? 0) * 60))
            }
        }
    }

    private func markKey(id: UUID?, name: String) -> String {
        id?.uuidString ?? "name:\(ExerciseCatalog.normalize(name))"
    }

    // MARK: - Pruebas de ascenso

    func trialMetrics(player: Player) -> TrialMetrics {
        let snapshots = sessions().map(\.snapshot)
        let yesterday = SistemaCalendar.addDays(-1, to: SistemaCalendar.startOfDay(now))
        let weekly = AscensionEngine.weeklyCompliance(itineraries: itineraries().map(\.snapshot), sessions: snapshots,
                                                      injuries: player.injuries, from: player.createdAt, through: yesterday)
        let since = player.rankEnteredAt
        let improvement = AscensionEngine.bestImprovement(records: exerciseLogs().compactMap(\.markRecord), since: since)
        let classes = snapshots.filter { $0.date >= since }.reduce(0) { $0 + $1.classCount }
        return TrialMetrics(weeklyCompliance: weekly, bestImprovement: improvement, classesInRank: classes)
    }

    /// Sincroniza el estado de las pruebas y aprueba la disponible si ya cumplís todo.
    func refreshTrials(player: Player) {
        var existing = trials()
        for rank in Rank.allCases where rank != .e && !existing.contains(where: { $0.target == rank }) {
            let trial = AscensionTrial(target: rank, state: .locked, now: now)
            context.insert(trial)
            existing.append(trial)
        }
        var progress = player.progress
        if case let .available(target) = progress.trialAvailability(now: now),
           AscensionEngine.allMet(target: target, metrics: trialMetrics(player: player)) {
            let events = progress.passTrial(now: now)
            player.progress = progress
            if let trial = existing.first(where: { $0.target == target }) {
                trial.state = .passed
                trial.passedAt = now
                trial.updatedAt = now
            }
            log(.trial, SystemMessages.trialPassed, player: player)
            announcements.append(Announcement(headline: "PRUEBA SUPERADA", message: SystemMessages.trialPassed, positive: true))
            announce(events, player: player)
        }
        let availability = progress.trialAvailability(now: now)
        for trial in existing {
            let newState: TrialState
            if trial.target <= progress.unlockedRank {
                newState = .passed
            } else if case let .available(target) = availability, target == trial.target {
                newState = .available
            } else {
                newState = .locked
            }
            if trial.state != newState {
                trial.state = newState
                trial.updatedAt = now
                if newState != .passed { trial.passedAt = nil }
            }
        }
    }

    // MARK: - Historial previo

    /// Acredita una sola vez el entrenamiento anterior a la app. No es una sesión: no toca racha,
    /// atributos, topes ni los requisitos de la siguiente prueba.
    func applyPriorHistory(xp: Int) {
        guard let player = player(), player.priorHistoryXP == nil, xp > 0 else { return }
        var progress = player.progress
        let events = progress.applyPriorHistory(xp: xp, now: now)
        player.progress = progress
        player.priorHistoryXP = xp
        log(.gain, "Historial previo reconocido: +\(xp) XP. Entrás en \(progress.position.title).", xpDelta: xp, player: player)
        announce(events, player: player)
        refreshTrials(player: player)
        for trial in trials() where trial.state == .passed && trial.passedAt == nil { trial.passedAt = now }
        save()
    }

    // MARK: - Modo lesión

    func startInjury(reason: String, until: Date) {
        guard let player = player() else { return }
        var list = player.injuries
        let period = InjuryPeriod.make(start: now, estimatedEnd: until, reason: reason)
        list.removeAll { $0.contains(now) }
        list.append(period)
        player.injuries = list
        log(.info, SystemMessages.injuryOn, player: player)
        save()
        rescheduleNotifications()
    }

    func endInjury() {
        guard let player = player() else { return }
        let today = SistemaCalendar.startOfDay(now)
        player.injuries = player.injuries.compactMap { period in
            guard period.contains(today) else { return period }
            // Hoy vuelve a contar: el periodo termina ayer (o se elimina si empezó hoy).
            guard period.start < today else { return nil }
            var p = period
            p.end = SistemaCalendar.addDays(-1, to: today)
            return p
        }
        log(.info, SystemMessages.injuryOff, player: player)
        save()
        rescheduleNotifications()
    }

    // MARK: - Ajustes

    func setReminder(hour: Int, minute: Int) {
        guard let player = player() else { return }
        player.reminderHour = hour
        player.reminderMinute = minute
        save()
        rescheduleNotifications()
    }

    func resetAll() {
        BackupService.deleteAll(in: context)
        announcements.removeAll()
        save()
        notifications.replaceAll(with: [])
    }

    func rescheduleNotifications() {
        guard let player = player(), let itinerary = activeItinerary() else {
            notifications.replaceAll(with: [])
            return
        }
        var names: [Weekday: String] = [:]
        for plan in itinerary.plan {
            if let r = routine(id: plan.routineID) { names[plan.weekday] = r.name }
        }
        let logged = Set(sessions().compactMap { $0.isPunishment ? nil : $0.plannedDay })
        let plan = NotificationPlanner.plan(itinerary: itinerary.snapshot, routineNames: names,
                                            reminderHour: player.reminderHour, reminderMinute: player.reminderMinute,
                                            loggedPlannedDays: logged, injuries: player.injuries, now: now)
        notifications.replaceAll(with: plan)
    }

    // MARK: - Utilidades

    func dismissAnnouncement() {
        if !announcements.isEmpty { announcements.removeFirst() }
    }

    func save() {
        try? context.save()
        revision += 1
    }

    private func announce(_ events: [ProgressEvent], player: Player) {
        for event in events {
            let kind: LogKind
            switch event {
            case .levelUp: kind = .levelUp
            case .levelDown: kind = .levelDown
            default: kind = .rank
            }
            log(kind, SystemMessages.forEvent(event), player: player)
            announcements.append(Announcement(headline: SystemMessages.headline(event),
                                              message: SystemMessages.forEvent(event),
                                              positive: event.isPositive))
        }
        if events.contains(where: { $0.isPositive }) {
            Haptics.levelUp()
        } else if !events.isEmpty {
            Haptics.warning()
        }
    }

    private func log(_ kind: LogKind, _ message: String, xpDelta: Int = 0, player: Player, date: Date? = nil) {
        context.insert(SystemLogEntry(date: date ?? now, kind: kind, message: message, xpDelta: xpDelta,
                                      totalXPAfter: player.totalXP))
    }
}
