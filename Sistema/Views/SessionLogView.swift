import SwiftData
import SwiftUI

/// Registro de sesión: lo prescrito precargado y campos para lo real.
@MainActor
struct SessionLogView: View {
    let mode: SessionLogMode

    @Environment(GameService.self) private var game
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Routine.name) private var routines: [Routine]

    @State private var title = ""
    @State private var date = Date()
    @State private var results: [BlockResult] = []
    @State private var rpe = 7
    @State private var notes = ""
    @State private var duration: Double = 60
    @State private var routineID: UUID?
    @State private var loaded = false
    @State private var lastPerformances = LastPerformanceIndex()
    @State private var timer: TimerRequest?
    @State private var bodyWeight: Double?
    @State private var bodyWeightUnit: WeightUnit = .kg

    var body: some View {
        Form {
            Section("Sesión") {
                if !isClassLog {
                    TextField("Título", text: $title)
                }
                if let day = lateDay {
                    DatePicker("Fecha y hora", selection: $date, in: day...SistemaCalendar.addDays(1, to: day).addingTimeInterval(-1))
                } else {
                    DatePicker("Fecha y hora", selection: $date)
                }
                if !isClassLog {
                    Button {
                        openTimer(for: results.first { $0.prescribed.kind == .circuit })
                    } label: {
                        Label("Abrir temporizador", systemImage: "timer")
                    }
                    .accessibilityIdentifier("log.timer")
                }
                if case .free = mode {
                    Picker("Basar en rutina", selection: $routineID) {
                        Text("Ninguna").tag(UUID?.none)
                        ForEach(routines) { r in Text(r.name).tag(UUID?.some(r.id)) }
                    }
                    .onChange(of: routineID) { _, id in
                        if let routine = routines.first(where: { $0.id == id }) { load(routine) }
                    }
                    Menu {
                        ForEach(BlockKind.allCases) { kind in
                            Button(kind.name) { addFreeBlock(kind) }
                        }
                    } label: {
                        Label("Agregar bloque", systemImage: "plus")
                    }
                }
            }

            ForEach($results) { $result in
                Section {
                    BlockResultEditor(result: $result, last: lastPerformances)
                    if result.prescribed.kind == .circuit {
                        Button {
                            openTimer(for: result)
                        } label: {
                            Label("Temporizador de este bloque", systemImage: "timer")
                        }
                    }
                } header: {
                    Label(result.prescribed.displayName, systemImage: result.prescribed.kind.symbol)
                } footer: {
                    Text("Prescrito: \(result.prescribed.summary) · Cumplimiento: \(Format.percent(ComplianceEngine.blockCompliance(result)))")
                }
            }
            .onDelete { results.remove(atOffsets: $0) }

            Section {
                Stepper("RPE: \(rpe)", value: $rpe, in: 1...10)
                    .accessibilityIdentifier("log.rpe")
                if !isClassLog {
                    NumberField(label: "Duración (min)", value: $duration, identifier: "log.duration")
                }
                TextField("Notas", text: $notes, axis: .vertical)
            } header: {
                Text("Esfuerzo")
            } footer: {
                Text(isClassLog ? "El XP depende de lo que duró. El sparring vale 25 % más y una pelea trae su premio aparte." : "La duración viene estimada y el XP depende de ella: poné lo que realmente duraste.")
            }

            if !isEditing {
                Section {
                    HStack {
                        Text("Peso al terminar")
                        Spacer()
                        TextField(lastWeightText ?? "—", value: $bodyWeight, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 80)
                            .accessibilityIdentifier("log.bodyWeight")
                        WeightUnitToggle(unit: $bodyWeightUnit)
                    }
                } header: {
                    Text("Peso corporal")
                } footer: {
                    Text(lastWeightText.map { "Último: \($0) \(bodyWeightUnit.symbol). Opcional: si lo llenás, queda como tu peso de hoy." }
                         ?? "Opcional: si lo llenás, queda como tu peso de hoy.")
                }
            }

            Section("Vista previa del Sistema") {
                let compliance = ComplianceEngine.sessionCompliance(results)
                HStack {
                    Text("Cumplimiento")
                    Spacer()
                    Text(Format.percent(compliance)).foregroundStyle(compliance < 0.5 ? Theme.danger : Theme.success)
                }
                HStack {
                    Text("XP estimado (antes de topes)")
                    Spacer()
                    Text("\(Int(previewXP(compliance: compliance).rounded()))")
                }
                if compliance < 0.5 && isPlanned && lateDay == nil {
                    Text("Menos de 50 %: al cerrar el día cuenta como media falta.")
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                }
                if !isClassLog {
                    Button("Rellenar con lo prescrito") {
                        results = results.map { BlockResult.asPrescribed($0.prescribed) }
                    }
                    .accessibilityIdentifier("log.fillPrescribed")
                }
            }
        }
        .systemBackground()
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") { save() }
                    .disabled(results.isEmpty || results.contains(where: \.prescribed.hasUnnamedExercise))
                    .accessibilityIdentifier("log.save")
            }
        }
        .onAppear(perform: setup)
        .fullScreenCover(item: $timer) { request in
            NavigationStack {
                WODTimerSetupView(config: request.config, isModal: true, onResult: resultHandler(for: request))
            }
        }
    }

    private func openTimer(for result: BlockResult?) {
        timer = TimerRequest(config: result.map { .from($0.prescribed) } ?? .standard(.rest),
                             amrapBlockID: result?.prescribed.circuit.isAMRAP == true ? result?.id : nil)
    }

    private func resultHandler(for request: TimerRequest) -> ((WODTimerResult) -> Void)? {
        guard let blockID = request.amrapBlockID else { return nil }
        return { timerResult in
            guard let index = results.firstIndex(where: { $0.id == blockID }) else { return }
            results[index].rounds = timerResult.rounds
            results[index].minutes = timerResult.minutes
        }
    }

    private var isClassLog: Bool {
        if case .classLog = mode { return true }
        return false
    }

    private var isPlanned: Bool {
        switch mode {
        case .planned: return true
        case let .edit(session): return session.isPlanned
        default: return false
        }
    }

    /// El día planeado cuando se registra después de que pasó.
    private var lateDay: Date? {
        switch mode {
        case let .planned(_, _, day):
            return day < SistemaCalendar.startOfDay(game.now) ? day : nil
        case let .edit(session):
            return session.plannedDay
        default:
            return nil
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .planned: return lateDay == nil ? "Misión de hoy" : "Día pendiente"
        case .free: return "Sesión libre"
        case .punishment: return PunishmentMission.title
        case .edit: return "Editar sesión"
        case .classLog: return "Registrar combate"
        }
    }

    private func setup() {
        guard !loaded else { return }
        loaded = true
        bodyWeightUnit = game.bodyEntries().last(where: { $0.weightKg != nil })?.weightUnit ?? .kg
        if case let .edit(session) = mode {
            lastPerformances = game.lastPerformances(excluding: session.id)
            title = session.title
            date = session.date
            results = session.results
            rpe = session.rpe
            notes = session.notes
            duration = session.durationMinutes
            routineID = session.routineID
            return
        }
        lastPerformances = game.lastPerformances()
        date = lateDay.map { $0.addingTimeInterval(12 * 3600) } ?? game.now
        switch mode {
        case let .planned(id, _, _):
            if let routine = game.routine(id: id) { load(routine) }
        case .free:
            title = "Sesión libre"
        case .punishment:
            title = PunishmentMission.title
            results = [BlockResult.asPrescribed(.circuit(CircuitPrescription(rounds: 4, exercises: [
                CircuitExercise(exerciseName: "Sentadilla", reps: 15),
                CircuitExercise(exerciseName: "Flexiones", reps: 10),
                CircuitExercise(exerciseName: "Plancha", seconds: 30),
                CircuitExercise(exerciseName: "Salto de cuerda", seconds: 60),
            ], restBetweenRoundsSeconds: 60)))]
            duration = 25
        case .classLog:
            results = [BlockResult.asPrescribed(.klass(ClassPrescription(discipline: .mma, minutes: 60)))]
        case .edit:
            break
        }
    }

    private func load(_ routine: Routine) {
        title = routine.name
        routineID = routine.id
        results = routine.blocks.map(BlockResult.asPrescribed)
        duration = max(ComplianceEngine.estimatedMinutes(routine.blocks).rounded(), 10)
    }

    private func addFreeBlock(_ kind: BlockKind) {
        var block = RoutineBlock(kind: kind)
        switch kind {
        case .strength: block.strength = StrengthPrescription(exerciseName: "", sets: 3, reps: 8, weight: 0)
        case .circuit: block.circuit = CircuitPrescription(rounds: 3, exercises: [CircuitExercise(exerciseName: "", reps: 10)])
        case .cardio: block.cardio = CardioPrescription(modality: .run, distanceKm: nil, minutes: 30)
        case .classSession: block.klass = ClassPrescription(discipline: .boxing, minutes: 60)
        }
        results.append(BlockResult.asPrescribed(block))
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var lastWeightText: String? {
        guard let kg = game.bodyEntries().last(where: { $0.weightKg != nil })?.weightKg else { return nil }
        return String(format: "%.1f", bodyWeightUnit.fromKg(kg))
    }

    private func saveBodyWeight() {
        guard let bodyWeight, bodyWeight > 0 else { return }
        game.recordBodyValue(.weight, value: bodyWeight, weightUnit: bodyWeightUnit)
    }

    private func previewXP(compliance: Double) -> Double {
        XPEngine.rawXP(.init(dominantKind: XPEngine.dominantKind(results.map(\.prescribed)),
                             minutes: isClassLog ? (results.first?.minutes ?? duration) : duration,
                             rpe: rpe, compliance: compliance, startedAt: date)) * game.recoveryXPMultiplier(date)
            * XPEngine.combatMultiplier(results.map(\.prescribed)) + Double(XPEngine.fightBonus(results))
    }

    private func save() {
        var finalResults = results
        if isClassLog, let klass = results.first {
            let p = klass.prescribed.klass
            title = p.combatKind == .lesson ? p.discipline.name : "\(p.combatKind.name) de \(p.discipline.name)"
            duration = klass.minutes ?? duration
        }
        var isUnplanned = isClassLog
        if case .free = mode { isUnplanned = true }
        if case let .edit(session) = mode, !session.isPlanned { isUnplanned = true }
        if isUnplanned {
            // En sesiones libres lo hecho es lo prescrito: se liga al catálogo para el historial.
            let linked = game.linkExercises(finalResults.map(\.prescribed))
            for index in finalResults.indices { finalResults[index].prescribed = linked[index] }
        }
        var draft = SessionDraft(title: title.isEmpty ? navigationTitle : title, date: date, results: finalResults,
                                 rpe: rpe, notes: notes, durationMinutes: duration, routineID: routineID)
        switch mode {
        case let .planned(_, itineraryID, day):
            draft.itineraryID = itineraryID
            draft.plannedDay = day
        case .free, .classLog:
            break
        case .punishment:
            draft.isPunishment = true
            draft.title = PunishmentMission.title
        case let .edit(session):
            draft.itineraryID = session.itineraryID
            draft.plannedDay = session.plannedDay
            game.updateSession(session, with: draft)
            dismiss()
            return
        }
        game.logSession(draft)
        saveBodyWeight()
        dismiss()
    }
}

/// Temporizador pedido desde una sesión. El AMRAP recibe sus rondas y su tiempo al terminar.
private struct TimerRequest: Identifiable {
    var config: WODTimerConfig
    var amrapBlockID: UUID?
    var id: UUID { config.id }
}

/// Campos de "lo real" para un bloque según su tipo.
struct BlockResultEditor: View {
    @Binding var result: BlockResult
    var last = LastPerformanceIndex()

    var body: some View {
        switch result.prescribed.kind {
        case .strength:
            if result.prescribed.strength.exerciseName.isEmpty || result.prescribed.strength.exerciseID == nil {
                TextField("Ejercicio", text: $result.prescribed.strength.exerciseName)
            } else {
                Text(result.prescribed.strength.exerciseName).font(.headline)
            }
            if let previous = last.find(id: result.prescribed.strength.exerciseID, name: result.prescribed.strength.exerciseName) {
                LastPerformanceRow(previous: previous) {
                    for index in result.sets.indices {
                        result.sets[index].weight = previous.weightKg
                        result.sets[index].unit = previous.unit
                    }
                }
            }
            ForEach($result.sets) { $set in
                HStack {
                    Text("Serie \((result.sets.firstIndex { $0.id == set.id } ?? 0) + 1)").foregroundStyle(Theme.secondaryText)
                    Spacer()
                    TextField("Reps", value: $set.reps, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 50)
                    Text("×")
                    TextField("0", value: $set.weight.inUnit(set.unit ?? .preferred), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 64)
                    WeightUnitToggle(unit: $set.unit.orPreferred)
                }
            }
            HStack {
                Button("+ Serie") {
                    let last = result.sets.last
                    result.sets.append(PerformedSet(reps: last?.reps ?? result.prescribed.strength.reps,
                                                    weight: last?.weight ?? result.prescribed.strength.weight,
                                                    unit: last?.unit ?? result.prescribed.strength.unit))
                }
                .buttonStyle(.borderless)
                Spacer()
                if !result.sets.isEmpty {
                    Button("− Serie", role: .destructive) { result.sets.removeLast() }
                        .buttonStyle(.borderless)
                }
            }
            if result.hasWeightImprovement {
                Label("Mejora: más peso que lo prescrito", systemImage: "arrow.up.right.circle.fill")
                    .foregroundStyle(Theme.success)
            }

        case .circuit:
            if result.prescribed.circuit.isAMRAP {
                NumberField(label: "Tiempo (presc. \(Format.minutes(result.prescribed.circuit.timeCapMinutes ?? 0)))",
                            value: $result.minutes.orZero, identifier: "log.amrapMinutes")
                Stepper("Rondas completadas: \(result.rounds)", value: $result.rounds, in: 0...99)
            } else {
                Stepper("Rondas: \(result.rounds) / \(result.prescribed.circuit.rounds)", value: $result.rounds, in: 0...99)
                    .onChange(of: result.rounds) { result.resizeRounds() }
                    .onAppear { if result.roundActuals == nil { result.resizeRounds() } }
            }
            if result.prescribed.circuit.isAMRAP {
                ForEach(Array(result.prescribed.circuit.exercises.enumerated()), id: \.element.id) { index, exercise in
                    if index < result.circuitActuals.count {
                        VStack(alignment: .leading, spacing: 4) {
                            exerciseHeader(index: index, exercise: exercise)
                            amountField(exercise, value: $result.circuitActuals[index])
                            WeightField(label: "Peso", kg: $result.circuitActuals[index].weight.orZero,
                                        unit: $result.circuitActuals[index].unit.orPreferred)
                        }
                    }
                }
            } else {
                ForEach(Array(result.prescribed.circuit.exercises.enumerated()), id: \.element.id) { index, exercise in
                    VStack(alignment: .leading, spacing: 6) {
                        exerciseHeader(index: index, exercise: exercise)
                        ForEach(0..<(result.roundActuals?.count ?? 0), id: \.self) { round in
                            if index < (result.roundActuals?[round].count ?? 0) {
                                RoundRow(round: round + 1, exercise: exercise, actual: roundBinding(round, index))
                            }
                        }
                    }
                }
            }

        case .cardio:
            if result.prescribed.cardio.distanceKm != nil {
                NumberField(label: "Distancia (km)", value: $result.distanceKm.orZero)
            }
            NumberField(label: "Tiempo (min)", value: $result.minutes.orZero)

        case .classSession:
            CombatEditor(result: $result)
        }
    }

    @ViewBuilder
    private func exerciseHeader(index: Int, exercise: CircuitExercise) -> some View {
        if exercise.exerciseName.isEmpty || exercise.exerciseID == nil {
            TextField("Ejercicio", text: $result.prescribed.circuit.exercises[index].exerciseName)
                .font(.subheadline.bold())
        } else {
            Text(exercise.exerciseName).font(.subheadline.bold())
        }
        Text(exercise.prescriptionText)
            .font(.caption)
            .foregroundStyle(Theme.secondaryText)
        if let previous = last.find(id: exercise.exerciseID, name: exercise.exerciseName) {
            LastPerformanceRow(previous: previous) {
                if var rounds = result.roundActuals {
                    for r in rounds.indices where index < rounds[r].count {
                        rounds[r][index].weight = previous.weightKg
                        rounds[r][index].unit = previous.unit
                    }
                    result.roundActuals = rounds
                    result.syncFromRounds()
                } else if index < result.circuitActuals.count {
                    result.circuitActuals[index].weight = previous.weightKg
                    result.circuitActuals[index].unit = previous.unit
                }
            }
        }
    }

    @ViewBuilder
    private func amountField(_ exercise: CircuitExercise, value: Binding<PerformedCircuitExercise>) -> some View {
        if exercise.seconds != nil {
            IntField(label: "Segundos (presc. \(exercise.seconds ?? 0))", value: value.seconds.orZero)
        } else {
            IntField(label: exercise.reps.map { "Reps (presc. \($0))" } ?? "Reps", value: value.reps.orZero)
        }
    }

    /// Una celda de una ronda; al cambiarla se recalcula el resumen del ejercicio.
    private func roundBinding(_ round: Int, _ index: Int) -> Binding<PerformedCircuitExercise> {
        Binding(
            get: {
                guard let rounds = result.roundActuals, round < rounds.count, index < rounds[round].count else {
                    return PerformedCircuitExercise()
                }
                return rounds[round][index]
            },
            set: { value in
                guard var rounds = result.roundActuals, round < rounds.count, index < rounds[round].count else { return }
                rounds[round][index] = value
                result.roundActuals = rounds
                result.syncFromRounds()
            }
        )
    }
}

/// "R1  [12] reps  [25] lb": lo de un ejercicio en una ronda.
private struct RoundRow: View {
    let round: Int
    let exercise: CircuitExercise
    @Binding var actual: PerformedCircuitExercise

    private var unit: WeightUnit { actual.unit ?? exercise.unit ?? .preferred }

    var body: some View {
        HStack(spacing: 8) {
            Text("R\(round)")
                .font(Theme.mono(14, weight: .bold))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 30, alignment: .leading)
            if exercise.seconds != nil {
                TextField("0", value: $actual.seconds, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 48)
                Text("s").foregroundStyle(Theme.secondaryText)
            } else {
                TextField("0", value: $actual.reps, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 48)
                Text("reps").foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 4)
            TextField("—", value: weightBinding, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
            WeightUnitToggle(unit: unitBinding)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ronda \(round)")
    }

    private var unitBinding: Binding<WeightUnit> {
        Binding(get: { unit }, set: { actual.unit = $0 })
    }

    /// Vacío es sin peso (peso corporal); internamente en kg.
    private var weightBinding: Binding<Double?> {
        Binding(
            get: { actual.weight.map { (unit.fromKg($0) * 10).rounded() / 10 } },
            set: { value in
                if actual.unit == nil { actual.unit = unit }
                actual.weight = value.flatMap { $0 > 0 ? unit.toKg($0) : nil }
            }
        )
    }
}

/// Clase, sparring o pelea: lo que cambia es qué se anota.
private struct CombatEditor: View {
    @Binding var result: BlockResult

    private var kind: Binding<CombatKind> {
        Binding(
            get: { result.prescribed.klass.combatKind },
            set: { value in
                result.prescribed.klass.combat = value == .lesson ? nil : value
                if value == .lesson {
                    result.fight = nil
                } else {
                    if result.prescribed.klass.rounds == nil { result.prescribed.klass.rounds = value == .fight ? 3 : 5 }
                    if result.prescribed.klass.roundMinutes == nil { result.prescribed.klass.roundMinutes = value == .fight ? 5 : 3 }
                    result.rounds = result.prescribed.klass.rounds ?? 0
                    result.fight = value == .fight ? (result.fight ?? FightResult()) : nil
                    updateMinutes()
                }
            }
        )
    }

    var body: some View {
        Picker("Tipo", selection: kind) {
            ForEach(CombatKind.allCases) { Text($0.name).tag($0) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("log.combatKind")
        Picker("Disciplina", selection: $result.prescribed.klass.discipline) {
            ForEach(ClassDiscipline.allCases) { Text($0.name).tag($0) }
        }
        .accessibilityIdentifier("log.discipline")

        switch result.prescribed.klass.combatKind {
        case .lesson:
            NumberField(label: "Duración (min)", value: $result.minutes.orZero)
        case .sparring:
            Stepper("Asaltos: \(result.rounds)", value: $result.rounds, in: 1...30)
                .onChange(of: result.rounds) { syncPrescribedRounds() }
            roundMinutesField
            NumberField(label: "Duración total (min)", value: $result.minutes.orZero)
        case .fight:
            Picker("Resultado", selection: fightBinding(\.outcome)) {
                ForEach(FightOutcome.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("log.fightOutcome")
            if result.fight?.outcome != .draw {
                Picker("Cómo terminó", selection: fightBinding(\.method)) {
                    ForEach(FightMethod.allCases) { Text($0.name).tag($0) }
                }
            }
            Stepper("Asaltos peleados: \(result.rounds)", value: $result.rounds, in: 1...12)
                .onChange(of: result.rounds) { syncPrescribedRounds() }
            roundMinutesField
            TextField("Rival (opcional)", text: optionalText(\.opponent))
            TextField("Evento (opcional)", text: optionalText(\.event))
            Text("Premio: +\(XPEngine.fightBonus([result])) XP aparte de los topes, más el XP de la sesión.")
                .font(.caption)
                .foregroundStyle(Theme.accent)
        }
    }

    private var roundMinutesField: some View {
        NumberField(label: "Minutos por asalto", value: Binding(
            get: { result.prescribed.klass.roundMinutes ?? 3 },
            set: { result.prescribed.klass.roundMinutes = $0; updateMinutes() }
        ))
    }

    private func syncPrescribedRounds() {
        result.prescribed.klass.rounds = result.rounds
        updateMinutes()
    }

    /// La duración sale de asaltos × minutos, con un minuto de descanso entre asaltos.
    private func updateMinutes() {
        let rounds = Double(max(result.rounds, 1))
        let minutes = rounds * (result.prescribed.klass.roundMinutes ?? 3) + (rounds - 1)
        result.minutes = minutes
        result.prescribed.klass.minutes = minutes
    }

    private func fightBinding<T>(_ path: WritableKeyPath<FightResult, T>) -> Binding<T> {
        Binding(
            get: { (result.fight ?? FightResult())[keyPath: path] },
            set: { value in
                var fight = result.fight ?? FightResult()
                fight[keyPath: path] = value
                result.fight = fight
            }
        )
    }

    private func optionalText(_ path: WritableKeyPath<FightResult, String?>) -> Binding<String> {
        Binding(
            get: { result.fight?[keyPath: path] ?? "" },
            set: { value in
                var fight = result.fight ?? FightResult()
                fight[keyPath: path] = value.isEmpty ? nil : value
                result.fight = fight
            }
        )
    }

}

/// "La vez pasada: 25 lb × 6", con un toque para volver a usarlo.
struct LastPerformanceRow: View {
    let previous: LastPerformance
    let use: () -> Void

    var body: some View {
        HStack {
            Text("La vez pasada: \(previous.text)")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            Spacer()
            Button("Usar", action: use)
                .buttonStyle(.secondaryAction)
                .controlSize(.small)
                .accessibilityIdentifier("log.useLast")
        }
    }
}
