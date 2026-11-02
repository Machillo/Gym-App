import Foundation

/// Reloj inyectable: la app usa el del sistema y las pruebas uno controlado.
protocol DateProvider: AnyObject {
    var now: Date { get }
}

final class SystemDateProvider: DateProvider {
    var now: Date { Date() }
}

/// Reloj manual para pruebas y simulaciones.
final class FixedDateProvider: DateProvider {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }

    func advance(days: Int) {
        now = SistemaCalendar.addDays(days, to: now)
    }

    func advance(hours: Double) {
        now = now.addingTimeInterval(hours * 3600)
    }
}
