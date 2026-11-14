import SwiftData
import XCTest
@testable import Sistema

@MainActor
final class CombatAndRoundsTests: XCTestCase {
    private var container: ModelContainer!
    private var clock: FixedDateProvider!
    private var game: GameService!

    override func setUp() async throws {
        container = try SistemaSchema.makeContainer(inMemory: true)
        clock = FixedDateProvider(T.day(0, hour: 9))
        game = GameService(context: container.mainContext, clock: clock, notifications: SilentNotificationService())
        game.createPlayer(name: "Tester")
    }

    // MARK: Rondas

    private func circuit(reps: Int?, rounds: Int = 3) -> RoutineBlock {
        .circuit(CircuitPrescription(rounds: rounds, exercises: [CircuitExercise(exerciseName: "Dominadas", reps: reps)]))
    }

    private func result(_ block: RoutineBlock, reps: [Int?]) -> BlockResult {
        var r = BlockResult.asPrescribed(block)
        r.rounds = reps.count
        r.roundActuals = reps.map { [PerformedCircuitExercise(reps: $0)] }
        r.syncFromRounds()
        return r
    }

    func testPrescribedCircuitStartsWithOneRowPerRound() {
        let r = BlockResult.asPrescribed(circuit(reps: 10, rounds: 4))
        XCTAssertEqual(r.roundActuals?.count, 4)
        XCTAssertEqual(r.roundActuals?.first?.first?.reps, 10)
    }

    func testRoundByRoundComplianceAddsAllRounds() {
        XCTAssertEqual(ComplianceEngine.blockCompliance(result(circuit(reps: 10), reps: [10, 8, 12])), 1, accuracy: 0.001)
        XCTAssertEqual(ComplianceEngine.blockCompliance(result(circuit(reps: 10), reps: [10, 8, 6])), 0.8, accuracy: 0.001)
    }

    func testMaxRepsCountsRoundsWithWork() {
        XCTAssertEqual(ComplianceEngine.blockCompliance(result(circuit(reps: nil), reps: [8, 6, 5])), 1, accuracy: 0.001)
        XCTAssertEqual(ComplianceEngine.blockCompliance(result(circuit(reps: nil), reps: [8, 6, nil])), 2.0 / 3, accuracy: 0.001)
    }

    func testSummaryAveragesRepsAndKeepsHeaviestWeight() {
        var r = BlockResult.asPrescribed(circuit(reps: 10))
        r.roundActuals = [
            [PerformedCircuitExercise(reps: 10, weight: 10, unit: .lb)],
            [PerformedCircuitExercise(reps: 8, weight: 20, unit: .lb)],
            [PerformedCircuitExercise(reps: 6)],
        ]
        r.syncFromRounds()
        XCTAssertEqual(r.circuitActuals.first?.reps, 8)
        XCTAssertEqual(r.circuitActuals.first?.weight, 20)
        XCTAssertEqual(r.circuitActuals.first?.unit, .lb)
    }

    func testResizeRoundsCopiesTheLastRound() {
        var r = result(circuit(reps: 10), reps: [10, 7])
        r.rounds = 4
        r.resizeRounds()
        XCTAssertEqual(r.roundActuals?.map { $0.first?.reps }, [10, 7, 7, 7])
        r.rounds = 1
        r.resizeRounds()
        XCTAssertEqual(r.roundActuals?.count, 1)
    }

    func testOldSessionJSONStillDecodes() throws {
        let block = circuit(reps: 10)
        var old = BlockResult.asPrescribed(block)
        old.roundActuals = nil
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        json.removeValue(forKey: "roundActuals")
        json.removeValue(forKey: "fight")
        let decoded = try JSONDecoder().decode(BlockResult.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.roundActuals)
        XCTAssertNil(decoded.prescribed.klass.combat)
        XCTAssertEqual(decoded.prescribed.klass.combatKind, .lesson)
    }

    // MARK: Libras

    func testPoundsAreTheDefaultUnit() {
        XCTAssertEqual(WeightUnit.preferred, .lb)
        let exercise = CircuitExercise(exerciseName: "Goblet squat", reps: 10, weight: WeightUnit.lb.toKg(35))
        XCTAssertTrue(exercise.prescriptionText.contains("35 lb"))
    }

    // MARK: Combate

    private func combat(_ kind: CombatKind, outcome: FightOutcome = .win, method: FightMethod = .decision) -> BlockResult {
        var block = ClassPrescription(discipline: .mma, minutes: 17, combat: kind == .lesson ? nil : kind, rounds: 3, roundMinutes: 5)
        if kind == .lesson { block.minutes = 60 }
        var r = BlockResult.asPrescribed(.klass(block))
        if kind == .fight { r.fight = FightResult(outcome: outcome, method: method) }
        return r
    }

    func testFightBonusGrowsWithWinAndFinish() {
        XCTAssertEqual(XPEngine.fightBonus([combat(.lesson)]), 0)
        XCTAssertEqual(XPEngine.fightBonus([combat(.sparring)]), 0)
        XCTAssertEqual(XPEngine.fightBonus([combat(.fight, outcome: .loss, method: .ko)]), Progression.fightXP)
        XCTAssertEqual(XPEngine.fightBonus([combat(.fight, outcome: .win)]), Progression.fightXP + Progression.fightWinXP)
        XCTAssertEqual(XPEngine.fightBonus([combat(.fight, outcome: .win, method: .ko)]),
                       Progression.fightXP + Progression.fightWinXP + Progression.fightFinishXP)
    }

    func testSparringIsWorthMoreThanAClass() {
        XCTAssertEqual(XPEngine.combatMultiplier([combat(.sparring).prescribed]), Progression.sparringXPMultiplier)
        XCTAssertEqual(XPEngine.combatMultiplier([combat(.lesson).prescribed]), 1)
    }

    func testFightAlwaysCountsAsDone() {
        XCTAssertEqual(ComplianceEngine.blockCompliance(combat(.fight)), 1)
    }

    func testFightBonusSkipsTheCapsAndDoesNotEatThem() throws {
        let fight = try XCTUnwrap(game.logSession(SessionDraft(title: "Pelea de MMA", date: T.day(0, hour: 19),
                                                               results: [combat(.fight, outcome: .win, method: .ko)],
                                                               rpe: 10, durationMinutes: 17)))
        let bonus = Progression.fightXP + Progression.fightWinXP + Progression.fightFinishXP
        XCTAssertGreaterThan(fight.xp, bonus, "El premio va encima del XP de la sesión")
        XCTAssertEqual(game.xpEarned(day: T.day(0)), fight.xp - bonus)

        let next = try XCTUnwrap(game.logSession(SessionDraft(title: "Fuerza", date: T.day(1, hour: 9),
                                                              results: [.asPrescribed(circuit(reps: 10))], durationMinutes: 45)))
        XCTAssertGreaterThan(next.xp, 0, "Una pelea no llena el tope semanal")
    }

    func testDeletingAFightTakesBackTheBonus() throws {
        let before = try XCTUnwrap(game.player()).progress.totalXP
        let outcome = try XCTUnwrap(game.logSession(SessionDraft(title: "Pelea", date: T.day(0, hour: 19),
                                                                 results: [combat(.fight)], rpe: 9, durationMinutes: 17)))
        game.deleteSession(outcome.session)
        XCTAssertEqual(try XCTUnwrap(game.player()).progress.totalXP, before)
    }
}
