import Foundation
@testable import Sistema

/// Fechas y snapshots de apoyo. 2026-11-02 es lunes.
enum T {
    static let monday = SistemaCalendar.date(year: 2026, month: 11, day: 2)

    static func day(_ offset: Int, hour: Double = 0) -> Date {
        SistemaCalendar.addDays(offset, to: monday).addingTimeInterval(hour * 3600)
    }

    static let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]

    static func itinerary(start: Int = 0, end: Int = 55, days: Set<Weekday> = weekdays) -> ItinerarySnapshot {
        ItinerarySnapshot(id: UUID(), start: day(start), end: day(end), plannedWeekdays: days)
    }

    static func session(day offset: Int, hour: Double = 7, compliance: Double = 1, xp: Int = 100,
                        planned: Bool = true, punishment: Bool = false, minutes: Double = 60) -> SessionSnapshot {
        SessionSnapshot(id: UUID(), date: day(offset, hour: hour), plannedDay: planned ? day(offset) : nil,
                        compliance: compliance, xpAwarded: xp, isPunishment: punishment, minutes: minutes)
    }

    /// Progreso con el XP indicado y el rango habilitado acorde al nivel.
    static func progress(xp: Int, startedAt: Date = day(-400)) -> PlayerProgress {
        var p = PlayerProgress(startedAt: startedAt)
        let rank = Rank.forLevel(LevelCurve.level(forTotalXP: xp))
        p.unlockedRank = rank
        p.highestRankEverUnlocked = rank
        p.totalXP = xp
        return p
    }

    /// Ledger evaluado hasta el domingo anterior al lunes base.
    static func ledger() -> PenaltyLedger {
        PenaltyLedger(lastEvaluatedDay: day(-1))
    }
}
