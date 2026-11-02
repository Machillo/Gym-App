import Foundation

/// Un día de un programa del gimnasio.
struct ProgramDay: Equatable {
    var name: String
    var focus: String?
    var blocks: [RoutineBlock]
}

struct ProgramTemplate {
    var name: String
    var changeDate: Date?
    var days: [ProgramDay]
}

/// Reparte los días de un programa en la semana, dejando descansos entre ellos cuando se puede.
enum ProgramSchedule {
    static func defaultWeekdays(dayCount: Int) -> [Weekday] {
        switch dayCount {
        case 1: return [.monday]
        case 2: return [.monday, .thursday]
        case 3: return [.monday, .wednesday, .friday]
        case 4: return [.monday, .tuesday, .thursday, .friday]
        default: return Array(Weekday.allCases.prefix(max(dayCount, 0)))
        }
    }

    /// Asigna las rutinas en orden a los días elegidos; si hay más días que rutinas, vuelve a empezar.
    static func plan(routineIDs: [UUID], on weekdays: Set<Weekday>) -> [DayPlan] {
        let ordered = Weekday.allCases.filter { weekdays.contains($0) }
        return Weekday.allCases.map { day in
            guard !routineIDs.isEmpty, let position = ordered.firstIndex(of: day) else { return DayPlan(weekday: day) }
            return DayPlan(weekday: day, routineID: routineIDs[position % routineIDs.count])
        }
    }
}

enum ProgramTemplates {
    static let seedKey = "seed.pedFighterWOD"

    private static func biSeries(_ first: CircuitExercise, _ second: CircuitExercise) -> RoutineBlock {
        .circuit(CircuitPrescription(rounds: 3, exercises: [first, second], format: .biSeries))
    }

    private static func tabata(_ name: String, note: String? = nil) -> CircuitExercise {
        CircuitExercise(exerciseName: name, seconds: 45, restSeconds: 60, note: note)
    }

    private static func reps(_ name: String, _ count: Int, note: String? = nil, rest: Int? = nil) -> CircuitExercise {
        CircuitExercise(exerciseName: name, reps: count, restSeconds: rest, note: note)
    }

    /// Programa PED-FighterWOD, tal como lo publica el gimnasio.
    static let pedFighterWOD = ProgramTemplate(
        name: "PED-FighterWOD",
        changeDate: SistemaCalendar.date(year: 2026, month: 11, day: 9),
        days: [
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
    )
}
