import AVFoundation
import AudioToolbox
import SwiftUI
import UserNotifications

/// Lo que se lleva a la sesión al terminar un AMRAP.
struct WODTimerResult: Equatable {
    var rounds: Int
    var minutes: Double
}

extension WODMode {
    var tint: Color {
        switch self {
        case .amrap: return Theme.warning
        case .forTime: return Color(red: 0.38, green: 0.64, blue: 1.0)
        case .emom: return Color(red: 0.72, green: 0.45, blue: 1.0)
        case .tabata: return Theme.success
        case .mix: return Color(red: 0.33, green: 0.85, blue: 0.80)
        case .rest: return Theme.danger
        }
    }

    var symbol: String {
        switch self {
        case .amrap: return "repeat"
        case .forTime: return "stopwatch"
        case .emom: return "metronome"
        case .tabata: return "bolt.fill"
        case .mix: return "square.stack.3d.up.fill"
        case .rest: return "pause.circle"
        }
    }
}

/// Última configuración de cada modo. Si no se puede leer, se vuelve a la estándar.
enum TimerMemory {
    private static func key(_ mode: WODMode) -> String { "timer.last.\(mode.rawValue)" }

    static func load(_ mode: WODMode) -> WODTimerConfig {
        guard let data = UserDefaults.standard.data(forKey: key(mode)),
              let config = try? JSONDecoder().decode(WODTimerConfig.self, from: data) else { return .standard(mode) }
        return config
    }

    static func save(_ config: WODTimerConfig) {
        if let data = try? JSONEncoder().encode(config) { UserDefaults.standard.set(data, forKey: key(config.mode)) }
    }
}

/// Sonido, vibración y aviso por si se bloquea el teléfono.
@MainActor
final class TimerFeedback {
    private static let endNoticeID = "wod-timer-end"
    private let countdown = TimerFeedback.player(frequency: 880, duration: 0.12)
    private let interval = TimerFeedback.player(frequency: 660, duration: 0.2)
    private let change = TimerFeedback.player(frequency: 1320, duration: 0.4)
    private let finish = TimerFeedback.player(frequency: 1760, duration: 0.9)

    private static func player(frequency: Double, duration: Double) -> AVAudioPlayer? {
        let player = try? AVAudioPlayer(data: TimerTone.wav(frequency: frequency, duration: duration))
        player?.prepareToPlay()
        return player
    }

    /// `.playback` suena aunque el iPhone esté en silencio; `.mixWithOthers` deja seguir tu música.
    func activate() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func play(_ cue: TimerCue) {
        let player: AVAudioPlayer?
        switch cue {
        case .countdown: player = countdown
        case .interval: player = interval
        case .phaseChange: player = change
        case .finish: player = finish
        }
        player?.currentTime = 0
        player?.play()
        if cue == .phaseChange || cue == .finish { AudioServicesPlaySystemSound(kSystemSoundID_Vibrate) }
    }

    func scheduleEndNotice(in seconds: TimeInterval) {
        cancelEndNotice()
        guard seconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Tiempo"
        content.body = "El temporizador terminó."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: Self.endNoticeID, content: content, trigger: trigger))
    }

    func cancelEndNotice() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.endNoticeID])
    }
}

// MARK: - Menú

@MainActor
struct WODTimerHomeView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 6) {
                    Text("Temporizador")
                        .font(Theme.display(40, weight: .black))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 18)
                ForEach(WODMode.allCases) { mode in
                    NavigationLink {
                        WODTimerSetupView(config: TimerMemory.load(mode))
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: mode.symbol)
                                .font(.title2)
                                .frame(width: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.name.uppercased())
                                    .font(Theme.mono(20, weight: .heavy))
                                    .tracking(1)
                                Text(mode.summary)
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.bold())
                        }
                        .foregroundStyle(mode.tint)
                        .systemPanel(tint: mode.tint)
                    }
                    .accessibilityIdentifier("timer.mode.\(mode.rawValue)")
                }
            }
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Configuración

/// Un valor editable: lo que muestra su caja y qué opciones da.
private struct TimerField: Identifiable {
    var title: String
    var keyPath: WritableKeyPath<WODTimerConfig, Int>
    var values: [Int]
    var text: (Int) -> String
    var id: String { title }
}

private enum TimerFormat {
    static func clock(_ seconds: Int) -> String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }
    static func minutes(_ value: Int) -> String { "\(value)" }
    static func limit(_ value: Int) -> String { value == 0 ? "ninguno" : "\(value) min" }
    static func interval(_ value: Int) -> String { value == 0 ? "ninguna" : clock(value) }
    static func plain(_ value: Int) -> String { "\(value)" }
}

private extension TimerField {
    static let minutes = TimerField(title: "Minutos", keyPath: \.minutes, values: Array(1...90), text: TimerFormat.minutes)
    static let limit = TimerField(title: "Límite de tiempo", keyPath: \.minutes, values: Array(0...90), text: TimerFormat.limit)
    static let every = TimerField(title: "Cada", keyPath: \.workSeconds, values: Array(stride(from: 15, through: 600, by: 15)), text: TimerFormat.clock)
    static let work = TimerField(title: "Trabajo", keyPath: \.workSeconds, values: Array(stride(from: 5, through: 600, by: 5)), text: TimerFormat.clock)
    static let rest = TimerField(title: "Descanso", keyPath: \.restSeconds, values: Array(stride(from: 0, through: 600, by: 5)), text: TimerFormat.clock)
    static let longRest = TimerField(title: "Descanso", keyPath: \.restSeconds, values: Array(stride(from: 15, through: 900, by: 15)), text: TimerFormat.clock)
    static let segmentRest = TimerField(title: "Descanso entre partes", keyPath: \.restSeconds, values: Array(stride(from: 0, through: 600, by: 15)), text: TimerFormat.clock)
    static let rounds = TimerField(title: "Rondas", keyPath: \.rounds, values: Array(1...60), text: TimerFormat.plain)
    static let sets = TimerField(title: "Series", keyPath: \.sets, values: Array(2...20), text: TimerFormat.plain)
    static let setRest = TimerField(title: "Descanso entre series", keyPath: \.restBetweenSets, values: Array(stride(from: 0, through: 900, by: 15)), text: TimerFormat.clock)
    static let signal = TimerField(title: "Señal cada", keyPath: \.intervalSeconds, values: [0] + Array(stride(from: 15, through: 600, by: 15)), text: TimerFormat.interval)
    static let prepare = TimerField(title: "Preparación", keyPath: \.prepareSeconds, values: Array(stride(from: 0, through: 60, by: 5)), text: TimerFormat.clock)
}

/// Las cajas de un modo. Se reutiliza para las partes de un Mix.
private struct TimerConfigFields: View {
    @Binding var config: WODTimerConfig
    var showsPrepare = true
    @State private var editing: TimerField?

    private var tint: Color { config.mode.tint }

    var body: some View {
        VStack(spacing: 12) {
            switch config.mode {
            case .amrap:
                box(.minutes)
            case .forTime:
                box(.limit)
            case .emom:
                box(.every)
                if config.deathBy {
                    Text("Cada ronda sumá una repetición, hasta que no podás terminar a tiempo.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    box(.rounds)
                }
            case .tabata:
                box(.rounds)
                box(.work)
                box(.rest)
            case .rest:
                box(.longRest)
            case .mix:
                box(.segmentRest)
            }

            if config.sets > 1 {
                box(.sets)
                box(.setRest)
                optionButton("Quitar series", symbol: "minus.circle") { config.sets = 1 }
            } else if config.mode != .rest {
                optionButton("Añadir series", symbol: "plus.circle") { config.sets = 2 }
            }
            if config.mode == .forTime || config.mode == .amrap {
                if config.intervalSeconds > 0 {
                    box(.signal)
                    optionButton("Quitar señal", symbol: "minus.circle") { config.intervalSeconds = 0 }
                } else {
                    optionButton("Añadir señal por intervalo", symbol: "plus.circle") { config.intervalSeconds = 60 }
                }
            }
            if config.mode == .emom {
                optionButton(config.deathBy ? "Volver a rondas fijas" : "Hasta no poder (Death By)",
                             symbol: config.deathBy ? "minus.circle" : "infinity.circle") { config.deathBy.toggle() }
            }
            if showsPrepare && config.mode != .rest { box(.prepare) }
        }
        .sheet(item: $editing) { field in
            TimerValuePicker(field: field, config: $config, tint: tint)
                .presentationDetents([.medium])
        }
    }

    private func box(_ field: TimerField) -> some View {
        Button {
            editing = field
        } label: {
            HStack(spacing: 14) {
                Text(field.text(config[keyPath: field.keyPath]))
                    .font(Theme.mono(30, weight: .black))
                    .foregroundStyle(.white)
                    .frame(minWidth: 112, minHeight: 66)
                    .padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.panel))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(tint.opacity(0.6), lineWidth: 1))
                Text(field.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
        }
        .accessibilityIdentifier("timer.field.\(field.title)")
    }

    private func optionButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
    }
}

private struct TimerValuePicker: View {
    let field: TimerField
    @Binding var config: WODTimerConfig
    let tint: Color
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Picker(field.title, selection: $config[dynamicMember: field.keyPath]) {
                ForEach(field.values, id: \.self) { value in
                    Text(field.text(value)).font(Theme.mono(22, weight: .bold)).tag(value)
                }
            }
            .pickerStyle(.wheel)
            .navigationTitle(field.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }.tint(tint)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

@MainActor
struct WODTimerSetupView: View {
    @State var config: WODTimerConfig
    /// Se muestra sobre otra pantalla y necesita botón para cerrar.
    var isModal = false
    /// Recibe rondas y tiempo al terminar, cuando el temporizador se abrió desde un bloque.
    var onResult: ((WODTimerResult) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var running: WODTimerConfig?
    @State private var editingSegment: UUID?

    private var tint: Color { config.mode.tint }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        Text(config.mode.name.uppercased())
                            .font(Theme.display(44, weight: .black))
                            .foregroundStyle(tint)
                        Text(description)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .padding(.top, 10)
                    if config.mode == .mix { segments }
                    TimerConfigFields(config: $config)
                        .systemPanel(tint: tint)
                }
                .padding()
            }
            startButton
                .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isModal {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .fullScreenCover(item: $running) { active in
            WODTimerRunView(config: active, onResult: onResult.map { save in
                { result in
                    save(result)
                    dismiss()
                }
            })
        }
        .sheet(item: Binding(get: { editingSegment.map(SegmentID.init) }, set: { editingSegment = $0?.id })) { segment in
            if let index = config.segments.firstIndex(where: { $0.id == segment.id }) {
                NavigationStack {
                    ScrollView {
                        TimerConfigFields(config: $config.segments[index], showsPrepare: false)
                            .systemPanel(tint: config.segments[index].mode.tint)
                            .padding()
                    }
                    .background(Theme.background.ignoresSafeArea())
                    .navigationTitle(config.segments[index].mode.name)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Listo") { editingSegment = nil }
                        }
                    }
                }
                .preferredColorScheme(.dark)
            }
        }
    }

    private struct SegmentID: Identifiable { var id: UUID }

    private var description: String {
        switch config.mode {
        case .amrap: return "El mayor número de rondas posible en \(config.minutes) min"
        case .forTime: return config.minutes == 0 ? "Lo más rápido posible, sin límite" : "Lo más rápido posible, máximo \(config.minutes) min"
        case .emom:
            let every = config.workSeconds == 60 ? "Cada minuto" : "Cada \(Format.seconds(config.workSeconds))"
            return config.deathBy ? "\(every), hasta no poder" : "\(every), por \(config.rounds) rondas"
        default: return config.mode.summary
        }
    }

    private var segments: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelHeader(title: "Partes", symbol: "square.stack.3d.up.fill", tint: tint)
            ForEach(Array(config.segments.enumerated()), id: \.element.id) { index, segment in
                HStack {
                    Button {
                        editingSegment = segment.id
                    } label: {
                        HStack {
                            Text("\(index + 1).").font(Theme.mono(14, weight: .bold))
                            Image(systemName: segment.mode.symbol)
                            Text(segment.mode.name).font(.headline)
                            Spacer()
                            Text(segment.isOpenEnded ? "sin límite" : TimerFormat.clock(segment.totalSeconds))
                                .font(Theme.mono(14))
                        }
                        .foregroundStyle(segment.mode.tint)
                    }
                    Button(role: .destructive) {
                        config.segments.remove(at: index)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Quitar \(segment.mode.name)")
                }
            }
            Menu {
                ForEach(WODMode.allCases.filter { $0 != .mix }) { mode in
                    Button(mode.name) { config.segments.append(.segment(mode)) }
                }
            } label: {
                Label("Agregar parte", systemImage: "plus.circle").font(.subheadline)
            }
        }
        .systemPanel(tint: tint)
    }

    private var startButton: some View {
        Button {
            TimerMemory.save(config)
            var active = config
            active.id = UUID()
            running = active
        } label: {
            VStack(spacing: 2) {
                Text("COMENZAR").font(Theme.mono(22, weight: .heavy)).tracking(2)
                Text(config.isOpenEnded ? "Sin límite: terminás vos" : "Tiempo total: \(TimerFormat.clock(config.totalSeconds))")
                    .font(.caption)
            }
            .foregroundStyle(Theme.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint))
        }
        .disabled(config.mode == .mix && config.segments.isEmpty)
        .accessibilityIdentifier("timer.start")
    }
}

// MARK: - En marcha

@MainActor
struct WODTimerRunView: View {
    let config: WODTimerConfig
    var onResult: ((WODTimerResult) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var clock = TimerClock()
    @State private var reading: TimerReading?
    @State private var finished = false
    @State private var finalElapsed: TimeInterval = 0
    @State private var roundsDone = 0
    @State private var feedback = TimerFeedback()

    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        let current = reading ?? config.reading(at: 0)
        let tint = color(current)
        ZStack {
            tint.opacity(finished ? 0.12 : 0.2).ignoresSafeArea()
            Theme.background.opacity(0.65).ignoresSafeArea()
            VStack(spacing: 18) {
                Text(config.mode.name.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.secondaryText)
                Spacer(minLength: 0)
                dial(current, tint: tint)
                detail(current)
                Spacer(minLength: 0)
                if countsRounds { roundCounter(tint) }
                controls(current, tint: tint)
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: start)
        .onDisappear(perform: stop)
        .onReceive(ticker) { _ in tick() }
    }

    private var countsRounds: Bool { config.mode == .amrap || config.mode == .forTime }

    private func dial(_ current: TimerReading, tint: Color) -> some View {
        ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: 14)
            if !finished && !config.isOpenEnded || current.phase?.countsUp == false {
                Circle()
                    .trim(from: 0, to: finished ? 1 : 1 - current.fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 4) {
                Text(label(current))
                    .font(Theme.mono(18, weight: .heavy))
                    .tracking(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(tint)
                Text(TimerFormat.clock(finished ? Int(config.activeSeconds(elapsed: finalElapsed)) : current.displaySeconds))
                    .font(Theme.display(92, weight: .black))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("timer.clock")
            }
            .padding(30)
        }
        .frame(maxWidth: 340, maxHeight: 340)
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func detail(_ current: TimerReading) -> some View {
        VStack(spacing: 4) {
            if !finished, let phase = current.phase {
                if config.deathBy && phase.kind == .work {
                    Text("Ronda \(phase.round): \(phase.round) reps").font(Theme.mono(20, weight: .bold))
                } else if phase.totalRounds > 1 {
                    Text("Ronda \(phase.round) de \(phase.totalRounds)").font(Theme.mono(20, weight: .bold))
                }
                if phase.totalSets > 1 {
                    Text("Serie \(phase.set) de \(phase.totalSets)").font(Theme.mono(14, weight: .semibold))
                }
                if let next = config.nextPhase(after: current), !config.deathBy {
                    Text("Sigue: \(next.label) · \(TimerFormat.clock(next.seconds))")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            } else if finished {
                Text("Tiempo total").font(.footnote).foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(minHeight: 60)
    }

    private func roundCounter(_ tint: Color) -> some View {
        Button {
            roundsDone += 1
            Haptics.success()
        } label: {
            VStack(spacing: 0) {
                Text("\(roundsDone)").font(Theme.mono(40, weight: .black)).foregroundStyle(.white)
                Text(finished ? "Rondas" : "Tocá al terminar cada ronda").font(.caption).foregroundStyle(tint)
            }
            .frame(maxWidth: .infinity)
            .systemPanel(tint: tint)
        }
        .disabled(finished)
        .accessibilityIdentifier("timer.round")
    }

    @ViewBuilder
    private func controls(_ current: TimerReading, tint: Color) -> some View {
        if finished {
            VStack(spacing: 10) {
                if let onResult {
                    Button {
                        onResult(WODTimerResult(rounds: roundsDone, minutes: (config.activeSeconds(elapsed: finalElapsed) / 6).rounded() / 10))
                        dismiss()
                    } label: {
                        Text("Guardar en la sesión").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primaryAction)
                    .accessibilityIdentifier("timer.saveResult")
                }
                HStack(spacing: 12) {
                    Button {
                        start()
                    } label: {
                        Text("Repetir").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.secondaryAction)
                    Button {
                        dismiss()
                    } label: {
                        Text("Cerrar").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.secondaryAction)
                    .accessibilityIdentifier("timer.close")
                }
            }
            .controlSize(.large)
        } else {
            HStack(spacing: 12) {
                Button {
                    finish(playing: true)
                } label: {
                    Label("Terminar", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.secondaryAction)
                .tint(Theme.danger)
                .accessibilityIdentifier("timer.end")
                if config.nextPhase(after: current) != nil {
                    Button {
                        skip(current)
                    } label: {
                        Image(systemName: "forward.end.fill")
                    }
                    .buttonStyle(.secondaryAction)
                    .accessibilityLabel("Saltar esta fase")
                }
                Button {
                    toggle()
                } label: {
                    Label(clock.isRunning ? "Pausar" : "Seguir", systemImage: clock.isRunning ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.primaryAction)
                .tint(tint)
                .accessibilityIdentifier("timer.toggle")
            }
            .controlSize(.large)
        }
    }

    private func label(_ reading: TimerReading) -> String {
        if finished { return "TIEMPO" }
        return (reading.phase?.label ?? "").uppercased()
    }

    private func color(_ reading: TimerReading) -> Color {
        if finished { return Theme.glow }
        switch reading.phase?.kind {
        case .prepare: return Theme.warning
        case .rest: return Theme.danger
        default: return config.mode == .rest ? Theme.danger : (config.mode == .tabata ? Theme.success : config.mode.tint)
        }
    }

    // MARK: - Control

    private func start() {
        clock.reset()
        finished = false
        finalElapsed = 0
        roundsDone = 0
        let now = Date()
        clock.start(at: now)
        reading = config.reading(at: 0)
        UIApplication.shared.isIdleTimerDisabled = true
        feedback.activate()
        scheduleNotice(now: now)
    }

    private func stop() {
        UIApplication.shared.isIdleTimerDisabled = false
        feedback.cancelEndNotice()
        feedback.deactivate()
    }

    private func scheduleNotice(now: Date) {
        guard !config.isOpenEnded else { return }
        feedback.scheduleEndNotice(in: TimeInterval(config.totalSeconds) - clock.elapsed(at: now))
    }

    private func toggle() {
        let now = Date()
        if clock.isRunning {
            clock.pause(at: now)
            feedback.cancelEndNotice()
        } else {
            clock.start(at: now)
            scheduleNotice(now: now)
        }
    }

    private func skip(_ current: TimerReading) {
        clock.skip(current.remaining)
        scheduleNotice(now: Date())
    }

    private func finish(playing: Bool) {
        let now = Date()
        finalElapsed = min(clock.elapsed(at: now), TimeInterval(config.totalSeconds))
        clock.pause(at: now)
        finished = true
        if playing { feedback.play(.finish) }
        UIApplication.shared.isIdleTimerDisabled = false
        feedback.cancelEndNotice()
    }

    private func tick() {
        guard let old = reading, clock.isRunning, !finished else { return }
        let new = config.reading(at: clock.elapsed(at: Date()))
        if new.isFinished {
            reading = new
            finish(playing: true)
            return
        }
        if let cue = config.cue(from: old, to: new) { feedback.play(cue) }
        reading = new
    }
}
