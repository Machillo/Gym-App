import Foundation
import UserNotifications

struct LocalNotification: Equatable {
    var id: String
    var date: Date
    var title: String
    var body: String
}

/// Calcula qué notificaciones locales programar (lógica pura, testeable).
enum NotificationPlanner {
    static let horizonDays = 14
    static let warningHour = 21

    static func plan(
        itinerary: ItinerarySnapshot?,
        routineNames: [Weekday: String],
        reminderHour: Int,
        reminderMinute: Int,
        loggedPlannedDays: Set<Date>,
        injuries: [InjuryPeriod],
        now: Date
    ) -> [LocalNotification] {
        guard let itinerary else { return [] }
        var result: [LocalNotification] = []
        let today = SistemaCalendar.startOfDay(now)
        for offset in 0..<horizonDays {
            let day = SistemaCalendar.addDays(offset, to: today)
            guard itinerary.covers(day), itinerary.isPlannedWeekday(day),
                  !injuries.contains(where: { $0.contains(day) }) else { continue }
            let key = dayKey(day)
            let weekday = SistemaCalendar.weekday(of: day)
            let routine = routineNames[weekday] ?? "tu entrenamiento"

            let morning = day.addingTimeInterval(Double(reminderHour * 3600 + reminderMinute * 60))
            if morning > now {
                result.append(LocalNotification(id: "morning-\(key)", date: morning,
                                                title: "El Sistema",
                                                body: "Misión de hoy: \(routine). No hay excusas."))
            }
            let warning = day.addingTimeInterval(Double(warningHour * 3600))
            if warning > now && !loggedPlannedDays.contains(day) {
                result.append(LocalNotification(id: "warning-\(key)", date: warning,
                                                title: "Advertencia del Sistema",
                                                body: "Quedan 3 horas antes de la penalización. Registrá tu sesión."))
            }
        }
        // Aviso 2 días antes de que venza el itinerario (9 a. m.).
        let expiry = SistemaCalendar.addDays(-2, to: SistemaCalendar.startOfDay(itinerary.end)).addingTimeInterval(9 * 3600)
        if expiry > now {
            result.append(LocalNotification(id: "itinerary-expiry", date: expiry,
                                            title: "Itinerario por vencer",
                                            body: "Tu itinerario vence en 2 días. Cargá el siguiente para evitar penalizaciones."))
        }
        return result.sorted { $0.date < $1.date }
    }

    private static func dayKey(_ day: Date) -> String {
        let c = SistemaCalendar.calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

protocol NotificationScheduling: AnyObject {
    func requestAuthorization()
    func replaceAll(with notifications: [LocalNotification])
}

final class LocalNotificationService: NotificationScheduling {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func replaceAll(with notifications: [LocalNotification]) {
        center.removeAllPendingNotificationRequests()
        for item in notifications.prefix(60) {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            let comps = SistemaCalendar.calendar.dateComponents(in: SistemaCalendar.timeZone, from: item.date)
            var trigger = DateComponents()
            trigger.calendar = SistemaCalendar.calendar
            trigger.timeZone = SistemaCalendar.timeZone
            trigger.year = comps.year
            trigger.month = comps.month
            trigger.day = comps.day
            trigger.hour = comps.hour
            trigger.minute = comps.minute
            let request = UNNotificationRequest(identifier: item.id, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: trigger, repeats: false))
            center.add(request)
        }
    }
}

/// No hace nada (pruebas y UI tests).
final class SilentNotificationService: NotificationScheduling {
    private(set) var scheduled: [LocalNotification] = []
    func requestAuthorization() {}
    func replaceAll(with notifications: [LocalNotification]) { scheduled = notifications }
}
