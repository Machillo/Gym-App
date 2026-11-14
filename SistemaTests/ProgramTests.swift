import SwiftData
import XCTest
@testable import Sistema

@MainActor
final class ProgramTests: XCTestCase {
    private var container: ModelContainer!
    private var clock: FixedDateProvider!
    private var game: GameService!

    override func setUp() async throws {
        container = try SistemaSchema.makeContainer(inMemory: true)
        clock = FixedDateProvider(T.day(0, hour: 6.5))
        game = GameService(context: container.mainContext, clock: clock, notifications: SilentNotificationService())
    }

    // MARK: Unidades

    func testPoundsRoundTripAndStayInKg() {
        XCTAssertEqual(WeightUnit.lb.toKg(25), 11.33980925, accuracy: 0.000001)
        XCTAssertEqual(WeightUnit.lb.fromKg(WeightUnit.lb.toKg(25)), 25, accuracy: 0.000001)
        XCTAssertEqual(WeightUnit.kg.toKg(25), 25)
        XCTAssertEqual(Format.weight(WeightUnit.lb.toKg(25), unit: .lb), "25 lb")
        XCTAssertEqual(Format.weight(WeightUnit.lb.toKg(12.5), unit: .lb), "12.5 lb")
        XCTAssertEqual(Format.weightBoth(WeightUnit.lb.toKg(25)), "25 lb · 11.3 kg")
    }

    func testImprovementComparesRealWeightAcrossUnits() {
        let block = RoutineBlock.strength(StrengthPrescription(exerciseName: "Press", sets: 1, reps: 5, weight: 20))
        var result = BlockResult.asPrescribed(block)
        result.sets = [PerformedSet(reps: 5, weight: WeightUnit.lb.toKg(45), unit: .lb)] // 20.4 kg
        XCTAssertTrue(result.hasWeightImprovement)
        result.sets = [PerformedSet(reps: 5, weight: WeightUnit.lb.toKg(40), unit: .lb)] // 18.1 kg
        XCTAssertFalse(result.hasWeightImprovement)
    }

    func testAsPrescribedKeepsUnit() {
        let block = RoutineBlock.strength(StrengthPrescription(exerciseName: "Press", sets: 2, reps: 5, weight: 20, unit: .lb))
        XCTAssertEqual(BlockResult.asPrescribed(block).sets.first?.unit, .lb)
    }

    // MARK: Datos ya guardados

    /// Rutinas y sesiones guardadas antes de los formatos y las libras deben seguir leyéndose.
    func testLegacyJSONStillDecodes() throws {
        let json = """
        [{"id":"\(UUID().uuidString)","kind":"circuit",
          "strength":{"exerciseName":"","sets":3,"reps":8,"weight":0},
          "circuit":{"rounds":3,"exercises":[{"id":"\(UUID().uuidString)","exerciseName":"Burpees","reps":10}],"restBetweenRoundsSeconds":60},
          "cardio":{"modality":"run"},
          "klass":{"discipline":"boxing","minutes":60}}]
        """
        let blocks = try JSONDecoder().decode([RoutineBlock].self, from: Data(json.utf8))
        XCTAssertEqual(blocks.first?.circuit.resolvedFormat, .circuit)
        XCTAssertEqual(blocks.first?.circuit.exercises.first?.exerciseName, "Burpees")
        XCTAssertNil(blocks.first?.circuit.exercises.first?.unit)
        XCTAssertEqual(ComplianceEngine.blockCompliance(BlockResult.asPrescribed(blocks[0])), 1)
    }

    // MARK: AMRAP

    func testAMRAPComplianceDependsOnTimeNotRounds() {
        let block = RoutineBlock.circuit(CircuitPrescription(rounds: 1, exercises: [CircuitExercise(exerciseName: "Swing", reps: 12)],
                                                             format: .amrap, timeCapMinutes: 15))
        var result = BlockResult.asPrescribed(block)
        XCTAssertEqual(result.rounds, 0)
        XCTAssertEqual(ComplianceEngine.blockCompliance(result), 1)
        result.minutes = 7.5
        XCTAssertEqual(ComplianceEngine.blockCompliance(result), 0.5, accuracy: 0.001)
        result.minutes = 20
        XCTAssertEqual(ComplianceEngine.blockCompliance(result), 1)
        XCTAssertEqual(ComplianceEngine.estimatedMinutes(block), 15)
    }

    func testRegularCircuitComplianceIsUnchanged() {
        let block = RoutineBlock.circuit(CircuitPrescription(rounds: 4, exercises: [CircuitExercise(exerciseName: "Swing", seconds: 45)],
                                                             format: .tabata))
        var result = BlockResult.asPrescribed(block)
        XCTAssertEqual(ComplianceEngine.blockCompliance(result), 1)
        result.rounds = 2
        XCTAssertEqual(ComplianceEngine.blockCompliance(result), 0.5, accuracy: 0.001)
    }

    // MARK: Programa cargado

    func testTemplateMatchesGymProgram() {
        let days = ProgramFixture.days
        XCTAssertEqual(days.map { $0.blocks.count }, [5, 1, 2, 1])
        XCTAssertEqual(days[0].blocks.prefix(4).map(\.circuit.rounds), [3, 3, 3, 3])
        XCTAssertEqual(days[1].blocks[0].circuit.exercises.count, 9)
        XCTAssertEqual(days[1].blocks[0].circuit.rounds, 4)
        XCTAssertEqual(days[2].blocks.map(\.circuit.timeCapMinutes), [15, 15])
        XCTAssertEqual(days[3].blocks[0].circuit.exercises.count, 5)
        for day in days {
            let results = day.blocks.map(BlockResult.asPrescribed)
            XCTAssertEqual(ComplianceEngine.sessionCompliance(results), 1, accuracy: 0.001, day.name)
        }
    }

    /// La app no trae rutinas: solo existen las que pasa el usuario.
    func testNewPlayerHasNoRoutinesOrItinerary() {
        game.createPlayer(name: "Tester")
        game.evaluate()
        XCTAssertTrue(game.routines().isEmpty)
        XCTAssertNil(game.activeItinerary())
    }

    func testBlankBlocksDoNotSuggestExercises() {
        for kind in [BlockKind.strength, .circuit] {
            XCTAssertTrue(BlockTemplates.defaultBlock(kind).hasUnnamedExercise, kind.name)
        }
        for format in CircuitFormat.allCases {
            XCTAssertTrue(BlockTemplates.defaultBlock(format: format).hasUnnamedExercise, format.name)
        }
    }

    func testResetLeavesNoRoutines() {
        game.createPlayer(name: "Tester")
        game.saveProgram(name: ProgramFixture.name, changeDate: nil, days: ProgramFixture.days)
        game.resetAll()
        XCTAssertTrue(game.routines().isEmpty)
    }

    func testRoutineInActiveItineraryCannotBeDeleted() {
        game.createPlayer(name: "Tester")
        let days = game.saveProgram(name: "P", changeDate: nil, days: ProgramFixture.days)
        let plan = ProgramSchedule.plan(routineIDs: [days[0].id], on: [.monday])
        game.createItinerary(name: "I", start: clock.now, end: T.day(10), plan: plan)
        game.deleteRoutine(days[0])
        game.deleteRoutine(days[1])
        XCTAssertEqual(game.routines().count, 3)
        XCTAssertNotNil(game.routine(id: days[0].id))
    }

    func testProgramSurvivesBackupRoundTrip() throws {
        game.createPlayer(name: "Tester")
        game.saveProgram(name: ProgramFixture.name, changeDate: ProgramFixture.changeDate, days: ProgramFixture.days)
        let data = try BackupService.exportData(from: container.mainContext, now: clock.now)
        try BackupService.importData(data, into: container.mainContext)
        let routine = try XCTUnwrap(game.routines().first { $0.programDay == 3 })
        XCTAssertEqual(routine.programName, ProgramFixture.name)
        XCTAssertEqual(routine.programChangeDate, ProgramFixture.changeDate)
        XCTAssertEqual(routine.focus, "Full Body")
        XCTAssertEqual(routine.blocks.first?.circuit.resolvedFormat, .amrap)
    }

    func testPlanAssignsDaysInWeekOrder() {
        let ids = [UUID(), UUID(), UUID(), UUID()]
        let plan = ProgramSchedule.plan(routineIDs: ids, on: Set(ProgramSchedule.defaultWeekdays(dayCount: 4)))
        XCTAssertEqual(plan.first { $0.weekday == .monday }?.routineID, ids[0])
        XCTAssertEqual(plan.first { $0.weekday == .tuesday }?.routineID, ids[1])
        XCTAssertNil(plan.first { $0.weekday == .wednesday }?.routineID)
        XCTAssertEqual(plan.first { $0.weekday == .thursday }?.routineID, ids[2])
        XCTAssertEqual(plan.first { $0.weekday == .friday }?.routineID, ids[3])
    }

    func testAMRAPWithoutRoundsStillRecordsWeights() {
        game.createPlayer(name: "Tester")
        let routine = game.saveRoutine(nil, name: "A", blocks: [
            .circuit(CircuitPrescription(rounds: 1, exercises: [CircuitExercise(exerciseName: "Swing nuevo", reps: 12)],
                                         format: .amrap, timeCapMinutes: 15)),
        ])
        var results = routine.blocks.map(BlockResult.asPrescribed)
        results[0].circuitActuals[0].weight = 16
        game.logSession(SessionDraft(title: "A", date: clock.now, results: results, durationMinutes: 15, routineID: routine.id))
        XCTAssertEqual(game.exerciseLogs().first?.weight, 16)
    }

    // MARK: Texto copiado de capturas

    private let screenshotText = """
    8:19
    Atrás
    PED-FIGHTERWOD
    Dia 1 - Bi Series WOD.
    Full Body.
    BI SERIES WOD: DEBERA EJECUTAR LOS
    MOVIMIENTOS DE FORMA SIMULTANEA Y
    DESCANSAR AL FINAL. TOTAL 3 ROUNDS
    POR BI SERIE.
    Trap bar deadlift
    6 Reps
    Bent over row DB
    10 reps
    2KB Front squat
    8 Reps
    Assisted dips machine
    6 reps con peso corporal 1 min
    No exercises available
    ABS
    Alternate V - abs
    16 Reps
    Dia 2 - Circuito.
    Full Body.
    TABATA - 45 SEC ON X 1 MIN OFF X 4 ROUNDS
    Goblet squat KB
    45 Sec 1 min
    Bench press DB
    45 sec . Ejecutar en el piso. 1 min
    Dia 3 - AMRAP WOD. 15 MIN ON
    x 12 REPS.
    Full Body.
    AMRAP WOD. 15 MIN ON X 12 REPS.
    Gorilla Row KB
    12 Reps c/l
    BLOQUE 2. 15 MIN ON X 12 REPS.
    DB Thrusters
    12 Reps 1 min
    Dia 4 - Circuito Cardio.
    Full Body
    CIRCUITO X 4 ROUNDS.
    Air row
    2 min / 20 kcal. 1 min
    Battle Rope 1
    3x45sec 45 sec
    Sprint SLED push
    2 min ON 1 min
    app.novofitclub.com
    """

    func testParsesWholeProgramFromScreenshotText() throws {
        let days = RoutineTextParser.parseProgram(screenshotText)
        XCTAssertEqual(days.map(\.name), ["Día 1 - Bi Series WOD", "Día 2 - Circuito", "Día 3 - AMRAP WOD. 15 MIN ON", "Día 4 - Circuito Cardio"])
        XCTAssertEqual(days[0].focus, "Full Body")

        // Día 1: dos bi-series de 3 rondas y un bloque ABS.
        XCTAssertEqual(days[0].blocks.count, 3)
        let first = days[0].blocks[0].circuit
        XCTAssertEqual(first.resolvedFormat, .biSeries)
        XCTAssertEqual(first.rounds, 3)
        XCTAssertEqual(first.exercises.map(\.exerciseName), ["Trap bar deadlift", "Bent over row DB"])
        XCTAssertEqual(first.exercises.map(\.reps), [6, 10])
        let second = days[0].blocks[1].circuit.exercises
        XCTAssertEqual(second[0].exerciseName, "2KB Front squat")
        XCTAssertEqual(second[1].note, "con peso corporal")
        XCTAssertEqual(second[1].restSeconds, 60)
        XCTAssertEqual(days[0].blocks[2].circuit.title, "Abs")
        XCTAssertEqual(days[0].blocks[2].circuit.exercises.first?.reps, 16)

        // Día 2: tabata.
        let tabata = days[1].blocks[0].circuit
        XCTAssertEqual(tabata.resolvedFormat, .tabata)
        XCTAssertEqual(tabata.rounds, 4)
        XCTAssertEqual(tabata.exercises[0].seconds, 45)
        XCTAssertEqual(tabata.exercises[0].restSeconds, 60)
        XCTAssertEqual(tabata.exercises[1].note, "Ejecutar en el piso")

        // Día 3: dos AMRAP de 15 min.
        XCTAssertEqual(days[2].blocks.map(\.circuit.timeCapMinutes), [15, 15])
        XCTAssertEqual(days[2].blocks.map(\.circuit.resolvedFormat), [.amrap, .amrap])
        XCTAssertEqual(days[2].blocks[0].circuit.exercises[0].note, "c/l")
        XCTAssertEqual(days[2].blocks[1].circuit.title, "Bloque 2")
        XCTAssertEqual(days[2].blocks[1].circuit.exercises[0].restSeconds, 60)

        // Día 4: circuito con medidas mixtas.
        let cardio = days[3].blocks[0].circuit
        XCTAssertEqual(cardio.rounds, 4)
        XCTAssertEqual(cardio.exercises.map(\.exerciseName), ["Air row", "Battle Rope 1", "Sprint SLED push"])
        XCTAssertEqual(cardio.exercises.map(\.seconds), [120, 135, 120])
        XCTAssertEqual(cardio.exercises.map(\.restSeconds), [60, 45, 60])
        XCTAssertEqual(cardio.exercises[0].note, "20 kcal")
    }

    func testParsesExercisesOnOneLine() {
        let items = RoutineTextParser.exercises(from: """
        Burpees 45 sec 1 min
        Goblet squat 12 reps c/l
        Press banca 3x10
        Plancha 1 min
        Peso muerto x 5
        Sombra
        """)
        XCTAssertEqual(items.map(\.exerciseName), ["Burpees", "Goblet squat", "Press banca", "Plancha", "Peso muerto", "Sombra"])
        XCTAssertEqual(items[0].seconds, 45)
        XCTAssertEqual(items[0].restSeconds, 60)
        XCTAssertEqual(items[1].reps, 12)
        XCTAssertEqual(items[1].note, "c/l")
        XCTAssertEqual(items[2].reps, 10)
        XCTAssertEqual(items[3].seconds, 60)
        XCTAssertEqual(items[4].reps, 5)
        XCTAssertNil(items[5].reps)
        XCTAssertNil(items[5].seconds)
    }

    func testEmptyTextGivesNoDays() {
        XCTAssertTrue(RoutineTextParser.parseProgram("  \n \n").isEmpty)
    }
}

/// Programa real de ejemplo para las pruebas. La app no trae rutinas: las pasa el usuario.
enum ProgramFixture {
    private static func biSeries(_ first: CircuitExercise, _ second: CircuitExercise) -> RoutineBlock {
        .circuit(CircuitPrescription(rounds: 3, exercises: [first, second], format: .biSeries))
    }

    private static func tabata(_ name: String, note: String? = nil) -> CircuitExercise {
        CircuitExercise(exerciseName: name, seconds: 45, restSeconds: 60, note: note)
    }

    private static func reps(_ name: String, _ count: Int, note: String? = nil, rest: Int? = nil) -> CircuitExercise {
        CircuitExercise(exerciseName: name, reps: count, restSeconds: rest, note: note)
    }

    static let name = "PED-FighterWOD"
    static let changeDate = SistemaCalendar.date(year: 2026, month: 11, day: 9)
    static let days: [ProgramDay] = [
            ProgramDay(name: "Día 1 - Bi Series WOD", focus: "Full Body", blocks: [
                biSeries(reps("Trap bar deadlift", 6), reps("Bent over row DB", 10)),
                biSeries(reps("Smith machine squat", 8), reps("Push up", 10)),
                biSeries(reps("2KB Front squat", 8), reps("Worms", 8)),
                biSeries(reps("American Kettlebell Swing", 12),
                         reps("Assisted dips machine", 6, note: "con peso corporal", rest: 60)),
                .circuit(CircuitPrescription(rounds: 1, exercises: [reps("Alternate V - abs", 16)], title: "ABS")),
            ]),
            ProgramDay(name: "Día 2 - Circuito", focus: "Full Body", blocks: [
                .circuit(CircuitPrescription(rounds: 4, exercises: [
                    tabata("Goblet squat KB"),
                    tabata("Climbers"),
                    tabata("Bench press DB", note: "Ejecutar en el piso"),
                    tabata("Cossack squat KB"),
                    tabata("Junior bar pronated bent over row"),
                    tabata("Battle Rope 1"),
                    tabata("DB push press"),
                    tabata("DB high plank rotation"),
                    tabata("Wall sit up"),
                ], format: .tabata)),
            ]),
            ProgramDay(name: "Día 3 - AMRAP WOD", focus: "Full Body", blocks: [
                .circuit(CircuitPrescription(rounds: 1, exercises: [
                    reps("Deadlift Romanian Barbell", 12),
                    reps("Gorilla Row KB", 12, note: "c/l"),
                    reps("KB Swing SA", 12, note: "c/l"),
                    reps("Decline push ups on bench", 12),
                    reps("Alt DB curl", 12, note: "c/l"),
                ], format: .amrap, timeCapMinutes: 15)),
                .circuit(CircuitPrescription(rounds: 1, exercises: [
                    reps("Bent over row DB", 12),
                    reps("Chest fly DB", 12, note: "Ejecutar en el piso"),
                    reps("Static lunge DB", 12, note: "c/l"),
                    reps("Skull crusher tricep bar", 12),
                    reps("DB Thrusters", 12, rest: 60),
                    reps("Bycicle abs", 12),
                ], format: .amrap, title: "Bloque 2", timeCapMinutes: 15)),
            ]),
            ProgramDay(name: "Día 4 - Circuito Cardio", focus: "Full Body", blocks: [
                .circuit(CircuitPrescription(rounds: 4, exercises: [
                    CircuitExercise(exerciseName: "Air bike", seconds: 180, restSeconds: 120,
                                    note: "8 min. Ejecutará 15 segundos de sprint y descansará activamente 45 segundos hasta completar el tiempo total de 3 minutos."),
                    CircuitExercise(exerciseName: "Air row", seconds: 120, restSeconds: 60, note: "2 min / 20 kcal"),
                    CircuitExercise(exerciseName: "Battle Rope 1", seconds: 135, restSeconds: 45, note: "3x45 s"),
                    CircuitExercise(exerciseName: "Burpees", seconds: 45, restSeconds: 60),
                    CircuitExercise(exerciseName: "Sprint SLED push", seconds: 120, restSeconds: 60, note: "2 min ON"),
                ], format: .circuit)),
            ]),
    ]
}
