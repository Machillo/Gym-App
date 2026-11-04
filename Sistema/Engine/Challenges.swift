import Foundation

/// Reto con su avance. Los semanales y mensuales se ajustan a lo que hiciste en el periodo anterior.
struct Challenge: Equatable, Identifiable {
    enum Period: Equatable { case week, month, milestone }

    var key: String
    var title: String
    var detail: String
    var period: Period
    var current: Double
    var target: Double

    var id: String { key }
    var isComplete: Bool { target > 0 && current >= target }
    var fraction: Double { target > 0 ? min(current / target, 1) : 0 }
}

struct ChallengeInput {
    var sessions: [SessionDigest]
    var itineraries: [ItinerarySnapshot]
    var records: [MarkRecord]
    var bodyEntryDates: [Date]
    var maxStreak: Int
    var now: Date
}

enum ChallengeEngine {
    static func active(_ input: ChallengeInput) -> [Challenge] {
        weekly(input) + monthly(input)
    }

    static func weekly(_ input: ChallengeInput) -> [Challenge] {
        let start = SistemaCalendar.startOfWeek(input.now)
        let end = SistemaCalendar.addDays(7, to: start)
        let previous = SistemaCalendar.addDays(-7, to: start)
        let key = SistemaCalendar.weekKey(start)
        let sessions = input.sessions.filter { !$0.isPunishment }
        let week = sessions.filter { $0.date >= start && $0.date < end }
        let lastWeek = sessions.filter { $0.date >= previous && $0.date < start }

        var result: [Challenge] = []
        let planned = plannedDays(from: start, to: end, itineraries: input.itineraries)
        if !planned.isEmpty {
            let done = Set(week.filter { $0.compliance >= Progression.halfFaultComplianceThreshold }
                .compactMap { $0.plannedDay.map(SistemaCalendar.startOfDay) })
            result.append(Challenge(key: "week-\(key)-plan", title: "Semana completa",
                                    detail: "Cumplí todos los días planeados de la semana.", period: .week,
                                    current: Double(planned.filter(done.contains).count), target: Double(planned.count)))
        }
        let lastMinutes = lastWeek.reduce(0) { $0 + $1.durationMinutes }
        result.append(Challenge(key: "week-\(key)-minutes", title: "Minutos de la semana",
                                detail: "Entrená un poco más que la semana pasada.", period: .week,
                                current: week.reduce(0) { $0 + $1.durationMinutes },
                                target: max(150, (lastMinutes * 1.05 / 10).rounded(.up) * 10)))
        result.append(Challenge(key: "week-\(key)-classes", title: "Tatami y ring",
                                detail: "Clases de box, Muay Thai o MMA esta semana.", period: .week,
                                current: Double(week.reduce(0) { $0 + $1.classes.count }),
                                target: Double(max(1, lastWeek.reduce(0) { $0 + $1.classes.count }))))
        return result
    }

    static func monthly(_ input: ChallengeInput) -> [Challenge] {
        let comps = SistemaCalendar.calendar.dateComponents([.year, .month], from: input.now)
        let start = SistemaCalendar.date(year: comps.year ?? 2026, month: comps.month ?? 1, day: 1)
        let end = SistemaCalendar.addMonths(1, to: start)
        let previous = SistemaCalendar.addMonths(-1, to: start)
        let key = String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
        let sessions = input.sessions.filter { !$0.isPunishment }
        let month = sessions.filter { $0.date >= start && $0.date < end }
        let lastMonth = sessions.filter { $0.date >= previous && $0.date < start }

        return [
            Challenge(key: "month-\(key)-sessions", title: "Reto del mes",
                      detail: "Superá tus sesiones del mes pasado.", period: .month,
                      current: Double(month.count), target: max(12, (Double(lastMonth.count) * 1.1).rounded(.up))),
            Challenge(key: "month-\(key)-classes", title: "Mes de pelea",
                      detail: "Clases de box, Muay Thai o MMA este mes.", period: .month,
                      current: Double(month.reduce(0) { $0 + $1.classes.count }),
                      target: max(4, (Double(lastMonth.reduce(0) { $0 + $1.classes.count }) * 1.1).rounded(.up))),
            Challenge(key: "month-\(key)-record", title: "Nueva marca",
                      detail: "Rompé una marca personal este mes.", period: .month,
                      current: Double(PersonalRecords.count(records: input.records, from: start, to: end)), target: 1),
            Challenge(key: "month-\(key)-body", title: "Cuerpo al día",
                      detail: "Registrá tu peso o medidas dos veces este mes.", period: .month,
                      current: Double(input.bodyEntryDates.filter { $0 >= start && $0 < end }.count), target: 2),
        ]
    }

    static func milestones(_ input: ChallengeInput) -> [Challenge] {
        let sessions = input.sessions.filter { !$0.isPunishment }
        let classes = sessions.flatMap(\.classes)
        let mma = classes.filter { $0 == .mma }.count
        let records = PersonalRecords.count(records: input.records, from: .distantPast, to: .distantFuture)

        func milestone(_ key: String, _ title: String, _ detail: String, _ current: Int, _ target: Int) -> Challenge {
            Challenge(key: "award-\(key)", title: title, detail: detail, period: .milestone,
                      current: Double(current), target: Double(target))
        }
        return [
            milestone("sessions-1", "Primer paso", "Registrá tu primera sesión.", sessions.count, 1),
            milestone("sessions-10", "Constante", "Completá 10 sesiones.", sessions.count, 10),
            milestone("sessions-50", "Sin excusas", "Completá 50 sesiones.", sessions.count, 50),
            milestone("sessions-100", "Centenario", "Completá 100 sesiones.", sessions.count, 100),
            milestone("mma-1", "Primera de MMA", "Registrá tu primera clase de MMA.", mma, 1),
            milestone("mma-10", "Jaula conocida", "Completá 10 clases de MMA.", mma, 10),
            milestone("classes-10", "Guantes gastados", "Completá 10 clases de pelea.", classes.count, 10),
            milestone("classes-50", "Peleador de verdad", "Completá 50 clases de pelea.", classes.count, 50),
            milestone("record-1", "Marca rota", "Rompé tu primera marca personal.", records, 1),
            milestone("streak-7", "Racha de 7", "Llegá a 7 días planeados seguidos.", input.maxStreak, 7),
            milestone("streak-30", "Racha de 30", "Llegá a 30 días planeados seguidos.", input.maxStreak, 30),
            milestone("body-1", "Punto de partida", "Registrá tu peso o medidas.", input.bodyEntryDates.count, 1),
            milestone("body-10", "Seguimiento real", "Hacé 10 registros de tu cuerpo.", input.bodyEntryDates.count, 10),
        ]
    }

    private static func plannedDays(from start: Date, to end: Date, itineraries: [ItinerarySnapshot]) -> [Date] {
        var days: [Date] = []
        var day = start
        while day < end {
            if let itinerary = itineraries.first(where: { $0.covers(day) }), itinerary.isPlannedWeekday(day) {
                days.append(day)
            }
            day = SistemaCalendar.addDays(1, to: day)
        }
        return days
    }
}
