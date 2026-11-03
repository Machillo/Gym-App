import SwiftData
import XCTest
@testable import Sistema

@MainActor
final class PendingDaysTests: XCTestCase {
    private var container: ModelContainer!
    private var clock: FixedDateProvider!
    private var game: GameService!

    override func setUp() async throws {
        container = try SistemaSchema.makeContainer(inMemory: true)
        clock = FixedDateProvider(T.day(0, hour: 9))
        game = GameService(context: container.mainContext, clock: clock, notifications: SilentNotificationService())
        game.createPlayer(name: "Tester")
    }

    private func everyDayPlan(_ routine: Routine) -> [DayPlan] {
        ProgramSchedule.plan(routineIDs: [routine.id], on: Set(Weekday.allCases))
    }

    private func draft(_ routine: Routine, day: Date, itinerary: Itinerary) -> SessionDraft {
        SessionDraft(title: routine.name, date: day.addingTimeInterval(12 * 3600),
                     results: routine.blocks.map(BlockResult.asPrescribed), durationMinutes: 45,
                     routineID: routine.id, itineraryID: itinerary.id, plannedDay: day)
    }

    // MARK: Cambio de programa

    func testAdoptProgramReplacesItineraryAndItsRoutine() throws {
        let old = game.saveRoutine(nil, name: "Rutina A", blocks: ProgramFixture.days[0].blocks)
        game.createItinerary(name: "Itinerario 1", start: clock.now, end: T.day(27), plan: everyDayPlan(old))
        game.saveProgram(name: ProgramFixture.name, changeDate: T.day(7), days: ProgramFixture.days)
        clock.now = T.day(1, hour: 9)

        game.adoptProgram(named: ProgramFixture.name)

        XCTAssertEqual(game.itineraries().count, 1)
        let active = try XCTUnwrap(game.activeItinerary())
        XCTAssertEqual(active.name, ProgramFixture.name)
        XCTAssertEqual(active.startDate, SistemaCalendar.startOfDay(T.day(0)))
        XCTAssertEqual(active.endDate, SistemaCalendar.startOfDay(T.day(7)))
        XCTAssertNil(game.routine(id: old.id))
        XCTAssertEqual(game.routines().count, ProgramFixture.days.count)
    }

    func testAdoptProgramTwiceChangesNothing() throws {
        game.saveProgram(name: ProgramFixture.name, changeDate: T.day(7), days: ProgramFixture.days)
        game.adoptProgram(named: ProgramFixture.name)
        let first = try XCTUnwrap(game.activeItinerary()).id
        game.adoptProgram(named: ProgramFixture.name)
        XCTAssertEqual(game.activeItinerary()?.id, first)
        XCTAssertEqual(game.itineraries().count, 1)
    }

    func testAdoptUnknownProgramKeepsCurrentItinerary() {
        let old = game.saveRoutine(nil, name: "Rutina A", blocks: ProgramFixture.days[0].blocks)
        game.createItinerary(name: "Itinerario 1", start: clock.now, end: T.day(27), plan: everyDayPlan(old))
        game.adoptProgram(named: "No existe")
        XCTAssertEqual(game.activeItinerary()?.name, "Itinerario 1")
        XCTAssertNotNil(game.routine(id: old.id))
    }

    // MARK: Días pendientes

    func testPastPlannedDayIsPendingUntilLogged() throws {
        let routine = game.saveRoutine(nil, name: "R", blocks: ProgramFixture.days[0].blocks)
        let itinerary = game.createItinerary(name: "I", start: clock.now, end: T.day(27), plan: everyDayPlan(routine))
        XCTAssertTrue(game.pendingMissions().isEmpty, "Hoy es la misión de hoy, no un pendiente")

        clock.now = T.day(1, hour: 9)
        let yesterday = SistemaCalendar.startOfDay(T.day(0))
        XCTAssertEqual(game.pendingMissions().map(\.day), [yesterday])

        let outcome = try XCTUnwrap(game.logSession(draft(routine, day: yesterday, itinerary: itinerary)))
        XCTAssertGreaterThan(outcome.xp, 0)
        XCTAssertTrue(game.pendingMissions().isEmpty)
        XCTAssertEqual(game.todayMission()?.day, SistemaCalendar.startOfDay(T.day(1)))
        XCTAssertNil(game.todayMission()?.completedSession, "El registro de ayer no cumple la misión de hoy")
    }

    func testRestDaysAndDaysBeforeItineraryAreNotPending() {
        let routine = game.saveRoutine(nil, name: "R", blocks: ProgramFixture.days[0].blocks)
        let rest = SistemaCalendar.weekday(of: T.day(1))
        let plan = ProgramSchedule.plan(routineIDs: [routine.id], on: Set(Weekday.allCases).subtracting([rest]))
        game.createItinerary(name: "I", start: T.day(1), end: T.day(27), plan: plan)
        clock.now = T.day(2, hour: 9)
        XCTAssertTrue(game.pendingMissions().isEmpty)
    }

    func testPendingStopsAfterLookback() {
        let routine = game.saveRoutine(nil, name: "R", blocks: ProgramFixture.days[0].blocks)
        game.createItinerary(name: "I", start: clock.now, end: T.day(27), plan: everyDayPlan(routine))
        clock.now = T.day(20, hour: 9)
        XCTAssertEqual(game.pendingMissions().count, 7)
    }

    /// Las reglas no cambian: el día ya cerrado sigue con su falta aunque se registre tarde.
    func testLateLogDoesNotRemoveChargedFault() throws {
        let routine = game.saveRoutine(nil, name: "R", blocks: ProgramFixture.days[0].blocks)
        let itinerary = game.createItinerary(name: "I", start: clock.now, end: T.day(27), plan: everyDayPlan(routine))
        clock.now = T.day(2, hour: 9)
        game.evaluate()
        let penalties = try container.mainContext.fetchCount(FetchDescriptor<PenaltyEvent>())
        XCTAssertEqual(penalties, 1)

        game.logSession(draft(routine, day: SistemaCalendar.startOfDay(T.day(1)), itinerary: itinerary))
        game.evaluate()
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<PenaltyEvent>()), penalties)
        XCTAssertNotNil(game.player()?.ledger.openMission)
    }
}
