import Foundation

enum BlockKind: String, Codable, CaseIterable, Identifiable {
    case strength, circuit, cardio, classSession

    var id: String { rawValue }

    var name: String {
        switch self {
        case .strength: return "Fuerza"
        case .circuit: return "Circuito"
        case .cardio: return "Cardio"
        case .classSession: return "Clase"
        }
    }

    var symbol: String {
        switch self {
        case .strength: return "dumbbell.fill"
        case .circuit: return "arrow.triangle.2.circlepath"
        case .cardio: return "figure.run"
        case .classSession: return "figure.boxing"
        }
    }
}

enum ClassDiscipline: String, Codable, CaseIterable, Identifiable {
    case boxing, muayThai

    var id: String { rawValue }
    var name: String { self == .boxing ? "Box" : "Muay Thai" }
}

enum CardioModality: String, Codable, CaseIterable, Identifiable {
    case run, bike, rope, row, swim, other

    var id: String { rawValue }

    var name: String {
        switch self {
        case .run: return "Correr"
        case .bike: return "Bici"
        case .rope: return "Cuerda"
        case .row: return "Remo"
        case .swim: return "Natación"
        case .other: return "Otro"
        }
    }
}

struct StrengthPrescription: Codable, Hashable {
    var exerciseID: UUID?
    var exerciseName: String = ""
    var sets: Int = 3
    var reps: Int = 8
    var weight: Double = 0
}

struct CircuitExercise: Codable, Hashable, Identifiable {
    var id = UUID()
    var exerciseID: UUID?
    var exerciseName: String = ""
    var reps: Int?
    var seconds: Int?
    var weight: Double?
    var restSeconds: Int?
}

struct CircuitPrescription: Codable, Hashable {
    var rounds: Int = 3
    var exercises: [CircuitExercise] = []
    var restBetweenRoundsSeconds: Int?
}

struct CardioPrescription: Codable, Hashable {
    var modality: CardioModality = .run
    var distanceKm: Double?
    var minutes: Double?
}

struct ClassPrescription: Codable, Hashable {
    var discipline: ClassDiscipline = .boxing
    var minutes: Double = 60
}

/// Bloque de una rutina. Solo el payload que corresponde a `kind` es significativo.
struct RoutineBlock: Codable, Hashable, Identifiable {
    var id = UUID()
    var kind: BlockKind
    var strength = StrengthPrescription()
    var circuit = CircuitPrescription()
    var cardio = CardioPrescription()
    var klass = ClassPrescription()

    init(kind: BlockKind) {
        self.kind = kind
    }

    static func strength(_ p: StrengthPrescription) -> RoutineBlock {
        var b = RoutineBlock(kind: .strength)
        b.strength = p
        return b
    }

    static func circuit(_ p: CircuitPrescription) -> RoutineBlock {
        var b = RoutineBlock(kind: .circuit)
        b.circuit = p
        return b
    }

    static func cardio(_ p: CardioPrescription) -> RoutineBlock {
        var b = RoutineBlock(kind: .cardio)
        b.cardio = p
        return b
    }

    static func klass(_ p: ClassPrescription) -> RoutineBlock {
        var b = RoutineBlock(kind: .classSession)
        b.klass = p
        return b
    }

    var summary: String {
        switch kind {
        case .strength:
            let w = strength.weight > 0 ? " @ \(Format.weight(strength.weight))" : ""
            return "\(strength.exerciseName) \(strength.sets)×\(strength.reps)\(w)"
        case .circuit:
            return "Circuito \(circuit.rounds) rondas · \(circuit.exercises.count) ejercicios"
        case .cardio:
            var parts: [String] = [cardio.modality.name]
            if let d = cardio.distanceKm { parts.append(Format.distance(d)) }
            if let m = cardio.minutes { parts.append(Format.minutes(m)) }
            return parts.joined(separator: " · ")
        case .classSession:
            return "Clase de \(klass.discipline.name) · \(Format.minutes(klass.minutes))"
        }
    }
}

struct PerformedSet: Codable, Hashable, Identifiable {
    var id = UUID()
    var reps: Int
    var weight: Double
}

/// Lo real de un ejercicio de circuito (por ronda, en promedio).
struct PerformedCircuitExercise: Codable, Hashable {
    var reps: Int?
    var seconds: Int?
    var weight: Double?
}

/// Prescrito vs. real de un bloque dentro de una sesión.
struct BlockResult: Codable, Hashable, Identifiable {
    var id = UUID()
    var prescribed: RoutineBlock
    var sets: [PerformedSet] = []
    var rounds: Int = 0
    var circuitActuals: [PerformedCircuitExercise] = []
    var distanceKm: Double?
    var minutes: Double?

    init(prescribed: RoutineBlock) {
        self.prescribed = prescribed
        circuitActuals = prescribed.circuit.exercises.map { _ in PerformedCircuitExercise() }
    }

    /// Resultado con lo prescrito cumplido al pie de la letra.
    static func asPrescribed(_ block: RoutineBlock) -> BlockResult {
        var r = BlockResult(prescribed: block)
        switch block.kind {
        case .strength:
            r.sets = (0..<max(block.strength.sets, 0)).map { _ in
                PerformedSet(reps: block.strength.reps, weight: block.strength.weight)
            }
        case .circuit:
            r.rounds = block.circuit.rounds
            r.circuitActuals = block.circuit.exercises.map {
                PerformedCircuitExercise(reps: $0.reps, seconds: $0.seconds, weight: $0.weight)
            }
        case .cardio:
            r.distanceKm = block.cardio.distanceKm
            r.minutes = block.cardio.minutes
        case .classSession:
            r.minutes = block.klass.minutes
        }
        return r
    }

    /// Mejora: más peso que lo prescrito con al menos las mismas reps.
    var hasWeightImprovement: Bool {
        guard prescribed.kind == .strength, prescribed.strength.weight > 0 else { return false }
        return sets.contains { $0.weight > prescribed.strength.weight && $0.reps >= prescribed.strength.reps }
    }
}

enum Format {
    static func weight(_ kg: Double) -> String {
        kg.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(kg)) kg" : String(format: "%.1f kg", kg)
    }

    static func distance(_ km: Double) -> String {
        String(format: "%.2f km", km)
    }

    static func minutes(_ m: Double) -> String {
        m.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(m)) min" : String(format: "%.1f min", m)
    }

    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
