import Foundation

/// Qué tipo de entrenamiento grabó el Watch, ya traducido a los bloques del Sistema.
enum HealthCategory: Equatable {
    case strength
    case cardio(CardioModality)
    case fight(ClassDiscipline)
    case other

    /// Se guarda como texto en la sesión: "strength", "cardio:run", "fight:mma", "other".
    var raw: String {
        switch self {
        case .strength: return "strength"
        case let .cardio(modality): return "cardio:\(modality.rawValue)"
        case let .fight(discipline): return "fight:\(discipline.rawValue)"
        case .other: return "other"
        }
    }

    init(raw: String) {
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        switch parts.first {
        case "strength": self = .strength
        case "cardio": self = .cardio(CardioModality(rawValue: parts.last ?? "") ?? .other)
        case "fight": self = .fight(ClassDiscipline(rawValue: parts.last ?? "") ?? .mma)
        default: self = .other
        }
    }

    var group: HealthMatchGroup {
        switch self {
        case .strength: return .strength
        case .cardio: return .cardio
        case .fight: return .fight
        case .other: return .none
        }
    }
}

/// Para no duplicar: un entrenamiento del Watch solo se une a una sesión del mismo grupo y del mismo día.
enum HealthMatchGroup: Equatable {
    case strength, cardio, fight, none

    /// Grupo de una sesión de la app según el bloque que domina.
    static func of(_ blocks: [RoutineBlock]) -> HealthMatchGroup {
        guard !blocks.isEmpty else { return .none }
        switch XPEngine.dominantKind(blocks) {
        case .strength, .circuit: return .strength
        case .cardio: return .cardio
        case .classSession: return .fight
        }
    }
}

/// Entrenamiento leído de Salud.
struct HealthWorkout: Equatable {
    var id: String
    var title: String
    var category: HealthCategory
    var start: Date
    var end: Date
    var kcal: Double?
    var avgHR: Double?
    var maxHR: Double?
    var distanceKm: Double?
    var sourceName: String

    var minutes: Double { max(end.timeIntervalSince(start) / 60, 1) }
}

enum HealthBodyKind: String, CaseIterable {
    case weight, bodyFat, leanMass, waist
}

/// Peso o grasa leídos de Salud (por ejemplo, de una balanza).
struct HealthBodySample: Equatable {
    var id: String
    var kind: HealthBodyKind
    /// kg para el peso; porcentaje 0–100 para la grasa.
    var value: Double
    var date: Date
}

/// Una medida que el Sistema manda a Salud.
struct HealthBodyExport: Equatable {
    var kind: HealthBodyKind
    /// kg, porcentaje 0–100 o cm, según el tipo.
    var value: Double
    var date: Date
    var syncID: String
}

/// Una clase de pelea que el Sistema manda a Salud, con calorías estimadas.
struct HealthWorkoutExport: Equatable {
    var syncID: String
    var discipline: ClassDiscipline
    var start: Date
    var end: Date
    var kcal: Double
}

/// Aros y pasos del día.
struct HealthActivitySnapshot: Equatable {
    var steps: Int
    var stepsWeekAverage: Int
    var moveKcal: Double
    var moveGoal: Double
    var exerciseMinutes: Double
    var exerciseGoal: Double
    var standHours: Double
    var standGoal: Double
    var hasRings: Bool
}

enum HealthSync {
    static func sessionSyncID(_ id: UUID) -> String { "sistema.session.\(id.uuidString)" }
    static func bodySyncID(_ id: UUID, _ kind: HealthBodyKind) -> String { "sistema.body.\(id.uuidString).\(kind.rawValue)" }

    /// MET aproximados (Compendio de Actividades Físicas) para una clase completa: calentamiento, técnica y rounds.
    static func met(_ discipline: ClassDiscipline) -> Double {
        switch discipline {
        case .boxing: return 7.8
        case .muayThai: return 9.0
        case .mma: return 9.0
        }
    }

    /// Calorías activas estimadas: MET × kg × horas, ajustado por el esfuerzo (RPE 7 = sin ajuste).
    static func estimatedKcal(discipline: ClassDiscipline, minutes: Double, weightKg: Double, rpe: Int) -> Double {
        let effort = min(max(0.7 + 0.3 * Double(rpe) / 7, 0.8), 1.15)
        // Se descuenta el gasto en reposo (1 MET): Salud cuenta las activas aparte.
        return ((met(discipline) - 1) * weightKg * minutes / 60 * effort).rounded()
    }

    /// Lo que va a Salud de un registro del cuerpo. La grasa y el peso que vinieron de Salud no se devuelven.
    static func bodyExports(id: UUID, date: Date, weightKg: Double?, bodyFatPercent: Double?, waistCm: Double?,
                            weightFromHealth: Bool, fatFromHealth: Bool) -> [HealthBodyExport] {
        var list: [HealthBodyExport] = []
        if let weightKg, !weightFromHealth {
            list.append(HealthBodyExport(kind: .weight, value: weightKg, date: date, syncID: bodySyncID(id, .weight)))
        }
        if let bodyFatPercent, !fatFromHealth {
            list.append(HealthBodyExport(kind: .bodyFat, value: bodyFatPercent, date: date, syncID: bodySyncID(id, .bodyFat)))
        }
        if let weightKg, let bodyFatPercent, !(weightFromHealth && fatFromHealth) {
            list.append(HealthBodyExport(kind: .leanMass, value: weightKg * (1 - bodyFatPercent / 100), date: date,
                                         syncID: bodySyncID(id, .leanMass)))
        }
        if let waistCm {
            list.append(HealthBodyExport(kind: .waist, value: waistCm, date: date, syncID: bodySyncID(id, .waist)))
        }
        return list
    }

    /// El bloque que representa un entrenamiento del Watch dentro del Sistema, cumplido al 100 %.
    static func result(for workout: HealthWorkout) -> BlockResult {
        let minutes = (workout.minutes * 10).rounded() / 10
        switch workout.category {
        case .strength:
            let block = RoutineBlock.circuit(CircuitPrescription(rounds: 0, exercises: [], format: .amrap,
                                                                 title: workout.title, timeCapMinutes: minutes))
            var result = BlockResult(prescribed: block)
            result.minutes = minutes
            return result
        case let .fight(discipline):
            var result = BlockResult(prescribed: .klass(ClassPrescription(discipline: discipline, minutes: minutes)))
            result.minutes = minutes
            return result
        case let .cardio(modality):
            var result = BlockResult(prescribed: .cardio(CardioPrescription(modality: modality, distanceKm: nil, minutes: minutes)))
            result.minutes = minutes
            result.distanceKm = workout.distanceKm
            return result
        case .other:
            var result = BlockResult(prescribed: .cardio(CardioPrescription(modality: .other, distanceKm: nil, minutes: minutes)))
            result.minutes = minutes
            return result
        }
    }
}
