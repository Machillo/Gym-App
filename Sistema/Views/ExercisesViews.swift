import Charts
import SwiftData
import SwiftUI

struct ExercisesView: View {
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query private var logs: [ExerciseLog]
    @State private var search = ""

    var body: some View {
        List {
            Section("Catálogo") {
                ForEach(filtered) { exercise in
                    NavigationLink {
                        ExerciseDetailView(exercise: exercise)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name)
                            if !exercise.aliases.isEmpty {
                                Text(exercise.aliases.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                }
            }
            .listRowBackground(Theme.panel)
            let cardioKeys = Set(logs.filter { $0.kind == .cardio }.map(\.markKey)).sorted()
            if !cardioKeys.isEmpty {
                Section("Cardio") {
                    ForEach(cardioKeys, id: \.self) { key in
                        NavigationLink {
                            CardioHistoryView(markKey: key)
                        } label: {
                            Text(CardioModality(rawValue: key.replacingOccurrences(of: "cardio:", with: ""))?.name ?? key)
                        }
                    }
                }
                .listRowBackground(Theme.panel)
            }
        }
        .systemBackground()
        .searchable(text: $search, prompt: "Buscar por nombre o alias")
        .navigationTitle("Ejercicios")
        .toolbar {
            NavigationLink {
                ExerciseEditorView(exercise: nil)
            } label: {
                Image(systemName: "plus")
            }
        }
    }

    private var filtered: [Exercise] {
        let key = ExerciseCatalog.normalize(search)
        guard !key.isEmpty else { return exercises }
        return exercises.filter { ex in
            ExerciseCatalog.normalize(ex.name).contains(key) || ex.aliases.contains { ExerciseCatalog.normalize($0).contains(key) }
        }
    }
}

@MainActor
struct ExerciseEditorView: View {
    let exercise: Exercise?

    @Environment(GameService.self) private var game
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var all: [Exercise]
    @State private var name = ""
    @State private var aliases = ""
    @State private var category: ExerciseCategory = .fullBody
    @State private var stats: Set<StatKind> = [.strength]
    @State private var duplicate: String?
    @State private var loaded = false

    var body: some View {
        Form {
            Section("Ejercicio") {
                TextField("Nombre", text: $name)
                TextField("Alias (separados por coma)", text: $aliases)
                Picker("Categoría", selection: $category) {
                    ForEach(ExerciseCategory.allCases) { Text($0.name).tag($0) }
                }
            }
            Section("Stats que alimenta") {
                ForEach(StatKind.allCases) { kind in
                    Toggle(kind.name, isOn: Binding(
                        get: { stats.contains(kind) },
                        set: { on in if on { stats.insert(kind) } else { stats.remove(kind) } }
                    ))
                }
            }
        }
        .systemBackground()
        .navigationTitle(exercise == nil ? "Nuevo ejercicio" : "Editar ejercicio")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar", action: save)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .alert("Ya existe", isPresented: Binding(get: { duplicate != nil }, set: { if !$0 { duplicate = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Ese nombre o alias ya corresponde a “\(duplicate ?? "")”.")
        }
        .onAppear {
            guard !loaded, let exercise else { return }
            loaded = true
            name = exercise.name
            aliases = exercise.aliases.joined(separator: ", ")
            category = exercise.category
            stats = Set(exercise.stats)
        }
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        let aliasList = aliases.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let others = all.filter { $0.id != exercise?.id }.map(\.catalogEntry)
        for candidate in [cleanName] + aliasList {
            if let match = ExerciseCatalog.match(candidate, in: others) {
                duplicate = match.name
                return
            }
        }
        let target = exercise ?? Exercise(name: cleanName, category: category, stats: [], now: game.now)
        target.name = cleanName
        target.aliases = aliasList
        target.category = category
        target.stats = StatKind.allCases.filter { stats.contains($0) }
        if exercise == nil { context.insert(target) }
        game.save()
        dismiss()
    }
}

struct ChartPoint: Identifiable {
    var date: Date
    var value: Double
    var id: Date { date }
}

enum ExerciseMetric: String, CaseIterable, Identifiable {
    case weight, e1rm, volume, reps

    var id: String { rawValue }

    var name: String {
        switch self {
        case .weight: return "Peso"
        case .e1rm: return "e1RM"
        case .volume: return "Volumen"
        case .reps: return "Reps"
        }
    }
}

struct ExerciseDetailView: View {
    let exercise: Exercise

    @Query private var allLogs: [ExerciseLog]
    @State private var metric: ExerciseMetric = .e1rm

    private var logs: [ExerciseLog] {
        allLogs.filter { $0.exerciseID == exercise.id }.sorted { $0.date < $1.date }
    }

    /// Un punto por sesión con el mejor valor de la métrica (volumen = suma).
    private var points: [ChartPoint] {
        let grouped = Dictionary(grouping: logs, by: \.sessionID)
        return grouped.values.compactMap { group -> ChartPoint? in
            guard let first = group.first else { return nil }
            let value: Double
            switch metric {
            case .weight: value = group.map(\.weight).max() ?? 0
            case .e1rm: value = group.map(\.e1RM).max() ?? 0
            case .volume: value = group.reduce(0.0) { $0 + $1.volume }
            case .reps: value = Double(group.map(\.reps).max() ?? 0)
            }
            return ChartPoint(date: first.date, value: value)
        }
        .sorted { $0.date < $1.date }
    }

    var body: some View {
        List {
            Section("Marcas personales") {
                record("Mejor peso", logs.map(\.weight).max().map(Format.weightBoth))
                record("Mejor e1RM (Epley)", logs.map(\.e1RM).max().map(Format.weightBoth))
                record("Reps máximas", logs.map(\.reps).max().map { "\($0)" })
                record("Mejor volumen en una sesión",
                       Dictionary(grouping: logs, by: \.sessionID).values.map { group in group.reduce(0.0) { $0 + $1.volume } }.max().map(Format.weightBoth))
                record("Mejor tiempo (circuito)", logs.map(\.seconds).filter { $0 > 0 }.max().map { "\(Int($0)) s" })
                record("Mejoras sobre lo prescrito", "\(logs.filter(\.isImprovement).count)")
            }
            .listRowBackground(Theme.panel)

            Section("Historial") {
                Picker("Métrica", selection: $metric) {
                    ForEach(ExerciseMetric.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                if points.isEmpty {
                    Text("Todavía no hay registros de este ejercicio.").foregroundStyle(Theme.secondaryText)
                } else {
                    Chart(points) { point in
                        LineMark(x: .value("Fecha", point.date), y: .value(metric.name, point.value))
                            .foregroundStyle(Theme.glow)
                        PointMark(x: .value("Fecha", point.date), y: .value(metric.name, point.value))
                            .foregroundStyle(Theme.accent)
                    }
                    .frame(height: 220)
                    Text("Peso, e1RM y volumen en kg.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .listRowBackground(Theme.panel)

            Section("Alias") {
                Text(exercise.aliases.isEmpty ? "—" : exercise.aliases.joined(separator: ", "))
                Text("Stats: \(exercise.stats.map(\.name).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            .listRowBackground(Theme.panel)
        }
        .systemBackground()
        .navigationTitle(exercise.name)
        .toolbar {
            NavigationLink("Editar") { ExerciseEditorView(exercise: exercise) }
        }
    }

    private func record(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value ?? "—").foregroundStyle(Theme.glow)
        }
    }
}

struct CardioHistoryView: View {
    let markKey: String

    @Query(sort: \ExerciseLog.date) private var allLogs: [ExerciseLog]
    @State private var showPace = true

    private var logs: [ExerciseLog] { allLogs.filter { $0.markKey == markKey } }

    var body: some View {
        List {
            Section("Marcas") {
                HStack {
                    Text("Mayor distancia")
                    Spacer()
                    Text(logs.map(\.distanceKm).max().map(Format.distance) ?? "—").foregroundStyle(Theme.glow)
                }
                HStack {
                    Text("Mejor ritmo")
                    Spacer()
                    Text(logs.compactMap(\.pace).min().map { String(format: "%.2f min/km", $0) } ?? "—").foregroundStyle(Theme.glow)
                }
                HStack {
                    Text("Mayor tiempo")
                    Spacer()
                    Text(logs.map(\.seconds).max().map { Format.minutes($0 / 60) } ?? "—").foregroundStyle(Theme.glow)
                }
            }
            .listRowBackground(Theme.panel)
            Section("Historial") {
                Picker("Métrica", selection: $showPace) {
                    Text("Ritmo").tag(true)
                    Text("Distancia").tag(false)
                }
                .pickerStyle(.segmented)
                Chart(logs) { log in
                    if showPace {
                        if let pace = log.pace {
                            LineMark(x: .value("Fecha", log.date), y: .value("min/km", pace)).foregroundStyle(Theme.glow)
                        }
                    } else {
                        LineMark(x: .value("Fecha", log.date), y: .value("km", log.distanceKm)).foregroundStyle(Theme.glow)
                    }
                }
                .frame(height: 220)
            }
            .listRowBackground(Theme.panel)
        }
        .systemBackground()
        .navigationTitle(CardioModality(rawValue: markKey.replacingOccurrences(of: "cardio:", with: ""))?.name ?? "Cardio")
    }
}
