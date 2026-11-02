import Foundation

struct PlayerStats: Codable, Equatable {
    var strength: Double = 0
    var endurance: Double = 0
    var technique: Double = 0
    var discipline: Double = 0
    var vitality: Double = 0

    subscript(kind: StatKind) -> Double {
        get {
            switch kind {
            case .strength: return strength
            case .endurance: return endurance
            case .technique: return technique
            case .discipline: return discipline
            case .vitality: return vitality
            }
        }
        set {
            switch kind {
            case .strength: strength = newValue
            case .endurance: endurance = newValue
            case .technique: technique = newValue
            case .discipline: discipline = newValue
            case .vitality: vitality = newValue
            }
        }
    }
}

/// Cuánto sube cada stat por sesión. Escala con minutos y cumplimiento.
enum StatsEngine {
    static let kindWeights: [BlockKind: [StatKind: Double]] = [
        .strength: [.strength: 1.0, .vitality: 0.3],
        .circuit: [.endurance: 0.7, .strength: 0.4, .vitality: 0.3],
        .cardio: [.endurance: 1.0, .vitality: 0.5],
        .classSession: [.technique: 1.0, .endurance: 0.5],
    ]

    /// Ganancia de stats de una sesión. `exerciseStats` agrega peso a los stats que alimenta cada ejercicio del catálogo.
    static func gains(
        results: [BlockResult],
        compliance: Double,
        planned: Bool,
        early: Bool,
        exerciseStats: [UUID: [StatKind]]
    ) -> PlayerStats {
        var gains = PlayerStats()
        for result in results {
            let ratio = ComplianceEngine.blockCompliance(result)
            let scale = ComplianceEngine.estimatedMinutes(result.prescribed) / 60 * ratio
            for (stat, weight) in kindWeights[result.prescribed.kind] ?? [:] {
                gains[stat] += weight * scale
            }
            for id in exerciseIDs(of: result.prescribed) {
                for stat in exerciseStats[id] ?? [] {
                    gains[stat] += 0.2 * scale
                }
            }
        }
        if planned { gains.discipline += 0.3 * compliance }
        if early { gains.discipline += 0.2 }
        return gains
    }

    static func exerciseIDs(of block: RoutineBlock) -> [UUID] {
        switch block.kind {
        case .strength: return block.strength.exerciseID.map { [$0] } ?? []
        case .circuit: return block.circuit.exercises.compactMap(\.exerciseID)
        default: return []
        }
    }
}
