import Foundation

enum WODMode: String, Codable, CaseIterable, Identifiable {
    case amrap, forTime, emom, tabata, mix, rest

    var id: String { rawValue }

    var name: String {
        switch self {
        case .forTime: return "For Time"
        case .amrap: return "AMRAP"
        case .emom: return "EMOM"
        case .tabata: return "Tabata"
        case .mix: return "Mix"
        case .rest: return "Descanso"
        }
    }

    var summary: String {
        switch self {
        case .forTime: return "Lo más rápido posible"
        case .amrap: return "El mayor número de rondas posible"
        case .emom: return "Un trabajo al inicio de cada intervalo"
        case .tabata: return "Trabajo y descanso por rondas"
        case .mix: return "Encadená varios temporizadores"
        case .rest: return "Cuenta regresiva entre series"
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
    var set = 1
    var totalSets = 1
    var label = ""
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

    /// Cuánto va de la fase, de 0 a 1.
    var fraction: Double {
        guard let phase, phase.seconds > 0 else { return 0 }
        return min(elapsedInPhase / TimeInterval(phase.seconds), 1)
    }
}

enum TimerCue: Equatable { case countdown, interval, phaseChange, finish }

struct WODTimerConfig: Identifiable, Equatable, Codable {
    /// Sin límite: en For Time, `minutes == 0`; se termina a mano.
    private static let openEndedSeconds = 24 * 3600
    private static let deathByRounds = 100

    var id = UUID()
    var mode: WODMode
    var minutes = 20
    var workSeconds = 20
    var restSeconds = 10
    var rounds = 8
    var prepareSeconds = 10
    /// Veces que se repite todo y descanso entre cada repetición.
    var sets = 1
    var restBetweenSets = 60
    /// Señal cada tantos segundos en For Time y AMRAP; 0 la apaga.
    var intervalSeconds = 0
    /// EMOM sin final: cada ronda suma una repetición hasta que no podás.
    var deathBy = false
    /// Partes de un Mix. Entre partes se descansa `restSeconds`.
    var segments: [WODTimerConfig] = []

    static func standard(_ mode: WODMode) -> WODTimerConfig {
        switch mode {
        case .forTime: return WODTimerConfig(mode: mode, minutes: 0)
        case .amrap: return WODTimerConfig(mode: mode, minutes: 10)
        case .emom: return WODTimerConfig(mode: mode, workSeconds: 60, rounds: 10)
        case .tabata: return WODTimerConfig(mode: mode)
        case .rest: return WODTimerConfig(mode: mode, restSeconds: 90, prepareSeconds: 0)
        case .mix:
            return WODTimerConfig(mode: mode, restSeconds: 60, segments: [segment(.amrap), segment(.tabata)])
        }
    }

    /// Una parte de un Mix: la preparación la pone el Mix.
    static func segment(_ mode: WODMode) -> WODTimerConfig {
        var config = standard(mode)
        config.prepareSeconds = 0
        if mode == .forTime { config.minutes = 10 }
        return config
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

    /// No tiene hora de fin: se termina a mano.
    var isOpenEnded: Bool {
        switch mode {
        case .forTime: return minutes == 0
        case .emom: return deathBy
        case .mix: return segments.contains(where: \.isOpenEnded)
        case .amrap, .tabata, .rest: return false
        }
    }

    var phases: [TimerPhase] {
        var result: [TimerPhase] = []
        if prepareSeconds > 0 {
            result.append(TimerPhase(kind: .prepare, seconds: prepareSeconds, round: 0, totalRounds: 0, label: "Preparate"))
        }
        let totalSets = max(sets, 1)
        for set in 1...totalSets {
            for var phase in bodyPhases {
                phase.set = set
                phase.totalSets = totalSets
                result.append(phase)
            }
            if set < totalSets && restBetweenSets > 0 {
                result.append(TimerPhase(kind: .rest, seconds: restBetweenSets, round: 0, totalRounds: 0, set: set,
                                         totalSets: totalSets, label: "Descanso entre series"))
            }
        }
        return result
    }

    private var bodyPhases: [TimerPhase] {
        switch mode {
        case .forTime:
            return [TimerPhase(kind: .work, seconds: minutes == 0 ? Self.openEndedSeconds : minutes * 60, round: 1, totalRounds: 1,
                               countsUp: true, label: mode.name)]
        case .amrap:
            return [TimerPhase(kind: .work, seconds: minutes * 60, round: 1, totalRounds: 1, label: mode.name)]
        case .emom:
            let total = deathBy ? Self.deathByRounds : max(rounds, 1)
            return (1...total).map { TimerPhase(kind: .work, seconds: workSeconds, round: $0, totalRounds: deathBy ? 0 : total, label: mode.name) }
        case .tabata:
            let total = max(rounds, 1)
            return (1...total).flatMap { round -> [TimerPhase] in
                var phases = [TimerPhase(kind: .work, seconds: workSeconds, round: round, totalRounds: total, label: "Trabajo")]
                if round < total && restSeconds > 0 {
                    phases.append(TimerPhase(kind: .rest, seconds: restSeconds, round: round, totalRounds: total, label: "Descanso"))
                }
                return phases
            }
        case .rest:
            return [TimerPhase(kind: .rest, seconds: restSeconds, round: 1, totalRounds: 1, label: mode.name)]
        case .mix:
            var result: [TimerPhase] = []
            for (index, segment) in segments.enumerated() {
                var part = segment
                part.prepareSeconds = 0
                result += part.phases
                if index < segments.count - 1 && restSeconds > 0 {
                    result.append(TimerPhase(kind: .rest, seconds: restSeconds, round: 0, totalRounds: 0, label: "Descanso"))
                }
            }
            return result
        }
    }

    var totalSeconds: Int { phases.reduce(0) { $0 + $1.seconds } }

    /// Duración de trabajo y descanso, sin contar la preparación.
    func activeSeconds(elapsed: TimeInterval) -> TimeInterval {
        max(elapsed - TimeInterval(prepareSeconds), 0)
    }

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

    /// La fase que sigue a la actual.
    func nextPhase(after reading: TimerReading) -> TimerPhase? {
        let all = phases
        return reading.phaseIndex + 1 < all.count ? all[reading.phaseIndex + 1] : nil
    }

    /// Qué sonido corresponde al pasar de una lectura a la siguiente.
    func cue(from old: TimerReading, to new: TimerReading) -> TimerCue? {
        if new.isFinished { return old.isFinished ? nil : .finish }
        if new.phaseIndex != old.phaseIndex { return .phaseChange }
        let before = Int(old.remaining.rounded(.up))
        let now = Int(new.remaining.rounded(.up))
        if now != before && (1...3).contains(now) { return .countdown }
        if intervalSeconds > 0, new.phase?.kind == .work, mode == .forTime || mode == .amrap,
           Int(new.elapsedInPhase) / intervalSeconds > Int(old.elapsedInPhase) / intervalSeconds {
            return .interval
        }
        return nil
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

    /// Adelanta el reloj, para saltar lo que queda de una fase.
    mutating func skip(_ seconds: TimeInterval) {
        accumulated += seconds
    }
}

/// Tono en WAV para el temporizador: sin archivos de sonido en la app.
enum TimerTone {
    static func wav(frequency: Double, duration: Double, sampleRate: Int = 44_100) -> Data {
        let count = Int(duration * Double(sampleRate))
        var samples = Data(capacity: count * 2)
        for index in 0..<count {
            let time = Double(index) / Double(sampleRate)
            // Entrada y salida suaves para que no truene el parlante.
            let edge = min(min(time, duration - time) / 0.005, 1)
            let value = Int16(sin(2 * .pi * frequency * time) * edge * 0.9 * Double(Int16.max))
            withUnsafeBytes(of: value.littleEndian) { samples.append(contentsOf: $0) }
        }
        var data = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        append(UInt32(36 + samples.count))
        data.append(Data("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))
        append(UInt16(2))
        append(UInt16(16))
        data.append(Data("data".utf8))
        append(UInt32(samples.count))
        data.append(samples)
        return data
    }
}
