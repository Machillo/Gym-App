import Foundation

/// Constantes de progresión. Ajustalas acá; scripts/calibrate.py y CalibrationTests
/// verifican que los tiempos sigan cayendo en la tabla del README.
enum Progression {
    // Curva: XP para pasar del nivel L al L+1 = round(curveBase + curveCoefficient × L^curveExponent)
    static let curveBase: Double = 50
    static let curveCoefficient: Double = 7.3
    static let curveExponent: Double = 1.5
    static let maxLevel = 100

    // XP por sesión = base × factor de duración × factor de intensidad × cumplimiento
    static let baseXPPerKind: [BlockKind: Double] = [
        .strength: 100, .circuit: 100, .cardio: 100, .classSession: 100,
    ]
    static let referenceMinutes: Double = 60
    static let minDurationFactor: Double = 0.25
    static let maxDurationFactor: Double = 1.5
    static let referenceRPE: Double = 7
    static let intensityPerRPEPoint: Double = 0.05
    static let minIntensityFactor: Double = 0.85
    static let maxIntensityFactor: Double = 1.15
    static let earlyBonus: Double = 0.10
    static let earlyBonusBeforeHour = 6

    // Combate. El sparring pesa más que una clase; la pelea da un premio aparte que no cuenta para los topes.
    static let sparringXPMultiplier: Double = 1.25
    static let fightXP = 300
    static let fightWinXP = 300
    static let fightFinishXP = 100

    // Topes anti-sobreentrenamiento
    static let dailyXPCap = 200
    static let weeklyXPCap = 700

    // Penalizaciones
    static let fullFaultXP = 100
    static let halfFaultFraction: Double = 0.5
    static let halfFaultComplianceThreshold: Double = 0.5
    static let faultsPerLevelDrop: Double = 3
    static let punishmentWindowHours: Double = 48
    static let punishmentMinMinutes: Double = 20
    static let itineraryGraceDays = 2
    static let maxInjuryDays = 14
}

/// Curva de niveles con XP acumulado precalculado.
enum LevelCurve {
    /// XP necesario para pasar de `level` a `level + 1`.
    static func xpToNext(from level: Int) -> Int {
        let l = Double(max(1, level))
        return Int((Progression.curveBase + Progression.curveCoefficient * pow(l, Progression.curveExponent)).rounded())
    }

    /// cumulative[L] = XP total para estar en el nivel L (cumulative[1] = 0).
    static let cumulative: [Int] = {
        var values = [0, 0]
        for level in 1..<Progression.maxLevel {
            values.append(values[level] + xpToNext(from: level))
        }
        return values
    }()

    static func threshold(for level: Int) -> Int {
        cumulative[min(max(level, 1), Progression.maxLevel)]
    }

    static func level(forTotalXP xp: Int) -> Int {
        var low = 1
        var high = Progression.maxLevel
        while low < high {
            let mid = (low + high + 1) / 2
            if cumulative[mid] <= xp { low = mid } else { high = mid - 1 }
        }
        return low
    }

    static var maxTotalXP: Int { cumulative[Progression.maxLevel] }
}

enum Rank: Int, Codable, CaseIterable, Comparable, Identifiable {
    case e = 0, d, c, b, a, s, ss

    var id: Int { rawValue }

    var letter: String {
        switch self {
        case .e: return "E"
        case .d: return "D"
        case .c: return "C"
        case .b: return "B"
        case .a: return "A"
        case .s: return "S"
        case .ss: return "SS"
        }
    }

    var levels: ClosedRange<Int> {
        switch self {
        case .e: return 1...9
        case .d: return 10...24
        case .c: return 25...44
        case .b: return 45...64
        case .a: return 65...84
        case .s: return 85...99
        case .ss: return 100...100
        }
    }

    /// Meses mínimos en el rango anterior antes de habilitar la prueba para entrar a este rango.
    var minMonthsInPreviousRank: Int {
        switch self {
        case .e: return 0
        case .d: return 1
        case .c: return 3
        case .b: return 6
        case .a: return 12
        case .s: return 24
        case .ss: return 36
        }
    }

    var next: Rank? { Rank(rawValue: rawValue + 1) }
    var previous: Rank? { Rank(rawValue: rawValue - 1) }

    static func forLevel(_ level: Int) -> Rank {
        allCases.first { $0.levels.contains(level) } ?? (level < 1 ? .e : .ss)
    }

    static func < (lhs: Rank, rhs: Rank) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum Division: Int, Codable, Comparable {
    case iii = 3, ii = 2, i = 1

    var roman: String {
        switch self {
        case .iii: return "III"
        case .ii: return "II"
        case .i: return "I"
        }
    }

    // III es la más baja; I la más alta.
    static func < (lhs: Division, rhs: Division) -> Bool { lhs.rawValue > rhs.rawValue }
}

/// Posición del jugador: rango, división y nivel.
struct RankPosition: Equatable, Codable {
    let level: Int
    let rank: Rank
    let division: Division?

    init(level: Int) {
        let clamped = min(max(level, 1), Progression.maxLevel)
        self.level = clamped
        self.rank = Rank.forLevel(clamped)
        let range = rank.levels
        let count = range.count
        if count < 3 {
            division = nil
        } else {
            // Reparte los niveles en tres tramos; el sobrante va a las divisiones altas
            // (C: III 25–30, II 31–37, I 38–44).
            let offset = clamped - range.lowerBound
            let base = count / 3
            let extra = count % 3
            let firstSize = base
            let secondSize = base + (extra > 1 ? 1 : 0)
            if offset < firstSize {
                division = .iii
            } else if offset < firstSize + secondSize {
                division = .ii
            } else {
                division = .i
            }
        }
    }

    var title: String {
        if let division {
            return "Rango \(rank.letter) · División \(division.roman) · Nivel \(level)"
        }
        return "Rango \(rank.letter) · Nivel \(level)"
    }
}
