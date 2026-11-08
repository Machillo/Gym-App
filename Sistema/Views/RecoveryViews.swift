import Charts
import SwiftUI

extension RecoveryZone {
    var color: Color {
        switch self {
        case .ready: return Theme.accent
        case .moderate: return Theme.warning
        case .recover: return Theme.danger
        }
    }
}

private func clockText(_ date: Date) -> String {
    date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: SistemaCalendar.timeZone))
}

/// Etiqueta corta de buff o debuff.
private struct StatusChip: View {
    var text: String
    var symbol: String
    var color: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(Theme.raised))
    }
}

private struct HunterChips: View {
    let state: HunterState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if state.isRested {
                    StatusChip(text: "Descansado +\(Int(RecoveryEngine.restedXPBonus * 100)) % XP", symbol: "arrow.up.circle.fill", color: Theme.accent)
                }
                if state.hasDebuff {
                    StatusChip(text: String(format: "Deuda de sueño %.1f h", state.sleepDebt), symbol: "exclamationmark.triangle.fill", color: Theme.danger)
                }
                if state.sleepStreak > 0 {
                    StatusChip(text: Format.count(state.sleepStreak, "noche") + " de racha", symbol: "moon.stars.fill", color: .white)
                }
            }
        }
    }
}

/// Tarjeta de la mañana en Estado: puntaje, recomendación, buffs y hora de acostarse.
@MainActor
struct HunterStateCard: View {
    @Environment(GameService.self) private var game
    @State private var checkingIn = false

    var body: some View {
        let _ = game.revision
        let state = game.hunterState()
        VStack(alignment: .leading, spacing: 12) {
            PanelHeader(title: "Estado del cazador")
            if let report = state.report {
                HStack(spacing: 14) {
                    Text("\(report.score)")
                        .font(Theme.display(56, weight: .black))
                        .foregroundStyle(report.zone.color)
                        .accessibilityIdentifier("hunter.score")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(report.zone.label).font(.title3.bold())
                        Text(state.fight?.advice ?? report.zone.advice)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            } else {
                Text("Contale al Sistema cómo amaneciste y calcula tu recuperación.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            HunterChips(state: state)
            if let fight = state.fight, fight.daysLeft >= 0 {
                Label(fight.daysLeft == 0 ? "Hoy es la pelea" : "Faltan \(Format.count(fight.daysLeft, "día")) para la pelea", systemImage: "flag.checkered")
                    .font(.subheadline.weight(.semibold))
            }
            Label("Acostate a las \(clockText(state.bedtime))", systemImage: "bed.double.fill")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            HStack(spacing: 10) {
                if state.today?.checkIn == nil {
                    Button { checkingIn = true } label: {
                        Text("Cómo amanecí").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primaryAction)
                    .accessibilityIdentifier("hunter.checkIn")
                }
                NavigationLink { RecoveryView() } label: {
                    Text("Ver detalle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.secondaryAction)
                .accessibilityIdentifier("hunter.detail")
            }
        }
        .systemPanel()
        .sheet(isPresented: $checkingIn) { RecoveryCheckInSheet() }
    }
}

/// Cuatro toques y listo.
@MainActor
struct RecoveryCheckInSheet: View {
    @Environment(GameService.self) private var game
    @Environment(\.dismiss) private var dismiss
    @State private var quality: Int?
    @State private var soreness: Int?
    @State private var stress: Int?
    @State private var energy: Int?
    @State private var hours = 7.0
    @State private var needsHours = false

    private var isComplete: Bool { quality != nil && soreness != nil && stress != nil && energy != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("¿Cómo amaneciste?").font(Theme.display(34, weight: .black))
                scale("Cómo dormiste", low: "Pésimo", high: "Excelente", value: $quality, id: "quality")
                scale("Dolor muscular", low: "Nada", high: "Mucho", value: $soreness, id: "soreness")
                scale("Estrés", low: "Nada", high: "Mucho", value: $stress, id: "stress")
                scale("Energía", low: "Sin pila", high: "A tope", value: $energy, id: "energy")
                if needsHours {
                    Stepper(value: $hours, in: 0...14, step: 0.5) {
                        Text("Horas dormidas: ") + Text(String(format: "%.1f", hours)).bold()
                    }
                    .accessibilityIdentifier("checkin.hours")
                }
                Button {
                    guard let quality, let soreness, let stress, let energy else { return }
                    game.saveCheckIn(RecoveryCheckIn(sleepQuality: quality, soreness: soreness, stress: stress, energy: energy),
                                     manualSleepHours: needsHours ? hours : nil)
                    Haptics.success()
                    dismiss()
                } label: {
                    Text("Listo").frame(maxWidth: .infinity)
                }
                .buttonStyle(.primaryAction)
                .disabled(!isComplete)
                .accessibilityIdentifier("checkin.save")
            }
            .padding(20)
        }
        .background(Theme.background.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationBackground(Theme.background)
        .onAppear { needsHours = game.recoveryRecord(for: game.now)?.sleepHours == nil }
    }

    private func scale(_ title: String, low: String, high: String, value: Binding<Int?>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { number in
                    Button {
                        value.wrappedValue = number
                        Haptics.tap()
                    } label: {
                        Text("\(number)")
                            .font(Theme.display(24, weight: .bold))
                            .foregroundStyle(value.wrappedValue == number ? Theme.onAccent : .white)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(value.wrappedValue == number ? Theme.accent : Theme.raised))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title): \(number) de 5")
                    .accessibilityIdentifier("checkin.\(id).\(number)")
                }
            }
            HStack {
                Text(low)
                Spacer()
                Text(high)
            }
            .font(.caption)
            .foregroundStyle(Theme.secondaryText)
        }
    }
}

/// Detalle: de qué sale el puntaje, hora de levantarse, modo pelea y patrones.
@MainActor
struct RecoveryView: View {
    @Environment(GameService.self) private var game
    @State private var wake = Date()
    @State private var hasFight = false
    @State private var fightDate = Date()
    @State private var loaded = false

    private struct NightBar: Identifiable {
        var id: Date { day }
        var day: Date
        var hours: Double
        var record: Bool
    }

    private var nights: [NightBar] {
        let records = game.daysWithRecords()
        let start = SistemaCalendar.addDays(-29, to: SistemaCalendar.startOfDay(game.now))
        return game.recoveryRecords().filter { $0.day >= start }.compactMap { r in
            r.sleepHours.map { NightBar(day: r.day, hours: $0, record: records.contains(r.day)) }
        }
    }

    var body: some View {
        let _ = game.revision
        let state = game.hunterState()
        List {
            if game.needsRecoveryPermission {
                Section {
                    Button {
                        Task { await game.connectHealth() }
                    } label: {
                        Label("Permitir sueño, pulso y HRV en Salud", systemImage: "heart.fill")
                    }
                    .accessibilityIdentifier("recovery.permission")
                }
                .listRowBackground(Theme.panel)
            }

            if let report = state.report {
                Section {
                    ForEach(report.components, id: \.name) { component in
                        HStack {
                            Text(component.name)
                            Spacer()
                            Text("\(Int(component.value.rounded()))").font(Theme.mono(16, weight: .bold))
                        }
                    }
                } header: {
                    Text("De qué sale tu \(report.score)")
                } footer: {
                    Text(report.calibrationDaysLeft > 0
                         ? "HRV y pulso entran al puntaje cuando haya 7 días con datos. Faltan \(report.calibrationDaysLeft)."
                         : "Comparado con tus propios últimos 28 días.")
                }
                .listRowBackground(Theme.panel)
            }

            Section {
                DatePicker("Me levanto a las", selection: $wake, displayedComponents: .hourAndMinute)
                    .onChange(of: wake) { _, value in
                        guard loaded else { return }
                        let c = SistemaCalendar.calendar.dateComponents([.hour, .minute], from: value)
                        game.setWakeTime(hour: c.hour ?? 4, minute: c.minute ?? 30)
                    }
                LabeledContent("Acostate a las", value: clockText(state.bedtime))
            } header: {
                Text("Hora de acostarte")
            } footer: {
                Text(state.wakeIsSet ? "Te avisamos 30 minutos antes. iOS no deja leer tu alarma: si la cambiás, cambiala acá también."
                                     : "iOS no deja leer tu alarma. Poné a qué hora te levantás y te avisamos 30 minutos antes.")
            }
            .listRowBackground(Theme.panel)

            Section {
                Toggle("Tengo pelea programada", isOn: $hasFight)
                    .onChange(of: hasFight) { _, on in
                        guard loaded else { return }
                        game.setFightDate(on ? fightDate : nil)
                    }
                if hasFight {
                    DatePicker("Fecha", selection: $fightDate, in: game.now..., displayedComponents: .date)
                        .onChange(of: fightDate) { _, value in
                            guard loaded else { return }
                            game.setFightDate(value)
                        }
                }
            } header: {
                Text("Modo pelea")
            } footer: {
                Text("En las últimas \(RecoveryEngine.fightModeDays / 7) semanas la meta de sueño sube a 8 horas y el puntaje exige más para decir Listo.")
            }
            .listRowBackground(Theme.panel)

            if !nights.isEmpty {
                Section {
                    Chart(nights) { night in
                        BarMark(x: .value("Día", night.day, unit: .day), y: .value("Horas", night.hours))
                            .foregroundStyle(night.hours >= RecoveryEngine.sleepGoalHours ? Theme.accent : Theme.raised)
                        if night.record {
                            PointMark(x: .value("Día", night.day, unit: .day), y: .value("Horas", night.hours + 0.6))
                                .symbol(.diamond)
                                .foregroundStyle(Theme.warning)
                        }
                        RuleMark(y: .value("Meta", RecoveryEngine.sleepGoalHours))
                            .foregroundStyle(Color.white.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    .chartXScale(domain: SistemaCalendar.addDays(-29, to: SistemaCalendar.startOfDay(game.now))...SistemaCalendar.addDays(1, to: SistemaCalendar.startOfDay(game.now)))
                    .frame(height: 180)
                } header: {
                    Text("Sueño de los últimos 30 días")
                } footer: {
                    Text("En verde, 7 horas o más. El rombo marca los días con marca nueva.")
                }
                .listRowBackground(Theme.panel)
            }

            patternsSection(game.sleepPatterns())
        }
        .systemBackground()
        .navigationTitle("Recuperación")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    @ViewBuilder
    private func patternsSection(_ patterns: SleepPatterns) -> some View {
        Section {
            if patterns.isMeaningful {
                patternRow("Sesiones", rested: "\(patterns.rested.sessions)", short: "\(patterns.short.sessions)")
                patternRow("Cumplimiento", rested: Format.percent(patterns.rested.averageCompliance), short: Format.percent(patterns.short.averageCompliance))
                patternRow("Marcas por sesión", rested: String(format: "%.1f", patterns.rested.improvementsPerSession),
                           short: String(format: "%.1f", patterns.short.improvementsPerSession))
                patternRow("Esfuerzo en clases", rested: patterns.rested.classAverageRPE.map { String(format: "%.1f", $0) } ?? "—",
                           short: patterns.short.classAverageRPE.map { String(format: "%.1f", $0) } ?? "—")
            } else {
                Text("Hacen falta al menos \(RecoveryEngine.minPatternSessions) sesiones después de dormir bien y \(RecoveryEngine.minPatternSessions) después de dormir poco.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        } header: {
            Text("Tu rendimiento según el sueño")
        } footer: {
            if patterns.isMeaningful { Text("Primera columna: 7 horas o más la noche anterior. Segunda: menos de 7.") }
        }
        .listRowBackground(Theme.panel)
    }

    private func patternRow(_ title: String, rested: String, short: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(rested).font(Theme.mono(15, weight: .bold)).foregroundStyle(Theme.accent).frame(minWidth: 52, alignment: .trailing)
            Text(short).font(Theme.mono(15, weight: .bold)).frame(minWidth: 52, alignment: .trailing)
        }
    }

    private func load() {
        guard !loaded else { return }
        let time = game.wakeTime()
        wake = SistemaCalendar.startOfDay(game.now).addingTimeInterval(Double(time.hour * 3600 + time.minute * 60))
        if let date = game.player()?.fightDate {
            hasFight = true
            fightDate = date
        } else {
            fightDate = SistemaCalendar.addDays(42, to: game.now)
        }
        DispatchQueue.main.async { loaded = true }
    }
}
