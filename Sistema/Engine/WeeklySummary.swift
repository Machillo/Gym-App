import Foundation

/// Marcas personales nuevas dentro de un periodo: superan todo lo anterior a ellas.
enum PersonalRecords {
    static func count(records: [MarkRecord], from start: Date, to end: Date) -> Int {
        var best: [String: Double] = [:]
        var total = 0
        for record in records.sorted(by: { $0.date < $1.date }) {
            if let previous = best[record.key] {
                let beats = record.higherIsBetter ? record.value > previous : record.value < previous
                if beats {
                    if record.date >= start && record.date < end { total += 1 }
                    best[record.key] = record.value
                }
            } else {
                best[record.key] = record.value
            }
        }
        return total
    }
}

struct WeeklySummary: Equatable {
    var weekStart: Date
    var sessions = 0
    var minutes = 0.0
    var volumeKg = 0.0
    var records = 0
    var classes = 0

    static func make(weekOf date: Date, sessions: [SessionDigest], volumes: [(date: Date, volume: Double)],
                     records: [MarkRecord]) -> WeeklySummary {
        let start = SistemaCalendar.startOfWeek(date)
        let end = SistemaCalendar.addDays(7, to: start)
        let inWeek = sessions.filter { $0.date >= start && $0.date < end }
        return WeeklySummary(
            weekStart: start,
            sessions: inWeek.count,
            minutes: inWeek.reduce(0) { $0 + $1.durationMinutes },
            volumeKg: volumes.filter { $0.date >= start && $0.date < end }.reduce(0) { $0 + $1.volume },
            records: PersonalRecords.count(records: records, from: start, to: end),
            classes: inWeek.reduce(0) { $0 + $1.classes.count }
        )
    }
}
