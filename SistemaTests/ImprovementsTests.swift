import SwiftData
import XCTest
@testable import Sistema

@MainActor
final class ImprovementsTests: XCTestCase {
    private var container: ModelContainer!
    private var clock: FixedDateProvider!
    private var game: GameService!

    override func setUp() async throws {
        container = try SistemaSchema.makeContainer(inMemory: true)
        clock = FixedDateProvider(T.day(0, hour: 9))
        game = GameService(context: container.mainContext, clock: clock, notifications: SilentNotificationService())
        game.createPlayer(name: "Tester")
    }

    private func press(kg: Double, unit: WeightUnit = .kg, reps: Int = 5) -> [BlockResult] {
        var result = BlockResult(prescribed: .strength(StrengthPrescription(exerciseName: "Press", sets: 2, reps: reps, weight: 0)))
        result.sets = [PerformedSet(reps: reps, weight: kg / 2, unit: unit), PerformedSet(reps: reps, weight: kg, unit: unit)]
        return [result]
    }

    private func klass(_ discipline: ClassDiscipline = .mma, minutes: Double = 60) -> [BlockResult] {
        [BlockResult.asPrescribed(.klass(ClassPrescription(discipline: discipline, minutes: minutes)))]
    }

    @discardableResult
    private func log(_ results: [BlockResult], at date: Date, minutes: Double = 60) throws -> WorkoutSession {
        try XCTUnwrap(game.logSession(SessionDraft(title: "S", date: date, results: results, durationMinutes: minutes))).session
    }

    // MARK: Último peso

    func testLastPerformanceUsesHeaviestSetOfLatestSession() throws {
        try log(press(kg: 40), at: T.day(0, hour: 8))
        try log(press(kg: 30, unit: .lb, reps: 6), at: T.day(1, hour: 8))
        let last = try XCTUnwrap(game.lastPerformances().find(id: nil, name: "press"))
        XCTAssertEqual(last.weightKg, 30)
        XCTAssertEqual(last.unit, .lb)
        XCTAssertEqual(last.reps, 6)
    }

    func testLastPerformanceIgnoresEditedSessionAndEmptyWeights() throws {
        let first = try log(press(kg: 40), at: T.day(0, hour: 8))
        let second = try log(press(kg: 50), at: T.day(1, hour: 8))
        XCTAssertEqual(game.lastPerformances(excluding: second.id).find(id: nil, name: "Press")?.weightKg, 40)
        XCTAssertNil(game.lastPerformances(excluding: second.id).find(id: nil, name: "Sentadilla"))
        try log(press(kg: 0), at: T.day(2, hour: 8))
        XCTAssertEqual(game.lastPerformances().find(id: nil, name: "Press")?.weightKg, 50)
        _ = first
    }

    // MARK: Temporizador

    func testTabataPhasesHaveNoTrailingRest() {
        let config = WODTimerConfig(mode: .tabata, workSeconds: 20, restSeconds: 10, rounds: 3, prepareSeconds: 5)
        XCTAssertEqual(config.phases.map(\.kind), [.prepare, .work, .rest, .work, .rest, .work])
        XCTAssertEqual(config.totalSeconds, 5 + 20 * 3 + 10 * 2)
    }

    func testTimerReadingCrossesPhasesAndFinishes() {
        let config = WODTimerConfig(mode: .tabata, workSeconds: 20, restSeconds: 10, rounds: 2, prepareSeconds: 0)
        XCTAssertEqual(config.reading(at: 5).displaySeconds, 15)
        XCTAssertEqual(config.reading(at: 25).phase?.kind, .rest)
        XCTAssertEqual(config.reading(at: 31).phase?.round, 2)
        XCTAssertFalse(config.reading(at: 49.9).isFinished)
        XCTAssertTrue(config.reading(at: 50).isFinished)
    }

    func testForTimeCountsUpAndEmomRepeats() {
        XCTAssertEqual(WODTimerConfig(mode: .forTime, minutes: 10, prepareSeconds: 0).reading(at: 65).displaySeconds, 65)
        let emom = WODTimerConfig(mode: .emom, workSeconds: 60, rounds: 3, prepareSeconds: 0)
        XCTAssertEqual(emom.reading(at: 130).phase?.round, 3)
    }

    func testCuesOnCountdownPhaseChangeAndFinish() {
        let config = WODTimerConfig(mode: .tabata, workSeconds: 10, restSeconds: 10, rounds: 1, prepareSeconds: 5)
        func cue(_ a: TimeInterval, _ b: TimeInterval) -> TimerCue? {
            config.cue(from: config.reading(at: a), to: config.reading(at: b))
        }
        XCTAssertNil(cue(0, 0.1))
        XCTAssertEqual(cue(1.95, 2.05), .countdown)
        XCTAssertEqual(cue(4.95, 5.05), .phaseChange)
        XCTAssertEqual(cue(14.95, 15.05), .finish)
        XCTAssertNil(cue(15.1, 15.2))
    }

    func testTimerClockSurvivesPause() {
        var clock = TimerClock()
        clock.start(at: T.day(0))
        XCTAssertEqual(clock.elapsed(at: T.day(0).addingTimeInterval(10)), 10)
        clock.pause(at: T.day(0).addingTimeInterval(10))
        XCTAssertEqual(clock.elapsed(at: T.day(0).addingTimeInterval(100)), 10)
        clock.start(at: T.day(0).addingTimeInterval(100))
        XCTAssertEqual(clock.elapsed(at: T.day(0).addingTimeInterval(105)), 15)
    }

    func testSetsRepeatEverythingWithRestBetween() {
        let config = WODTimerConfig(mode: .amrap, minutes: 5, prepareSeconds: 10, sets: 3, restBetweenSets: 60)
        XCTAssertEqual(config.phases.map(\.kind), [.prepare, .work, .rest, .work, .rest, .work])
        XCTAssertEqual(config.totalSeconds, 10 + 300 * 3 + 60 * 2)
        XCTAssertEqual(config.reading(at: 10 + 300 + 60 + 1).phase?.set, 2)
    }

    func testForTimeWithoutLimitEndsByHand() {
        let config = WODTimerConfig.standard(.forTime)
        XCTAssertTrue(config.isOpenEnded)
        XCTAssertFalse(config.reading(at: 7200).isFinished)
        XCTAssertEqual(config.reading(at: 10 + 125).displaySeconds, 125)
        XCTAssertFalse(WODTimerConfig(mode: .forTime, minutes: 10).isOpenEnded)
    }

    func testDeathByHasNoFixedRounds() {
        var config = WODTimerConfig.standard(.emom)
        XCTAssertFalse(config.isOpenEnded)
        XCTAssertEqual(config.phases.count, 11)
        config.deathBy = true
        XCTAssertTrue(config.isOpenEnded)
        XCTAssertEqual(config.reading(at: 10 + 60 * 25 + 1).phase?.round, 26)
    }

    func testIntervalSignalOnlyWhenOn() {
        var config = WODTimerConfig(mode: .forTime, minutes: 10, prepareSeconds: 0)
        func cue(_ a: TimeInterval, _ b: TimeInterval) -> TimerCue? {
            config.cue(from: config.reading(at: a), to: config.reading(at: b))
        }
        XCTAssertNil(cue(59.95, 60.05))
        config.intervalSeconds = 60
        XCTAssertEqual(cue(59.95, 60.05), .interval)
        XCTAssertNil(cue(60.05, 60.15))
    }

    func testMixChainsSegmentsWithRestAndSinglePreparation() {
        let config = WODTimerConfig(mode: .mix, restSeconds: 30, prepareSeconds: 10, segments: [
            WODTimerConfig(mode: .amrap, minutes: 2, prepareSeconds: 10),
            WODTimerConfig(mode: .tabata, workSeconds: 20, restSeconds: 10, rounds: 2, prepareSeconds: 10),
        ])
        XCTAssertEqual(config.phases.map(\.kind), [.prepare, .work, .rest, .work, .rest, .work])
        XCTAssertEqual(config.totalSeconds, 10 + 120 + 30 + 20 + 10 + 20)
        XCTAssertEqual(config.reading(at: 11).phase?.label, "AMRAP")
    }

    func testNextPhaseAndSkip() {
        let config = WODTimerConfig(mode: .tabata, workSeconds: 20, restSeconds: 10, rounds: 2, prepareSeconds: 0)
        let first = config.reading(at: 5)
        XCTAssertEqual(config.nextPhase(after: first)?.kind, .rest)
        var clock = TimerClock()
        clock.start(at: T.day(0))
        clock.skip(first.remaining)
        XCTAssertEqual(config.reading(at: clock.elapsed(at: T.day(0).addingTimeInterval(5))).phase?.kind, .rest)
    }

    func testConfigIsRememberedAsJSON() throws {
        var config = WODTimerConfig.standard(.mix)
        config.sets = 3
        let copy = try JSONDecoder().decode(WODTimerConfig.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(copy, config)
        XCTAssertEqual(copy.segments.count, 2)
    }

    func testToneIsValidWAV() throws {
        let data = TimerTone.wav(frequency: 880, duration: 0.1)
        XCTAssertEqual(data.prefix(4), Data("RIFF".utf8))
        XCTAssertEqual(data.count, 44 + 4410 * 2)
    }

    func testTimerConfigFromBlock() {
        let amrap = RoutineBlock.circuit(CircuitPrescription(rounds: 1, format: .amrap, timeCapMinutes: 12))
        XCTAssertEqual(WODTimerConfig.from(amrap).mode, .amrap)
        XCTAssertEqual(WODTimerConfig.from(amrap).minutes, 12)
        let series = RoutineBlock.circuit(CircuitPrescription(rounds: 3, restBetweenRoundsSeconds: 75, format: .biSeries))
        XCTAssertEqual(WODTimerConfig.from(series).mode, .rest)
        XCTAssertEqual(WODTimerConfig.from(series).restSeconds, 75)
    }

    // MARK: Corregir sesiones

    func testDeleteSessionRemovesItsXPStatsAndLogs() throws {
        let startXP = try XCTUnwrap(game.player()).totalXP
        let session = try log(press(kg: 40), at: T.day(0, hour: 8))
        XCTAssertGreaterThan(try XCTUnwrap(game.player()).totalXP, startXP)
        XCTAssertFalse(game.exerciseLogs().isEmpty)

        game.deleteSession(session)

        let player = try XCTUnwrap(game.player())
        XCTAssertEqual(player.totalXP, startXP)
        XCTAssertEqual(player.stats.strength, 0, accuracy: 0.0001)
        XCTAssertTrue(game.sessions().isEmpty)
        XCTAssertTrue(game.exerciseLogs().isEmpty)
    }

    func testEditSessionRecalculatesXPAndReplacesLogs() throws {
        let session = try log(press(kg: 40), at: T.day(0, hour: 8), minutes: 30)
        let before = session.xpAwarded
        var draft = SessionDraft(title: "Corregida", date: session.date, results: press(kg: 60), durationMinutes: 60)
        draft.rpe = session.rpe

        game.updateSession(session, with: draft)

        XCTAssertGreaterThan(session.xpAwarded, before)
        XCTAssertEqual(try XCTUnwrap(game.player()).totalXP, session.xpAwarded)
        XCTAssertEqual(game.sessions().count, 1)
        XCTAssertEqual(game.exerciseLogs().map(\.weight).max(), 60)
        XCTAssertEqual(game.exerciseLogs().count, 2)
    }

    func testEditDoesNotGrowStatsWhenNothingChanges() throws {
        let session = try log(press(kg: 40), at: T.day(0, hour: 8))
        let stats = try XCTUnwrap(game.player()).stats
        let xp = try XCTUnwrap(game.player()).totalXP
        game.updateSession(session, with: SessionDraft(title: session.title, date: session.date, results: session.results,
                                                       rpe: session.rpe, durationMinutes: session.durationMinutes))
        XCTAssertEqual(try XCTUnwrap(game.player()).totalXP, xp)
        XCTAssertEqual(try XCTUnwrap(game.player()).stats.strength, stats.strength, accuracy: 0.0001)
    }

    func testPunishmentSessionsCannotBeChanged() throws {
        var draft = SessionDraft(title: "Castigo", date: T.day(0, hour: 8), results: press(kg: 40), durationMinutes: 25)
        draft.isPunishment = true
        let session = try XCTUnwrap(game.logSession(draft)).session
        let xp = try XCTUnwrap(game.player()).totalXP
        game.deleteSession(session)
        XCTAssertEqual(game.sessions().count, 1)
        XCTAssertEqual(try XCTUnwrap(game.player()).totalXP, xp)
    }

    // MARK: Itinerarios

    func testArchivedItineraryNoLongerCovers() throws {
        let routine = game.saveRoutine(nil, name: "R", blocks: [.klass(ClassPrescription(discipline: .mma, minutes: 60))])
        let plan = ProgramSchedule.plan(routineIDs: [routine.id], on: Set(Weekday.allCases))
        let old = game.createItinerary(name: "Viejo", start: T.day(0), end: T.day(60), plan: plan)
        game.createItinerary(name: "Nuevo", start: T.day(3), end: T.day(5), plan: plan)
        XCTAssertEqual(old.endDate, T.day(2))
        XCTAssertFalse(old.snapshot.covers(T.day(10)))
        XCTAssertTrue(old.snapshot.covers(T.day(2)))
    }

    // MARK: Vencimiento y respaldo

    func testExpiryIsParsedFromSignedProfile() throws {
        let plist = #"<?xml version="1.0"?><plist version="1.0"><dict><key>ExpirationDate</key><date>2026-11-09T14:15:07Z</date></dict></plist>"#
        var data = Data([0x30, 0x82, 0x01])
        data.append(Data(plist.utf8))
        data.append(Data([0xA0, 0x00]))
        let date = try XCTUnwrap(AppExpiry.parse(data))
        XCTAssertEqual(date, ISO8601DateFormatter().date(from: "2026-11-09T14:15:07Z"))
        XCTAssertNil(AppExpiry.parse(Data("nada".utf8)))
    }

    func testExpiryNoticesOnlyInTheFuture() {
        let expiry = T.day(7)
        XCTAssertEqual(AppExpiry.notices(expiry: expiry, now: T.day(0)).count, 3)
        XCTAssertEqual(AppExpiry.notices(expiry: expiry, now: T.day(6)).map(\.id), ["app-expiry-3"])
        XCTAssertTrue(AppExpiry.notices(expiry: nil, now: T.day(0)).isEmpty)
    }

    func testAutoBackupIsWeeklyAndKeepsFour() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let context = container.mainContext
        XCTAssertNotNil(try AutoBackup.runIfDue(context: context, now: T.day(0), directory: directory))
        XCTAssertNil(try AutoBackup.runIfDue(context: context, now: T.day(6), directory: directory))
        for week in 1...5 {
            XCTAssertNotNil(try AutoBackup.runIfDue(context: context, now: T.day(7 * week), directory: directory))
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files.count, AutoBackup.keep)
        XCTAssertEqual(AutoBackup.latestDate(in: directory), T.day(35))
    }

    // MARK: MMA, cuerpo y respaldo

    func testMMACountsAsClassForTrials() throws {
        try log(klass(.mma), at: T.day(0, hour: 18))
        XCTAssertEqual(game.sessions().first?.snapshot.classCount, 1)
        XCTAssertEqual(game.exerciseLogs().first?.markKey, "class:mma")
    }

    func testBodyTrendAndLeanMass() {
        let entries = [
            BodySnapshot(date: T.day(0), weightKg: 80, bodyFatPercent: 20, measures: [.waist: 90]),
            BodySnapshot(date: T.day(7), weightKg: 78, measures: [:]),
            BodySnapshot(date: T.day(14), weightKg: 76, bodyFatPercent: 15, measures: [.waist: 85]),
        ]
        XCTAssertEqual(BodyTrend.make(.weight, entries: entries)?.changeSinceFirst, -4)
        XCTAssertEqual(BodyTrend.make(.measure(.waist), entries: entries)?.current, 85)
        XCTAssertEqual(try XCTUnwrap(BodyTrend.make(.leanMass, entries: entries)).current, 64.6, accuracy: 0.001)
        XCTAssertNil(BodyTrend.make(.measure(.calf), entries: entries))
    }

    func testNewDataSurvivesBackupRoundTrip() throws {
        game.saveBodyEntry(nil, date: T.day(0), weightKg: WeightUnit.lb.toKg(180), weightUnit: .lb, bodyFatPercent: 18,
                           measures: [.armRight: 38], notes: "ayunas")
        try log(klass(), at: T.day(0, hour: 18))
        let doc = try BackupService.makeDocument(from: container.mainContext, now: clock.now)
        let data = try BackupService.exportData(from: container.mainContext, now: clock.now)
        try BackupService.importData(data, into: container.mainContext)
        XCTAssertEqual(try BackupService.makeDocument(from: container.mainContext, now: clock.now), doc)
        let entry = try XCTUnwrap(game.bodyEntries().first)
        XCTAssertEqual(entry.weightUnit, .lb)
        XCTAssertEqual(entry.measures[.armRight], 38)
        XCTAssertFalse(game.awards().isEmpty)
        XCTAssertNotNil(game.player()?.profileTitle)
    }

    func testOldBackupWithoutNewFieldsStillImports() throws {
        let data = try BackupService.exportData(from: container.mainContext, now: clock.now)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "bodyEntries")
        json.removeValue(forKey: "awards")
        let old = try JSONSerialization.data(withJSONObject: json)
        XCTAssertNoThrow(try BackupService.importData(old, into: container.mainContext))
    }

    // MARK: Perfil

    func testProfileFollowsWhatYouTrainAndRank() {
        let stats = PlayerStats(strength: 5, endurance: 3, technique: 1, discipline: 2, vitality: 2)
        func digest(_ results: [BlockResult], day: Int = 0) -> SessionDigest {
            SessionDigest(id: UUID(), date: T.day(day, hour: 8), results: results, plannedDay: nil, compliance: 1,
                          isPunishment: false, durationMinutes: 60)
        }
        var profile = FighterProfile.make(sessions: [], stats: PlayerStats(), rank: .c, now: T.day(1))
        XCTAssertNil(profile.title)

        profile = FighterProfile.make(sessions: [digest(klass(.mma))], stats: stats, rank: .c, now: T.day(1))
        XCTAssertEqual(profile.title, "Peleador de MMA · Competidor")
        XCTAssertEqual(profile.strongest, .strength)
        XCTAssertEqual(profile.weakest, .technique)

        profile = FighterProfile.make(sessions: [digest(klass(.mma)), digest(klass(.boxing))], stats: stats, rank: .b, now: T.day(1))
        XCTAssertEqual(profile.title, "Peleador mixto · Veterano")

        // Lo de hace más de 8 semanas ya no define tu estilo.
        profile = FighterProfile.make(sessions: [digest(klass(.mma), day: -60), digest(press(kg: 40))], stats: stats, rank: .c, now: T.day(1))
        XCTAssertEqual(profile.style, "Atleta de fuerza")
    }

    func testProfileChangeIsLoggedOnce() throws {
        try log(klass(), at: T.day(0, hour: 18))
        try log(klass(), at: T.day(0, hour: 20))
        let title = try XCTUnwrap(game.player()?.profileTitle)
        XCTAssertTrue(title.hasPrefix("Peleador de MMA"))
        let entries = try container.mainContext.fetch(FetchDescriptor<SystemLogEntry>()).filter { $0.kind == .profile }
        XCTAssertEqual(entries.count, 1)
    }

    // MARK: Retos

    private func input(sessions: [SessionDigest] = [], records: [MarkRecord] = [], body: [Date] = [],
                       streak: Int = 0, now: Date = T.day(3)) -> ChallengeInput {
        ChallengeInput(sessions: sessions, itineraries: [T.itinerary()], records: records, bodyEntryDates: body, maxStreak: streak, now: now)
    }

    private func digest(day: Int, results: [BlockResult] = [], minutes: Double = 60, planned: Bool = false) -> SessionDigest {
        SessionDigest(id: UUID(), date: T.day(day, hour: 8), results: results, plannedDay: planned ? T.day(day) : nil,
                      compliance: 1, isPunishment: false, durationMinutes: minutes)
    }

    func testWeeklyPlanChallengeCountsPlannedDays() throws {
        let sessions = (0..<5).map { digest(day: $0, planned: true) }
        let plan = try XCTUnwrap(ChallengeEngine.weekly(input(sessions: sessions)).first { $0.title == "Semana completa" })
        XCTAssertEqual(plan.target, 5)
        XCTAssertTrue(plan.isComplete)
        XCTAssertTrue(plan.key.contains("W45"))
    }

    func testTargetsGrowFromPreviousPeriod() throws {
        let lastWeek = (0..<4).map { digest(day: -7 + $0, minutes: 100) }
        let minutes = try XCTUnwrap(ChallengeEngine.weekly(input(sessions: lastWeek)).first { $0.title == "Minutos de la semana" })
        XCTAssertEqual(minutes.target, 420)
        XCTAssertEqual(minutes.current, 0)

        let october = (0..<20).map { digest(day: -$0 - 2) }
        let month = try XCTUnwrap(ChallengeEngine.monthly(input(sessions: october)).first { $0.title == "Reto del mes" })
        XCTAssertEqual(month.target, 22)
    }

    func testPunishmentDoesNotCountForChallenges() throws {
        var punishment = digest(day: 0)
        punishment.isPunishment = true
        let first = try XCTUnwrap(ChallengeEngine.milestones(input(sessions: [punishment])).first)
        XCTAssertEqual(first.current, 0)
    }

    func testPersonalRecordsNeedAPreviousMark() {
        let records = [
            MarkRecord(key: "a", date: T.day(0), value: 100, higherIsBetter: true),
            MarkRecord(key: "a", date: T.day(7), value: 90, higherIsBetter: true),
            MarkRecord(key: "a", date: T.day(8), value: 110, higherIsBetter: true),
            MarkRecord(key: "b", date: T.day(8), value: 5, higherIsBetter: false),
        ]
        XCTAssertEqual(PersonalRecords.count(records: records, from: T.day(7), to: T.day(14)), 1)
        XCTAssertEqual(PersonalRecords.count(records: records, from: T.day(0), to: T.day(7)), 0)
    }

    func testChallengeAwardIsEarnedOnceAndGivesNoXP() throws {
        let session = try log(klass(), at: T.day(0, hour: 18))
        let keys = game.awards().map(\.key)
        XCTAssertTrue(keys.contains("award-mma-1"))
        XCTAssertEqual(try XCTUnwrap(game.player()).totalXP, session.xpAwarded)
        game.evaluate()
        XCTAssertEqual(game.awards().map(\.key).sorted(), keys.sorted())
    }

    // MARK: Resumen semanal

    func testWeeklySummaryOnlyCountsThatWeek() {
        let sessions = [digest(day: 0, results: klass(), minutes: 60), digest(day: 7, minutes: 30)]
        let summary = WeeklySummary.make(weekOf: T.day(2), sessions: sessions,
                                         volumes: [(T.day(1), 500), (T.day(8), 900)], records: [])
        XCTAssertEqual(summary.sessions, 1)
        XCTAssertEqual(summary.minutes, 60)
        XCTAssertEqual(summary.volumeKg, 500)
        XCTAssertEqual(summary.classes, 1)
    }

    // MARK: - Figura del cuerpo

    func testBodyMapMergesMeasuresIntoTodaysEntry() {
        game.recordBodyValue(.measure(.waist), value: 82.5)
        clock.now = T.day(0, hour: 18)
        game.recordBodyValue(.measure(.armRight), value: 36)
        game.recordBodyValue(.weight, value: 180, weightUnit: .lb)
        game.recordBodyValue(.bodyFat, value: 17)
        let entries = game.bodyEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].measures, [.waist: 82.5, .armRight: 36])
        XCTAssertEqual(entries[0].weightKg!, WeightUnit.lb.toKg(180), accuracy: 0.001)
        XCTAssertEqual(entries[0].weightUnit, .lb)
        XCTAssertEqual(entries[0].bodyFatPercent, 17)
    }

    func testBodyMapOverwritesSameMeasureAndStartsNewEntryNextDay() {
        game.recordBodyValue(.measure(.waist), value: 84)
        game.recordBodyValue(.measure(.waist), value: 83)
        XCTAssertEqual(game.bodyEntries().first?.measures[.waist], 83)
        clock.now = T.day(1, hour: 9)
        game.recordBodyValue(.measure(.waist), value: 82)
        let entries = game.bodyEntries()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.map { $0.measures[.waist] }, [83, 82])
        XCTAssertEqual(BodyTrend.make(.measure(.waist), entries: entries.map(\.snapshot))?.changeSinceFirst, -1)
    }

    func testBodyMapIgnoresLeanMass() {
        game.recordBodyValue(.leanMass, value: 70)
        XCTAssertTrue(game.bodyEntries().first.map { $0.weightKg == nil && $0.measures.isEmpty } ?? true)
    }
}
