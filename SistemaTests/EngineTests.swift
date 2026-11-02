import XCTest
@testable import Sistema

final class ComplianceTests: XCTestCase {
    func testStrengthUsesSetsTimesReps() {
        var r = BlockResult(prescribed: .strength(StrengthPrescription(exerciseName: "Press banca", sets: 3, reps: 8, weight: 60)))
        r.sets = [PerformedSet(reps: 8, weight: 60), PerformedSet(reps: 8, weight: 60), PerformedSet(reps: 4, weight: 60)]
        XCTAssertEqual(ComplianceEngine.blockCompliance(r), 20.0 / 24.0, accuracy: 0.0001)
    }

    func testBlockComplianceIsCappedAt100ButRealDataIsKept() {
        var r = BlockResult(prescribed: .strength(StrengthPrescription(exerciseName: "Sentadilla", sets: 3, reps: 5, weight: 80)))
        r.sets = (0..<5).map { _ in PerformedSet(reps: 8, weight: 90) }
        XCTAssertEqual(ComplianceEngine.blockCompliance(r), 1)
        XCTAssertEqual(r.sets.count, 5)
    }

    func testCircuitCombinesRoundsAndRepsOrTime() {
        let block = RoutineBlock.circuit(CircuitPrescription(rounds: 3, exercises: [
            CircuitExercise(exerciseName: "Burpees", reps: 10),
            CircuitExercise(exerciseName: "Plancha", seconds: 30),
        ]))
        var r = BlockResult(prescribed: block)
        r.rounds = 2
        r.circuitActuals = [PerformedCircuitExercise(reps: 10), PerformedCircuitExercise(seconds: 15)]
        XCTAssertEqual(ComplianceEngine.blockCompliance(r), (2.0 / 3.0) * 0.75, accuracy: 0.0001)
    }

    func testCardioPrefersDistanceThenTime() {
        var byDistance = BlockResult(prescribed: .cardio(CardioPrescription(modality: .run, distanceKm: 5, minutes: 30)))
        byDistance.distanceKm = 4
        byDistance.minutes = 40
        XCTAssertEqual(ComplianceEngine.blockCompliance(byDistance), 0.8, accuracy: 0.0001)

        var byTime = BlockResult(prescribed: .cardio(CardioPrescription(modality: .rope, distanceKm: nil, minutes: 20)))
        byTime.minutes = 10
        XCTAssertEqual(ComplianceEngine.blockCompliance(byTime), 0.5, accuracy: 0.0001)
    }

    func testClassUsesDuration() {
        var r = BlockResult(prescribed: .klass(ClassPrescription(discipline: .muayThai, minutes: 60)))
        r.minutes = 45
        XCTAssertEqual(ComplianceEngine.blockCompliance(r), 0.75, accuracy: 0.0001)
    }

    func testSessionIsWeightedByEstimatedMinutes() {
        let strength = BlockResult.asPrescribed(.strength(StrengthPrescription(exerciseName: "Press", sets: 3, reps: 5, weight: 50)))
        var klass = BlockResult(prescribed: .klass(ClassPrescription(discipline: .boxing, minutes: 60)))
        klass.minutes = 30
        let expected = (1.0 * 7.5 + 0.5 * 60) / 67.5
        XCTAssertEqual(ComplianceEngine.sessionCompliance([strength, klass]), expected, accuracy: 0.0001)
    }

    func testAsPrescribedIsFullCompliance() {
        for kind in BlockKind.allCases {
            let r = BlockResult.asPrescribed(BlockTemplates.defaultBlock(kind))
            XCTAssertEqual(ComplianceEngine.blockCompliance(r), 1, accuracy: 0.0001, "\(kind)")
        }
    }

    func testHeavierWeightWithSameRepsIsImprovement() {
        var r = BlockResult(prescribed: .strength(StrengthPrescription(exerciseName: "Press", sets: 1, reps: 5, weight: 60)))
        r.sets = [PerformedSet(reps: 5, weight: 62.5)]
        XCTAssertTrue(r.hasWeightImprovement)
        r.sets = [PerformedSet(reps: 4, weight: 62.5)]
        XCTAssertFalse(r.hasWeightImprovement)
    }
}

final class XPTests: XCTestCase {
    private func xp(minutes: Double = 60, rpe: Int = 7, compliance: Double = 1, hour: Double = 7) -> Double {
        XPEngine.rawXP(.init(dominantKind: .strength, minutes: minutes, rpe: rpe, compliance: compliance, startedAt: T.day(0, hour: hour)))
    }

    func testTypicalSessionIsAbout100XP() {
        XCTAssertEqual(xp(), 100, accuracy: 0.001)
    }

    func testEarlyBonusBefore6AM() {
        XCTAssertEqual(xp(hour: 4.5), 110, accuracy: 0.001)
        XCTAssertEqual(xp(hour: 6), 100, accuracy: 0.001)
    }

    func testFactorsForDurationIntensityAndCompliance() {
        XCTAssertEqual(xp(minutes: 30), 50, accuracy: 0.001)
        XCTAssertEqual(xp(minutes: 300), 150, accuracy: 0.001) // tope 1.5×
        XCTAssertEqual(xp(rpe: 9), 110, accuracy: 0.001)
        XCTAssertEqual(xp(rpe: 1), 85, accuracy: 0.001) // piso 0.85×
        XCTAssertEqual(xp(compliance: 0.5), 50, accuracy: 0.001)
    }

    func testDailyAndWeeklyCaps() {
        XCTAssertEqual(XPEngine.cappedXP(raw: 100, earnedToday: 150, earnedThisWeek: 150), 50)
        XCTAssertEqual(XPEngine.cappedXP(raw: 100, earnedToday: 0, earnedThisWeek: 680), 20)
        XCTAssertEqual(XPEngine.cappedXP(raw: 400, earnedToday: 0, earnedThisWeek: 0), 200)
        XCTAssertEqual(XPEngine.cappedXP(raw: 100, earnedToday: 200, earnedThisWeek: 200), 0)
    }
}

final class LevelAndRankTests: XCTestCase {
    func testCurveFormula() {
        XCTAssertEqual(LevelCurve.xpToNext(from: 1), Int((50 + 7.3).rounded()))
        XCTAssertEqual(LevelCurve.xpToNext(from: 10), Int((50 + 7.3 * pow(10, 1.5)).rounded()))
        XCTAssertEqual(LevelCurve.cumulative.count, Progression.maxLevel + 1)
        for level in 2...Progression.maxLevel {
            XCTAssertGreaterThan(LevelCurve.threshold(for: level), LevelCurve.threshold(for: level - 1))
        }
    }

    func testLevelForXP() {
        XCTAssertEqual(LevelCurve.level(forTotalXP: 0), 1)
        for level in [2, 10, 25, 64, 99, 100] {
            XCTAssertEqual(LevelCurve.level(forTotalXP: LevelCurve.threshold(for: level)), level)
            XCTAssertEqual(LevelCurve.level(forTotalXP: LevelCurve.threshold(for: level) - 1), level - 1)
        }
        XCTAssertEqual(LevelCurve.level(forTotalXP: Int.max / 2), 100)
    }

    func testRanksCoverAllLevels() {
        var covered: [Int] = []
        for rank in Rank.allCases { covered += Array(rank.levels) }
        XCTAssertEqual(covered, Array(1...100))
        XCTAssertEqual(Rank.forLevel(9), .e)
        XCTAssertEqual(Rank.forLevel(10), .d)
        XCTAssertEqual(Rank.forLevel(100), .ss)
    }

    func testDivisions() {
        XCTAssertEqual(RankPosition(level: 1).division, .iii)
        XCTAssertEqual(RankPosition(level: 4).division, .ii)
        XCTAssertEqual(RankPosition(level: 9).division, .i)
        XCTAssertEqual(RankPosition(level: 14).division, .iii)
        XCTAssertEqual(RankPosition(level: 15).division, .ii)
        XCTAssertEqual(RankPosition(level: 24).division, .i)
        XCTAssertEqual(RankPosition(level: 30).division, .iii)
        XCTAssertEqual(RankPosition(level: 31).title, "Rango C · División II · Nivel 31")
        XCTAssertEqual(RankPosition(level: 38).division, .i)
        XCTAssertNil(RankPosition(level: 100).division)
        XCTAssertEqual(RankPosition(level: 100).title, "Rango SS · Nivel 100")
    }

    func testMinimumMonthsBeforeTrial() {
        XCTAssertEqual(Rank.allCases.map(\.minMonthsInPreviousRank), [0, 1, 3, 6, 12, 24, 36])
    }

    func testGainEmitsLevelDivisionAndRankEvents() {
        var p = PlayerProgress(startedAt: T.day(0))
        let events = p.applyGain(LevelCurve.threshold(for: 4), now: T.day(0))
        XCTAssertTrue(events.contains(.levelUp(from: 1, to: 4)))
        XCTAssertTrue(events.contains(.divisionUp(RankPosition(level: 4))))
    }
}

final class OverflowAndTrialTests: XCTestCase {
    func testCappedAtTopOfRankWithOverflowLimitedToOneLevel() {
        var p = PlayerProgress(startedAt: T.day(0))
        p.applyGain(5_000, now: T.day(10))
        XCTAssertEqual(p.level, 9)
        XCTAssertTrue(p.isCapped)
        XCTAssertEqual(p.totalXP, LevelCurve.threshold(for: 10) - 1)
        XCTAssertEqual(p.overflowXP, LevelCurve.xpToNext(from: 9))
    }

    func testTrialNeedsLevelThenTimeThenIsAvailable() {
        var p = PlayerProgress(startedAt: T.day(0))
        XCTAssertEqual(p.trialAvailability(now: T.day(1)), .needsLevel(9))
        p.applyGain(5_000, now: T.day(10))
        if case .needsTime = p.trialAvailability(now: T.day(20)) {} else { XCTFail("debería exigir 1 mes en E") }
        XCTAssertEqual(p.trialAvailability(now: T.day(31)), .available(.d))
    }

    func testPassingTrialReleasesOverflow() {
        var p = PlayerProgress(startedAt: T.day(0))
        p.applyGain(5_000, now: T.day(10))
        let events = p.passTrial(now: T.day(31))
        XCTAssertEqual(p.unlockedRank, .d)
        XCTAssertEqual(p.overflowXP, 0)
        XCTAssertEqual(p.totalXP, LevelCurve.threshold(for: 10) - 1 + LevelCurve.xpToNext(from: 9))
        XCTAssertEqual(p.position.rank, .d)
        XCTAssertTrue(events.contains(.rankUp(.d)))
        XCTAssertEqual(p.rankEnteredAt, T.day(31))
    }

    func testMinimumTimesForEachRank() {
        for rank in Rank.allCases where rank != .e {
            let previous = rank.previous!
            var p = PlayerProgress(startedAt: T.day(0))
            p.unlockedRank = previous
            p.highestRankEverUnlocked = previous
            p.totalXP = LevelCurve.threshold(for: previous.levels.upperBound)
            p.rankEnteredAt = T.day(0)
            let justBefore = SistemaCalendar.addDays(-1, to: SistemaCalendar.addMonths(rank.minMonthsInPreviousRank, to: T.day(0)))
            let onTime = SistemaCalendar.addMonths(rank.minMonthsInPreviousRank, to: T.day(0))
            if case .needsTime = p.trialAvailability(now: justBefore) {} else { XCTFail("\(rank) antes de tiempo") }
            XCTAssertEqual(p.trialAvailability(now: onTime), .available(rank))
        }
    }

    func testRequirementsUseOwnRecords() {
        let metrics = TrialMetrics(weeklyCompliance: [0.5, 0.9, 0.9, 0.86, 0.95, 0.88, 0.9], bestImprovement: 0.06, classesInRank: 3)
        XCTAssertEqual(metrics.trailingWeeks(atLeast: 0.85), 6)
        XCTAssertTrue(AscensionEngine.allMet(target: .d, metrics: metrics))
        XCTAssertTrue(AscensionEngine.allMet(target: .c, metrics: metrics))
        XCTAssertFalse(AscensionEngine.allMet(target: .b, metrics: metrics))
        let statuses = AscensionEngine.evaluate(target: .b, metrics: metrics)
        XCTAssertEqual(statuses.map(\.met), [false, false, false])
    }

    func testBestImprovementAgainstPreviousBestOrFirstInRank() {
        let since = T.day(30)
        let records = [
            MarkRecord(key: "press", date: T.day(1), value: 100, higherIsBetter: true),
            MarkRecord(key: "press", date: T.day(40), value: 108, higherIsBetter: true),
            MarkRecord(key: "cardio:run", date: T.day(35), value: 6.0, higherIsBetter: false),
            MarkRecord(key: "cardio:run", date: T.day(50), value: 5.0, higherIsBetter: false),
        ]
        XCTAssertEqual(AscensionEngine.bestImprovement(records: records, since: since), 0.2, accuracy: 0.0001)
    }

    func testWeeklyComplianceCountsMissedDaysAsZero() {
        let it = T.itinerary()
        let sessions = [0, 1, 2, 3].map { T.session(day: $0) } + [7, 8, 9, 10, 11].map { T.session(day: $0, compliance: 0.9) }
        let weeks = AscensionEngine.weeklyCompliance(itineraries: [it], sessions: sessions, injuries: [], from: T.day(0), through: T.day(13))
        XCTAssertEqual(weeks.count, 2)
        XCTAssertEqual(weeks[0], 0.8, accuracy: 0.0001)
        XCTAssertEqual(weeks[1], 0.9, accuracy: 0.0001)
    }
}

final class CatalogMatchTests: XCTestCase {
    private let entries = [
        CatalogEntry(id: UUID(), name: "Press banca", aliases: ["bench press"]),
        CatalogEntry(id: UUID(), name: "Sentadilla", aliases: ["squat"]),
    ]

    func testMatchesByNameAliasCaseAndAccents() {
        XCTAssertEqual(ExerciseCatalog.match("press BANCA", in: entries)?.name, "Press banca")
        XCTAssertEqual(ExerciseCatalog.match("  Bench   Press ", in: entries)?.name, "Press banca")
        XCTAssertEqual(ExerciseCatalog.match("SENTADÍLLA", in: entries)?.name, "Sentadilla")
        XCTAssertNil(ExerciseCatalog.match("peso muerto", in: entries))
    }

    func testEpley() {
        XCTAssertEqual(ExerciseMath.epley(weight: 100, reps: 1), 100)
        XCTAssertEqual(ExerciseMath.epley(weight: 100, reps: 10), 100 * (1 + 10.0 / 30), accuracy: 0.0001)
    }
}
