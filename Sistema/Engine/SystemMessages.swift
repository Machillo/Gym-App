import Foundation

/// Textos de "El Sistema" (voseo, tono frío y directo).
enum SystemMessages {
    static func forEvent(_ event: ProgressEvent) -> String {
        switch event {
        case let .levelUp(_, to):
            return "Nivel \(to) alcanzado. El Sistema registra tu progreso."
        case let .levelDown(_, to):
            return "Bajaste al nivel \(to). La disciplina no se negocia."
        case let .divisionUp(position):
            return "Ascenso de división: \(position.title)."
        case let .divisionDown(position):
            return "Descenso de división: \(position.title)."
        case let .rankUp(rank):
            return "RANGO \(rank.letter) DESBLOQUEADO. Ya no sos el mismo que empezó."
        case let .rankDown(from, to):
            return "Perdiste el rango \(from.letter). Volvés a \(to.letter). La prueba deberá superarse otra vez."
        }
    }

    static func headline(_ event: ProgressEvent) -> String {
        switch event {
        case .levelUp: return "SUBISTE DE NIVEL"
        case .levelDown: return "BAJASTE DE NIVEL"
        case .divisionUp: return "NUEVA DIVISIÓN"
        case .divisionDown: return "DIVISIÓN PERDIDA"
        case .rankUp: return "NUEVO RANGO"
        case .rankDown: return "RANGO PERDIDO"
        }
    }

    static func penalty(_ record: PenaltyRecord) -> String {
        var text = "Penalización: \(record.reason.label.lowercased()). −\(record.xpLost) XP."
        if record.levelsLost > 0 { text += " Perdiste \(record.levelsLost) nivel(es)." }
        if record.rankLost { text += " Perdiste el rango." }
        return text
    }

    static func sessionLogged(xp: Int, compliance: Double, capped: Bool) -> String {
        var text = "Sesión registrada: \(Format.percent(compliance)) de cumplimiento, +\(xp) XP."
        if capped { text += " Tope de XP alcanzado: el descanso también es entrenamiento." }
        return text
    }

    static let missionAssigned = "Entraste en Zona de penalización. Misión de castigo asignada: tenés 48 horas."
    static let missionCompleted = "Misión de castigo cumplida. Saliste de la Zona de penalización."
    static let trialPassed = "Prueba de ascenso superada. El siguiente rango te espera."
    static let itineraryExpired = "Tu itinerario venció. El Sistema exige uno nuevo en menos de 48 horas."
    static let injuryOn = "Modo lesión/enfermo activado. Penalizaciones y racha congeladas. Recuperate."
    static let injuryOff = "Modo lesión/enfermo desactivado. El Sistema vuelve a evaluarte."
    static let welcome = "Jugador registrado. El Sistema te observa desde hoy."
}
