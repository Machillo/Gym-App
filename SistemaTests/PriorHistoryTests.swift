import SwiftData
import XCTest
@testable import Sistema

@MainActor
final class PriorHistoryTests: XCTestCase {
    private var container: ModelContainer!
    private var clock: FixedDateProvider!
    private var game: GameService!

    override func setUp() async throws {
        container = try SistemaSchema.makeContainer(inMemory: true)
        clock = FixedDateProvider(T.day(0, hour: 9))
        game = GameService(context: container.mainContext, clock: clock, notifications: SilentNotificationService())
        game.createPlayer(name: "Tester")
    }

    private var player: Player { game.player()! }

    func testCreditReachesRankCLevel34WithEarlierTrialsPassed() {
        game.applyPriorHistory(xp: 20_800)
        XCTAssertEqual(player.totalXP, 20_800)
        XCTAssertEqual(player.position.rank, .c)
        XCTAssertEqual(player.level, 34)
        XCTAssertEqual(player.progress.unlockedRank, .c)
        let states = Dictionary(uniqueKeysWithValues: game.trials().map { ($0.target, $0.state) })
        XCTAssertEqual(states[.d], .passed)
        XCTAssertEqual(states[.c], .passed)
        XCTAssertEqual(states[.b], .locked)
        XCTAssertNotNil(game.trials().first { $0.target == .c }?.passedAt)
    }

    func testCreditAppliesOnlyOnce() {
        game.applyPriorHistory(xp: 20_800)
        game.applyPriorHistory(xp: 20_800)
        XCTAssertEqual(player.totalXP, 20_800)
        XCTAssertEqual(player.priorHistoryXP, 20_800)
    }

    func testCreditIsNotASession() {
        game.applyPriorHistory(xp: 20_800)
        XCTAssertTrue(game.sessions().isEmpty)
        XCTAssertEqual(player.currentStreak, 0)
        XCTAssertEqual(player.stats, PlayerStats())
    }

    func testNextTrialTimeCountsFromCredit() {
        game.applyPriorHistory(xp: 20_800)
        var progress = player.progress
        XCTAssertEqual(progress.trialAvailability(now: clock.now), .needsLevel(44))
        progress.totalXP = LevelCurve.threshold(for: 44)
        guard case let .needsTime(date) = progress.trialAvailability(now: clock.now) else {
            return XCTFail("La prueba a B debe exigir 6 meses desde el crédito")
        }
        XCTAssertEqual(date, SistemaCalendar.addMonths(6, to: clock.now))
    }

    func testExistingXPIsKeptAndMissedDayDoesNotLoseRank() {
        player.totalXP = 100
        game.applyPriorHistory(xp: 20_800)
        XCTAssertEqual(player.totalXP, 20_900)
        var progress = player.progress
        progress.applyLoss(100, now: clock.now)
        XCTAssertEqual(progress.position.rank, .c)
        XCTAssertEqual(progress.unlockedRank, .c)
    }

    func testCreditSurvivesBackupAndCannotRepeatAfterImport() throws {
        game.applyPriorHistory(xp: 20_800)
        let data = try BackupService.exportData(from: container.mainContext, now: clock.now)
        try BackupService.importData(data, into: container.mainContext)
        XCTAssertEqual(player.priorHistoryXP, 20_800)
        game.applyPriorHistory(xp: 20_800)
        XCTAssertEqual(player.totalXP, 20_800)
    }
}
