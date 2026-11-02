import Foundation

/// Estado de progresión del jugador (lógica pura).
struct PlayerProgress: Codable, Equatable {
    var totalXP: Int = 0
    /// XP retenido mientras estás topado esperando la prueba de ascenso.
    var overflowXP: Int = 0
    /// Rango más alto cuya prueba está superada (E viene habilitado).
    var unlockedRank: Rank = .e
    /// Rango más alto que llegaste a habilitar alguna vez (para no repetir el tiempo mínimo).
    var highestRankEverUnlocked: Rank = .e
    /// Fecha en que entraste al rango visible actual.
    var rankEnteredAt: Date

    init(startedAt: Date) {
        rankEnteredAt = startedAt
    }

    var level: Int { LevelCurve.level(forTotalXP: totalXP) }
    var position: RankPosition { RankPosition(level: level) }
    var capLevel: Int { unlockedRank.levels.upperBound }
    var isCapped: Bool { level >= capLevel && unlockedRank.next != nil }

    /// XP dentro del nivel actual y XP necesario para el siguiente.
    var levelProgress: (current: Int, needed: Int) {
        let lvl = level
        guard lvl < Progression.maxLevel else { return (0, 0) }
        return (totalXP - LevelCurve.threshold(for: lvl), LevelCurve.xpToNext(from: lvl))
    }

    private var xpCeiling: Int {
        capLevel >= Progression.maxLevel ? LevelCurve.maxTotalXP : LevelCurve.threshold(for: capLevel + 1) - 1
    }

    private var overflowLimit: Int {
        capLevel >= Progression.maxLevel ? 0 : LevelCurve.xpToNext(from: capLevel)
    }

    @discardableResult
    mutating func applyGain(_ xp: Int, now: Date) -> [ProgressEvent] {
        guard xp > 0 else { return [] }
        let before = position
        let room = max(0, xpCeiling - totalXP)
        let added = min(xp, room)
        totalXP += added
        let extra = xp - added
        if extra > 0 {
            overflowXP = min(overflowLimit, overflowXP + extra)
        }
        return finish(from: before, now: now)
    }

    /// Resta XP: primero del desborde, luego del total. Piso: 0 XP (E · nivel 1).
    @discardableResult
    mutating func applyLoss(_ xp: Int, now: Date) -> [ProgressEvent] {
        guard xp > 0 else { return [] }
        let before = position
        let fromOverflow = min(overflowXP, xp)
        overflowXP -= fromOverflow
        totalXP = max(0, totalXP - (xp - fromOverflow))
        return finish(from: before, now: now)
    }

    /// Baja exactamente un nivel conservando (en lo posible) el avance dentro del nivel.
    @discardableResult
    mutating func dropOneLevel(now: Date) -> [ProgressEvent] {
        let before = position
        overflowXP = 0
        let lvl = level
        if lvl <= 1 {
            totalXP = 0
        } else {
            let lowered = totalXP - LevelCurve.xpToNext(from: lvl - 1)
            totalXP = max(LevelCurve.threshold(for: lvl - 1), min(lowered, LevelCurve.threshold(for: lvl) - 1))
        }
        return finish(from: before, now: now)
    }

    /// Reconoce entrenamiento anterior a la app: suma el XP y da por superadas las pruebas de los rangos
    /// alcanzados. El tiempo mínimo de la siguiente prueba cuenta desde hoy.
    @discardableResult
    mutating func applyPriorHistory(xp: Int, now: Date) -> [ProgressEvent] {
        guard xp > 0 else { return [] }
        let before = position
        totalXP = min(totalXP + xp, LevelCurve.maxTotalXP)
        unlockedRank = max(unlockedRank, position.rank)
        highestRankEverUnlocked = max(highestRankEverUnlocked, unlockedRank)
        return finish(from: before, now: now)
    }

    /// Supera la prueba de ascenso: habilita el siguiente rango y libera el desborde.
    @discardableResult
    mutating func passTrial(now: Date) -> [ProgressEvent] {
        guard let next = unlockedRank.next else { return [] }
        let before = position
        unlockedRank = next
        highestRankEverUnlocked = max(highestRankEverUnlocked, next)
        totalXP = min(totalXP + overflowXP, xpCeiling)
        overflowXP = 0
        return finish(from: before, now: now)
    }

    func trialAvailability(now: Date) -> TrialAvailability {
        guard let next = unlockedRank.next else { return .maxed }
        guard level >= capLevel else { return .needsLevel(capLevel) }
        if next > highestRankEverUnlocked {
            let availableFrom = SistemaCalendar.addMonths(next.minMonthsInPreviousRank, to: rankEnteredAt)
            if now < availableFrom { return .needsTime(availableFrom) }
        }
        return .available(next)
    }

    private mutating func finish(from before: RankPosition, now: Date) -> [ProgressEvent] {
        let after = position
        if after.rank != before.rank {
            rankEnteredAt = now
        }
        if after.rank < before.rank {
            // Perdiste el rango: la prueba se tiene que volver a pasar.
            unlockedRank = after.rank
            overflowXP = 0
        }
        return ProgressEvent.transitions(from: before, to: after)
    }
}

enum TrialAvailability: Equatable {
    case needsLevel(Int)
    case needsTime(Date)
    case available(Rank)
    case maxed
}

enum ProgressEvent: Equatable {
    case levelUp(from: Int, to: Int)
    case levelDown(from: Int, to: Int)
    case divisionUp(RankPosition)
    case divisionDown(RankPosition)
    case rankUp(Rank)
    case rankDown(from: Rank, to: Rank)

    static func transitions(from before: RankPosition, to after: RankPosition) -> [ProgressEvent] {
        var events: [ProgressEvent] = []
        if after.level > before.level { events.append(.levelUp(from: before.level, to: after.level)) }
        if after.level < before.level { events.append(.levelDown(from: before.level, to: after.level)) }
        if after.rank > before.rank {
            events.append(.rankUp(after.rank))
        } else if after.rank < before.rank {
            events.append(.rankDown(from: before.rank, to: after.rank))
        } else if let a = after.division, let b = before.division, a != b {
            events.append(a > b ? .divisionUp(after) : .divisionDown(after))
        }
        return events
    }

    var isPositive: Bool {
        switch self {
        case .levelUp, .divisionUp, .rankUp: return true
        default: return false
        }
    }
}
