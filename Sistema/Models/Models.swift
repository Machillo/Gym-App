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
    /// Último perfil anunciado ("Peleador de MMA · Competidor"), para detectar cuando evoluciona.
    var profileTitle: String?
    /// Hora real de levantarse, para calcular a qué hora acostarse.
    var wakeHour: Int?
    var wakeMinute: Int?
    /// Fecha de la próxima pelea o campeonato.
    var fightDate: Date?

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

    // Apple Salud. Todo opcional para que la base existente migre sola.
    /// Entrenamiento del Watch (UUID de Salud) unido a esta sesión.
    var healthWorkoutID: String?
    /// Categoría del entrenamiento del Watch (`HealthCategory.raw`).
    var watchCategoryRaw: String?
    var watchSource: String?
    var watchKcal: Double?
    var watchAvgHR: Double?
    var watchMaxHR: Double?
    /// La creó el Sistema solo, al leer un entrenamiento del Watch.
    var isAutoImported: Bool?
    /// Calorías estimadas que se mandaron a Salud (clases de pelea sin reloj).
    var estimatedKcal: Double?
    /// true: la estimación está en Salud y al día. nil: falta mandarla o rehacerla.
    var healthExported: Bool?

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

    var isClass: Bool { results.contains { $0.prescribed.kind == .classSession } }
    var isFromWatch: Bool { isAutoImported == true }
    /// XP sujeto a topes: todo menos el premio de pelea.
    var cappedXP: Int { xpAwarded - XPEngine.fightBonus(results) }
    var fight: FightResult? { results.lazy.compactMap(\.fight).first }

    var digest: SessionDigest {
        SessionDigest(id: id, date: date, results: results, plannedDay: plannedDay, compliance: compliance,
                      isPunishment: isPunishment, durationMinutes: durationMinutes)
    }

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
    case info, gain, levelUp, levelDown, rank, penalty, mission, trial, profile
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

/// Un registro del cuerpo. Todo es opcional: se apunta lo que se midió ese día.
@Model
final class BodyEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var weightKg: Double?
    /// Unidad en que se escribió el peso; se guarda en kg.
    var weightUnitRaw: String?
    var bodyFatPercent: Double?
    /// [BodyMeasure: cm] en JSON.
    var measuresData: Data
    var notes: String
    // InBody
    var skeletalMuscleKg: Double?
    var visceralFatLevel: Int?
    var inBodyScore: Int?
    // Apple Salud
    /// true: lo que se puede mandar a Salud ya está ahí. nil/false: falta mandarlo.
    var healthSynced: Bool?
    /// El peso o la grasa vinieron de Salud (balanza): no se devuelven.
    var weightFromHealth: Bool?
    var fatFromHealth: Bool?

    init(date: Date, weightKg: Double?, weightUnit: WeightUnit, bodyFatPercent: Double?, measures: [BodyMeasure: Double], notes: String) {
        id = UUID()
        self.date = date
        self.weightKg = weightKg
        weightUnitRaw = weightUnit.rawValue
        self.bodyFatPercent = bodyFatPercent
        measuresData = JSONCoding.encode(measures)
        self.notes = notes
    }

    var weightUnit: WeightUnit { weightUnitRaw.flatMap(WeightUnit.init(rawValue:)) ?? .kg }

    var measures: [BodyMeasure: Double] {
        get { JSONCoding.decode([BodyMeasure: Double].self, from: measuresData, default: [:]) }
        set { measuresData = JSONCoding.encode(newValue) }
    }

    var snapshot: BodySnapshot {
        BodySnapshot(date: date, weightKg: weightKg, bodyFatPercent: bodyFatPercent, measures: measures,
                     skeletalMuscleKg: skeletalMuscleKg, visceralFatLevel: visceralFatLevel.map(Double.init),
                     inBodyScore: inBodyScore.map(Double.init))
    }
}

/// Sueño, pulso, HRV y cómo amaneciste en un día. Se queda en el teléfono.
@Model
final class DailyRecovery {
    @Attribute(.unique) var day: Date
    var sleepHours: Double?
    var sleepFromHealth: Bool?
    var restingHR: Double?
    var hrv: Double?
    var sleepQuality: Int?
    var soreness: Int?
    var stress: Int?
    var energy: Int?
    /// XP de la misión de descanso de esa noche; nil si todavía no se evaluó.
    var missionXP: Int?

    init(day: Date) {
        self.day = SistemaCalendar.startOfDay(day)
    }

    var checkIn: RecoveryCheckIn? {
        get {
            guard let sleepQuality, let soreness, let stress, let energy else { return nil }
            return RecoveryCheckIn(sleepQuality: sleepQuality, soreness: soreness, stress: stress, energy: energy)
        }
        set {
            sleepQuality = newValue?.sleepQuality
            soreness = newValue?.soreness
            stress = newValue?.stress
            energy = newValue?.energy
        }
    }

    var snapshot: RecoveryDay {
        RecoveryDay(day: day, sleepHours: sleepHours, restingHR: restingHR, hrv: hrv, checkIn: checkIn)
    }
}

/// Reto o logro ya ganado. Queda aunque después se edite el historial.
@Model
final class ChallengeAward {
    @Attribute(.unique) var key: String
    var title: String
    var detail: String
    var date: Date

    init(key: String, title: String, detail: String, date: Date) {
        self.key = key
        self.title = title
        self.detail = detail
        self.date = date
    }
}

enum SistemaSchema {
    static let models: [any PersistentModel.Type] = [
        Player.self, Itinerary.self, Routine.self, Exercise.self, WorkoutSession.self,
        ExerciseLog.self, PenaltyEvent.self, AscensionTrial.self, SystemLogEntry.self,
        BodyEntry.self, ChallengeAward.self, DailyRecovery.self,
    ]

    static func makeContainer(inMemory: Bool) throws -> ModelContainer {
        let schema = Schema(models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
