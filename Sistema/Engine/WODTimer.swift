import Foundation

enum WODMode: String, CaseIterable, Identifiable {
    case forTime, amrap, emom, tabata, rest

    var id: String { rawValue }

    var name: String {
        switch self {
        case .forTime: return "For Time"
        case .amrap: return "AMRAP"
        case .emom: return "EMOM"
        case .tabata: return "Tabata"
        case .rest: return "Descanso"
        }
    }

    var summary: String {
        switch self {
        case .forTime: return "Cuenta hacia arriba hasta el tope de tiempo."
        case .amrap: return "Todas las rondas que podás antes de que acabe el tiempo."
        case .emom: return "Un trabajo al inicio de cada intervalo."
        case .tabata: return "Trabajo y descanso por rondas."
        case .rest: return "Cuenta regresiva entre series."
        }
    }
}

struct TimerPhase: Equatable {
    enum Kind: Equatable { case prepare, work, rest }

    var kind: Kind
    var seconds: Int
    var round: Int
    var totalRounds: Int
    var countsUp = false
}

struct TimerReading: Equatable {
    var phaseIndex: Int
    var phase: TimerPhase?
    var remaining: TimeInterval
    var elapsedInPhase: TimeInterval
    var isFinished: Bool

    /// Segundos enteros que muestra la pantalla.
    var displaySeconds: Int {
        if phase?.countsUp == true { return Int(elapsedInPhase) }
        return Int(remaining.rounded(.up))
    }
}

enum TimerCue: Equatable { case countdown, phaseChange, finish }

struct WODTimerConfig: Identifiable, Equatable {
    var id = UUID()
    var mode: WODMode
    var minutes = 20
    var workSeconds = 20
    var restSeconds = 10
    var rounds = 8
    var prepareSeconds = 10

    static func standard(_ mode: WODMode) -> WODTimerConfig {
        switch mode {
        case .forTime, .amrap: return WODTimerConfig(mode: mode)
        case .emom: return WODTimerConfig(mode: mode, workSeconds: 60, rounds: 10)
        case .tabata: return WODTimerConfig(mode: mode)
        case .rest: return WODTimerConfig(mode: mode, restSeconds: 90, prepareSeconds: 0)
        }
    }

    /// Temporizador listo para un bloque de la rutina.
    static func from(_ block: RoutineBlock) -> WODTimerConfig {
        let circuit = block.circuit
        switch circuit.resolvedFormat {
        case .amrap:
            return WODTimerConfig(mode: .amrap, minutes: Int(circuit.timeCapMinutes ?? 20))
        case .tabata:
            return WODTimerConfig(mode: .tabata, workSeconds: circuit.exercises.compactMap(\.seconds).first ?? 20,
                                  restSeconds: circuit.restBetweenRoundsSeconds ?? circuit.exercises.compactMap(\.restSeconds).first ?? 10,
                                  rounds: max(circuit.rounds, 1))
        case .circuit, .biSeries:
            return WODTimerConfig(mode: .rest, restSeconds: circuit.restBetweenRoundsSeconds ?? 60, prepareSeconds: 0)
        }
    }

    var phases: [TimerPhase] {
        var result: [TimerPhase] = []
        if prepareSeconds > 0 { result.append(TimerPhase(kind: .prepare, seconds: prepareSeconds, round: 0, totalRounds: 0)) }
        switch mode {
        case .forTime:
            result.append(TimerPhase(kind: .work, seconds: minutes * 60, round: 1, totalRounds: 1, countsUp: true))
        case .amrap:
            result.append(TimerPhase(kind: .work, seconds: minutes * 60, round: 1, totalRounds: 1))
        case .emom:
            for round in 1...max(rounds, 1) {
                result.append(TimerPhase(kind: .work, seconds: workSeconds, round: round, totalRounds: max(rounds, 1)))
            }
        case .tabata:
            for round in 1...max(rounds, 1) {
                result.append(TimerPhase(kind: .work, seconds: workSeconds, round: round, totalRounds: max(rounds, 1)))
                if round < rounds && restSeconds > 0 {
                    result.append(TimerPhase(kind: .rest, seconds: restSeconds, round: round, totalRounds: max(rounds, 1)))
                }
            }
        case .rest:
            result.append(TimerPhase(kind: .rest, seconds: restSeconds, round: 1, totalRounds: 1))
        }
        return result
    }

    var totalSeconds: Int { phases.reduce(0) { $0 + $1.seconds } }

    func reading(at elapsed: TimeInterval) -> TimerReading {
        var start: TimeInterval = 0
        let all = phases
        for (index, phase) in all.enumerated() {
            let end = start + TimeInterval(phase.seconds)
            if elapsed < end {
                return TimerReading(phaseIndex: index, phase: phase, remaining: end - elapsed,
                                    elapsedInPhase: max(elapsed - start, 0), isFinished: false)
            }
            start = end
        }
        return TimerReading(phaseIndex: all.count, phase: all.last, remaining: 0,
                            elapsedInPhase: TimeInterval(all.last?.seconds ?? 0), isFinished: true)
    }

    /// Qué sonido corresponde al pasar de una lectura a la siguiente.
    func cue(from old: TimerReading, to new: TimerReading) -> TimerCue? {
        if new.isFinished { return old.isFinished ? nil : .finish }
        if new.phaseIndex != old.phaseIndex { return .phaseChange }
        let before = Int(old.remaining.rounded(.up))
        let now = Int(new.remaining.rounded(.up))
        return now != before && (1...3).contains(now) ? .countdown : nil
    }
}

/// Reloj por hora real: bloquear el teléfono o pasar a segundo plano no lo atrasa.
struct TimerClock: Equatable {
    private(set) var accumulated: TimeInterval = 0
    private(set) var startedAt: Date?

    var isRunning: Bool { startedAt != nil }

    func elapsed(at now: Date) -> TimeInterval {
        accumulated + (startedAt.map { now.timeIntervalSince($0) } ?? 0)
    }

    mutating func start(at now: Date) {
        if startedAt == nil { startedAt = now }
    }

    mutating func pause(at now: Date) {
        accumulated = elapsed(at: now)
        startedAt = nil
    }

    mutating func reset() {
        accumulated = 0
        startedAt = nil
    }
}
