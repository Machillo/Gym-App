import Foundation
import SwiftData

/// Respaldo completo en JSON. Exportar → importar produce los mismos datos.
struct BackupDocument: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var exportedAt: Date
    var players: [PlayerDTO]
    var itineraries: [ItineraryDTO]
    var routines: [RoutineDTO]
    var exercises: [ExerciseDTO]
    var sessions: [SessionDTO]
    var exerciseLogs: [ExerciseLogDTO]
    var penalties: [PenaltyDTO]
    var trials: [TrialDTO]
    var logs: [LogDTO]

    struct PlayerDTO: Codable, Equatable {
        var id: UUID, name: String, createdAt: Date, totalXP: Int, overflowXP: Int
        var unlockedRankRaw: Int, highestRankRaw: Int, rankEnteredAt: Date
        var strength: Double, endurance: Double, technique: Double, discipline: Double, vitality: Double
        var ledger: PenaltyLedger, injuries: [InjuryPeriod]
        var lastCalculatedAt: Date, reminderHour: Int, reminderMinute: Int
    }

    struct ItineraryDTO: Codable, Equatable {
        var id: UUID, name: String, startDate: Date, endDate: Date, isActive: Bool, createdAt: Date, plan: [DayPlan]
    }

    struct RoutineDTO: Codable, Equatable {
        var id: UUID, name: String, createdAt: Date, blocks: [RoutineBlock]
    }

    struct ExerciseDTO: Codable, Equatable {
        var id: UUID, name: String, aliases: [String], categoryRaw: String, statsRaw: [String], createdAt: Date
    }

    struct SessionDTO: Codable, Equatable {
        var id: UUID, date: Date, itineraryID: UUID?, plannedDay: Date?, routineID: UUID?, title: String
        var results: [BlockResult], rpe: Int, notes: String, durationMinutes: Double
        var compliance: Double, xpAwarded: Int, isPunishment: Bool
    }

    struct ExerciseLogDTO: Codable, Equatable {
        var id: UUID, exerciseID: UUID?, markKey: String, sessionID: UUID, date: Date, kindRaw: String
        var setIndex: Int, reps: Int, weight: Double, seconds: Double, distanceKm: Double, isImprovement: Bool
    }

    struct PenaltyDTO: Codable, Equatable {
        var id: UUID, date: Date, reasonRaw: String, faultWeight: Double, xpLost: Int, levelsLost: Int, rankLost: Bool
    }

    struct TrialDTO: Codable, Equatable {
        var id: UUID, targetRankRaw: Int, stateRaw: String, passedAt: Date?, updatedAt: Date
    }

    struct LogDTO: Codable, Equatable {
        var id: UUID, date: Date, kindRaw: String, message: String, xpDelta: Int, totalXPAfter: Int
    }
}

enum BackupError: LocalizedError {
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(v): return "Versión de respaldo no soportada: \(v)"
        }
    }
}

enum BackupService {
    static func makeDocument(from context: ModelContext, now: Date) throws -> BackupDocument {
        typealias D = BackupDocument

        let players: [D.PlayerDTO] = try context.fetch(FetchDescriptor<Player>()).map { p in
            D.PlayerDTO(id: p.id, name: p.name, createdAt: p.createdAt, totalXP: p.totalXP, overflowXP: p.overflowXP,
                        unlockedRankRaw: p.unlockedRankRaw, highestRankRaw: p.highestRankRaw, rankEnteredAt: p.rankEnteredAt,
                        strength: p.strength, endurance: p.endurance, technique: p.technique, discipline: p.discipline,
                        vitality: p.vitality, ledger: p.ledger, injuries: p.injuries, lastCalculatedAt: p.lastCalculatedAt,
                        reminderHour: p.reminderHour, reminderMinute: p.reminderMinute)
        }
        let itineraries: [D.ItineraryDTO] = try context.fetch(FetchDescriptor<Itinerary>()).map { i in
            D.ItineraryDTO(id: i.id, name: i.name, startDate: i.startDate, endDate: i.endDate, isActive: i.isActive,
                           createdAt: i.createdAt, plan: i.plan)
        }
        let routines: [D.RoutineDTO] = try context.fetch(FetchDescriptor<Routine>()).map { r in
            D.RoutineDTO(id: r.id, name: r.name, createdAt: r.createdAt, blocks: r.blocks)
        }
        let exercises: [D.ExerciseDTO] = try context.fetch(FetchDescriptor<Exercise>()).map { e in
            D.ExerciseDTO(id: e.id, name: e.name, aliases: e.aliases, categoryRaw: e.categoryRaw, statsRaw: e.statsRaw,
                          createdAt: e.createdAt)
        }
        let sessions: [D.SessionDTO] = try context.fetch(FetchDescriptor<WorkoutSession>()).map { s in
            D.SessionDTO(id: s.id, date: s.date, itineraryID: s.itineraryID, plannedDay: s.plannedDay, routineID: s.routineID,
                         title: s.title, results: s.results, rpe: s.rpe, notes: s.notes, durationMinutes: s.durationMinutes,
                         compliance: s.compliance, xpAwarded: s.xpAwarded, isPunishment: s.isPunishment)
        }
        let logsByExercise: [D.ExerciseLogDTO] = try context.fetch(FetchDescriptor<ExerciseLog>()).map { l in
            D.ExerciseLogDTO(id: l.id, exerciseID: l.exerciseID, markKey: l.markKey, sessionID: l.sessionID, date: l.date,
                             kindRaw: l.kindRaw, setIndex: l.setIndex, reps: l.reps, weight: l.weight, seconds: l.seconds,
                             distanceKm: l.distanceKm, isImprovement: l.isImprovement)
        }
        let penalties: [D.PenaltyDTO] = try context.fetch(FetchDescriptor<PenaltyEvent>()).map { p in
            D.PenaltyDTO(id: p.id, date: p.date, reasonRaw: p.reasonRaw, faultWeight: p.faultWeight, xpLost: p.xpLost,
                         levelsLost: p.levelsLost, rankLost: p.rankLost)
        }
        let trials: [D.TrialDTO] = try context.fetch(FetchDescriptor<AscensionTrial>()).map { t in
            D.TrialDTO(id: t.id, targetRankRaw: t.targetRankRaw, stateRaw: t.stateRaw, passedAt: t.passedAt, updatedAt: t.updatedAt)
        }
        let logs: [D.LogDTO] = try context.fetch(FetchDescriptor<SystemLogEntry>()).map { l in
            D.LogDTO(id: l.id, date: l.date, kindRaw: l.kindRaw, message: l.message, xpDelta: l.xpDelta,
                     totalXPAfter: l.totalXPAfter)
        }

        return BackupDocument(
            version: BackupDocument.currentVersion,
            exportedAt: now,
            players: players.sorted { $0.id.uuidString < $1.id.uuidString },
            itineraries: itineraries.sorted { $0.id.uuidString < $1.id.uuidString },
            routines: routines.sorted { $0.id.uuidString < $1.id.uuidString },
            exercises: exercises.sorted { $0.id.uuidString < $1.id.uuidString },
            sessions: sessions.sorted { $0.id.uuidString < $1.id.uuidString },
            exerciseLogs: logsByExercise.sorted { $0.id.uuidString < $1.id.uuidString },
            penalties: penalties.sorted { $0.id.uuidString < $1.id.uuidString },
            trials: trials.sorted { $0.id.uuidString < $1.id.uuidString },
            logs: logs.sorted { $0.id.uuidString < $1.id.uuidString }
        )
    }

    static func exportData(from context: ModelContext, now: Date) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(makeDocument(from: context, now: now))
    }

    static func decode(_ data: Data) throws -> BackupDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let doc = try decoder.decode(BackupDocument.self, from: data)
        guard doc.version <= BackupDocument.currentVersion else { throw BackupError.unsupportedVersion(doc.version) }
        return doc
    }

    /// Reemplaza todos los datos por los del respaldo.
    static func importData(_ data: Data, into context: ModelContext) throws {
        let doc = try decode(data)
        deleteAll(in: context)
        try context.save()

        for p in doc.players {
            let player = Player(name: p.name, now: p.createdAt)
            player.id = p.id
            player.totalXP = p.totalXP
            player.overflowXP = p.overflowXP
            player.unlockedRankRaw = p.unlockedRankRaw
            player.highestRankRaw = p.highestRankRaw
            player.rankEnteredAt = p.rankEnteredAt
            player.strength = p.strength
            player.endurance = p.endurance
            player.technique = p.technique
            player.discipline = p.discipline
            player.vitality = p.vitality
            player.ledger = p.ledger
            player.injuries = p.injuries
            player.lastCalculatedAt = p.lastCalculatedAt
            player.reminderHour = p.reminderHour
            player.reminderMinute = p.reminderMinute
            context.insert(player)
        }
        for i in doc.itineraries {
            let it = Itinerary(name: i.name, startDate: i.startDate, endDate: i.endDate, plan: i.plan, isActive: i.isActive, now: i.createdAt)
            it.id = i.id
            it.startDate = i.startDate
            it.endDate = i.endDate
            context.insert(it)
        }
        for r in doc.routines {
            let routine = Routine(name: r.name, blocks: r.blocks, now: r.createdAt)
            routine.id = r.id
            context.insert(routine)
        }
        for e in doc.exercises {
            let ex = Exercise(name: e.name, aliases: e.aliases, category: .fullBody, stats: [], now: e.createdAt)
            ex.id = e.id
            ex.categoryRaw = e.categoryRaw
            ex.statsRaw = e.statsRaw
            context.insert(ex)
        }
        for s in doc.sessions {
            let session = WorkoutSession(date: s.date, title: s.title, results: s.results, rpe: s.rpe, notes: s.notes,
                                         durationMinutes: s.durationMinutes, itineraryID: s.itineraryID, plannedDay: nil,
                                         routineID: s.routineID, isPunishment: s.isPunishment)
            session.id = s.id
            session.plannedDay = s.plannedDay
            session.compliance = s.compliance
            session.xpAwarded = s.xpAwarded
            context.insert(session)
        }
        for l in doc.exerciseLogs {
            let log = ExerciseLog(exerciseID: l.exerciseID, markKey: l.markKey, sessionID: l.sessionID, date: l.date,
                                  kind: .strength, setIndex: l.setIndex, reps: l.reps, weight: l.weight, seconds: l.seconds,
                                  distanceKm: l.distanceKm, isImprovement: l.isImprovement)
            log.id = l.id
            log.kindRaw = l.kindRaw
            context.insert(log)
        }
        for p in doc.penalties {
            let event = PenaltyEvent(record: PenaltyRecord(day: p.date, reason: .missedDay, faultWeight: p.faultWeight,
                                                           xpLost: p.xpLost, levelsLost: p.levelsLost, rankLost: p.rankLost))
            event.id = p.id
            event.reasonRaw = p.reasonRaw
            context.insert(event)
        }
        for t in doc.trials {
            let trial = AscensionTrial(target: Rank(rawValue: t.targetRankRaw) ?? .d, state: .locked, now: t.updatedAt)
            trial.id = t.id
            trial.targetRankRaw = t.targetRankRaw
            trial.stateRaw = t.stateRaw
            trial.passedAt = t.passedAt
            context.insert(trial)
        }
        for l in doc.logs {
            let entry = SystemLogEntry(date: l.date, kind: .info, message: l.message, xpDelta: l.xpDelta, totalXPAfter: l.totalXPAfter)
            entry.id = l.id
            entry.kindRaw = l.kindRaw
            context.insert(entry)
        }
        try context.save()
    }

    static func deleteAll(in context: ModelContext) {
        try? context.delete(model: SystemLogEntry.self)
        try? context.delete(model: AscensionTrial.self)
        try? context.delete(model: PenaltyEvent.self)
        try? context.delete(model: ExerciseLog.self)
        try? context.delete(model: WorkoutSession.self)
        try? context.delete(model: Exercise.self)
        try? context.delete(model: Routine.self)
        try? context.delete(model: Itinerary.self)
        try? context.delete(model: Player.self)
    }

    static func suggestedFileName(now: Date) -> String {
        let c = SistemaCalendar.calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "sistema-respaldo-%04d-%02d-%02d.json", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
