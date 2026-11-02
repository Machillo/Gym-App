import Foundation

/// Calendario único del motor: zona America/Costa_Rica, semanas de lunes a domingo.
enum SistemaCalendar {
    static let timeZone = TimeZone(identifier: "America/Costa_Rica") ?? TimeZone(secondsFromGMT: -6 * 3600)!

    static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        cal.locale = Locale(identifier: "es_CR")
        return cal
    }()

    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static func addDays(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date.addingTimeInterval(Double(days) * 86_400)
    }

    static func addMonths(_ months: Int, to date: Date) -> Date {
        calendar.date(byAdding: .month, value: months, to: date) ?? date
    }

    /// Días calendario entre dos fechas (inicio de día a inicio de día).
    static func daysBetween(_ from: Date, _ to: Date) -> Int {
        calendar.dateComponents([.day], from: startOfDay(from), to: startOfDay(to)).day ?? 0
    }

    static func weekday(of date: Date) -> Weekday {
        // Calendar: 1 = domingo ... 7 = sábado.
        let raw = calendar.component(.weekday, from: date)
        return Weekday(rawValue: (raw + 5) % 7 + 1) ?? .monday
    }

    static func startOfWeek(_ date: Date) -> Date {
        let day = startOfDay(date)
        let offset = weekday(of: day).rawValue - 1
        return addDays(-offset, to: day)
    }

    /// Clave estable de semana calendario, p. ej. "2026-W44".
    static func weekKey(_ date: Date) -> String {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", comps.yearForWeekOfYear ?? 0, comps.weekOfYear ?? 0)
    }

    static func hour(of date: Date) -> Int {
        calendar.component(.hour, from: date)
    }

    static func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        return calendar.date(from: comps) ?? Date()
    }
}

/// Día de la semana con lunes = 1.
enum Weekday: Int, Codable, CaseIterable, Identifiable, Comparable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    var id: Int { rawValue }

    var shortName: String {
        switch self {
        case .monday: return "Lun"
        case .tuesday: return "Mar"
        case .wednesday: return "Mié"
        case .thursday: return "Jue"
        case .friday: return "Vie"
        case .saturday: return "Sáb"
        case .sunday: return "Dom"
        }
    }

    var name: String {
        switch self {
        case .monday: return "Lunes"
        case .tuesday: return "Martes"
        case .wednesday: return "Miércoles"
        case .thursday: return "Jueves"
        case .friday: return "Viernes"
        case .saturday: return "Sábado"
        case .sunday: return "Domingo"
        }
    }

    static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }
}
