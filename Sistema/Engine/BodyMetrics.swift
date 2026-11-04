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
}

/// Lo que se puede graficar del cuerpo.
enum BodyMetric: Hashable, Identifiable {
    case weight, bodyFat, leanMass, measure(BodyMeasure)

    var id: String {
        switch self {
        case .weight: return "weight"
        case .bodyFat: return "bodyFat"
        case .leanMass: return "leanMass"
        case let .measure(measure): return measure.rawValue
        }
    }

    var name: String {
        switch self {
        case .weight: return "Peso"
        case .bodyFat: return "Grasa"
        case .leanMass: return "Masa magra"
        case let .measure(measure): return measure.name
        }
    }

    static var all: [BodyMetric] { [.weight, .bodyFat, .leanMass] + BodyMeasure.allCases.map(BodyMetric.measure) }

    /// El valor en su unidad de pantalla.
    func text(_ value: Double, weightUnit: WeightUnit) -> String {
        switch self {
        case .weight, .leanMass: return Format.weight(value, unit: weightUnit)
        case .bodyFat: return String(format: "%.1f %%", value)
        case .measure: return String(format: "%.1f cm", value)
        }
    }
}

struct BodySnapshot: Equatable {
    var date: Date
    var weightKg: Double?
    var bodyFatPercent: Double?
    var measures: [BodyMeasure: Double] = [:]

    var leanMassKg: Double? {
        guard let weightKg, let bodyFatPercent else { return nil }
        return weightKg * (1 - bodyFatPercent / 100)
    }

    func value(_ metric: BodyMetric) -> Double? {
        switch metric {
        case .weight: return weightKg
        case .bodyFat: return bodyFatPercent
        case .leanMass: return leanMassKg
        case let .measure(measure): return measures[measure]
        }
    }
}

/// Valor actual de una métrica y cuánto cambió desde el primer registro que la tiene.
struct BodyTrend: Equatable {
    var current: Double
    var changeSinceFirst: Double
    var hasHistory: Bool

    static func make(_ metric: BodyMetric, entries: [BodySnapshot]) -> BodyTrend? {
        let values = entries.sorted { $0.date < $1.date }.compactMap { $0.value(metric) }
        guard let first = values.first, let last = values.last else { return nil }
        return BodyTrend(current: last, changeSinceFirst: last - first, hasHistory: values.count > 1)
    }
}
