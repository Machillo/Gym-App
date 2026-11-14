import Foundation

/// XP por sesión y topes diario/semanal.
enum XPEngine {
    struct SessionInput {
        var dominantKind: BlockKind
        var minutes: Double
        var rpe: Int
        var compliance: Double
        var startedAt: Date
    }

    static func durationFactor(minutes: Double) -> Double {
        min(max(minutes / Progression.referenceMinutes, Progression.minDurationFactor), Progression.maxDurationFactor)
    }

    static func intensityFactor(rpe: Int) -> Double {
        let raw = 1 + (Double(min(max(rpe, 1), 10)) - Progression.referenceRPE) * Progression.intensityPerRPEPoint
        return min(max(raw, Progression.minIntensityFactor), Progression.maxIntensityFactor)
    }

    static func isEarly(_ date: Date) -> Bool {
        SistemaCalendar.hour(of: date) < Progression.earlyBonusBeforeHour
    }

    /// XP sin topes.
    static func rawXP(_ input: SessionInput) -> Double {
        guard input.minutes > 0, input.compliance > 0 else { return 0 }
        let base = Progression.baseXPPerKind[input.dominantKind] ?? 100
        var xp = base * durationFactor(minutes: input.minutes) * intensityFactor(rpe: input.rpe) * min(input.compliance, 1)
        if isEarly(input.startedAt) {
            xp *= 1 + Progression.earlyBonus
        }
        return xp
    }

    /// Aplica los topes: devuelve el XP que realmente se otorga.
    static func cappedXP(raw: Double, earnedToday: Int, earnedThisWeek: Int) -> Int {
        let wanted = Int(raw.rounded())
        let dayRoom = max(0, Progression.dailyXPCap - earnedToday)
        let weekRoom = max(0, Progression.weeklyXPCap - earnedThisWeek)
        return max(0, min(wanted, dayRoom, weekRoom))
    }

    /// Multiplicador por sparring: se aplica antes de los topes.
    static func combatMultiplier(_ blocks: [RoutineBlock]) -> Double {
        blocks.contains { $0.kind == .classSession && $0.klass.combatKind == .sparring } ? Progression.sparringXPMultiplier : 1
    }

    /// Premio por pelear, ganar y terminar antes de tiempo. Va aparte de los topes: una pelea no es sobreentrenamiento.
    static func fightBonus(_ results: [BlockResult]) -> Int {
        results.reduce(0) { total, result in
            guard result.prescribed.kind == .classSession, result.prescribed.klass.combatKind == .fight,
                  let fight = result.fight else { return total }
            var xp = Progression.fightXP
            if fight.outcome == .win {
                xp += Progression.fightWinXP
                if fight.method.isFinish { xp += Progression.fightFinishXP }
            }
            return total + xp
        }
    }

    /// Tipo de bloque con más minutos estimados.
    static func dominantKind(_ blocks: [RoutineBlock]) -> BlockKind {
        var totals: [BlockKind: Double] = [:]
        for block in blocks {
            totals[block.kind, default: 0] += ComplianceEngine.estimatedMinutes(block)
        }
        return totals.max { $0.value < $1.value }?.key ?? .strength
    }
}
