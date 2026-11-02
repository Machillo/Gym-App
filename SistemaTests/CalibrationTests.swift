import XCTest
@testable import Sistema

/// Simula años de entrenamiento con el reloj inyectado y verifica que los tiempos de llegada
/// a cada rango caigan en la tabla del README (5 sesiones/semana de 60 min, RPE 7).
/// Supuesto: los requisitos de cada prueba se cumplen en cuanto la prueba se habilita;
/// lo que se calibra es la curva de XP y los tiempos mínimos.
final class CalibrationTests: XCTestCase {
    private let daysPerYear = 365.25
    private let daysPerMonth = 30.4375

    private func simulate(compliance: Double, early: Bool, years: Double = 20) -> [Rank: Int] {
        let clock = FixedDateProvider(T.monday)
        var progress = PlayerProgress(startedAt: clock.now)
        var arrivals: [Rank: Int] = [.e: 0]
        var weekXP = 0
        for day in 0..<Int(years * daysPerYear) {
            let date = SistemaCalendar.addDays(day, to: T.monday)
            let weekday = SistemaCalendar.weekday(of: date)
            if weekday == .monday { weekXP = 0 }
            if weekday.rawValue <= 5 {
                clock.now = date.addingTimeInterval(early ? 4.5 * 3600 : 7 * 3600)
                let raw = XPEngine.rawXP(.init(dominantKind: .strength, minutes: 60, rpe: 7,
                                               compliance: compliance, startedAt: clock.now))
                let xp = XPEngine.cappedXP(raw: raw, earnedToday: 0, earnedThisWeek: weekXP)
                weekXP += xp
                progress.applyGain(xp, now: clock.now)
            }
            clock.now = date.addingTimeInterval(12 * 3600)
            if case .available = progress.trialAvailability(now: clock.now) {
                progress.passTrial(now: clock.now)
            }
            let rank = progress.position.rank
            if arrivals[rank] == nil { arrivals[rank] = day }
        }
        return arrivals
    }

    private func assertWithinTable(_ arrivals: [Rank: Int], label: String) {
        let windows: [(Rank, ClosedRange<Double>)] = [
            (.d, 28...62),
            (.c, 3.8 * daysPerMonth...5.5 * daysPerMonth),
            (.b, 1.35 * daysPerYear...1.8 * daysPerYear),
            (.a, 3.3 * daysPerYear...4.2 * daysPerYear),
            (.s, 6.5 * daysPerYear...8.0 * daysPerYear),
            (.ss, 10.0 * daysPerYear...12.0 * daysPerYear),
        ]
        for (rank, window) in windows {
            guard let day = arrivals[rank] else {
                XCTFail("\(label): nunca llegó a \(rank.letter)")
                continue
            }
            XCTAssertTrue(window.contains(Double(day)),
                          "\(label): llegó a \(rank.letter) en \(String(format: "%.2f", Double(day) / daysPerYear)) años, fuera de la tabla")
        }
    }

    func testPerfectComplianceMatchesTable() {
        let arrivals = simulate(compliance: 1, early: false)
        report(arrivals, label: "100 %")
        assertWithinTable(arrivals, label: "100 %")
    }

    func testPerfectComplianceWithEarlyBonusStillMatchesTable() {
        let arrivals = simulate(compliance: 1, early: true)
        report(arrivals, label: "100 % madrugada")
        assertWithinTable(arrivals, label: "100 % madrugada")
    }

    func testLowerComplianceIsSlower() {
        let perfect = simulate(compliance: 1, early: false)
        let eighty = simulate(compliance: 0.8, early: false)
        let sixty = simulate(compliance: 0.6, early: false)
        report(eighty, label: "80 %")
        report(sixty, label: "60 %")
        for rank in [Rank.c, .b, .a, .s, .ss] {
            let p = perfect[rank] ?? .max, e = eighty[rank] ?? .max, s = sixty[rank] ?? .max
            XCTAssertLessThan(p, e, "80 % debería tardar más en \(rank.letter)")
            XCTAssertLessThan(e, s, "60 % debería tardar más en \(rank.letter)")
        }
        XCTAssertGreaterThan(Double(eighty[.ss] ?? .max), 13 * daysPerYear)
        XCTAssertGreaterThan(Double(sixty[.ss] ?? .max), 17 * daysPerYear)
    }

    private func report(_ arrivals: [Rank: Int], label: String) {
        let line = Rank.allCases.map { rank -> String in
            guard let day = arrivals[rank] else { return "\(rank.letter): —" }
            return "\(rank.letter): \(String(format: "%.2f", Double(day) / daysPerYear)) a"
        }.joined(separator: " | ")
        print("[Calibración] \(label) → \(line)")
    }
}
