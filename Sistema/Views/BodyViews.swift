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
    @State private var quick: BodyMetric?

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

    private func last(_ metric: BodyMetric) -> (value: Double, date: Date)? {
        snapshots.last { $0.value(metric) != nil }.flatMap { snapshot in snapshot.value(metric).map { ($0, snapshot.date) } }
    }

    private var selectedMeasure: BodyMeasure? {
        if case let .measure(measure) = quick { return measure }
        return nil
    }

    private var measured: Set<BodyMeasure> { Set(snapshots.flatMap { $0.measures.keys }) }

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    tile(.weight)
                    tile(.bodyFat)
                    tile(.leanMass)
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 4, trailing: 12))
                BodyMapFigure(measured: measured, selected: selectedMeasure) { measure in
                    quick = .measure(measure)
                }
                .frame(height: 380)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowSeparator(.hidden)
            } header: {
                Text("Tocá una parte para medirla")
            } footer: {
                Text("Cada medida se guarda en el registro de hoy. Las zonas pintadas ya tienen medida.")
            }
            .listRowBackground(Theme.panel)

            if !measured.isEmpty {
                Section("Medidas") {
                    ForEach(BodyMeasure.allCases.filter(measured.contains)) { measure in
                        measureRow(measure)
                    }
                }
                .listRowBackground(Theme.panel)
            }

            if available.contains(where: { BodyTrend.make($0, entries: snapshots)?.hasHistory == true }) {
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
                                .foregroundStyle(Theme.accent)
                            PointMark(x: .value("Fecha", point.date), y: .value(metric.name, point.value))
                                .foregroundStyle(Theme.accent)
                                .symbolSize(30)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 200)
                    } else {
                        Text("Con un segundo registro de \(metric.name.lowercased()) aparece el gráfico.")
                            .foregroundStyle(Theme.secondaryText)
                    }
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
        .sheet(item: $quick) { metric in
            BodyValueSheet(metric: metric, last: last(metric), weightUnit: weightUnit)
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

    /// Cifra grande de peso, grasa o masa magra. La masa magra se calcula: no se toca.
    private func tile(_ item: BodyMetric) -> some View {
        let trend = BodyTrend.make(item, entries: snapshots)
        let editable = item != .leanMass
        return Button {
            quick = item
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.secondaryText)
                Text(trend.map { item.text($0.current, weightUnit: weightUnit) } ?? "—")
                    .font(Theme.display(22, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(trend.flatMap { $0.hasHistory ? changeText($0.changeSinceFirst, item) : nil } ?? (editable ? "Tocá para anotar" : "Peso + grasa"))
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.raised))
        }
        .buttonStyle(.plain)
        .disabled(!editable)
        .accessibilityIdentifier("body.tile.\(item.id)")
    }

    private func measureRow(_ measure: BodyMeasure) -> some View {
        let item = BodyMetric.measure(measure)
        let trend = BodyTrend.make(item, entries: snapshots)
        return Button {
            quick = item
        } label: {
            HStack {
                Text(measure.name).foregroundStyle(.white)
                Spacer()
                if let trend {
                    if trend.hasHistory {
                        Text(changeText(trend.changeSinceFirst, item))
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Text(item.text(trend.current, weightUnit: weightUnit))
                        .font(Theme.mono(16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
            }
        }
        .accessibilityIdentifier("body.measure.\(measure.rawValue)")
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
