import SwiftData
import XCTest
@testable import Sistema

@MainActor
final class ServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var clock: FixedDateProvider!
    private var game: GameService!

    override func setUp() async throws {
        container = try SistemaSchema.makeContainer(inMemory: true)
        clock = FixedDateProvider(T.day(0, hour: 6.5))
        game = GameService(context: container.mainContext, clock: clock, notifications: SilentNotificationService())
    }

    private func onboard() -> (Routine, Itinerary) {
        game.createPlayer(name: "Tester")
        let routine = game.saveRoutine(nil, name: "Empuje", blocks: [
            .strength(StrengthPrescription(exerciseName: "bench press", sets: 4, reps: 6, weight: 60)),
        ])
        let plan = Weekday.allCases.map { DayPlan(weekday: $0, routineID: T.weekdays.contains($0) ? routine.id : nil) }
        let itinerary = game.createItinerary(name: "Bloque 1", start: clock.now, end: T.day(55), plan: plan)
        return (routine, itinerary)
    }

    private func logPlanned(_ routine: Routine, _ itinerary: Itinerary, day: Int, weight: Double? = nil) -> SessionOutcome? {
        var results = routine.blocks.map(BlockResult.asPrescribed)
        if let weight { results[0].sets = results[0].sets.map { PerformedSet(reps: $0.reps, weight: weight) } }
        return game.logSession(SessionDraft(title: routine.name, date: T.day(day, hour: 7), results: results,
                                            durationMinutes: 60, routineID: routine.id,
                                            itineraryID: itinerary.id, plannedDay: T.day(day)))
    }

    // MARK: Catálogo

    func testAliasDoesNotDuplicateExercise() throws {
        _ = onboard()
        let byAlias = game.exercises().filter { $0.name == "Press banca" }
        XCTAssertEqual(byAlias.count, 1)
        let again = game.findOrCreateExercise(named: "PRESS DE BANCA")
        XCTAssertEqual(again?.id, byAlias.first?.id)
        XCTAssertEqual(game.exercises().filter { ExerciseCatalog.normalize($0.name) == "press banca" }.count, 1)
        let created = game.findOrCreateExercise(named: "Hip thrust")
        XCTAssertNotNil(created)
        XCTAssertEqual(game.findOrCreateExercise(named: "hip  THRUST")?.id, created?.id)
    }

    func testExerciseHistoryPersistsWhenRoutineChanges() throws {
        let (routine, itinerary) = onboard()
        let pressID = try XCTUnwrap(routine.blocks.first?.strength.exerciseID)
        _ = logPlanned(routine, itinerary, day: 0)

        // Se cambia la rutina por completo y luego se usa el ejercicio desde otra rutina con otro nombre.
        game.saveRoutine(routine, name: "Empuje v2", blocks: [
            .strength(StrengthPrescription(exerciseName: "Press militar", sets: 3, reps: 8, weight: 30)),
        ])
        let other = game.saveRoutine(nil, name: "Pecho", blocks: [
            .strength(StrengthPrescription(exerciseName: "Press de banca", sets: 3, reps: 5, weight: 70)),
        ])
        XCTAssertEqual(other.blocks.first?.strength.exerciseID, pressID)
        clock.now = T.day(1, hour: 6.5)
        _ = logPlanned(other, itinerary, day: 1)

        let pressLogs = game.exerciseLogs().filter { $0.exerciseID == pressID }
        XCTAssertEqual(pressLogs.count, 4 + 3)
        XCTAssertEqual(pressLogs.map(\.weight).max(), 70)
    }

    func testImprovementIsMarkedInExerciseHistory() throws {
        let (routine, itinerary) = onboard()
        _ = logPlanned(routine, itinerary, day: 0, weight: 62.5)
        XCTAssertEqual(game.exerciseLogs().filter(\.isImprovement).count, 4)
    }

    // MARK: Juego

    func testLoggingPlannedSessionGivesXPStatsAndNoPenalty() throws {
        let (routine, itinerary) = onboard()
        let outcome = try XCTUnwrap(logPlanned(routine, itinerary, day: 0))
        XCTAssertEqual(outcome.xp, 100) // 60 min, RPE 7, 100 %, 7 a. m. (sin bonus)
        XCTAssertEqual(outcome.session.compliance, 1, accuracy: 0.0001)
        let player = try XCTUnwrap(game.player())
        XCTAssertEqual(player.totalXP, 100)
        XCTAssertGreaterThan(player.stats.strength, 0)
        XCTAssertGreaterThan(player.stats.discipline, 0)
        XCTAssertNotNil(game.todayMission()?.completedSession)

        clock.now = T.day(1, hour: 8)
        game.evaluate()
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<PenaltyEvent>()).count, 0)
        XCTAssertEqual(player.currentStreak, 0, "el día del onboarding queda fuera de la evaluación")
    }

    func testDailyCapAcrossSessions() throws {
        let (routine, itinerary) = onboard()
        let first = try XCTUnwrap(logPlanned(routine, itinerary, day: 0))
        let second = try XCTUnwrap(game.logSession(SessionDraft(title: "Extra", date: T.day(0, hour: 18),
                                                                results: routine.blocks.map(BlockResult.asPrescribed),
                                                                rpe: 10, durationMinutes: 120)))
        XCTAssertEqual(first.xp + second.xp, Progression.dailyXPCap)
        XCTAssertEqual(game.player()?.totalXP, Progression.dailyXPCap)
    }

    func testEvaluateNextDayPenalizesMissedDayOnlyOnce() throws {
        _ = onboard()
        clock.now = T.day(1, hour: 8)
        game.evaluate()
        game.evaluate()
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<PenaltyEvent>()).count, 0, "el día del onboarding no se penaliza")
        clock.now = T.day(2, hour: 8)
        game.evaluate()
        game.evaluate()
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<PenaltyEvent>()).count, 1)
        XCTAssertEqual(game.player()?.status(now: clock.now), .penaltyZone)
    }

    // MARK: Respaldo

    func testExportImportRoundTripIsIdentical() throws {
        clock.now = T.day(21, hour: 6.5)
        SampleData.load(into: game)
        clock.now = T.day(23, hour: 9)
        game.evaluate()
        game.startInjury(reason: "Prueba", until: T.day(25))

        let exported = try BackupService.exportData(from: container.mainContext, now: clock.now)
        let original = try BackupService.decode(exported)
        XCTAssertFalse(original.sessions.isEmpty)
        XCTAssertFalse(original.exerciseLogs.isEmpty)

        let other = try SistemaSchema.makeContainer(inMemory: true)
        try BackupService.importData(exported, into: other.mainContext)
        let reexported = try BackupService.exportData(from: other.mainContext, now: clock.now)
        XCTAssertEqual(try BackupService.decode(reexported), original)
        XCTAssertEqual(reexported, exported)

        // Importar encima de datos existentes también reemplaza todo.
        try BackupService.importData(exported, into: container.mainContext)
        XCTAssertEqual(try BackupService.exportData(from: container.mainContext, now: clock.now), exported)
    }

    // MARK: Notificaciones

    func testNotificationPlan() {
        let it = T.itinerary(start: 0, end: 9)
        let plan = NotificationPlanner.plan(itinerary: it, routineNames: [.monday: "Empuje"], reminderHour: 4, reminderMinute: 30,
                                            loggedPlannedDays: [T.day(1)], injuries: [], now: T.day(0, hour: 5))
        XCTAssertFalse(plan.contains { $0.id.hasPrefix("morning") && $0.date == T.day(0, hour: 4.5) }, "ya pasó")
        XCTAssertTrue(plan.contains { $0.id.hasPrefix("warning") && $0.date == T.day(0, hour: 21) })
        XCTAssertFalse(plan.contains { $0.id.hasPrefix("warning") && $0.date == T.day(1, hour: 21) }, "día ya registrado")
        XCTAssertTrue(plan.contains { $0.id == "itinerary-expiry" && $0.date == T.day(7, hour: 9) })
        XCTAssertFalse(plan.contains { $0.date >= T.day(5) && $0.date < T.day(7) }, "fin de semana de descanso")
    }
}
