import SwiftData
import XCTest
@testable import Sistema

/// Salud de mentira: guarda lo que el Sistema le manda y devuelve lo que la prueba le pone.
@MainActor
final class FakeHealth: HealthSyncing {
    var isAvailable = true
    var workoutsToReturn: [HealthWorkout] = []
    var samplesToReturn: [HealthBodySample] = []
    var activityToReturn: HealthActivitySnapshot?
    var savedWorkouts: [HealthWorkoutExport] = []
    var deletedWorkouts: [String] = []
    var savedBody: [UUID: [HealthBodyExport]] = [:]
    var deletedBody: [UUID] = []

    func requestAuthorization() async throws {}
    func workouts(since: Date) async throws -> [HealthWorkout] { workoutsToReturn.filter { $0.start >= since } }
    func bodySamples(since: Date) async throws -> [HealthBodySample] { samplesToReturn }
    func activity(on day: Date) async throws -> HealthActivitySnapshot? { activityToReturn }
    func replaceWorkout(_ workout: HealthWorkoutExport) async throws { savedWorkouts.append(workout) }
    func deleteWorkout(syncID: String) async throws { deletedWorkouts.append(syncID) }
    func replaceBody(_ samples: [HealthBodyExport], entryID: UUID) async throws { savedBody[entryID] = samples }
    func deleteBody(entryID: UUID) async throws { deletedBody.append(entryID) }
}

@MainActor
final class HealthTests: XCTestCase {
    private var container: ModelContainer!
    private var clock: FixedDateProvider!
    private var game: GameService!
    private var health: FakeHealth!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        container = try SistemaSchema.makeContainer(inMemory: true)
        clock = FixedDateProvider(T.day(0, hour: 6))
        health = FakeHealth()
        defaults = UserDefaults(suiteName: "health-tests-\(UUID().uuidString)")
        game = GameService(context: container.mainContext, clock: clock, notifications: SilentNotificationService(),
                           health: health, defaults: defaults)
        game.createPlayer(name: "Tester")
        game.healthConnected = true
    }

    private func watch(_ category: HealthCategory, day: Int = 0, hour: Double = 7, minutes: Double = 50,
                       id: String = UUID().uuidString) -> HealthWorkout {
        let start = T.day(day, hour: hour)
        return HealthWorkout(id: id, title: "Fuerza", category: category, start: start,
                             end: start.addingTimeInterval(minutes * 60), kcal: 420, avgHR: 132, maxHR: 171,
                             distanceKm: nil, sourceName: "Apple Watch")
    }

    private func press() -> [BlockResult] {
        var result = BlockResult(prescribed: .strength(StrengthPrescription(exerciseName: "Press", sets: 3, reps: 5, weight: 0)))
        result.sets = (0..<3).map { _ in PerformedSet(reps: 5, weight: 40, unit: .kg) }
        return [result]
    }

    private func klass(_ discipline: ClassDiscipline = .mma, minutes: Double = 60) -> [BlockResult] {
        [BlockResult.asPrescribed(.klass(ClassPrescription(discipline: discipline, minutes: minutes)))]
    }

    // MARK: - Del Watch al Sistema

    func testWatchWorkoutBecomesSessionWithXPOnce() {
        clock.now = T.day(0, hour: 9)
        let workout = watch(.strength)
        XCTAssertEqual(game.importWatchWorkouts([workout]), 1)
        XCTAssertEqual(game.importWatchWorkouts([workout]), 0, "el mismo entrenamiento no entra dos veces")
        let session = try! XCTUnwrap(game.sessions().first)
        XCTAssertTrue(session.isFromWatch)
        XCTAssertGreaterThan(session.xpAwarded, 0)
        XCTAssertEqual(session.watchKcal, 420)
        XCTAssertEqual(session.watchMaxHR, 171)
        XCTAssertEqual(session.durationMinutes, 50)
        XCTAssertEqual(game.player()?.totalXP, session.xpAwarded)
    }

    func testLoggingTheSameTrainingAbsorbsTheWatchSessionWithoutDuplicating() throws {
        clock.now = T.day(0, hour: 9)
        game.importWatchWorkouts([watch(.strength)])
        let auto = try XCTUnwrap(game.sessions().first)

        // Lo que daría la misma sesión registrada sola, sin el Watch.
        let referenceContainer = try SistemaSchema.makeContainer(inMemory: true)
        let reference = GameService(context: referenceContainer.mainContext, clock: clock,
                                    notifications: SilentNotificationService(), health: FakeHealth(),
                                    defaults: UserDefaults(suiteName: "ref-\(UUID().uuidString)")!)
        reference.createPlayer(name: "Ref")
        let expected = try XCTUnwrap(reference.logSession(SessionDraft(title: "Día 1", date: T.day(0, hour: 7), results: press(),
                                                                       durationMinutes: 50, plannedDay: T.day(0)))).xp

        let outcome = try XCTUnwrap(game.logSession(SessionDraft(title: "Día 1", date: T.day(0, hour: 9), results: press(),
                                                                 durationMinutes: 50, plannedDay: T.day(0))))
        XCTAssertEqual(game.sessions().count, 1, "no se duplica")
        XCTAssertEqual(outcome.session.id, auto.id)
        XCTAssertFalse(outcome.session.isFromWatch)
        XCTAssertEqual(outcome.session.title, "Día 1")
        XCTAssertEqual(outcome.session.plannedDay, T.day(0))
        XCTAssertEqual(outcome.session.watchKcal, 420, "conserva lo que midió el reloj")
        XCTAssertEqual(outcome.session.date, T.day(0, hour: 7), "queda a la hora real del entrenamiento")
        XCTAssertEqual(outcome.xp, expected)
        XCTAssertEqual(game.player()?.totalXP, expected)
    }

    func testWatchWorkoutAfterLoggingLinksToTheSession() throws {
        clock.now = T.day(0, hour: 10)
        let logged = try XCTUnwrap(game.logSession(SessionDraft(title: "Día 1", date: T.day(0, hour: 9), results: press(),
                                                                durationMinutes: 60, plannedDay: T.day(0)))).session
        let xp = game.player()?.totalXP
        XCTAssertEqual(game.importWatchWorkouts([watch(.strength, hour: 7.5)]), 0)
        XCTAssertEqual(game.sessions().count, 1)
        XCTAssertNotNil(logged.healthWorkoutID)
        XCTAssertEqual(logged.watchAvgHR, 132)
        XCTAssertEqual(game.player()?.totalXP, xp, "unir no cambia el XP")
    }

    func testDifferentKindOrDayIsNotMerged() throws {
        clock.now = T.day(1, hour: 10)
        try XCTUnwrap(game.logSession(SessionDraft(title: "Día 1", date: T.day(1, hour: 9), results: press(), durationMinutes: 60)))
        XCTAssertEqual(game.importWatchWorkouts([watch(.cardio(.run), day: 1), watch(.strength, day: 0)]), 2)
        XCTAssertEqual(game.sessions().count, 3)
        let run = try XCTUnwrap(game.sessions().first { $0.watchCategoryRaw == "cardio:run" })
        XCTAssertEqual(run.results.first?.prescribed.kind, .cardio)
    }

    func testDeletedWatchSessionIsNotImportedAgainAndOldWorkoutsAreIgnored() throws {
        clock.now = T.day(0, hour: 9)
        let workout = watch(.strength)
        game.importWatchWorkouts([workout, watch(.strength, day: -3)])
        XCTAssertEqual(game.sessions().count, 1, "lo de antes de crear el jugador no cuenta")
        game.deleteSession(try XCTUnwrap(game.sessions().first))
        XCTAssertEqual(game.importWatchWorkouts([workout]), 0)
        XCTAssertTrue(game.sessions().isEmpty)
    }

    func testFightClassFromWatchLinksToClassLog() throws {
        clock.now = T.day(0, hour: 21)
        let session = try XCTUnwrap(game.logSession(SessionDraft(title: "MMA", date: T.day(0, hour: 20), results: klass(),
                                                                 durationMinutes: 60))).session
        game.importWatchWorkouts([watch(.fight(.mma), hour: 19)])
        XCTAssertEqual(game.sessions().count, 1)
        XCTAssertNotNil(session.healthWorkoutID)
    }

    // MARK: - Del Sistema a Salud

    func testFightClassIsExportedWithEstimatedCaloriesOnce() async throws {
        clock.now = T.day(0, hour: 21)
        game.saveBodyEntry(nil, date: T.day(0, hour: 6), weightKg: 74, weightUnit: .kg, bodyFatPercent: nil, measures: [:], notes: "")
        let session = try XCTUnwrap(game.logSession(SessionDraft(title: "Muay Thai", date: T.day(0, hour: 19), results: klass(.muayThai),
                                                                 rpe: 7, durationMinutes: 60))).session
        await game.syncHealth()
        XCTAssertEqual(health.savedWorkouts.count, 1)
        let export = try XCTUnwrap(health.savedWorkouts.first)
        XCTAssertEqual(export.discipline, .muayThai)
        XCTAssertEqual(export.kcal, HealthSync.estimatedKcal(discipline: .muayThai, minutes: 60, weightKg: 74, rpe: 7))
        XCTAssertEqual(export.start, T.day(0, hour: 19))
        XCTAssertEqual(export.end, T.day(0, hour: 20))
        XCTAssertEqual(session.estimatedKcal, export.kcal)

        await game.syncHealth()
        XCTAssertEqual(health.savedWorkouts.count, 1, "no se manda dos veces")

        var draft = SessionDraft(title: "Muay Thai", date: T.day(0, hour: 19), results: klass(.muayThai, minutes: 90),
                                 rpe: 8, durationMinutes: 90)
        draft.plannedDay = nil
        game.updateSession(session, with: draft)
        await game.syncHealth()
        XCTAssertEqual(health.savedWorkouts.count, 2, "al corregirla se rehace")
        XCTAssertEqual(health.savedWorkouts.last?.end, T.day(0, hour: 20.5))
    }

    func testStrengthSessionsAreNotExported() async throws {
        clock.now = T.day(0, hour: 10)
        try XCTUnwrap(game.logSession(SessionDraft(title: "Día 1", date: T.day(0, hour: 9), results: press(), durationMinutes: 60)))
        await game.syncHealth()
        XCTAssertTrue(health.savedWorkouts.isEmpty)
    }

    func testClassInTheFutureIsShiftedToEndNow() throws {
        clock.now = T.day(0, hour: 20.25)
        let session = try XCTUnwrap(game.logSession(SessionDraft(title: "Box", date: T.day(0, hour: 20), results: klass(.boxing),
                                                                 durationMinutes: 60))).session
        let export = try XCTUnwrap(game.healthExport(for: session))
        XCTAssertEqual(export.end, clock.now)
        XCTAssertEqual(export.start, T.day(0, hour: 19.25))
    }

    func testEstimatedCalories() {
        XCTAssertEqual(HealthSync.estimatedKcal(discipline: .boxing, minutes: 60, weightKg: 75, rpe: 7), 510)
        XCTAssertGreaterThan(HealthSync.estimatedKcal(discipline: .mma, minutes: 60, weightKg: 75, rpe: 9),
                             HealthSync.estimatedKcal(discipline: .mma, minutes: 60, weightKg: 75, rpe: 7))
    }

    func testBodyEntryGoesToHealthWithLeanMassAndWaist() async throws {
        game.saveBodyEntry(nil, date: T.day(0, hour: 6), weightKg: 73.6, weightUnit: .kg, bodyFatPercent: 24.9,
                           measures: [.waist: 82, .chest: 100], notes: "", skeletalMuscleKg: 31.1)
        await game.syncHealth()
        let entry = try XCTUnwrap(game.bodyEntries().first)
        let saved = try XCTUnwrap(health.savedBody[entry.id])
        XCTAssertEqual(Set(saved.map(\.kind)), [.weight, .bodyFat, .leanMass, .waist])
        XCTAssertEqual(saved.first { $0.kind == .leanMass }?.value ?? 0, 73.6 * 0.751, accuracy: 0.001)
        XCTAssertEqual(entry.healthSynced, true)
        health.savedBody = [:]
        await game.syncHealth()
        XCTAssertTrue(health.savedBody.isEmpty, "solo se manda lo que cambió")
    }

    func testScaleWeightFillsTheDayAndIsNotSentBack() async throws {
        game.recordBodyValue(.bodyFat, value: 25)
        let samples = [
            HealthBodySample(id: "a", kind: .weight, value: 74.2, date: T.day(0, hour: 6.5)),
            HealthBodySample(id: "b", kind: .weight, value: 74.0, date: T.day(-1, hour: 6.5)),
        ]
        game.importBodySamples(samples)
        game.importBodySamples(samples)
        let entries = game.bodyEntries()
        XCTAssertEqual(entries.count, 2)
        let today = try XCTUnwrap(entries.last)
        XCTAssertEqual(today.weightKg, 74.2)
        XCTAssertEqual(today.bodyFatPercent, 25)
        XCTAssertEqual(today.weightFromHealth, true)
        await game.syncHealth()
        let sent = try XCTUnwrap(health.savedBody[today.id])
        XCTAssertFalse(sent.contains { $0.kind == .weight }, "el peso de la balanza ya está en Salud")
        XCTAssertTrue(sent.contains { $0.kind == .bodyFat })
    }

    func testActivityIsReadOnSync() async {
        health.activityToReturn = HealthActivitySnapshot(steps: 8123, stepsWeekAverage: 9000, moveKcal: 300, moveGoal: 600,
                                                         exerciseMinutes: 20, exerciseGoal: 30, standHours: 6, standGoal: 12,
                                                         hasRings: true)
        await game.syncHealth()
        XCTAssertEqual(game.activity?.steps, 8123)
    }

    func testNothingHappensUntilConnected() async throws {
        game.healthConnected = false
        clock.now = T.day(0, hour: 21)
        try XCTUnwrap(game.logSession(SessionDraft(title: "Box", date: T.day(0, hour: 19), results: klass(.boxing), durationMinutes: 60)))
        health.workoutsToReturn = [watch(.strength)]
        await game.syncHealth()
        XCTAssertTrue(health.savedWorkouts.isEmpty)
        XCTAssertEqual(game.sessions().count, 1)
    }

    // MARK: - InBody

    func testInBodyHistoryImportIsIdempotentAndDerivesFatMass() throws {
        let items = [
            BodyHistoryImport(date: T.day(-200, hour: 10), weightKg: 73.1, bodyFatPercent: 27.9, skeletalMuscleKg: 29.6,
                              visceralFatLevel: 8, inBodyScore: 68),
            BodyHistoryImport(date: T.day(-100, hour: 16), weightKg: 73.6, bodyFatPercent: 24.9, skeletalMuscleKg: 31.1,
                              visceralFatLevel: 7, inBodyScore: 71),
        ]
        XCTAssertEqual(game.importBodyHistory(items), 2)
        XCTAssertEqual(game.importBodyHistory(items), 0)
        let snapshots = game.bodyEntries().map(\.snapshot)
        let fat = try XCTUnwrap(BodyTrend.make(.fatMass, entries: snapshots))
        XCTAssertEqual(fat.current, 73.6 * 0.249, accuracy: 0.001)
        let muscle = try XCTUnwrap(BodyTrend.make(.muscleMass, entries: snapshots))
        XCTAssertEqual(muscle.changeSincePrevious, 1.5, accuracy: 0.001)
        XCTAssertEqual(BodyTrend.make(.visceralFat, entries: snapshots)?.current, 7)
        XCTAssertEqual(BodyTrend.make(.inBodyScore, entries: snapshots)?.changeSincePrevious, 3)
    }

    func testEditorKeepsInBodyFieldsAndBackupRoundTrips() throws {
        game.saveBodyEntry(nil, date: T.day(0, hour: 6), weightKg: 74, weightUnit: .kg, bodyFatPercent: 25, measures: [:], notes: "",
                           skeletalMuscleKg: 31.2, visceralFatLevel: 8, inBodyScore: 71)
        clock.now = T.day(0, hour: 9)
        game.importWatchWorkouts([watch(.strength)])
        let data = try BackupService.exportData(from: container.mainContext, now: clock.now)
        let before = try BackupService.makeDocument(from: container.mainContext, now: clock.now)
        try BackupService.importData(data, into: container.mainContext)
        XCTAssertEqual(try BackupService.makeDocument(from: container.mainContext, now: clock.now), before)
        let entry = try XCTUnwrap(game.bodyEntries().first)
        XCTAssertEqual(entry.skeletalMuscleKg, 31.2)
        XCTAssertEqual(entry.inBodyScore, 71)
        XCTAssertEqual(game.sessions().first?.watchKcal, 420)
        XCTAssertEqual(game.sessions().first?.isAutoImported, true)
    }

    func testHealthCategoryRawRoundTrip() {
        for category in [HealthCategory.strength, .cardio(.swim), .fight(.muayThai), .other] {
            XCTAssertEqual(HealthCategory(raw: category.raw), category)
        }
        XCTAssertEqual(HealthMatchGroup.of([.klass(ClassPrescription())]), .fight)
    }
}
