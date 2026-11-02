import Foundation

/// Datos de ejemplo para depuración (solo se cargan desde Ajustes > Depuración).
@MainActor
enum SampleData {
    static func load(into game: GameService) {
        if game.player() == nil { game.createPlayer(name: "Jugador de prueba") }
        let push = game.saveRoutine(nil, name: "Empuje + core", blocks: [
            .strength(StrengthPrescription(exerciseName: "Press banca", sets: 4, reps: 6, weight: 60)),
            .strength(StrengthPrescription(exerciseName: "Press militar", sets: 3, reps: 8, weight: 35)),
            .circuit(CircuitPrescription(rounds: 3, exercises: [
                CircuitExercise(exerciseName: "Flexiones", reps: 15),
                CircuitExercise(exerciseName: "Plancha", seconds: 45),
            ], restBetweenRoundsSeconds: 60)),
        ])
        let legs = game.saveRoutine(nil, name: "Piernas", blocks: [
            .strength(StrengthPrescription(exerciseName: "Sentadilla", sets: 5, reps: 5, weight: 80)),
            .strength(StrengthPrescription(exerciseName: "Peso muerto", sets: 3, reps: 5, weight: 100)),
        ])
        let run = game.saveRoutine(nil, name: "Carrera 5K", blocks: [
            .cardio(CardioPrescription(modality: .run, distanceKm: 5, minutes: 30)),
        ])
        let muayThai = game.saveRoutine(nil, name: "Muay Thai", blocks: [
            .klass(ClassPrescription(discipline: .muayThai, minutes: 60)),
        ])

        let start = SistemaCalendar.addDays(-21, to: SistemaCalendar.startOfDay(game.now))
        let plan: [DayPlan] = [
            DayPlan(weekday: .monday, routineID: push.id),
            DayPlan(weekday: .tuesday, routineID: muayThai.id),
            DayPlan(weekday: .wednesday, routineID: legs.id),
            DayPlan(weekday: .thursday, routineID: run.id),
            DayPlan(weekday: .friday, routineID: push.id),
            DayPlan(weekday: .saturday, routineID: nil),
            DayPlan(weekday: .sunday, routineID: nil),
        ]
        let itinerary = game.createItinerary(name: "Bloque de ejemplo", start: start,
                                             end: SistemaCalendar.addDays(56, to: start), plan: plan)

        for offset in 0..<21 {
            let day = SistemaCalendar.addDays(offset, to: start)
            guard let dayPlan = itinerary.dayPlan(for: day), let routine = game.routine(id: dayPlan.routineID) else { continue }
            let date = day.addingTimeInterval(5 * 3600)
            var results = routine.blocks.map(BlockResult.asPrescribed)
            if offset % 6 == 0, !results.isEmpty, results[0].prescribed.kind == .strength {
                results[0].sets = results[0].sets.map { PerformedSet(reps: $0.reps, weight: $0.weight + 2.5) }
            }
            game.logSession(SessionDraft(title: routine.name, date: date, results: results, rpe: 7 + offset % 3,
                                         durationMinutes: max(ComplianceEngine.estimatedMinutes(routine.blocks), 30),
                                         routineID: routine.id, itineraryID: itinerary.id, plannedDay: day))
        }
        game.announcements.removeAll()
        game.save()
    }
}
