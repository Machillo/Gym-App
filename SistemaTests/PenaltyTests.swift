import XCTest
@testable import Sistema

final class PenaltyTests: XCTestCase {
    private var progress = T.progress(xp: 2_000)
    private var ledger = T.ledger()

    @discardableResult
    private func evaluate(at now: Date, itineraries: [ItinerarySnapshot] = [T.itinerary()],
                          sessions: [SessionSnapshot] = [], injuries: [InjuryPeriod] = []) -> EvaluationOutcome {
        PenaltyEngine.evaluate(progress: &progress, ledger: &ledger, itineraries: itineraries,
                               sessions: sessions, injuries: injuries, now: now)
    }

    func testMissedPlannedDayIsFullFault() {
        let outcome = evaluate(at: T.day(1, hour: 8))
        XCTAssertEqual(outcome.penalties.map(\.reason), [.missedDay])
        XCTAssertEqual(progress.totalXP, 1_900)
        XCTAssertEqual(outcome.newMissions.count, 1)
        XCTAssertEqual(PenaltyEngine.status(ledger: ledger, injuries: [], now: T.day(1, hour: 8)), .penaltyZone)
        XCTAssertEqual(ledger.faultsByWeek[SistemaCalendar.weekKey(T.day(0))], 1)
    }

    func testLowComplianceIsHalfFault() {
        let outcome = evaluate(at: T.day(1, hour: 8), sessions: [T.session(day: 0, compliance: 0.4, xp: 41)])
        XCTAssertEqual(outcome.penalties.count, 1)
        XCTAssertEqual(outcome.penalties[0].reason, .lowCompliance)
        XCTAssertEqual(outcome.penalties[0].faultWeight, 0.5)
        XCTAssertEqual(outcome.penalties[0].xpLost, 21)
        XCTAssertTrue(outcome.newMissions.isEmpty)
    }

    func testCompletedDayGrowsStreakAndFaultBreaksIt() {
        evaluate(at: T.day(2), sessions: [T.session(day: 0), T.session(day: 1)])
        XCTAssertEqual(ledger.currentStreak, 2)
        evaluate(at: T.day(3), sessions: [T.session(day: 0), T.session(day: 1)])
        XCTAssertEqual(ledger.currentStreak, 0)
        XCTAssertEqual(ledger.maxStreak, 2)
    }

    func testThreeFaultsInAWeekDropOneLevel() {
        // Lunes, martes y miércoles sin sesión; las misiones de castigo se cumplen para aislar las 3 faltas.
        let punishments = [T.session(day: 1, hour: 18, planned: false, punishment: true, minutes: 25),
                           T.session(day: 2, hour: 18, planned: false, punishment: true, minutes: 25)]
        var expected = progress
        expected.applyLoss(300, now: T.day(3))
        expected.dropOneLevel(now: T.day(3))

        let outcome = evaluate(at: T.day(3, hour: 8), sessions: punishments)
        XCTAssertEqual(outcome.penalties.filter { $0.reason == .missedDay }.count, 3)
        XCTAssertFalse(outcome.penalties.contains { $0.reason == .punishmentFailed })
        XCTAssertEqual(ledger.levelDropsByWeek[SistemaCalendar.weekKey(T.day(0))], 1)
        XCTAssertEqual(progress.level, expected.level)
        XCTAssertEqual(progress.totalXP, expected.totalXP)
        XCTAssertGreaterThan(outcome.penalties.last?.levelsLost ?? 0, 0)
    }

    func testHalfFaultsAddUp() {
        let sessions = [0, 1, 2, 3, 4, 7].map { T.session(day: $0, compliance: 0.3, xp: 30) }
        evaluate(at: T.day(5), sessions: sessions)
        XCTAssertEqual(ledger.faultsByWeek[SistemaCalendar.weekKey(T.day(0))], 2.5)
        XCTAssertEqual(ledger.levelDropsByWeek[SistemaCalendar.weekKey(T.day(0))] ?? 0, 0)
    }

    func testFallingBelowRankFloorLosesRank() {
        progress = T.progress(xp: LevelCurve.threshold(for: 10) + 50)
        XCTAssertEqual(progress.unlockedRank, .d)
        let outcome = evaluate(at: T.day(1, hour: 8))
        XCTAssertEqual(progress.level, 9)
        XCTAssertEqual(progress.position.rank, .e)
        XCTAssertEqual(progress.unlockedRank, .e)
        XCTAssertTrue(outcome.penalties[0].rankLost)
        XCTAssertTrue(outcome.progressEvents.contains(.rankDown(from: .d, to: .e)))
        // La prueba se repite, pero sin volver a cumplir el tiempo mínimo.
        XCTAssertEqual(progress.trialAvailability(now: T.day(1, hour: 9)), .available(.d))
    }

    func testFloorIsRankELevel1() {
        progress = T.progress(xp: 30)
        evaluate(at: T.day(12))
        XCTAssertEqual(progress.totalXP, 0)
        XCTAssertEqual(progress.level, 1)
        XCTAssertEqual(progress.position.rank, .e)
    }

    func testIdempotentWhenReopenedManyTimes() {
        evaluate(at: T.day(1, hour: 8))
        let progressAfter = progress
        let ledgerAfter = ledger
        for hour in [9.0, 12, 18, 23.5] {
            let outcome = evaluate(at: T.day(1, hour: hour))
            XCTAssertTrue(outcome.penalties.isEmpty)
        }
        XCTAssertEqual(progress, progressAfter)
        XCTAssertEqual(ledger, ledgerAfter)
    }

    func testWalksEveryDayWhenAppWasNotOpened() {
        let outcome = evaluate(at: T.day(5, hour: 10))
        XCTAssertEqual(outcome.penalties.filter { $0.reason == .missedDay }.count, 5)
        XCTAssertEqual(ledger.lastEvaluatedDay, T.day(4))
        XCTAssertGreaterThanOrEqual(ledger.levelDropsByWeek[SistemaCalendar.weekKey(T.day(0))] ?? 0, 2)
    }

    func testTodayIsNeverPenalizedBeforeItEnds() {
        let outcome = evaluate(at: T.day(0, hour: 23.9))
        XCTAssertTrue(outcome.penalties.isEmpty)
    }

    func testInjuryModeFreezesPenaltiesAndStreak() {
        evaluate(at: T.day(1), sessions: [T.session(day: 0)])
        XCTAssertEqual(ledger.currentStreak, 1)
        let injury = InjuryPeriod.make(start: T.day(1), estimatedEnd: T.day(3), reason: "Esguince")
        let outcome = evaluate(at: T.day(4, hour: 8), sessions: [T.session(day: 0)], injuries: [injury])
        XCTAssertTrue(outcome.penalties.isEmpty)
        XCTAssertEqual(ledger.currentStreak, 1)
        XCTAssertEqual(PenaltyEngine.status(ledger: ledger, injuries: [injury], now: T.day(2)), .injured)
    }

    func testInjuryIsCappedAt14Days() {
        let injury = InjuryPeriod.make(start: T.day(0), estimatedEnd: T.day(40), reason: "Gripe")
        XCTAssertEqual(SistemaCalendar.daysBetween(injury.start, injury.end), 13)
        XCTAssertTrue(injury.contains(T.day(13)))
        XCTAssertFalse(injury.contains(T.day(14)))
    }

    func testRestDaysNeverPenalize() {
        let outcome = evaluate(at: T.day(7), itineraries: [T.itinerary(days: [.monday])], sessions: [T.session(day: 0)])
        XCTAssertTrue(outcome.penalties.isEmpty)
    }

    func testUnplannedSessionDoesNotEraseFault() {
        let outcome = evaluate(at: T.day(1), sessions: [T.session(day: 0, planned: false)])
        XCTAssertEqual(outcome.penalties.map(\.reason), [.missedDay])
    }

    func testExpiredItineraryAfter48HoursCountsTypicalDays() {
        // Itinerario que terminó el domingo anterior: lunes y martes son de gracia.
        let old = T.itinerary(start: -28, end: -1)
        let outcome = evaluate(at: T.day(5), itineraries: [old])
        XCTAssertEqual(outcome.penalties.filter { $0.reason == .noItinerary }.map(\.day), [T.day(2), T.day(3), T.day(4)])
    }

    func testPunishmentMissionCompletedClearsZone() {
        evaluate(at: T.day(1, hour: 8))
        let punishment = T.session(day: 1, hour: 19, planned: false, punishment: true, minutes: 25)
        let outcome = evaluate(at: T.day(3), sessions: [punishment, T.session(day: 1), T.session(day: 2)])
        XCTAssertEqual(outcome.completedMissions.count, 1)
        XCTAssertFalse(outcome.penalties.contains { $0.reason == .punishmentFailed })
        XCTAssertEqual(PenaltyEngine.status(ledger: ledger, injuries: [], now: T.day(3)), .normal)
    }

    func testShortPunishmentDoesNotCount() {
        evaluate(at: T.day(1, hour: 8))
        let tooShort = T.session(day: 1, hour: 19, planned: false, punishment: true, minutes: 10)
        let outcome = evaluate(at: T.day(3, hour: 1), sessions: [tooShort, T.session(day: 1), T.session(day: 2)])
        XCTAssertEqual(outcome.penalties.map(\.reason), [.punishmentFailed])
    }

    func testPunishmentMissionNotDoneIn48HoursIsAnotherFault() {
        evaluate(at: T.day(1, hour: 8))
        let outcome = evaluate(at: T.day(3, hour: 1), sessions: [T.session(day: 1), T.session(day: 2)])
        XCTAssertEqual(outcome.penalties.map(\.reason), [.punishmentFailed])
        XCTAssertEqual(ledger.faultsByWeek[SistemaCalendar.weekKey(T.day(0))], 2)
        XCTAssertNil(ledger.openMission)
    }
}
