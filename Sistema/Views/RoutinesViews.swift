import SwiftData
import SwiftUI

@MainActor
struct TrainingHubView: View {
    @Environment(GameService.self) private var game
    @Query(sort: \BodyEntry.date) private var bodyEntries: [BodyEntry]
    @State private var logFree = false
    @State private var logClass = false
    @State private var updatingWeight = false

    var body: some View {
        List {
            Section {
                BodyWeightCard(entries: bodyEntries) { updatingWeight = true }
                    .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
            }
            .listRowBackground(Theme.panel)
            Section {
                NavigationLink { WODTimerHomeView() } label: {
                    Label("Temporizador", systemImage: "timer")
                }
                .accessibilityIdentifier("hub.timer")
                Button {
                    logClass = true
                } label: {
                    Label("Clase, sparring o pelea", systemImage: "figure.boxing")
                }
            }
            .listRowBackground(Theme.panel)
            Section {
                NavigationLink { ItinerariesView() } label: {
                    Label("Itinerarios", systemImage: "calendar")
                }
                NavigationLink { RoutinesView() } label: {
                    Label("Rutinas", systemImage: "list.bullet.rectangle")
                }
                NavigationLink { ExercisesView() } label: {
                    Label("Ejercicios", systemImage: "figure.strengthtraining.traditional")
                }
            }
            .listRowBackground(Theme.panel)
            Section {
                Button {
                    logFree = true
                } label: {
                    Label("Registrar sesión libre", systemImage: "plus.circle.fill")
                }
                NavigationLink { SessionHistoryView() } label: {
                    Label("Historial de sesiones", systemImage: "clock.arrow.circlepath")
                }
            }
            .listRowBackground(Theme.panel)
        }
        .systemBackground()
        .navigationTitle("Entrenar")
        .sheet(isPresented: $logFree) {
            NavigationStack { SessionLogView(mode: .free) }
        }
        .sheet(isPresented: $logClass) {
            NavigationStack { SessionLogView(mode: .classLog) }
        }
        .sheet(isPresented: $updatingWeight) {
            let weighed = bodyEntries.filter { $0.weightKg != nil }
            BodyValueSheet(metric: .weight, last: weighed.last.flatMap { e in e.weightKg.map { ($0, e.date) } },
                           weightUnit: weighed.last?.weightUnit ?? .kg)
        }
    }
}

/// Peso corporal a la vista en Entrenar: el último, cuándo fue, cuánto cambió y la tendencia reciente.
struct BodyWeightCard: View {
    let entries: [BodyEntry]
    var onUpdate: () -> Void

    private var weighed: [BodyEntry] { entries.filter { $0.weightKg != nil } }
    private var unit: WeightUnit { weighed.last?.weightUnit ?? .kg }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PESO CORPORAL")
                        .font(.caption.weight(.semibold))
                        .tracking(0.8)
                        .foregroundStyle(Theme.secondaryText)
                    if let last = weighed.last, let kg = last.weightKg {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(String(format: "%.1f", unit.fromKg(kg)))
                                .font(Theme.display(44, weight: .black))
                                .accessibilityIdentifier("hub.weight")
                            Text(unit.symbol).font(.title3.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                        }
                        Text(detail(last: last, kg: kg))
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    } else {
                        Text("Sin registrar").font(Theme.display(32, weight: .bold))
                    }
                }
                Spacer()
                sparkline
                    .frame(width: 110, height: 52)
                    .padding(.top, 18)
            }
            Button(action: onUpdate) {
                Label("Actualizar peso", systemImage: "scalemass").frame(maxWidth: .infinity)
            }
            .buttonStyle(.secondaryAction)
            .accessibilityIdentifier("hub.updateWeight")
        }
    }

    private func detail(last: BodyEntry, kg: Double) -> String {
        let days = SistemaCalendar.daysBetween(last.date, Date())
        var text = days == 0 ? "Hoy" : (days == 1 ? "Ayer" : "Hace \(days) días")
        if weighed.count > 1, let previous = weighed[weighed.count - 2].weightKg {
            let change = unit.fromKg(kg) - unit.fromKg(previous)
            if abs(change) >= 0.05 {
                text += " · " + (change > 0 ? "+" : "−") + String(format: "%.1f %@", abs(change), unit.symbol) + " vs anterior"
            } else {
                text += " · igual que la anterior"
            }
        }
        return text
    }

    /// Últimos pesos como una línea simple; el punto final marca el actual.
    private var sparkline: some View {
        let values = weighed.suffix(10).compactMap(\.weightKg)
        return GeometryReader { geo in
            if values.count > 1, let low = values.min(), let high = values.max() {
                let span = max(high - low, 0.5)
                let points = values.enumerated().map { index, value in
                    CGPoint(x: geo.size.width * CGFloat(index) / CGFloat(values.count - 1),
                            y: geo.size.height * (1 - CGFloat((value - low) / span)) * 0.85 + geo.size.height * 0.075)
                }
                Path { path in path.addLines(points) }
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if let end = points.last {
                    Circle().fill(Theme.accent).frame(width: 7, height: 7).position(end)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

@MainActor
struct SessionHistoryView: View {
    @Environment(GameService.self) private var game
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @State private var editing: SessionLogMode?
    @State private var toDelete: WorkoutSession?

    var body: some View {
        List(sessions) { session in
            Button {
                if game.canModify(session) { editing = .edit(session) }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(session.title).font(.headline)
                        Spacer()
                        Text("+\(session.xpAwarded) XP").foregroundStyle(Theme.glow)
                    }
                    Text("\(session.date.formatted(date: .abbreviated, time: .shortened)) · \(Format.percent(session.compliance)) · RPE \(session.rpe)")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    SessionHealthLine(session: session)
                    if let fight = session.fight {
                        Label(fightLine(fight), systemImage: "trophy.fill")
                            .font(.caption.bold())
                            .foregroundStyle(fight.outcome == .win ? Theme.accent : Theme.secondaryText)
                    }
                    Text(session.isPunishment ? "Misión de castigo" : (session.isPlanned ? "Planeada" : (session.isFromWatch ? "Desde el Apple Watch" : "No planeada")))
                        .font(.caption2)
                        .foregroundStyle(session.isPunishment ? Theme.danger : Theme.accent)
                    if !session.notes.isEmpty {
                        Text(session.notes).font(.caption).italic()
                    }
                }
            }
            .tint(.white)
            .accessibilityIdentifier("history.session")
            .swipeActions {
                if game.canModify(session) {
                    Button("Borrar", role: .destructive) { toDelete = session }
                }
            }
            .listRowBackground(Theme.panel)
        }
        .systemBackground()
        .navigationTitle("Sesiones")
        .overlay {
            if sessions.isEmpty { ContentUnavailableView("Sin sesiones", systemImage: "tray") }
        }
        .sheet(item: $editing) { mode in
            NavigationStack { SessionLogView(mode: mode) }
        }
        .confirmationDialog("¿Borrar esta sesión?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Borrar", role: .destructive) {
                if let toDelete { game.deleteSession(toDelete) }
                toDelete = nil
            }
        } message: {
            Text("Se le resta el XP y los atributos que dio. Una falta o racha de un día ya cerrado no cambia.")
        }
    }

    private func fightLine(_ fight: FightResult) -> String {
        var text = fight.outcome == .draw ? "Empate" : "\(fight.outcome == .win ? "Victoria" : "Derrota") por \(fight.method.name)"
        if let opponent = fight.opponent { text += " vs \(opponent)" }
        if let event = fight.event { text += " · \(event)" }
        return text
    }
}

@MainActor
struct RoutinesView: View {
    @Environment(GameService.self) private var game
    @Query(sort: \Routine.name) private var routines: [Routine]
    @State private var showImport = false
    @State private var showNewRoutine = false

    /// Programas del gimnasio, con sus días en orden.
    private var programs: [(name: String, days: [Routine])] {
        Dictionary(grouping: routines.filter { $0.programName != nil }, by: { $0.programName ?? "" })
            .map { (name: $0.key, days: $0.value.sorted { ($0.programDay ?? 0) < ($1.programDay ?? 0) }) }
            .sorted { $0.name < $1.name }
    }

    private var looseRoutines: [Routine] {
        routines.filter { $0.programName == nil }
    }

    var body: some View {
        List {
            ForEach(programs, id: \.name) { program in
                Section {
                    routineRows(program.days)
                    NavigationLink {
                        ItineraryEditorView(itinerary: nil, program: program.days)
                    } label: {
                        Label("Usar en un itinerario", systemImage: "calendar.badge.plus")
                    }
                    .accessibilityIdentifier("routines.useProgram")
                    .listRowBackground(Theme.panel)
                } header: {
                    programHeader(program.name, change: program.days.first?.programChangeDate)
                }
            }
            if !looseRoutines.isEmpty {
                Section(programs.isEmpty ? "" : "Rutinas sueltas") {
                    routineRows(looseRoutines)
                }
            }
        }
        .systemBackground()
        .navigationTitle("Rutinas")
        .toolbar {
            Menu {
                Button("Programa completo (pegar texto)") { showImport = true }
                Button("Rutina individual") { showNewRoutine = true }
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityIdentifier("routines.add")
        }
        .navigationDestination(isPresented: $showImport) { ProgramImportView() }
        .navigationDestination(isPresented: $showNewRoutine) { RoutineEditorView(routine: nil) }
        .overlay {
            if routines.isEmpty { ContentUnavailableView("Sin rutinas", systemImage: "list.bullet") }
        }
    }

    private func programHeader(_ name: String, change: Date?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.headline).foregroundStyle(Theme.glow)
            if let change {
                Text("Cambio de rutina: \(change.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func routineRows(_ items: [Routine]) -> some View {
        ForEach(items) { routine in
            NavigationLink {
                RoutineEditorView(routine: routine)
            } label: {
                VStack(alignment: .leading) {
                    Text(routine.name).font(.headline)
                    Text("\(routine.focus.map { "\($0) · " } ?? "")\(Format.count(routine.blocks.count, "bloque")) · ~\(Int(ComplianceEngine.estimatedMinutes(routine.blocks))) min")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .deleteDisabled(game.isRoutineInUse(routine))
            .listRowBackground(Theme.panel)
        }
        .onDelete { offsets in
            for index in offsets { game.deleteRoutine(items[index]) }
        }
    }
}

@MainActor
struct RoutineEditorView: View {
    let routine: Routine?

    @Environment(GameService.self) private var game
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var blocks: [RoutineBlock] = []
    @State private var loaded = false

    var body: some View {
        Form {
            Section("Nombre") {
                TextField("Ej. Empuje + core", text: $name)
                    .accessibilityIdentifier("routine.name")
            }
            Section("Bloques") {
                ForEach($blocks) { $block in
                    NavigationLink {
                        BlockEditorView(block: $block)
                    } label: {
                        Label(block.summary.isEmpty ? block.kind.name : block.summary, systemImage: block.kind.symbol)
                    }
                }
                .onDelete { blocks.remove(atOffsets: $0) }
                .onMove { blocks.move(fromOffsets: $0, toOffset: $1) }
                Menu {
                    ForEach(BlockKind.allCases) { kind in
                        Button(kind.name) { blocks.append(BlockTemplates.defaultBlock(kind)) }
                    }
                    ForEach([CircuitFormat.biSeries, .tabata, .amrap]) { format in
                        Button(format.name) { blocks.append(BlockTemplates.defaultBlock(format: format)) }
                    }
                } label: {
                    Label("Agregar bloque", systemImage: "plus")
                }
                .accessibilityIdentifier("routine.addBlock")
            }
            Section {
                Text("Duración estimada: ~\(Int(ComplianceEngine.estimatedMinutes(blocks))) min")
                    .foregroundStyle(Theme.secondaryText)
                if blocks.contains(where: \.hasUnnamedExercise) {
                    Text("Ponele nombre a todos los ejercicios para poder guardar.")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                }
            }
        }
        .systemBackground()
        .navigationTitle(routine == nil ? "Nueva rutina" : "Editar rutina")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") {
                    game.saveRoutine(routine, name: name.trimmingCharacters(in: .whitespaces), blocks: blocks)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || blocks.isEmpty || blocks.contains(where: \.hasUnnamedExercise))
                .accessibilityIdentifier("routine.save")
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            name = routine?.name ?? ""
            blocks = routine?.blocks ?? []
        }
    }
}

enum BlockTemplates {
    static func defaultBlock(_ kind: BlockKind) -> RoutineBlock {
        switch kind {
        case .strength:
            return .strength(StrengthPrescription(exerciseName: "", sets: 3, reps: 8, weight: 0))
        case .circuit:
            return .circuit(CircuitPrescription(rounds: 3, exercises: [CircuitExercise(exerciseName: "", reps: 10)]))
        case .cardio:
            return .cardio(CardioPrescription(modality: .run, distanceKm: nil, minutes: 30))
        case .classSession:
            return .klass(ClassPrescription(discipline: .muayThai, minutes: 60))
        }
    }

    static func defaultBlock(format: CircuitFormat) -> RoutineBlock {
        switch format {
        case .circuit:
            return defaultBlock(BlockKind.circuit)
        case .biSeries:
            return .circuit(CircuitPrescription(rounds: 3, exercises: [
                CircuitExercise(exerciseName: "", reps: 10),
                CircuitExercise(exerciseName: "", reps: 10),
            ], format: .biSeries))
        case .tabata:
            return .circuit(CircuitPrescription(rounds: 4, exercises: [
                CircuitExercise(exerciseName: "", seconds: 45, restSeconds: 60),
            ], format: .tabata))
        case .amrap:
            return .circuit(CircuitPrescription(rounds: 1, exercises: [
                CircuitExercise(exerciseName: "", reps: 12),
            ], format: .amrap, timeCapMinutes: 15))
        }
    }
}

/// Editor de lo prescrito de un bloque.
struct BlockEditorView: View {
    @Binding var block: RoutineBlock
    @State private var quickList = ""

    private var formatSelection: Binding<CircuitFormat> {
        Binding(
            get: { block.circuit.resolvedFormat },
            set: { format in
                block.circuit.format = format
                if format == .amrap, block.circuit.timeCapMinutes == nil { block.circuit.timeCapMinutes = 15 }
            }
        )
    }

    var body: some View {
        Form {
            switch block.kind {
            case .strength:
                Section("Ejercicio") {
                    ExerciseNameField(name: $block.strength.exerciseName)
                }
                Section("Prescripción") {
                    Stepper("Series: \(block.strength.sets)", value: $block.strength.sets, in: 1...20)
                    Stepper("Reps: \(block.strength.reps)", value: $block.strength.reps, in: 1...100)
                    WeightField(label: "Peso", kg: $block.strength.weight, unit: $block.strength.unit.orPreferred)
                }

            case .circuit:
                Section("Formato") {
                    Picker("Formato", selection: formatSelection) {
                        ForEach(CircuitFormat.allCases) { Text($0.name).tag($0) }
                    }
                    TextField("Título opcional (ej. ABS)", text: $block.circuit.title.orEmpty)
                    if block.circuit.isAMRAP {
                        NumberField(label: "Tiempo (min)", value: $block.circuit.timeCapMinutes.orZero)
                    } else {
                        Stepper("Rondas: \(block.circuit.rounds)", value: $block.circuit.rounds, in: 1...50)
                        IntField(label: "Descanso entre rondas (s)", value: $block.circuit.restBetweenRoundsSeconds.orZero)
                    }
                }
                ForEach($block.circuit.exercises) { $exercise in
                    Section {
                        ExerciseNameField(name: $exercise.exerciseName)
                        Picker("Medida", selection: Binding(
                            get: { exercise.seconds != nil },
                            set: { useTime in
                                var updated = $exercise.wrappedValue
                                if useTime {
                                    updated.seconds = updated.seconds ?? 30
                                    updated.reps = nil
                                } else {
                                    updated.reps = updated.reps ?? 10
                                    updated.seconds = nil
                                }
                                $exercise.wrappedValue = updated
                            }
                        )) {
                            Text("Reps").tag(false)
                            Text("Tiempo").tag(true)
                        }
                        .pickerStyle(.segmented)
                        if exercise.seconds != nil {
                            IntField(label: "Segundos", value: $exercise.seconds.orZero)
                        } else {
                            IntField(label: "Reps", value: $exercise.reps.orZero)
                        }
                        WeightField(label: "Peso opcional", kg: $exercise.weight.orZero, unit: $exercise.unit.orPreferred)
                        IntField(label: "Descanso opcional (s)", value: $exercise.restSeconds.orZero)
                        TextField("Nota opcional (ej. c/l)", text: $exercise.note.orEmpty)
                        Button("Quitar ejercicio", role: .destructive) {
                            block.circuit.exercises.removeAll { $0.id == exercise.id }
                        }
                    }
                }
                Section {
                    Button("Agregar ejercicio") {
                        block.circuit.exercises.append(CircuitExercise(exerciseName: "", reps: 10))
                    }
                }
                Section {
                    TextEditor(text: $quickList)
                        .frame(minHeight: 100)
                    Button("Agregar lista") {
                        block.circuit.exercises += RoutineTextParser.exercises(from: quickList)
                        quickList = ""
                    }
                    .disabled(quickList.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("Agregar varios de una vez")
                } footer: {
                    Text("Un ejercicio por línea, por ejemplo: Burpees 45 sec 1 min, o Goblet squat 12 reps c/l.")
                }

            case .cardio:
                Section("Cardio") {
                    Picker("Modalidad", selection: $block.cardio.modality) {
                        ForEach(CardioModality.allCases) { Text($0.name).tag($0) }
                    }
                    NumberField(label: "Distancia (km, opcional)", value: $block.cardio.distanceKm.orZero)
                    NumberField(label: "Tiempo (min, opcional)", value: $block.cardio.minutes.orZero)
                }

            case .classSession:
                Section("Clase") {
                    Picker("Disciplina", selection: $block.klass.discipline) {
                        ForEach(ClassDiscipline.allCases) { Text($0.name).tag($0) }
                    }
                    NumberField(label: "Duración (min)", value: $block.klass.minutes)
                }
            }
        }
        .systemBackground()
        .navigationTitle(block.kind.name)
    }
}

/// Campo de ejercicio con sugerencias del catálogo (por nombre o alias) para no duplicar.
struct ExerciseNameField: View {
    @Binding var name: String
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    var body: some View {
        TextField("Nombre o alias", text: $name)
            .textInputAutocapitalization(.sentences)
        let entries = exercises.map(\.catalogEntry)
        if let exact = ExerciseCatalog.match(name, in: entries) {
            if exact.name != name {
                Button("Usar “\(exact.name)” del catálogo") { name = exact.name }
                    .font(.caption)
            }
        } else {
            ForEach(ExerciseCatalog.suggestions(name, in: entries, limit: 4), id: \.id) { entry in
                Button("¿\(entry.name)?") { name = entry.name }
                    .font(.caption)
            }
            if !name.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("Nuevo ejercicio: se agregará al catálogo al guardar.")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}
