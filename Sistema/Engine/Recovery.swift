import Foundation

/// Cómo amaneciste, de 1 a 5. En dolor y estrés, 5 es peor.
struct RecoveryCheckIn: Codable, Equatable {
    var sleepQuality: Int
    var soreness: Int
    var stress: Int
    var energy: Int

    /// 0–100: más es mejor.
    var score: Double {
        let positive = Double(sleepQuality + energy + (6 - soreness) + (6 - stress)) / 4
        return (positive - 1) / 4 * 100
    }
}

/// Lo que se sabe de un día. El sueño es el de la noche que terminó ese día.
struct RecoveryDay: Equatable {
    var day: Date
    var sleepHours: Double?
    var restingHR: Double?
    var hrv: Double?
    var checkIn: RecoveryCheckIn?
}

enum RecoveryZone: String, Equatable {
    case ready, moderate, recover

    var label: String {
        switch self {
        case .ready: return "Listo"
        case .moderate: return "Moderado"
        case .recover: return "Recuperar"
        }
    }

    var advice: String {
        switch self {
        case .ready: return "Día para ir fuerte o buscar récords."
        case .moderate: return "Entreno normal, sin forzar."
        case .recover: return "Técnica, movilidad o descanso activo."
        }
    }
}

struct RecoveryComponent: Equatable {
    var name: String
    var value: Double
    var weight: Double
}

struct RecoveryReport: Equatable {
    var score: Int
    var zone: RecoveryZone
    var components: [RecoveryComponent]
    /// Noches con HRV o pulso que faltan para comparar contra tu promedio; 0 si ya alcanza.
    var calibrationDaysLeft: Int
}

/// Modo pelea: cuenta regresiva y prioridad a la recuperación en las últimas semanas.
struct FightMode: Equatable {
    var daysLeft: Int

    var isActive: Bool { daysLeft >= 0 && daysLeft <= RecoveryEngine.fightModeDays }

    var advice: String? {
        guard isActive else { return nil }
        return daysLeft <= 7 ? "Semana de pelea: el descanso manda. Nada de buscar récords." : "Modo pelea: priorizá dormir y recuperar."
    }
}

/// Sesión con la noche anterior, para buscar patrones.
struct SleepPatternSample: Equatable {
    var sleepHours: Double
    var compliance: Double
    var improvements: Int
    var isClass: Bool
    var rpe: Int
}

struct SleepPatternGroup: Equatable {
    var sessions: Int
    var averageCompliance: Double
    var improvementsPerSession: Double
    var classes: Int
    var classAverageRPE: Double?
}

struct SleepPatterns: Equatable {
    var rested: SleepPatternGroup
    var short: SleepPatternGroup
    /// Hay suficientes sesiones en los dos grupos para comparar.
    var isMeaningful: Bool { rested.sessions >= RecoveryEngine.minPatternSessions && short.sessions >= RecoveryEngine.minPatternSessions }
}

/// Puntaje de recuperación contra tu propio promedio. Lógica pura.
enum RecoveryEngine {
    static let sleepGoalHours = 7.0
    static let sleepTargetHours = 7.5
    static let fightSleepTargetHours = 8.0
    static let fallAsleepMinutes = 15.0
    static let sleepDebtDebuffHours = 5.0
    static let sleepDebtEarlierHours = 3.0
    static let baselineDays = 28
    static let minBaselineSamples = 7
    static let fightModeDays = 21
    static let restedXPBonus = 0.05
    static let sleepMissionXP = 20.0
    static let sleepStreakMilestones = [7, 14, 30]
    static let minPatternSessions = 3

    // MARK: - Sueño

    /// Horas dormidas en la noche que termina `day` (de las 6 p. m. anteriores a las 2 p. m.).
    /// Une los tramos: el Watch y el iPhone suelen registrar la misma noche por duplicado.
    static func sleepHours(intervals: [DateInterval], day: Date) -> Double? {
        let start = SistemaCalendar.startOfDay(day)
        let windowStart = start.addingTimeInterval(-6 * 3600)
        let windowEnd = start.addingTimeInterval(14 * 3600)
        let clipped = intervals.compactMap { interval -> DateInterval? in
            let from = max(interval.start, windowStart)
            let to = min(interval.end, windowEnd)
            return from < to ? DateInterval(start: from, end: to) : nil
        }.sorted { $0.start < $1.start }
        guard var current = clipped.first else { return nil }
        var seconds = 0.0
        for interval in clipped.dropFirst() {
            if interval.start <= current.end {
                current = DateInterval(start: current.start, end: max(current.end, interval.end))
            } else {
                seconds += current.duration
                current = interval
            }
        }
        seconds += current.duration
        return seconds / 3600
    }

    /// Horas que faltaron para la meta en las últimas 7 noches registradas hasta `today`.
    static func sleepDebt(days: [RecoveryDay], today: Date, target: Double = sleepTargetHours) -> Double {
        let end = SistemaCalendar.startOfDay(today)
        let start = SistemaCalendar.addDays(-6, to: end)
        return days.filter { $0.day >= start && $0.day <= end }
            .compactMap(\.sleepHours)
            .reduce(0) { $0 + max(0, target - $1) }
    }

    /// Noches seguidas de 7 horas o más. Si hoy todavía no hay dato, cuenta desde ayer.
    static func sleepStreak(days: [RecoveryDay], today: Date) -> Int {
        let hours = Dictionary(days.compactMap { d in d.sleepHours.map { (SistemaCalendar.startOfDay(d.day), $0) } }, uniquingKeysWith: max)
        var day = SistemaCalendar.startOfDay(today)
        if hours[day] == nil { day = SistemaCalendar.addDays(-1, to: day) }
        var streak = 0
        while let value = hours[day], value >= sleepGoalHours {
            streak += 1
            day = SistemaCalendar.addDays(-1, to: day)
        }
        return streak
    }

    /// A qué hora acostarse para despertar en `wake` con la meta cumplida. Con deuda, media hora antes.
    static func bedtime(wake: Date, debt: Double, target: Double) -> Date {
        let extra = debt >= sleepDebtEarlierHours ? 30.0 : 0
        return wake.addingTimeInterval(-(target * 3600 + (fallAsleepMinutes + extra) * 60))
    }

    // MARK: - Puntaje

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 100) }

    private static func baseline(_ values: [Double]) -> (mean: Double, sd: Double)? {
        guard values.count >= minBaselineSamples else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        // Piso: con datos casi iguales, un cambio mínimo no debe parecer enorme.
        return (mean, max(variance.squareRoot(), abs(mean) * 0.05))
    }

    /// `history`: días anteriores a hoy. `dailyLoad`: minutos × RPE de cada día, por inicio de día.
    static func report(today: RecoveryDay, history: [RecoveryDay], dailyLoad: [Date: Double], fight: FightMode?) -> RecoveryReport? {
        let dayStart = SistemaCalendar.startOfDay(today.day)
        let windowStart = SistemaCalendar.addDays(-baselineDays, to: dayStart)
        let past = history.filter { $0.day >= windowStart && $0.day < dayStart }
        let fighting = fight?.isActive == true
        let target = fighting ? fightSleepTargetHours : sleepTargetHours
        var components: [RecoveryComponent] = []

        if let hours = today.sleepHours {
            let absolute = clamp((hours - 4) / (target - 4) * 100)
            var value = absolute
            if let base = baseline(past.compactMap(\.sleepHours)) {
                value = 0.6 * absolute + 0.4 * clamp(60 + (hours - base.mean) / base.sd * 20)
            }
            components.append(RecoveryComponent(name: "Sueño", value: value, weight: 35))
        }
        if let checkIn = today.checkIn {
            components.append(RecoveryComponent(name: "Cómo amaneciste", value: checkIn.score, weight: 20))
        }
        let hrvBase = baseline(past.compactMap(\.hrv))
        if let hrv = today.hrv, let hrvBase {
            components.append(RecoveryComponent(name: "HRV", value: clamp(60 + (hrv - hrvBase.mean) / hrvBase.sd * 20), weight: 25))
        }
        let heartBase = baseline(past.compactMap(\.restingHR))
        if let heart = today.restingHR, let heartBase {
            components.append(RecoveryComponent(name: "Pulso en reposo", value: clamp(60 - (heart - heartBase.mean) / heartBase.sd * 20), weight: 15))
        }
        guard !components.isEmpty else { return nil }

        let loads = (1...baselineDays).map { dailyLoad[SistemaCalendar.addDays(-$0, to: dayStart)] ?? 0 }
        let chronic = loads.reduce(0, +) / Double(baselineDays)
        if loads.filter({ $0 > 0 }).count >= 4, chronic > 0 {
            let acute = loads.prefix(3).reduce(0, +) / 3
            components.append(RecoveryComponent(name: "Carga de entreno", value: clamp(100 - max(0, acute / chronic - 1) * 100), weight: 15))
        }

        let totalWeight = components.reduce(0) { $0 + $1.weight }
        let score = Int((components.reduce(0) { $0 + $1.value * $1.weight } / totalWeight).rounded())
        let shift = fighting ? 5 : 0
        let zone: RecoveryZone = score >= 70 + shift ? .ready : (score >= 45 + shift ? .moderate : .recover)
        let samples = max(past.compactMap(\.hrv).count, past.compactMap(\.restingHR).count)
        return RecoveryReport(score: score, zone: zone, components: components,
                              calibrationDaysLeft: max(0, minBaselineSamples - samples))
    }

    // MARK: - Patrones

    static func patterns(_ samples: [SleepPatternSample]) -> SleepPatterns {
        func group(_ items: [SleepPatternSample]) -> SleepPatternGroup {
            let count = Double(max(items.count, 1))
            let classes = items.filter(\.isClass)
            return SleepPatternGroup(
                sessions: items.count,
                averageCompliance: items.reduce(0) { $0 + $1.compliance } / count,
                improvementsPerSession: Double(items.reduce(0) { $0 + $1.improvements }) / count,
                classes: classes.count,
                classAverageRPE: classes.isEmpty ? nil : Double(classes.reduce(0) { $0 + $1.rpe }) / Double(classes.count)
            )
        }
        return SleepPatterns(rested: group(samples.filter { $0.sleepHours >= sleepGoalHours }),
                             short: group(samples.filter { $0.sleepHours < sleepGoalHours }))
    }
}
