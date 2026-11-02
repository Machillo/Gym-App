import Foundation

enum ExerciseCategory: String, Codable, CaseIterable, Identifiable {
    case push, pull, legs, core, fullBody, cardio, combat, mobility

    var id: String { rawValue }

    var name: String {
        switch self {
        case .push: return "Empuje"
        case .pull: return "Tracción"
        case .legs: return "Piernas"
        case .core: return "Core"
        case .fullBody: return "Cuerpo completo"
        case .cardio: return "Cardio"
        case .combat: return "Combate"
        case .mobility: return "Movilidad"
        }
    }
}

enum StatKind: String, Codable, CaseIterable, Identifiable {
    case strength, endurance, technique, discipline, vitality

    var id: String { rawValue }

    var name: String {
        switch self {
        case .strength: return "Fuerza"
        case .endurance: return "Resistencia"
        case .technique: return "Técnica"
        case .discipline: return "Disciplina"
        case .vitality: return "Vitalidad"
        }
    }

    var short: String {
        switch self {
        case .strength: return "FUE"
        case .endurance: return "RES"
        case .technique: return "TÉC"
        case .discipline: return "DIS"
        case .vitality: return "VIT"
        }
    }
}

/// Entrada mínima del catálogo para buscar duplicados.
struct CatalogEntry: Equatable {
    var id: UUID
    var name: String
    var aliases: [String]
}

enum ExerciseCatalog {
    /// Normaliza para comparar: minúsculas, sin tildes, espacios colapsados.
    static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "es_CR"))
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Busca un ejercicio existente por nombre o alias.
    static func match(_ query: String, in entries: [CatalogEntry]) -> CatalogEntry? {
        let key = normalize(query)
        guard !key.isEmpty else { return nil }
        return entries.first { entry in
            normalize(entry.name) == key || entry.aliases.contains { normalize($0) == key }
        }
    }

    /// Sugerencias que contienen el texto en nombre o alias.
    static func suggestions(_ query: String, in entries: [CatalogEntry], limit: Int = 6) -> [CatalogEntry] {
        let key = normalize(query)
        guard !key.isEmpty else { return [] }
        return Array(entries.filter { entry in
            normalize(entry.name).contains(key) || entry.aliases.contains { normalize($0).contains(key) }
        }.prefix(limit))
    }

    /// Catálogo inicial (nombres genéricos de ejercicios).
    static let starter: [(name: String, aliases: [String], category: ExerciseCategory, stats: [StatKind])] = [
        ("Press banca", ["bench press", "press de banca"], .push, [.strength]),
        ("Sentadilla", ["squat", "back squat"], .legs, [.strength, .vitality]),
        ("Peso muerto", ["deadlift"], .pull, [.strength, .vitality]),
        ("Press militar", ["overhead press", "press de hombro", "ohp"], .push, [.strength]),
        ("Dominadas", ["pull up", "pull-ups", "chin up"], .pull, [.strength, .endurance]),
        ("Remo con barra", ["barbell row", "remo"], .pull, [.strength]),
        ("Fondos", ["dips"], .push, [.strength, .endurance]),
        ("Flexiones", ["push up", "lagartijas", "pushups"], .push, [.endurance, .strength]),
        ("Zancadas", ["lunges", "estocadas"], .legs, [.strength, .endurance]),
        ("Burpees", ["burpee"], .fullBody, [.endurance, .vitality]),
        ("Plancha", ["plank"], .core, [.endurance, .discipline]),
        ("Swing con kettlebell", ["kettlebell swing", "kb swing"], .fullBody, [.endurance, .strength]),
        ("Salto de cuerda", ["jump rope", "cuerda", "suiza"], .cardio, [.endurance, .technique]),
        ("Golpes al saco", ["bag work", "saco"], .combat, [.technique, .endurance]),
        ("Sombra", ["shadow boxing", "shadowboxing"], .combat, [.technique]),
    ]
}

/// Cálculos de marcas por ejercicio.
enum ExerciseMath {
    /// e1RM con la fórmula de Epley.
    static func epley(weight: Double, reps: Int) -> Double {
        guard weight > 0, reps > 0 else { return 0 }
        if reps == 1 { return weight }
        return weight * (1 + Double(reps) / 30)
    }

    /// Ritmo en minutos por km.
    static func pace(minutes: Double, km: Double) -> Double? {
        guard minutes > 0, km > 0 else { return nil }
        return minutes / km
    }
}
