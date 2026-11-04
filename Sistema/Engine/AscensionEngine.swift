import Foundation

enum TrialRequirement: Codable, Hashable {
    /// N semanas calendario seguidas con cumplimiento semanal ≥ mínimo.
    case consistency(weeks: Int, minCompliance: Double)
    /// Mejorar en un % tu mejor marca registrada en algún ejercicio o cardio.
    case improvement(percent: Double)
    /// Completar N clases de box, Muay Thai o MMA dentro del rango.
    case classes(count: Int)

    var description: String {
        switch self {
        case let .consistency(weeks, minCompliance):
            return "\(weeks) semanas seguidas con ≥\(Format.percent(minCompliance)) de cumplimiento"
        case let .improvement(percent):
            return "Mejorar \(Format.percent(percent)) una marca personal (e1RM o ritmo de cardio)"
        case let .classes(count):
            return "Completar \(count) clases de box, Muay Thai o MMA en este rango"
        }
    }
}

struct TrialMetrics: Equatable {
    /// Cumplimiento de cada semana completa, en orden cronológico.
    var weeklyCompliance: [Double]
    /// Mejor mejora relativa de una marca dentro del rango (0.1 = 10 %).
    var bestImprovement: Double
    var classesInRank: Int

    func trailingWeeks(atLeast threshold: Double) -> Int {
        var count = 0
        for value in weeklyCompliance.reversed() {
            guard value >= threshold - 0.0001 else { break }
            count += 1
        }
        return count
    }
}

struct RequirementStatus: Equatable, Identifiable {
    var requirement: TrialRequirement
    var progress: String
    var met: Bool

    var id: String { requirement.description }
}

/// Pruebas de ascenso: usan tu propia constancia y tus récords, no números de élite.
enum AscensionEngine {
    static func requirements(for rank: Rank) -> [TrialRequirement] {
        switch rank {
        case .e: return []
        case .d: return [.consistency(weeks: 3, minCompliance: 0.70)]
        case .c: return [.consistency(weeks: 6, minCompliance: 0.75), .improvement(percent: 0.05)]
        case .b: return [.consistency(weeks: 8, minCompliance: 0.80), .improvement(percent: 0.10), .classes(count: 8)]
        case .a: return [.consistency(weeks: 12, minCompliance: 0.85), .improvement(percent: 0.15), .classes(count: 20)]
        case .s: return [.consistency(weeks: 16, minCompliance: 0.85), .improvement(percent: 0.20), .classes(count: 40)]
        case .ss: return [.consistency(weeks: 24, minCompliance: 0.90), .improvement(percent: 0.25), .classes(count: 60)]
        }
    }

    static func evaluate(target: Rank, metrics: TrialMetrics) -> [RequirementStatus] {
        requirements(for: target).map { requirement in
            switch requirement {
            case let .consistency(weeks, minCompliance):
                let have = metrics.trailingWeeks(atLeast: minCompliance)
                return RequirementStatus(requirement: requirement, progress: "\(min(have, weeks))/\(weeks) semanas", met: have >= weeks)
            case let .improvement(percent):
                let best = max(metrics.bestImprovement, 0)
                return RequirementStatus(requirement: requirement, progress: "Mejor: +\(Format.percent(best))", met: best >= percent - 0.0001)
            case let .classes(count):
                return RequirementStatus(requirement: requirement, progress: "\(min(metrics.classesInRank, count))/\(count) clases", met: metrics.classesInRank >= count)
            }
        }
    }

    static func allMet(target: Rank, metrics: TrialMetrics) -> Bool {
        evaluate(target: target, metrics: metrics).allSatisfy(\.met)
    }

    /// Cumplimiento por semana completa: promedio de los días planeados (sin sesión = 0). Excluye días de lesión.
    static func weeklyCompliance(
        itineraries: [ItinerarySnapshot],
        sessions: [SessionSnapshot],
        injuries: [InjuryPeriod],
        from: Date,
        through: Date
    ) -> [Double] {
        let start = SistemaCalendar.startOfWeek(from)
        let last = SistemaCalendar.startOfDay(through)
        var bestByDay: [Date: Double] = [:]
        for session in sessions where !session.isPunishment {
            guard let planned = session.plannedDay else { continue }
            let day = SistemaCalendar.startOfDay(planned)
            bestByDay[day] = max(bestByDay[day] ?? 0, session.compliance)
        }

        var result: [Double] = []
        var weekStart = start
        while SistemaCalendar.addDays(6, to: weekStart) <= last {
            var sum = 0.0
            var count = 0
            for offset in 0..<7 {
                let day = SistemaCalendar.addDays(offset, to: weekStart)
                guard day >= SistemaCalendar.startOfDay(from),
                      !injuries.contains(where: { $0.contains(day) }),
                      let it = itineraries.first(where: { $0.covers(day) }),
                      it.isPlannedWeekday(day) else { continue }
                sum += bestByDay[day] ?? 0
                count += 1
            }
            if count > 0 { result.append(sum / Double(count)) }
            weekStart = SistemaCalendar.addDays(7, to: weekStart)
        }
        return result
    }

    /// Mejor mejora relativa de una marca dentro del rango. La base es tu mejor marca previa
    /// o, si no hay, la primera registrada en el rango.
    static func bestImprovement(records: [MarkRecord], since: Date) -> Double {
        var best = 0.0
        for (_, group) in Dictionary(grouping: records, by: \.key) {
            let sorted = group.sorted { $0.date < $1.date }
            let before = sorted.filter { $0.date < since }
            let inRank = sorted.filter { $0.date >= since }
            guard !inRank.isEmpty else { continue }
            let higherIsBetter = group[0].higherIsBetter
            let pick: ([MarkRecord]) -> Double? = { list in
                higherIsBetter ? list.map(\.value).max() : list.map(\.value).min()
            }
            guard let baseline = pick(before) ?? inRank.first?.value,
                  let top = pick(inRank), baseline > 0, top > 0 else { continue }
            let improvement = higherIsBetter ? top / baseline - 1 : baseline / top - 1
            best = max(best, improvement)
        }
        return best
    }
}

/// Una marca comparable: e1RM de un ejercicio (más es mejor) o ritmo de cardio en min/km (menos es mejor).
struct MarkRecord: Equatable {
    var key: String
    var date: Date
    var value: Double
    var higherIsBetter: Bool
}
