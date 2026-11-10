import Foundation

/// Un programa escrito como JSON, para cargarlo sin pasar por el texto copiado de una captura.
/// Cada bloque trae solo una de sus partes: `strength`, `circuit` o `cardio`.
struct ProgramImport: Codable, Equatable {
    struct Exercise: Codable, Equatable {
        var name: String
        var reps: Int?
        var seconds: Int?
        var rest: Int?
        var note: String?
    }

    struct Strength: Codable, Equatable {
        var exercise: String
        var sets: Int
        var reps: Int
    }

    struct Circuit: Codable, Equatable {
        var title: String?
        var rounds: Int
        var exercises: [Exercise]
    }

    struct Cardio: Codable, Equatable {
        var modality: CardioModality
        var minutes: Double?
        var km: Double?
    }

    struct Block: Codable, Equatable {
        var strength: Strength?
        var circuit: Circuit?
        var cardio: Cardio?

        var routineBlock: RoutineBlock? {
            if let s = strength {
                return .strength(StrengthPrescription(exerciseName: s.exercise, sets: s.sets, reps: s.reps))
            }
            if let c = circuit {
                let exercises = c.exercises.map {
                    CircuitExercise(exerciseName: $0.name, reps: $0.reps, seconds: $0.seconds, restSeconds: $0.rest, note: $0.note)
                }
                return .circuit(CircuitPrescription(rounds: c.rounds, exercises: exercises, format: .circuit, title: c.title))
            }
            if let c = cardio {
                return .cardio(CardioPrescription(modality: c.modality, distanceKm: c.km, minutes: c.minutes))
            }
            return nil
        }
    }

    struct Day: Codable, Equatable {
        var name: String
        var focus: String?
        var blocks: [Block]
    }

    var name: String
    var changeDate: Date?
    var days: [Day]

    var programDays: [ProgramDay] {
        days.map { ProgramDay(name: $0.name, focus: $0.focus, blocks: $0.blocks.compactMap(\.routineBlock)) }
            .filter { !$0.blocks.isEmpty }
    }
}

extension GameService {
    /// Guarda las rutinas del programa y lo deja como itinerario activo. Si ya existe con ese nombre, no lo repite.
    @discardableResult
    func importProgram(_ program: ProgramImport) -> Bool {
        let days = program.programDays
        guard !days.isEmpty, !routines().contains(where: { $0.programName == program.name }) else { return false }
        saveProgram(name: program.name, changeDate: program.changeDate.map(SistemaCalendar.startOfDay), days: days)
        adoptProgram(named: program.name)
        if let player = player() { log(.info, "Programa \(program.name) cargado: \(days.count) días.", player: player) }
        save()
        return true
    }
}
