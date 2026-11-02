import Foundation
import SwiftData

enum JSONCoding {
    static func encode<T: Encodable>(_ value: T) -> Data {
        (try? encoder.encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data, default fallback: T) -> T {
        (try? decoder.decode(type, from: data)) ?? fallback
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()
}

@Model
final class Player {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var totalXP: Int
    var overflowXP: Int
    var unlockedRankRaw: Int
    var highestRankRaw: Int
    var rankEnteredAt: Date
    var strength: Double
    var endurance: Double
    var technique: Double
    var discipline: Double
    var vitality: Double
    /// PenaltyLedger en JSON: racha, faltas por semana, misiones de castigo.
    var ledgerData: Data
    /// [InjuryPeriod] en JSON.
    var injuriesData: Data
    var lastCalculatedAt: Date
    var reminderHour: Int
    var reminderMinute: Int
    /// XP reconocido por entrenamiento anterior a la app. Se acredita una sola vez.
    var priorHistoryXP: Int?

    init(name: String, now: Date) {
        id = UUID()
        self.name = name
        createdAt = now
        totalXP = 0
        overflowXP = 0
        unlockedRankRaw = Rank.e.rawValue
        highestRankRaw = Rank.e.rawValue
        rankEnteredAt = now
        strength = 0
        endurance = 0
        technique = 0
        discipline = 0
        vitality = 0
        ledgerData = JSONCoding.encode(PenaltyLedger(lastEvaluatedDay: now))
        injuriesData = JSONCoding.encode([InjuryPeriod]())
        lastCalculatedAt = now
        reminderHour = 4
        reminderMinute = 30
    }

    var progress: PlayerProgress {
        get {
            var p = PlayerProgress(startedAt: rankEnteredAt)
            p.totalXP = totalXP
            p.overflowXP = overflowXP
            p.unlockedRank = Rank(rawValue: unlockedRankRaw) ?? .e
            p.highestRankEverUnlocked = Rank(rawValue: highestRankRaw) ?? .e
            return p
        }
        set {
            totalXP = newValue.totalXP
            overflowXP = newValue.overflowXP
            unlockedRankRaw = newValue.unlockedRank.rawValue
            highestRankRaw = newValue.highestRankEverUnlocked.rawValue
            rankEnteredAt = newValue.rankEnteredAt
        }
    }

    var stats: PlayerStats {
        get { PlayerStats(strength: strength, endurance: endurance, technique: technique, discipline: discipline, vitality: vitality) }
        set {
            strength = newValue.strength
            endurance = newValue.endurance
            technique = newValue.technique
            discipline = newValue.discipline
            vitality = newValue.vitality
        }
    }

    var ledger: PenaltyLedger {
        get { JSONCoding.decode(PenaltyLedger.self, from: ledgerData, default: PenaltyLedger(lastEvaluatedDay: createdAt)) }
        set { ledgerData = JSONCoding.encode(newValue) }
    }

    var injuries: [InjuryPeriod] {
        get { JSONCoding.decode([InjuryPeriod].self, from: injuriesData, default: []) }
        set { injuriesData = JSONCoding.encode(newValue) }
    }

    var level: Int { LevelCurve.level(forTotalXP: totalXP) }
    var position: RankPosition { RankPosition(level: level) }
    var currentStreak: Int { ledger.currentStreak }
    var maxStreak: Int { ledger.maxStreak }

    func status(now: Date) -> PlayerStatus {
        PenaltyEngine.status(ledger: ledger, injuries: injuries, now: now)
    }

    func activeInjury(now: Date) -> InjuryPeriod? {
        injuries.first { $0.contains(now) }
    }
}

/// Plan de un día de la semana: rutina asignada o descanso.
struct DayPlan: Codable, Hashable, Identifiable {
    var weekday: Weekday
    var routineID: UUID?

    var id: Int { weekday.rawValue }
    var isRest: Bool { routineID == nil }
}

@Model
final class Itinerary {
    @Attribute(.unique) var id: UUID
    var name: String
    var startDate: Date
    var endDate: Date
    var isActive: Bool
    var createdAt: Date
    var planData: Data

    init(name: String, startDate: Date, endDate: Date, plan: [DayPlan], isActive: Bool = true, now: Date = Date()) {
        id = UUID()
        self.name = name
        self.startDate = SistemaCalendar.startOfDay(startDate)
        self.endDate = SistemaCalendar.startOfDay(endDate)
        self.isActive = isActive
        createdAt = now
        planData = JSONCoding.encode(plan)
    }

    var plan: [DayPlan] {
        get {
            let stored = JSONCoding.decode([DayPlan].self, from: planData, default: [])
            return Weekday.allCases.map { day in stored.first { $0.weekday == day } ?? DayPlan(weekday: day) }
        }
        set { planData = JSONCoding.encode(newValue) }
    }

    func dayPlan(for date: Date) -> DayPlan? {
        let weekday = SistemaCalendar.weekday(of: date)
        return plan.first { $0.weekday == weekday }
    }

    var snapshot: ItinerarySnapshot {
        ItinerarySnapshot(id: id, start: startDate, end: endDate,
                          plannedWeekdays: Set(plan.filter { !$0.isRest }.map(\.weekday)))
    }
}

@Model
final class Routine {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var blocksData: Data
    /// Programa del gimnasio al que pertenece este día, si aplica.
    var programName: String?
    var programDay: Int?
    var focus: String?
    var programChangeDate: Date?

    init(name: String, blocks: [RoutineBlock], now: Date = Date()) {
        id = UUID()
        self.name = name
        createdAt = now
        blocksData = JSONCoding.encode(blocks)
    }

    var blocks: [RoutineBlock] {
        get { JSONCoding.decode([RoutineBlock].self, from: blocksData, default: []) }
        set { blocksData = JSONCoding.encode(newValue) }
    }
}

@Model
final class Exercise {
    @Attribute(.unique) var id: UUID
    var name: String
    var aliases: [String]
    var categoryRaw: String
    var statsRaw: [String]
    var createdAt: Date

    init(name: String, aliases: [String] = [], category: ExerciseCategory, stats: [StatKind], now: Date = Date()) {
        id = UUID()
        self.name = name
        self.aliases = aliases
        categoryRaw = category.rawValue
        statsRaw = stats.map(\.rawValue)
        createdAt = now
    }

    var category: ExerciseCategory {
        get { ExerciseCategory(rawValue: categoryRaw) ?? .fullBody }
        set { categoryRaw = newValue.rawValue }
    }

    var stats: [StatKind] {
        get { statsRaw.compactMap(StatKind.init(rawValue:)) }
        set { statsRaw = newValue.map(\.rawValue) }
    }

    var catalogEntry: CatalogEntry { CatalogEntry(id: id, name: name, aliases: aliases) }
}

@Model
final class WorkoutSession {
    @Attribute(.unique) var id: UUID
    var date: Date
    var itineraryID: UUID?
    /// Día planeado (inicio de día) o nil si fue una sesión libre.
    var plannedDay: Date?
    var routineID: UUID?
    var title: String
    var resultsData: Data
    var rpe: Int
    var notes: String
    var durationMinutes: Double
    var compliance: Double
    var xpAwarded: Int
    var isPunishment: Bool

    init(date: Date, title: String, results: [BlockResult], rpe: Int, notes: String, durationMinutes: Double,
         itineraryID: UUID?, plannedDay: Date?, routineID: UUID?, isPunishment: Bool) {
        id = UUID()
        self.date = date
        self.title = title
        resultsData = JSONCoding.encode(results)
        self.rpe = rpe
        self.notes = notes
        self.durationMinutes = durationMinutes
        self.itineraryID = itineraryID
        self.plannedDay = plannedDay.map(SistemaCalendar.startOfDay)
        self.routineID = routineID
        self.isPunishment = isPunishment
        compliance = 0
        xpAwarded = 0
    }

    var results: [BlockResult] {
        get { JSONCoding.decode([BlockResult].self, from: resultsData, default: []) }
        set { resultsData = JSONCoding.encode(newValue) }
    }

    var isPlanned: Bool { plannedDay != nil }

    var snapshot: SessionSnapshot {
        SessionSnapshot(id: id, date: date, plannedDay: plannedDay, compliance: compliance, xpAwarded: xpAwarded,
                        isPunishment: isPunishment, minutes: durationMinutes,
                        classCount: results.filter { $0.prescribed.kind == .classSession && ComplianceEngine.blockCompliance($0) >= 0.5 }.count)
    }
}

/// Cada serie / ronda / tramo de cardio, ligado al ejercicio del catálogo (o a la modalidad de cardio).
@Model
final class ExerciseLog {
    @Attribute(.unique) var id: UUID
    var exerciseID: UUID?
    /// Clave de marca: id del ejercicio o "cardio:<modalidad>".
    var markKey: String
    var sessionID: UUID
    var date: Date
    var kindRaw: String
    var setIndex: Int
    var reps: Int
    var weight: Double
    var seconds: Double
    var distanceKm: Double
    var isImprovement: Bool

    init(exerciseID: UUID?, markKey: String, sessionID: UUID, date: Date, kind: BlockKind, setIndex: Int,
         reps: Int = 0, weight: Double = 0, seconds: Double = 0, distanceKm: Double = 0, isImprovement: Bool = false) {
        id = UUID()
        self.exerciseID = exerciseID
        self.markKey = markKey
        self.sessionID = sessionID
        self.date = date
        kindRaw = kind.rawValue
        self.setIndex = setIndex
        self.reps = reps
        self.weight = weight
        self.seconds = seconds
        self.distanceKm = distanceKm
        self.isImprovement = isImprovement
    }

    var kind: BlockKind { BlockKind(rawValue: kindRaw) ?? .strength }
    var e1RM: Double { ExerciseMath.epley(weight: weight, reps: reps) }
    var volume: Double { weight * Double(reps) }
    var pace: Double? { ExerciseMath.pace(minutes: seconds / 60, km: distanceKm) }

    var markRecord: MarkRecord? {
        if kind == .cardio, let pace {
            return MarkRecord(key: markKey, date: date, value: pace, higherIsBetter: false)
        }
        if e1RM > 0 {
            return MarkRecord(key: markKey, date: date, value: e1RM, higherIsBetter: true)
        }
        return nil
    }
}

@Model
final class PenaltyEvent {
    @Attribute(.unique) var id: UUID
    var date: Date
    var reasonRaw: String
    var faultWeight: Double
    var xpLost: Int
    var levelsLost: Int
    var rankLost: Bool

    init(record: PenaltyRecord) {
        id = UUID()
        date = record.day
        reasonRaw = record.reason.rawValue
        faultWeight = record.faultWeight
        xpLost = record.xpLost
        levelsLost = record.levelsLost
        rankLost = record.rankLost
    }

    var reason: FaultReason { FaultReason(rawValue: reasonRaw) ?? .missedDay }
}

enum TrialState: String, Codable {
    case locked, available, passed

    var label: String {
        switch self {
        case .locked: return "Bloqueada"
        case .available: return "Disponible"
        case .passed: return "Superada"
        }
    }
}

@Model
final class AscensionTrial {
    @Attribute(.unique) var id: UUID
    var targetRankRaw: Int
    var stateRaw: String
    var passedAt: Date?
    var updatedAt: Date

    init(target: Rank, state: TrialState, now: Date) {
        id = UUID()
        targetRankRaw = target.rawValue
        stateRaw = state.rawValue
        updatedAt = now
    }

    var target: Rank { Rank(rawValue: targetRankRaw) ?? .d }

    var state: TrialState {
        get { TrialState(rawValue: stateRaw) ?? .locked }
        set { stateRaw = newValue.rawValue }
    }
}

enum LogKind: String, Codable {
    case info, gain, levelUp, levelDown, rank, penalty, mission, trial
}

/// Bitácora del Sistema.
@Model
final class SystemLogEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var kindRaw: String
    var message: String
    var xpDelta: Int
    var totalXPAfter: Int

    init(date: Date, kind: LogKind, message: String, xpDelta: Int = 0, totalXPAfter: Int) {
        id = UUID()
        self.date = date
        kindRaw = kind.rawValue
        self.message = message
        self.xpDelta = xpDelta
        self.totalXPAfter = totalXPAfter
    }

    var kind: LogKind { LogKind(rawValue: kindRaw) ?? .info }
}

enum SistemaSchema {
    static let models: [any PersistentModel.Type] = [
        Player.self, Itinerary.self, Routine.self, Exercise.self, WorkoutSession.self,
        ExerciseLog.self, PenaltyEvent.self, AscensionTrial.self, SystemLogEntry.self,
    ]

    static func makeContainer(inMemory: Bool) throws -> ModelContainer {
        let schema = Schema(models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
