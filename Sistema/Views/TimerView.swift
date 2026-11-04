import AudioToolbox
import Combine
import SwiftUI
import UserNotifications

/// Sonido y vibración del temporizador, más un aviso por si se bloquea el teléfono.
enum TimerFeedback {
    private static let endNoticeID = "wod-timer-end"

    static func play(_ cue: TimerCue) {
        switch cue {
        case .countdown:
            AudioServicesPlaySystemSound(1103)
        case .phaseChange:
            AudioServicesPlaySystemSound(1016)
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        case .finish:
            AudioServicesPlaySystemSound(1005)
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }

    static func scheduleEndNotice(in seconds: TimeInterval) {
        cancelEndNotice()
        guard seconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Tiempo"
        content.body = "El temporizador terminó."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: endNoticeID, content: content, trigger: trigger))
    }

    static func cancelEndNotice() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [endNoticeID])
    }
}

@MainActor
struct WODTimerView: View {
    @State var config: WODTimerConfig
    /// Se muestra sobre otra pantalla y necesita botón para cerrar.
    var isModal = false

    @Environment(\.dismiss) private var dismiss
    @State private var clock = TimerClock()
    @State private var reading: TimerReading?
    @State private var roundsDone = 0

    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let reading {
                running(reading)
            } else {
                setup
            }
        }
        .navigationTitle(reading == nil ? "Temporizador" : config.mode.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isModal {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { close() }
                }
            }
        }
        .onReceive(ticker) { _ in tick() }
        .onDisappear(perform: stopKeepingAwake)
    }

    // MARK: - Configuración

    private var setup: some View {
        Form {
            Section {
                Picker("Modo", selection: Binding(get: { config.mode }, set: { config = .standard($0) })) {
                    ForEach(WODMode.allCases) { Text($0.name).tag($0) }
                }
                .accessibilityIdentifier("timer.mode")
            } footer: {
                Text(config.mode.summary)
            }
            Section("Tiempos") {
                switch config.mode {
                case .forTime:
                    Stepper("Tope: \(config.minutes) min", value: $config.minutes, in: 1...90)
                case .amrap:
                    Stepper("Duración: \(config.minutes) min", value: $config.minutes, in: 1...90)
                case .emom:
                    Stepper("Cada: \(Format.seconds(config.workSeconds))", value: $config.workSeconds, in: 15...300, step: 15)
                    Stepper("Rondas: \(config.rounds)", value: $config.rounds, in: 1...60)
                case .tabata:
                    Stepper("Trabajo: \(Format.seconds(config.workSeconds))", value: $config.workSeconds, in: 5...300, step: 5)
                    Stepper("Descanso: \(Format.seconds(config.restSeconds))", value: $config.restSeconds, in: 0...300, step: 5)
                    Stepper("Rondas: \(config.rounds)", value: $config.rounds, in: 1...60)
                case .rest:
                    Stepper("Descanso: \(Format.seconds(config.restSeconds))", value: $config.restSeconds, in: 15...600, step: 15)
                }
                if config.mode != .rest {
                    Stepper("Preparación: \(Format.seconds(config.prepareSeconds))", value: $config.prepareSeconds, in: 0...60, step: 5)
                }
            }
            Section {
                Button {
                    start()
                } label: {
                    Label("Empezar", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("timer.start")
            }
            .listRowBackground(Color.clear)
        }
        .systemBackground()
    }

    // MARK: - En marcha

    private func running(_ reading: TimerReading) -> some View {
        let tint = color(reading)
        return ZStack {
            tint.opacity(0.22).ignoresSafeArea()
            VStack(spacing: 18) {
                Text(label(reading))
                    .font(Theme.mono(26, weight: .heavy))
                    .tracking(3)
                    .foregroundStyle(tint)
                Text(clockText(reading.displaySeconds))
                    .font(.system(size: 104, weight: .black, design: .monospaced))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("timer.clock")
                if let phase = reading.phase, phase.totalRounds > 1 {
                    Text("Ronda \(phase.round) de \(phase.totalRounds)")
                        .font(Theme.mono(20, weight: .bold))
                        .foregroundStyle(.white)
                }
                if config.mode == .amrap || config.mode == .forTime {
                    Button {
                        roundsDone += 1
                        Haptics.success()
                    } label: {
                        VStack {
                            Text("\(roundsDone)").font(Theme.mono(44, weight: .black))
                            Text("Tocá al terminar cada ronda").font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(tint)
                }
                HStack(spacing: 14) {
                    Button(role: .destructive) {
                        reset()
                    } label: {
                        Label("Reiniciar", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    if !reading.isFinished {
                        Button {
                            toggle()
                        } label: {
                            Label(clock.isRunning ? "Pausar" : "Seguir", systemImage: clock.isRunning ? "pause.fill" : "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("timer.toggle")
                    }
                }
                .controlSize(.large)
            }
            .padding(24)
        }
    }

    private func label(_ reading: TimerReading) -> String {
        if reading.isFinished { return "TIEMPO" }
        switch reading.phase?.kind {
        case .prepare: return "PREPARATE"
        case .rest: return "DESCANSO"
        default: return "TRABAJO"
        }
    }

    private func color(_ reading: TimerReading) -> Color {
        if reading.isFinished { return Theme.glow }
        switch reading.phase?.kind {
        case .prepare: return Theme.warning
        case .rest: return Theme.danger
        default: return Theme.success
        }
    }

    private func clockText(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Control

    private func start() {
        clock.reset()
        roundsDone = 0
        clock.start(at: Date())
        reading = config.reading(at: 0)
        keepAwake()
        TimerFeedback.scheduleEndNotice(in: TimeInterval(config.totalSeconds))
    }

    private func toggle() {
        let now = Date()
        if clock.isRunning {
            clock.pause(at: now)
            TimerFeedback.cancelEndNotice()
        } else {
            clock.start(at: now)
            TimerFeedback.scheduleEndNotice(in: TimeInterval(config.totalSeconds) - clock.elapsed(at: now))
        }
    }

    private func reset() {
        clock.reset()
        reading = nil
        stopKeepingAwake()
        TimerFeedback.cancelEndNotice()
    }

    private func close() {
        reset()
        dismiss()
    }

    private func tick() {
        guard let old = reading, clock.isRunning else { return }
        let new = config.reading(at: clock.elapsed(at: Date()))
        if let cue = config.cue(from: old, to: new) { TimerFeedback.play(cue) }
        reading = new
        if new.isFinished {
            clock.pause(at: Date())
            stopKeepingAwake()
            TimerFeedback.cancelEndNotice()
        }
    }

    private func keepAwake() { UIApplication.shared.isIdleTimerDisabled = true }
    private func stopKeepingAwake() { UIApplication.shared.isIdleTimerDisabled = false }
}
