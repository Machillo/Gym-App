import Foundation

/// Medidas corporales, siempre en centímetros.
enum BodyMeasure: String, Codable, CaseIterable, Identifiable {
    case neck, shoulders, chest, waist, hips, armLeft, armRight, forearm, thighLeft, thighRight, calf

    var id: String { rawValue }

    var name: String {
        switch self {
        case .neck: return "Cuello"
        case .shoulders: return "Hombros"
        case .chest: return "Pecho"
        case .waist: return "Cintura"
        case .hips: return "Cadera"
        case .armLeft: return "Brazo izquierdo"
        case .armRight: return "Brazo derecho"
        case .forearm: return "Antebrazo"
        case .thighLeft: return "Muslo izquierdo"
        case .thighRight: return "Muslo derecho"
        case .calf: return "Pantorrilla"
        }
    }

    /// Dónde poner la cinta, para que cada medida se compare con la anterior.
    var tip: String {
        switch self {
        case .neck: return "Debajo de la manzana de Adán, cinta horizontal."
        case .shoulders: return "Alrededor de los hombros, en la parte más ancha, brazos relajados."
        case .chest: return "A la altura de los pezones, después de soltar el aire."
        case .waist: return "A la altura del ombligo, abdomen relajado, sin apretar."
        case .hips: return "En la parte más ancha de los glúteos, pies juntos."
        case .armLeft, .armRight: return "En la parte más gruesa del bíceps, brazo relajado colgando."
        case .forearm: return "En la parte más gruesa, justo debajo del codo."
        case .thighLeft, .thighRight: return "Unos 15 cm arriba de la rodilla, de pie y relajado."
        case .calf: return "En la parte más gruesa, de pie con el peso repartido."
        }
    }
}

/// Lo que se puede graficar del cuerpo.
enum BodyMetric: Hashable, Identifiable {
    case weight, bodyFat, leanMass, muscleMass, fatMass, visceralFat, inBodyScore, measure(BodyMeasure)

    var id: String {
        switch self {
        case .weight: return "weight"
        case .bodyFat: return "bodyFat"
        case .leanMass: return "leanMass"
        case .muscleMass: return "muscleMass"
        case .fatMass: return "fatMass"
        case .visceralFat: return "visceralFat"
        case .inBodyScore: return "inBodyScore"
        case let .measure(measure): return measure.rawValue
        }
    }

    var name: String {
        switch self {
        case .weight: return "Peso"
        case .bodyFat: return "% de grasa"
        case .leanMass: return "Masa magra"
        case .muscleMass: return "Masa muscular"
        case .fatMass: return "Grasa (kg)"
        case .visceralFat: return "Grasa visceral"
        case .inBodyScore: return "Puntos InBody"
        case let .measure(measure): return measure.name
        }
    }

    static var all: [BodyMetric] { inBody + [.leanMass] + BodyMeasure.allCases.map(BodyMetric.measure) }

    /// Lo que trae la hoja de InBody, en el orden en que se anota.
    static let inBody: [BodyMetric] = [.weight, .muscleMass, .bodyFat, .fatMass, .visceralFat, .inBodyScore]

    /// Se calcula con otros datos: no se anota.
    var isDerived: Bool { self == .leanMass || self == .fatMass }

    /// Si subir es bueno (verde), malo (rojo) o neutro.
    var upIsGood: Bool? {
        switch self {
        case .muscleMass, .leanMass, .inBodyScore: return true
        case .bodyFat, .fatMass, .visceralFat: return false
        case .weight: return nil
        case let .measure(measure): return measure == .waist || measure == .hips ? false : nil
        }
    }

    var unitSymbol: String {
        switch self {
        case .weight, .leanMass, .muscleMass, .fatMass: return "kg"
        case .bodyFat: return "%"
        case .visceralFat: return "nivel"
        case .inBodyScore: return "pts"
        case .measure: return "cm"
        }
    }

    /// El valor en su unidad de pantalla.
    func text(_ value: Double, weightUnit: WeightUnit) -> String {
        switch self {
        case .weight, .leanMass, .muscleMass, .fatMass: return Format.weight(value, unit: weightUnit)
        case .bodyFat: return String(format: "%.1f %%", value)
        case .visceralFat: return "Nivel \(Int(value.rounded()))"
        case .inBodyScore: return "\(Int(value.rounded())) pts"
        case .measure: return String(format: "%.1f cm", value)
        }
    }
}

struct BodySnapshot: Equatable {
    var date: Date
    var weightKg: Double?
    var bodyFatPercent: Double?
    var measures: [BodyMeasure: Double] = [:]
    var skeletalMuscleKg: Double?
    var visceralFatLevel: Double?
    var inBodyScore: Double?

    var fatMassKg: Double? {
        guard let weightKg, let bodyFatPercent else { return nil }
        return weightKg * bodyFatPercent / 100
    }

    var leanMassKg: Double? {
        guard let weightKg, let bodyFatPercent else { return nil }
        return weightKg * (1 - bodyFatPercent / 100)
    }

    func value(_ metric: BodyMetric) -> Double? {
        switch metric {
        case .weight: return weightKg
        case .bodyFat: return bodyFatPercent
        case .leanMass: return leanMassKg
        case .muscleMass: return skeletalMuscleKg
        case .fatMass: return fatMassKg
        case .visceralFat: return visceralFatLevel
        case .inBodyScore: return inBodyScore
        case let .measure(measure): return measures[measure]
        }
    }
}

/// Valor actual de una métrica y cuánto cambió desde el primer registro que la tiene.
struct BodyTrend: Equatable {
    var current: Double
    var changeSinceFirst: Double
    var hasHistory: Bool
    var changeSincePrevious: Double = 0
    var date: Date?

    static func make(_ metric: BodyMetric, entries: [BodySnapshot]) -> BodyTrend? {
        let points = entries.sorted { $0.date < $1.date }.compactMap { e in e.value(metric).map { (e.date, $0) } }
        guard let first = points.first, let last = points.last else { return nil }
        let previous = points.count > 1 ? points[points.count - 2].1 : last.1
        return BodyTrend(current: last.1, changeSinceFirst: last.1 - first.1, hasHistory: points.count > 1,
                         changeSincePrevious: last.1 - previous, date: last.0)
    }
}
