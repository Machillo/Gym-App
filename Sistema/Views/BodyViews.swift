import Charts
import SwiftData
import SwiftUI

@MainActor
struct BodyView: View {
    @Environment(GameService.self) private var game
    @Query(sort: \BodyEntry.date) private var entries: [BodyEntry]
    @State private var metric: BodyMetric = .weight
    @State private var editing: BodyEntry?
    @State private var adding = false
    @State private var toDelete: BodyEntry?

    private var snapshots: [BodySnapshot] { entries.map(\.snapshot) }
    /// Se muestra en la unidad del último peso registrado.
    private var weightUnit: WeightUnit { entries.last(where: { $0.weightKg != nil })?.weightUnit ?? .kg }
    private var available: [BodyMetric] { BodyMetric.all.filter { BodyTrend.make($0, entries: snapshots) != nil } }

    private func display(_ value: Double, _ metric: BodyMetric) -> Double {
        switch metric {
        case .weight, .leanMass: return weightUnit.fromKg(value)
        default: return value
        }
    }

    var body: some View {
        List {
            if !available.isEmpty {
                Section("Evolución") {
                    Picker("Métrica", selection: $metric) {
                        ForEach(available) { Text($0.name).tag($0) }
                    }
                    let points = snapshots.compactMap { snapshot in
                        snapshot.value(metric).map { ChartPoint(date: snapshot.date, value: display($0, metric)) }
                    }
                    if points.count > 1 {
                        Chart(points) { point in
                            LineMark(x: .value("Fecha", point.date), y: .value(metric.name, point.value))
                                .foregroundStyle(Theme.glow)
                            PointMark(x: .value("Fecha", point.date), y: .value(metric.name, point.value))
                                .foregroundStyle(Theme.accent)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 220)
                    } else {
                        Text("Con un segundo registro aparece el gráfico.").foregroundStyle(Theme.secondaryText)
                    }
                }
                .listRowBackground(Theme.panel)

                Section {
                    ForEach(available) { item in
                        if let trend = BodyTrend.make(item, entries: snapshots) {
                            HStack {
                                Text(item.name)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(item.text(trend.current, weightUnit: weightUnit)).foregroundStyle(Theme.glow)
                                    if trend.hasHistory {
                                        Text(changeText(trend.changeSinceFirst, item))
                                            .font(.caption)
                                            .foregroundStyle(Theme.secondaryText)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Lo más reciente")
                } footer: {
                    Text("El cambio se cuenta desde tu primer registro. La masa magra se calcula con el peso y la grasa de un mismo día.")
                }
                .listRowBackground(Theme.panel)
            }

            Section("Registros") {
                ForEach(entries.reversed()) { entry in
                    Button {
                        editing = entry
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.date.formatted(date: .abbreviated, time: .omitted)).font(.headline)
                            Text(summary(entry)).font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .tint(.white)
                    .swipeActions {
                        Button("Borrar", role: .destructive) { toDelete = entry }
                    }
                }
            }
            .listRowBackground(Theme.panel)
        }
        .systemBackground()
        .navigationTitle("Cuerpo")
        .toolbar {
            Button {
                adding = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Agregar registro")
            .accessibilityIdentifier("body.add")
        }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView("Sin registros", systemImage: "figure.stand",
                                       description: Text("Apuntá tu peso, grasa y medidas para ver cómo cambiás."))
            }
        }
        .sheet(isPresented: $adding) {
            NavigationStack { BodyEntryEditor(entry: nil) }
        }
        .sheet(item: $editing) { entry in
            NavigationStack { BodyEntryEditor(entry: entry) }
        }
        .confirmationDialog("¿Borrar este registro?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Borrar", role: .destructive) {
                if let toDelete { game.deleteBodyEntry(toDelete) }
                toDelete = nil
            }
        }
        .onChange(of: available) { _, list in
            if !list.contains(metric), let first = list.first { metric = first }
        }
        .onAppear {
            if !available.contains(metric), let first = available.first { metric = first }
        }
    }

    private func changeText(_ change: Double, _ item: BodyMetric) -> String {
        let sign = change > 0 ? "+" : (change < 0 ? "−" : "")
        return sign + item.text(abs(change), weightUnit: weightUnit)
    }

    private func summary(_ entry: BodyEntry) -> String {
        var parts: [String] = []
        if let weight = entry.weightKg { parts.append(Format.weight(weight, unit: entry.weightUnit)) }
        if let fat = entry.bodyFatPercent { parts.append(BodyMetric.bodyFat.text(fat, weightUnit: .kg)) }
        if !entry.measures.isEmpty { parts.append(Format.count(entry.measures.count, "medida")) }
        return parts.isEmpty ? "Sin datos" : parts.joined(separator: " · ")
    }
}

@MainActor
struct BodyEntryEditor: View {
    let entry: BodyEntry?

    @Environment(GameService.self) private var game
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var weight: Double?
    @State private var unit: WeightUnit = .kg
    @State private var bodyFat: Double?
    @State private var measures: [BodyMeasure: Double] = [:]
    @State private var notes = ""
    @State private var loaded = false

    private var hasData: Bool { weight != nil || bodyFat != nil || !measures.isEmpty }

    var body: some View {
        Form {
            Section {
                DatePicker("Fecha", selection: $date, in: ...game.now, displayedComponents: .date)
                HStack {
                    Text("Peso")
                    Spacer()
                    TextField("—", value: $weight, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90)
                        .accessibilityIdentifier("body.weight")
                    WeightUnitToggle(unit: $unit)
                }
                numberRow("Grasa corporal", unit: "%", value: $bodyFat, identifier: "body.fat")
            } header: {
                Text("General")
            } footer: {
                Text("Llená solo lo que mediste. Medite en condiciones parecidas para poder comparar.")
            }
            Section("Medidas (cm)") {
                ForEach(BodyMeasure.allCases) { measure in
                    numberRow(measure.name, unit: "cm", value: Binding(
                        get: { measures[measure] },
                        set: { measures[measure] = $0 }
                    ), identifier: "body.\(measure.rawValue)")
                }
            }
            Section("Notas") {
                TextField("Opcional", text: $notes, axis: .vertical)
            }
        }
        .systemBackground()
        .navigationTitle(entry == nil ? "Nuevo registro" : "Editar registro")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") {
                    game.saveBodyEntry(entry, date: date, weightKg: weight.map(unit.toKg), weightUnit: unit,
                                       bodyFatPercent: bodyFat, measures: measures, notes: notes)
                    dismiss()
                }
                .disabled(!hasData)
                .accessibilityIdentifier("body.save")
            }
        }
        .onAppear(perform: load)
    }

    private func numberRow(_ label: String, unit: String, value: Binding<Double?>, identifier: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("—", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
                .accessibilityIdentifier(identifier)
            Text(unit).foregroundStyle(Theme.secondaryText)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        date = game.now
        unit = game.bodyEntries().last(where: { $0.weightKg != nil })?.weightUnit ?? .kg
        if let entry {
            date = entry.date
            unit = entry.weightUnit
            weight = entry.weightKg.map(entry.weightUnit.fromKg)
            bodyFat = entry.bodyFatPercent
            measures = entry.measures
            notes = entry.notes
        }
    }
}
