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

/// Unidad en que se ve y se escribe un peso. Internamente todo se guarda en kg,
/// así las marcas y el e1RM no dependen de la unidad.
enum WeightUnit: String, Codable, CaseIterable, Identifiable {
    case kg, lb

    static let kgPerPound = 0.45359237

    var id: String { rawValue }
    var symbol: String { rawValue }
    var other: WeightUnit { self == .kg ? .lb : .kg }

    func fromKg(_ kg: Double) -> Double {
        self == .kg ? kg : kg / Self.kgPerPound
    }

    func toKg(_ value: Double) -> Double {
        self == .kg ? value : value * Self.kgPerPound
    }
}

/// Formato de un bloque de circuito.
enum CircuitFormat: String, Codable, CaseIterable, Identifiable {
    case circuit, biSeries, tabata, amrap

    var id: String { rawValue }

    var name: String {
        switch self {
        case .circuit: return "Circuito"
        case .biSeries: return "Bi-serie"
        case .tabata: return "Tabata"
        case .amrap: return "AMRAP"
        }
    }
}

// Los campos nuevos de estos tipos son opcionales a propósito: rutinas, sesiones y respaldos
// se guardan como JSON, y un campo no opcional impediría leer los datos ya guardados.

struct StrengthPrescription: Codable, Hashable {
    var exerciseID: UUID?
    var exerciseName: String = ""
    var sets: Int = 3
    var reps: Int = 8
    var weight: Double = 0
    var unit: WeightUnit?
}

struct CircuitExercise: Codable, Hashable, Identifiable {
    var id = UUID()
    var exerciseID: UUID?
    var exerciseName: String = ""
    var reps: Int?
    var seconds: Int?
    var weight: Double?
    var restSeconds: Int?
    var unit: WeightUnit?
    var note: String?

    /// Lo prescrito en una línea, p. ej. "12 reps · c/l · desc. 60 s".
    var prescriptionText: String {
        var parts: [String] = []
        if let seconds { parts.append(Format.seconds(seconds)) }
        if let reps { parts.append("\(reps) reps") }
        if let weight, weight > 0 { parts.append(Format.weight(weight, unit: unit ?? .kg)) }
        if let note, !note.isEmpty { parts.append(note) }
        if let restSeconds, restSeconds > 0 { parts.append("desc. \(Format.seconds(restSeconds))") }
        return parts.joined(separator: " · ")
    }
}

struct CircuitPrescription: Codable, Hashable {
    var rounds: Int = 3
    var exercises: [CircuitExercise] = []
    var restBetweenRoundsSeconds: Int?
    var format: CircuitFormat?
    var title: String?
    var timeCapMinutes: Double?

    var resolvedFormat: CircuitFormat { format ?? .circuit }
    var isAMRAP: Bool { resolvedFormat == .amrap }
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

    /// Bloque de fuerza o circuito con algún ejercicio todavía sin nombre.
    var hasUnnamedExercise: Bool {
        func isBlank(_ name: String) -> Bool { name.trimmingCharacters(in: .whitespaces).isEmpty }
        switch kind {
        case .strength: return isBlank(strength.exerciseName)
        case .circuit: return circuit.exercises.contains { isBlank($0.exerciseName) }
        case .cardio, .classSession: return false
        }
    }

    /// Nombre para encabezados: el título del bloque o su tipo.
    var displayName: String {
        guard kind == .circuit else { return kind.name }
        return circuit.title ?? circuit.resolvedFormat.name
    }

    var summary: String {
        switch kind {
        case .strength:
            let w = strength.weight > 0 ? " @ \(Format.weight(strength.weight))" : ""
            let name = strength.exerciseName.isEmpty ? "Sin nombre" : strength.exerciseName
            return "\(name) \(strength.sets)×\(strength.reps)\(w)"
        case .circuit:
            let prefix = circuit.title.map { "\($0): " } ?? ""
            let count = Format.count(circuit.exercises.count, "ejercicio")
            switch circuit.resolvedFormat {
            case .circuit:
                return "\(prefix)Circuito \(Format.count(circuit.rounds, "ronda")) · \(count)"
            case .biSeries:
                let names = circuit.exercises.map(\.exerciseName).joined(separator: " + ")
                return "\(prefix)Bi-serie ×\(circuit.rounds): \(names)"
            case .tabata:
                return "\(prefix)Tabata ×\(circuit.rounds) · \(count)"
            case .amrap:
                return "\(prefix)AMRAP \(Format.minutes(circuit.timeCapMinutes ?? 0)) · \(count)"
            }
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
    var unit: WeightUnit?
}

/// Lo real de un ejercicio de circuito (por ronda, en promedio).
struct PerformedCircuitExercise: Codable, Hashable {
    var reps: Int?
    var seconds: Int?
    var weight: Double?
    var unit: WeightUnit?
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
                PerformedSet(reps: block.strength.reps, weight: block.strength.weight, unit: block.strength.unit)
            }
        case .circuit:
            // En un AMRAP las rondas son el resultado, no la meta: lo prescrito es el tiempo.
            if block.circuit.isAMRAP {
                r.minutes = block.circuit.timeCapMinutes
            } else {
                r.rounds = block.circuit.rounds
            }
            r.circuitActuals = block.circuit.exercises.map {
                PerformedCircuitExercise(reps: $0.reps, seconds: $0.seconds, weight: $0.weight, unit: $0.unit)
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

    static func weight(_ kg: Double, unit: WeightUnit) -> String {
        let value = (unit.fromKg(kg) * 10).rounded() / 10
        let number = value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value))" : String(format: "%.1f", value)
        return "\(number) \(unit.symbol)"
    }

    /// Para marcas e historial, que mezclan pesas en ambas unidades.
    static func weightBoth(_ kg: Double) -> String {
        guard kg > 0 else { return weight(kg) }
        return "\(weight(kg, unit: .kg)) · \(weight(kg, unit: .lb))"
    }

    static func count(_ n: Int, _ singular: String) -> String {
        "\(n) \(singular)\(n == 1 ? "" : "s")"
    }

    static func seconds(_ s: Int) -> String {
        guard s >= 60 else { return "\(s) s" }
        return s % 60 == 0 ? "\(s / 60) min" : "\(s / 60) min \(s % 60) s"
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
