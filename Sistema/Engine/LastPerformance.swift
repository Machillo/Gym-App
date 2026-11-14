import Foundation

/// Lo esencial de una sesión para los cálculos de progreso, sin depender de SwiftData.
struct SessionDigest: Equatable {
    var id: UUID
    var date: Date
    var results: [BlockResult]
    var plannedDay: Date?
    var compliance: Double
    var isPunishment: Bool
    var durationMinutes: Double

    /// Minutos reales de un bloque: lo estimado por lo cumplido.
    static func minutes(of result: BlockResult) -> Double {
        ComplianceEngine.estimatedMinutes(result.prescribed) * ComplianceEngine.blockCompliance(result)
    }

    var classes: [ClassDiscipline] {
        results.filter { $0.prescribed.kind == .classSession && ComplianceEngine.blockCompliance($0) >= 0.5 }
            .map(\.prescribed.klass.discipline)
    }
}

/// El peso más alto usado la última vez en un ejercicio.
struct LastPerformance: Equatable {
    var weightKg: Double
    var unit: WeightUnit
    var reps: Int
    var date: Date

    var text: String {
        let weight = Format.weight(weightKg, unit: unit)
        return reps > 0 ? "\(weight) × \(reps)" : weight
    }
}

/// Índice del último peso por ejercicio, por id del catálogo y por nombre.
struct LastPerformanceIndex: Equatable {
    private var byKey: [String: LastPerformance] = [:]

    init(sessions: [SessionDigest] = []) {
        for session in sessions.sorted(by: { $0.date < $1.date }) {
            var best: [String: LastPerformance] = [:]
            for result in session.results {
                let block = result.prescribed
                switch block.kind {
                case .strength:
                    for set in result.sets where set.weight > 0 {
                        let found = LastPerformance(weightKg: set.weight, unit: set.unit ?? block.strength.unit ?? .preferred,
                                                    reps: set.reps, date: session.date)
                        Self.keep(found, id: block.strength.exerciseID, name: block.strength.exerciseName, in: &best)
                    }
                case .circuit:
                    for (index, exercise) in block.circuit.exercises.enumerated() where index < result.circuitActuals.count {
                        let actual = result.circuitActuals[index]
                        guard let weight = actual.weight, weight > 0 else { continue }
                        let found = LastPerformance(weightKg: weight, unit: actual.unit ?? exercise.unit ?? .preferred,
                                                    reps: actual.reps ?? 0, date: session.date)
                        Self.keep(found, id: exercise.exerciseID, name: exercise.exerciseName, in: &best)
                    }
                default:
                    break
                }
            }
            byKey.merge(best) { _, new in new }
        }
    }

    func find(id: UUID?, name: String) -> LastPerformance? {
        if let id, let found = byKey[Self.idKey(id)] { return found }
        return byKey[Self.nameKey(name)]
    }

    private static func keep(_ found: LastPerformance, id: UUID?, name: String, in best: inout [String: LastPerformance]) {
        var keys = [nameKey(name)]
        if let id { keys.append(idKey(id)) }
        for key in keys where found.weightKg > (best[key]?.weightKg ?? 0) { best[key] = found }
    }

    private static func idKey(_ id: UUID) -> String { "id:\(id.uuidString)" }
    private static func nameKey(_ name: String) -> String { "name:\(ExerciseCatalog.normalize(name))" }
}
