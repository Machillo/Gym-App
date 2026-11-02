import Foundation

/// Cumplimiento real/prescrito por bloque y por sesión. Cada bloque topa en 100 %.
enum ComplianceEngine {
    static func blockCompliance(_ result: BlockResult) -> Double {
        let p = result.prescribed
        switch p.kind {
        case .strength:
            let prescribed = Double(p.strength.sets * p.strength.reps)
            guard prescribed > 0 else { return result.sets.isEmpty ? 0 : 1 }
            let done = Double(result.sets.reduce(0) { $0 + max($1.reps, 0) })
            return clamp(done / prescribed)

        case .circuit:
            let rounds = p.circuit.rounds
            guard rounds > 0 else { return 0 }
            let roundRatio = clamp(Double(result.rounds) / Double(rounds))
            let exercises = p.circuit.exercises
            guard !exercises.isEmpty else { return roundRatio }
            var sum = 0.0
            for (index, exercise) in exercises.enumerated() {
                let actual = index < result.circuitActuals.count ? result.circuitActuals[index] : PerformedCircuitExercise()
                sum += exerciseRatio(prescribed: exercise, actual: actual)
            }
            return roundRatio * (sum / Double(exercises.count))

        case .cardio:
            if let distance = p.cardio.distanceKm, distance > 0 {
                return clamp((result.distanceKm ?? 0) / distance)
            }
            if let minutes = p.cardio.minutes, minutes > 0 {
                return clamp((result.minutes ?? 0) / minutes)
            }
            return 0

        case .classSession:
            guard p.klass.minutes > 0 else { return 0 }
            return clamp((result.minutes ?? 0) / p.klass.minutes)
        }
    }

    /// Promedio ponderado por los minutos estimados de cada bloque.
    static func sessionCompliance(_ results: [BlockResult]) -> Double {
        guard !results.isEmpty else { return 0 }
        var weighted = 0.0
        var totalWeight = 0.0
        for result in results {
            let weight = max(estimatedMinutes(result.prescribed), 1)
            weighted += blockCompliance(result) * weight
            totalWeight += weight
        }
        return totalWeight > 0 ? weighted / totalWeight : 0
    }

    /// Minutos estimados de un bloque (para ponderar y precargar la duración).
    static func estimatedMinutes(_ block: RoutineBlock) -> Double {
        switch block.kind {
        case .strength:
            return Double(max(block.strength.sets, 0)) * 2.5
        case .circuit:
            let perRoundSeconds = block.circuit.exercises.reduce(0.0) { acc, e in
                let work = Double(e.seconds ?? ((e.reps ?? 0) * 3))
                return acc + work + Double(e.restSeconds ?? 0)
            }
            let rest = Double(block.circuit.restBetweenRoundsSeconds ?? 0)
            return Double(max(block.circuit.rounds, 0)) * (perRoundSeconds + rest) / 60
        case .cardio:
            if let minutes = block.cardio.minutes { return minutes }
            return (block.cardio.distanceKm ?? 0) * 6
        case .classSession:
            return block.klass.minutes
        }
    }

    static func estimatedMinutes(_ blocks: [RoutineBlock]) -> Double {
        blocks.reduce(0) { $0 + estimatedMinutes($1) }
    }

    private static func exerciseRatio(prescribed: CircuitExercise, actual: PerformedCircuitExercise) -> Double {
        if let reps = prescribed.reps, reps > 0 {
            return clamp(Double(actual.reps ?? 0) / Double(reps))
        }
        if let seconds = prescribed.seconds, seconds > 0 {
            return clamp(Double(actual.seconds ?? 0) / Double(seconds))
        }
        return 1
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
