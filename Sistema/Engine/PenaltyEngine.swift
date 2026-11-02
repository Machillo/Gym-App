import Foundation

struct ItinerarySnapshot: Equatable {
    var id: UUID
    var start: Date
    var end: Date
    var plannedWeekdays: Set<Weekday>

    func covers(_ day: Date) -> Bool {
        let d = SistemaCalendar.startOfDay(day)
        return d >= SistemaCalendar.startOfDay(start) && d <= SistemaCalendar.startOfDay(end)
    }

    func isPlannedWeekday(_ day: Date) -> Bool {
        plannedWeekdays.contains(SistemaCalendar.weekday(of: day))
    }
}

struct SessionSnapshot: Equatable {
    var id: UUID
    var date: Date
    /// Día planeado al que corresponde (inicio de día) o nil si fue libre.
    var plannedDay: Date?
    var compliance: Double
    var xpAwarded: Int
    var isPunishment: Bool
    var minutes: Double
    var classCount: Int = 0
}

struct InjuryPeriod: Codable, Equatable, Identifiable {
    var id = UUID()
    var start: Date
    var end: Date
    var reason: String

    /// Crea un periodo topado a `Progression.maxInjuryDays` días seguidos.
    static func make(start: Date, estimatedEnd: Date, reason: String) -> InjuryPeriod {
        let s = SistemaCalendar.startOfDay(start)
        let maxEnd = SistemaCalendar.addDays(Progression.maxInjuryDays - 1, to: s)
        let e = min(max(SistemaCalendar.startOfDay(estimatedEnd), s), maxEnd)
        return InjuryPeriod(start: s, end: e, reason: reason)
    }

    func contains(_ day: Date) -> Bool {
        let d = SistemaCalendar.startOfDay(day)
        return d >= start && d <= end
    }
}

struct PunishmentMission: Codable, Equatable, Identifiable {
    var id = UUID()
    var faultDay: Date
    var availableFrom: Date
    var deadline: Date
    var completedAt: Date?
    var failed = false

    var isOpen: Bool { completedAt == nil && !failed }

    static let title = "Misión de castigo"
    static let detail = "25 min · 4 rondas: 15 sentadillas, 10 flexiones, 30 s de plancha, 1 min de cuerda o saltos. Ritmo controlado."
}

enum FaultReason: String, Codable {
    case missedDay, lowCompliance, punishmentFailed, noItinerary

    var label: String {
        switch self {
        case .missedDay: return "Día planeado sin sesión"
        case .lowCompliance: return "Sesión con cumplimiento menor a 50 %"
        case .punishmentFailed: return "Misión de castigo no cumplida en 48 h"
        case .noItinerary: return "Sin itinerario vigente"
        }
    }
}

struct PenaltyRecord: Equatable {
    var day: Date
    var reason: FaultReason
    var faultWeight: Double
    var xpLost: Int
    var levelsLost: Int
    var rankLost: Bool
}

/// Libro de penalizaciones persistido junto al jugador.
struct PenaltyLedger: Codable, Equatable {
    var lastEvaluatedDay: Date
    var faultsByWeek: [String: Double] = [:]
    var levelDropsByWeek: [String: Int] = [:]
    var currentStreak = 0
    var maxStreak = 0
    var missions: [PunishmentMission] = []

    init(lastEvaluatedDay: Date) {
        self.lastEvaluatedDay = SistemaCalendar.startOfDay(lastEvaluatedDay)
    }

    var openMission: PunishmentMission? { missions.first { $0.isOpen } }
}

enum PlayerStatus: String, Codable {
    case normal, penaltyZone, injured

    var label: String {
        switch self {
        case .normal: return "Normal"
        case .penaltyZone: return "Zona de penalización"
        case .injured: return "Modo lesión/enfermo"
        }
    }
}

struct EvaluationOutcome {
    var penalties: [PenaltyRecord] = []
    var progressEvents: [ProgressEvent] = []
    var newMissions: [PunishmentMission] = []
    var completedMissions: [PunishmentMission] = []
    var streakIncrements = 0
}

/// Recorre cada día cerrado desde el último cálculo. Idempotente: un día evaluado no se vuelve a castigar.
enum PenaltyEngine {
    static func status(ledger: PenaltyLedger, injuries: [InjuryPeriod], now: Date) -> PlayerStatus {
        if injuries.contains(where: { $0.contains(now) }) { return .injured }
        if ledger.openMission != nil { return .penaltyZone }
        return .normal
    }

    static func evaluate(
        progress: inout PlayerProgress,
        ledger: inout PenaltyLedger,
        itineraries: [ItinerarySnapshot],
        sessions: [SessionSnapshot],
        injuries: [InjuryPeriod],
        now: Date
    ) -> EvaluationOutcome {
        var outcome = EvaluationOutcome()
        resolveMissions(ledger: &ledger, sessions: sessions, outcome: &outcome)

        let today = SistemaCalendar.startOfDay(now)
        var day = SistemaCalendar.addDays(1, to: ledger.lastEvaluatedDay)
        while day < today {
            evaluateDay(day, progress: &progress, ledger: &ledger, itineraries: itineraries,
                        sessions: sessions, injuries: injuries, outcome: &outcome)
            ledger.lastEvaluatedDay = day
            day = SistemaCalendar.addDays(1, to: day)
        }
        return outcome
    }

    /// Marca como cumplidas las misiones de castigo con una sesión de castigo válida dentro de su ventana.
    static func resolveMissions(ledger: inout PenaltyLedger, sessions: [SessionSnapshot], outcome: inout EvaluationOutcome) {
        for index in ledger.missions.indices where ledger.missions[index].isOpen {
            let mission = ledger.missions[index]
            let match = sessions.first {
                $0.isPunishment && $0.minutes >= Progression.punishmentMinMinutes
                    && $0.date >= mission.availableFrom && $0.date < mission.deadline
            }
            if let match {
                ledger.missions[index].completedAt = match.date
                outcome.completedMissions.append(ledger.missions[index])
            }
        }
    }

    private static func evaluateDay(
        _ day: Date,
        progress: inout PlayerProgress,
        ledger: inout PenaltyLedger,
        itineraries: [ItinerarySnapshot],
        sessions: [SessionSnapshot],
        injuries: [InjuryPeriod],
        outcome: inout EvaluationOutcome
    ) {
        if injuries.contains(where: { $0.contains(day) }) {
            // Congelado: sin castigos ni cambios de racha. Las misiones abiertas se corren un día.
            for index in ledger.missions.indices where ledger.missions[index].isOpen {
                ledger.missions[index].deadline = SistemaCalendar.addDays(1, to: ledger.missions[index].deadline)
            }
            return
        }

        if let itinerary = itineraries.first(where: { $0.covers(day) }) {
            if itinerary.isPlannedWeekday(day) {
                let planned = sessions.filter {
                    !$0.isPunishment && $0.plannedDay.map { SistemaCalendar.startOfDay($0) } == day
                }
                if let best = planned.max(by: { $0.compliance < $1.compliance }) {
                    if best.compliance < Progression.halfFaultComplianceThreshold {
                        let loss = Int((Double(best.xpAwarded) * Progression.halfFaultFraction).rounded(.up))
                        applyFault(day: day, reason: .lowCompliance, weight: 0.5, xp: loss, spawnMission: false,
                                   progress: &progress, ledger: &ledger, outcome: &outcome)
                    } else {
                        ledger.currentStreak += 1
                        ledger.maxStreak = max(ledger.maxStreak, ledger.currentStreak)
                        outcome.streakIncrements += 1
                    }
                } else {
                    applyFault(day: day, reason: .missedDay, weight: 1, xp: Progression.fullFaultXP, spawnMission: true,
                               progress: &progress, ledger: &ledger, outcome: &outcome)
                }
            }
        } else if let last = itineraries.filter({ SistemaCalendar.startOfDay($0.end) < day }).max(by: { $0.end < $1.end }),
                  SistemaCalendar.daysBetween(last.end, day) > Progression.itineraryGraceDays,
                  last.isPlannedWeekday(day) {
            applyFault(day: day, reason: .noItinerary, weight: 1, xp: Progression.fullFaultXP,
                       spawnMission: ledger.openMission == nil,
                       progress: &progress, ledger: &ledger, outcome: &outcome)
        }

        // Misiones de castigo vencidas al cierre de este día.
        resolveMissions(ledger: &ledger, sessions: sessions, outcome: &outcome)
        let endOfDay = SistemaCalendar.addDays(1, to: day)
        for index in ledger.missions.indices where ledger.missions[index].isOpen && ledger.missions[index].deadline <= endOfDay {
            ledger.missions[index].failed = true
            applyFault(day: day, reason: .punishmentFailed, weight: 1, xp: Progression.fullFaultXP, spawnMission: false,
                       progress: &progress, ledger: &ledger, outcome: &outcome)
        }
    }

    private static func applyFault(
        day: Date,
        reason: FaultReason,
        weight: Double,
        xp: Int,
        spawnMission: Bool,
        progress: inout PlayerProgress,
        ledger: inout PenaltyLedger,
        outcome: inout EvaluationOutcome
    ) {
        let eventDate = SistemaCalendar.addDays(1, to: day)
        let before = progress.position
        let xpBefore = progress.totalXP + progress.overflowXP
        outcome.progressEvents += progress.applyLoss(xp, now: eventDate)

        ledger.currentStreak = 0
        let week = SistemaCalendar.weekKey(day)
        let faults = ledger.faultsByWeek[week, default: 0] + weight
        ledger.faultsByWeek[week] = faults
        let dropsDue = Int(faults / Progression.faultsPerLevelDrop) - ledger.levelDropsByWeek[week, default: 0]
        if dropsDue > 0 {
            for _ in 0..<dropsDue {
                outcome.progressEvents += progress.dropOneLevel(now: eventDate)
            }
            ledger.levelDropsByWeek[week, default: 0] += dropsDue
        }

        let after = progress.position
        outcome.penalties.append(PenaltyRecord(
            day: day,
            reason: reason,
            faultWeight: weight,
            xpLost: xpBefore - (progress.totalXP + progress.overflowXP),
            levelsLost: max(0, before.level - after.level),
            rankLost: after.rank < before.rank
        ))

        if spawnMission {
            let from = SistemaCalendar.addDays(1, to: day)
            let mission = PunishmentMission(
                faultDay: day,
                availableFrom: from,
                deadline: from.addingTimeInterval(Progression.punishmentWindowHours * 3600)
            )
            ledger.missions.append(mission)
            outcome.newMissions.append(mission)
        }
    }
}
