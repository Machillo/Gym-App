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

    var body: some View {
        Form {
            Section("Sesión") {
                TextField("Título", text: $title)
                DatePicker("Fecha y hora", selection: $date)
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
                    BlockResultEditor(result: $result)
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
                NumberField(label: "Duración (min)", value: $duration, identifier: "log.duration")
                TextField("Notas", text: $notes, axis: .vertical)
            } header: {
                Text("Esfuerzo")
            } footer: {
                Text("La duración viene estimada y el XP depende de ella: poné lo que realmente duraste.")
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
                if compliance < 0.5 && isPlanned {
                    Text("Menos de 50 %: al cerrar el día cuenta como media falta.")
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                }
                Button("Rellenar con lo prescrito") {
                    results = results.map { BlockResult.asPrescribed($0.prescribed) }
                }
                .accessibilityIdentifier("log.fillPrescribed")
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
                    .disabled(results.isEmpty)
                    .accessibilityIdentifier("log.save")
            }
        }
        .onAppear(perform: setup)
    }

    private var isPlanned: Bool {
        if case .planned = mode { return true }
        return false
    }

    private var navigationTitle: String {
        switch mode {
        case .planned: return "Misión de hoy"
        case .free: return "Sesión libre"
        case .punishment: return PunishmentMission.title
        }
    }

    private func setup() {
        guard !loaded else { return }
        loaded = true
        date = game.now
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
        case .circuit: block.circuit = CircuitPrescription(rounds: 3, exercises: [CircuitExercise(exerciseName: "Burpees", reps: 10)])
        case .cardio: block.cardio = CardioPrescription(modality: .run, distanceKm: nil, minutes: 30)
        case .classSession: block.klass = ClassPrescription(discipline: .boxing, minutes: 60)
        }
        results.append(BlockResult.asPrescribed(block))
    }

    private func previewXP(compliance: Double) -> Double {
        XPEngine.rawXP(.init(dominantKind: XPEngine.dominantKind(results.map(\.prescribed)), minutes: duration,
                             rpe: rpe, compliance: compliance, startedAt: date))
    }

    private func save() {
        var finalResults = results
        if case .free = mode {
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
        case .free:
            break
        case .punishment:
            draft.isPunishment = true
            draft.title = PunishmentMission.title
        }
        game.logSession(draft)
        dismiss()
    }
}

/// Campos de "lo real" para un bloque según su tipo.
struct BlockResultEditor: View {
    @Binding var result: BlockResult

    var body: some View {
        switch result.prescribed.kind {
        case .strength:
            if result.prescribed.strength.exerciseName.isEmpty || result.prescribed.strength.exerciseID == nil {
                TextField("Ejercicio", text: $result.prescribed.strength.exerciseName)
            } else {
                Text(result.prescribed.strength.exerciseName).font(.headline)
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
                    TextField("0", value: $set.weight.inUnit(set.unit ?? .kg), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 64)
                    WeightUnitToggle(unit: $set.unit.orKg)
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
            }
            ForEach(Array(result.prescribed.circuit.exercises.enumerated()), id: \.element.id) { index, exercise in
                if index < result.circuitActuals.count {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.exerciseName).font(.subheadline.bold())
                        Text(exercise.prescriptionText)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                        if exercise.seconds != nil {
                            IntField(label: "Segundos (presc. \(exercise.seconds ?? 0))", value: $result.circuitActuals[index].seconds.orZero)
                        } else {
                            IntField(label: "Reps (presc. \(exercise.reps ?? 0))", value: $result.circuitActuals[index].reps.orZero)
                        }
                        WeightField(label: "Peso", kg: $result.circuitActuals[index].weight.orZero,
                                    unit: $result.circuitActuals[index].unit.orKg)
                    }
                }
            }

        case .cardio:
            if result.prescribed.cardio.distanceKm != nil {
                NumberField(label: "Distancia (km)", value: $result.distanceKm.orZero)
            }
            NumberField(label: "Tiempo (min)", value: $result.minutes.orZero)

        case .classSession:
            NumberField(label: "Duración (min)", value: $result.minutes.orZero)
        }
    }
}
