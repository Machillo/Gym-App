import Foundation

/// Quién sos según lo que realmente venís haciendo: el rango da la experiencia y las últimas 8 semanas, el estilo.
struct FighterProfile: Equatable {
    static let windowDays = 56

    struct Discipline: Equatable, Identifiable {
        var discipline: ClassDiscipline
        var classes: Int
        var minutes: Double
        var id: String { discipline.rawValue }
    }

    var style: String?
    var tier: String
    var fightMinutes = 0.0
    var strengthMinutes = 0.0
    var conditioningMinutes = 0.0
    var disciplines: [Discipline] = []
    var strongest: StatKind?
    var weakest: StatKind?

    var totalMinutes: Double { fightMinutes + strengthMinutes + conditioningMinutes }
    /// Nil hasta que haya entrenamiento registrado.
    var title: String? { style.map { "\($0) · \(tier)" } }

    static func tier(for rank: Rank) -> String {
        switch rank {
        case .e: return "Novato"
        case .d: return "Aprendiz"
        case .c: return "Competidor"
        case .b: return "Veterano"
        case .a: return "Élite"
        case .s: return "Maestro"
        case .ss: return "Leyenda"
        }
    }

    static func make(sessions: [SessionDigest], stats: PlayerStats, rank: Rank, now: Date) -> FighterProfile {
        var profile = FighterProfile(tier: tier(for: rank))
        let since = SistemaCalendar.addDays(-windowDays, to: SistemaCalendar.startOfDay(now))
        var byDiscipline: [ClassDiscipline: Discipline] = [:]
        for session in sessions where !session.isPunishment && session.date >= since {
            for result in session.results {
                let minutes = SessionDigest.minutes(of: result)
                switch result.prescribed.kind {
                case .classSession:
                    profile.fightMinutes += minutes
                    let discipline = result.prescribed.klass.discipline
                    var item = byDiscipline[discipline] ?? Discipline(discipline: discipline, classes: 0, minutes: 0)
                    item.classes += 1
                    item.minutes += minutes
                    byDiscipline[discipline] = item
                case .strength:
                    profile.strengthMinutes += minutes
                case .circuit, .cardio:
                    profile.conditioningMinutes += minutes
                }
            }
        }
        profile.disciplines = byDiscipline.values.sorted { $0.minutes > $1.minutes }
        profile.style = style(profile)
        let trained = StatKind.allCases.filter { stats[$0] > 0 }
        if !trained.isEmpty {
            profile.strongest = StatKind.allCases.max { stats[$0] < stats[$1] }
            profile.weakest = StatKind.allCases.min { stats[$0] < stats[$1] }
        }
        return profile
    }

    private static func style(_ profile: FighterProfile) -> String? {
        let total = profile.totalMinutes
        guard total > 0 else { return nil }
        if profile.fightMinutes / total >= 0.5 {
            if profile.disciplines.count > 1 { return "Peleador mixto" }
            switch profile.disciplines.first?.discipline {
            case .boxing: return "Boxeador"
            case .muayThai: return "Peleador de Muay Thai"
            case .mma: return "Peleador de MMA"
            case nil: return "Peleador"
            }
        }
        if profile.strengthMinutes / total >= 0.5 { return "Atleta de fuerza" }
        if profile.conditioningMinutes / total >= 0.5 {
            return profile.fightMinutes > 0 ? "Peleador en acondicionamiento" : "Atleta funcional"
        }
        return "Atleta híbrido"
    }
}
