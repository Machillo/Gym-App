import SwiftData
import XCTest
@testable import Sistema

@MainActor
final class RecoveryTests: XCTestCase {
    private var container: ModelContainer!
    private var clock: FixedDateProvider!
    private var game: GameService!
    private var health: FakeHealth!
    private var notifications: SilentNotificationService!

    override func setUp() async throws {
        container = try SistemaSchema.makeContainer(inMemory: true)
        clock = FixedDateProvider(T.day(0, hour: 6))
        health = FakeHealth()
        notifications = SilentNotificationService()
        game = GameService(context: container.mainContext, clock: clock, notifications: notifications, health: health,
                           defaults: UserDefaults(suiteName: "recovery-\(UUID().uuidString)")!)
        game.createPlayer(name: "Tester")
        game.healthConnected = true
    }

    private let good = RecoveryCheckIn(sleepQuality: 5, soreness: 1, stress: 1, energy: 5)
    private let bad = RecoveryCheckIn(sleepQuality: 1, soreness: 5, stress: 5, energy: 1)

    private func press() -> [BlockResult] {
        var result = BlockResult(prescribed: .strength(StrengthPrescription(exerciseName: "Press", sets: 3, reps: 5, weight: 0)))
        result.sets = (0..<3).map { _ in PerformedSet(reps: 5, weight: 40, unit: .kg) }
        return [result]
    }

    private func history(days: Int, hrv: Double = 60, heart: Double = 55, sleep: Double = 7.5) -> [RecoveryDay] {
        (1...days).map { RecoveryDay(day: T.day(-$0), sleepHours: sleep + ($0 % 2 == 0 ? 0.5 : -0.5), restingHR: heart + ($0 % 2 == 0 ? 2 : -2),
                                     hrv: hrv + ($0 % 2 == 0 ? 6 : -6)) }
    }

    // MARK: - Sueño

    func testOverlappingSourcesAreCountedOnceAndClippedToTheNight() throws {
        let night = T.day(0, hour: -3) // 9 p. m.
        let intervals = [
            DateInterval(start: night, duration: 4 * 3600),
            DateInterval(start: night.addingTimeInterval(3600), duration: 4 * 3600), // el iPhone repite parte
            DateInterval(start: T.day(0, hour: 3), duration: 3600),
            DateInterval(start: T.day(0, hour: 15), duration: 3600), // siesta: fuera de la noche
        ]
        XCTAssertEqual(try XCTUnwrap(RecoveryEngine.sleepHours(intervals: intervals, day: T.day(0))), 6, accuracy: 0.001)
        XCTAssertNil(RecoveryEngine.sleepHours(intervals: [], day: T.day(0)))
    }

    func testDebtAndStreak() {
        let days = [RecoveryDay(day: T.day(-3), sleepHours: 5), RecoveryDay(day: T.day(-2), sleepHours: 7.5),
                    RecoveryDay(day: T.day(-1), sleepHours: 7), RecoveryDay(day: T.day(0), sleepHours: 8)]
        XCTAssertEqual(RecoveryEngine.sleepDebt(days: days, today: T.day(0)), 3, accuracy: 0.001)
        XCTAssertEqual(RecoveryEngine.sleepStreak(days: days, today: T.day(0)), 3)
        XCTAssertEqual(RecoveryEngine.sleepStreak(days: Array(days.dropLast()), today: T.day(0)), 2, "hoy sin dato cuenta desde ayer")
    }

    func testBedtimeGoesEarlierWithDebt() {
        let wake = T.day(1, hour: 4.5)
        XCTAssertEqual(RecoveryEngine.bedtime(wake: wake, debt: 0, target: 7.5), T.day(0, hour: 20.75))
        XCTAssertEqual(RecoveryEngine.bedtime(wake: wake, debt: 3, target: 7.5), T.day(0, hour: 20.25))
    }

    // MARK: - Puntaje

    func testScoreComparesAgainstOwnBaseline() throws {
        let past = history(days: 14)
        let great = RecoveryDay(day: T.day(0), sleepHours: 8, restingHR: 50, hrv: 75, checkIn: good)
        let awful = RecoveryDay(day: T.day(0), sleepHours: 4.5, restingHR: 66, hrv: 40, checkIn: bad)
        let high = try XCTUnwrap(RecoveryEngine.report(today: great, history: past, dailyLoad: [:], fight: nil))
        let low = try XCTUnwrap(RecoveryEngine.report(today: awful, history: past, dailyLoad: [:], fight: nil))
        XCTAssertEqual(high.zone, .ready)
        XCTAssertEqual(low.zone, .recover)
        XCTAssertEqual(high.calibrationDaysLeft, 0)
        // La misma HRV es buena para quien suele tener menos.
        let athlete = try XCTUnwrap(RecoveryEngine.report(today: RecoveryDay(day: T.day(0), hrv: 60), history: history(days: 14, hrv: 90), dailyLoad: [:], fight: nil))
        let other = try XCTUnwrap(RecoveryEngine.report(today: RecoveryDay(day: T.day(0), hrv: 60), history: history(days: 14, hrv: 40), dailyLoad: [:], fight: nil))
        XCTAssertLessThan(athlete.score, other.score)
    }

    func testWithoutWatchTheCheckInIsEnoughAndHRVWaitsForBaseline() throws {
        XCTAssertNil(RecoveryEngine.report(today: RecoveryDay(day: T.day(0)), history: [], dailyLoad: [:], fight: nil))
        let report = try XCTUnwrap(RecoveryEngine.report(today: RecoveryDay(day: T.day(0), hrv: 60, checkIn: good), history: history(days: 3), dailyLoad: [:], fight: nil))
        XCTAssertEqual(report.score, 100)
        XCTAssertEqual(report.components.map(\.name), ["Cómo amaneciste"])
        XCTAssertEqual(report.calibrationDaysLeft, 4)
    }

    func testTrainingSpikeLowersScore() throws {
        var steady: [Date: Double] = [:]
        for offset in 1...28 where offset % 2 == 0 { steady[T.day(-offset)] = 400 }
        var spike = steady
        for offset in 1...3 { spike[T.day(-offset)] = 900 }
        let today = RecoveryDay(day: T.day(0), checkIn: RecoveryCheckIn(sleepQuality: 4, soreness: 2, stress: 2, energy: 4))
        let calm = try XCTUnwrap(RecoveryEngine.report(today: today, history: [], dailyLoad: steady, fight: nil))
        let loaded = try XCTUnwrap(RecoveryEngine.report(today: today, history: [], dailyLoad: spike, fight: nil))
        XCTAssertLessThan(loaded.score, calm.score)
    }

    func testFightModeDemandsMore() throws {
        XCTAssertFalse(FightMode(daysLeft: 22).isActive)
        XCTAssertTrue(FightMode(daysLeft: 21).isActive)
        XCTAssertFalse(FightMode(daysLeft: -1).isActive)
        let today = RecoveryDay(day: T.day(0), sleepHours: 6.5)
        XCTAssertEqual(RecoveryEngine.report(today: today, history: [], dailyLoad: [:], fight: nil)?.zone, .ready)
        XCTAssertEqual(RecoveryEngine.report(today: today, history: [], dailyLoad: [:], fight: FightMode(daysLeft: 10))?.zone, .moderate)
    }

    // MARK: - XP

    func testSleepMissionPaysOncePerNight() async {
        health.recoveryToReturn = [HealthRecoveryDay(day: T.day(0), sleepHours: 7.5, restingHR: 55, hrv: 60)]
        await game.syncHealth()
        await game.syncHealth()
        XCTAssertEqual(game.player()?.totalXP, 20)
        XCTAssertEqual(game.recoveryRecord(for: T.day(0))?.missionXP, 20)
    }

    func testShortNightPaysNothingAndDebtCostsNoXP() throws {
        game.importRecoveryDays([HealthRecoveryDay(day: T.day(0), sleepHours: 5)])
        XCTAssertEqual(game.player()?.totalXP, 0)
        XCTAssertEqual(game.recoveryXPMultiplier(T.day(0)), 1)
    }

    func testRestedBonusAppliesAndRespectsCaps() throws {
        let draft = SessionDraft(title: "S", date: T.day(0, hour: 10), results: press(), rpe: 7, durationMinutes: 60)
        let base = try XCTUnwrap(game.logSession(draft)).xp
        XCTAssertEqual(base, 100)

        clock.now = T.day(1, hour: 6)
        game.importRecoveryDays([HealthRecoveryDay(day: T.day(1), sleepHours: 8)])
        var next = draft
        next.date = T.day(1, hour: 10)
        XCTAssertEqual(try XCTUnwrap(game.logSession(next)).xp, 105)

        // Con el día casi topado, la misión no se pasa del tope.
        clock.now = T.day(2, hour: 6)
        for hour in [10.0, 14.0] {
            var more = draft
            more.date = T.day(2, hour: hour)
            more.durationMinutes = 90
            try XCTUnwrap(game.logSession(more))
        }
        XCTAssertEqual(game.xpEarned(day: T.day(2)), Progression.dailyXPCap)
        game.importRecoveryDays([HealthRecoveryDay(day: T.day(2), sleepHours: 8)])
        XCTAssertEqual(game.recoveryRecord(for: T.day(2))?.missionXP, 0)
        XCTAssertEqual(game.xpEarned(day: T.day(2)), Progression.dailyXPCap)
    }

    func testManualHoursDoNotOverrideHealth() {
        game.importRecoveryDays([HealthRecoveryDay(day: T.day(0), sleepHours: 6.2)])
        game.saveCheckIn(good, manualSleepHours: 9)
        XCTAssertEqual(game.recoveryRecord(for: T.day(0))?.sleepHours, 6.2)
        XCTAssertEqual(game.hunterState().today?.checkIn, good)
        clock.now = T.day(1, hour: 6)
        game.saveCheckIn(good, manualSleepHours: 7)
        XCTAssertEqual(game.recoveryRecord(for: T.day(1))?.sleepHours, 7)
        XCTAssertEqual(game.recoveryRecord(for: T.day(1))?.missionXP, 20)
    }

    func testSleepStreakAwardIsEarnedOnce() throws {
        clock.now = T.day(7, hour: 6)
        game.importRecoveryDays((1...7).map { HealthRecoveryDay(day: T.day($0), sleepHours: 7.5) })
        game.importRecoveryDays([HealthRecoveryDay(day: T.day(7), sleepHours: 7.6)])
        XCTAssertEqual(game.awards().filter { $0.key == "sleep-7" }.count, 1)
    }

    // MARK: - Aviso, permisos, respaldo y patrones

    func testBedtimeNoticesNeedAWakeTime() throws {
        XCTAssertTrue(game.bedtimeNotices().isEmpty)
        game.setWakeTime(hour: 4, minute: 30)
        let first = try XCTUnwrap(game.bedtimeNotices().first)
        XCTAssertEqual(first.date, T.day(0, hour: 20.25))
        XCTAssertTrue(first.body.contains("acostate"))
        XCTAssertTrue(notifications.scheduled.contains { $0.id == first.id })
        XCTAssertEqual(game.hunterState().bedtime, T.day(0, hour: 20.75))
    }

    func testExistingConnectionsMustAuthorizeSleep() async {
        XCTAssertTrue(game.needsRecoveryPermission)
        await game.connectHealth()
        XCTAssertFalse(game.needsRecoveryPermission)
    }

    func testBackupRoundTripKeepsRecovery() throws {
        game.setWakeTime(hour: 4, minute: 15)
        game.setFightDate(T.day(30))
        game.importRecoveryDays([HealthRecoveryDay(day: T.day(0), sleepHours: 7.5, restingHR: 54, hrv: 61)])
        game.saveCheckIn(good, manualSleepHours: nil)
        let before = try BackupService.makeDocument(from: container.mainContext, now: clock.now)
        let data = try BackupService.exportData(from: container.mainContext, now: clock.now)
        try BackupService.importData(data, into: container.mainContext)
        XCTAssertEqual(try BackupService.makeDocument(from: container.mainContext, now: clock.now), before)
        XCTAssertEqual(game.recoveryRecord(for: T.day(0))?.checkIn, good)
        XCTAssertEqual(game.player()?.fightDate, T.day(30))
    }

    func testPatternsNeedEnoughSessionsOnBothSides() {
        func sample(_ hours: Double, improvements: Int) -> SleepPatternSample {
            SleepPatternSample(sleepHours: hours, compliance: 1, improvements: improvements, isClass: false, rpe: 7)
        }
        let few = RecoveryEngine.patterns([sample(8, improvements: 1), sample(5, improvements: 0)])
        XCTAssertFalse(few.isMeaningful)
        let enough = RecoveryEngine.patterns((0..<3).map { _ in sample(8, improvements: 2) } + (0..<3).map { _ in sample(5, improvements: 0) })
        XCTAssertTrue(enough.isMeaningful)
        XCTAssertEqual(enough.rested.improvementsPerSession, 2)
        XCTAssertEqual(enough.short.improvementsPerSession, 0)
    }
}
