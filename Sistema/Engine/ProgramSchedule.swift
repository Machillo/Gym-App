import Foundation

/// Un día de un programa del gimnasio.
struct ProgramDay: Equatable {
    var name: String
    var focus: String?
    var blocks: [RoutineBlock]
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
