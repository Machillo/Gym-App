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
    @State private var measuring = false

    private var snapshots: [BodySnapshot] { entries.map(\.snapshot) }
    /// Se muestra en la unidad del último peso registrado.
    private var weightUnit: WeightUnit { entries.last(where: { $0.weightKg != nil })?.weightUnit ?? .kg }
    private var available: [BodyMetric] { BodyMetric.all.filter { BodyTrend.make($0, entries: snapshots) != nil } }

    private func display(_ value: Double, _ metric: BodyMetric) -> Double {
        switch metric {
        case .weight, .leanMass, .muscleMass, .fatMass: return weightUnit.fromKg(value)
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
                inBodyCard
                    .listRowInsets(EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))
            }
            .listRowBackground(Theme.panel)

            Section {
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
        .fullScreenCover(isPresented: $measuring) {
            InBodyFlowView()
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

    private var latestInBody: Date? {
        snapshots.last { $0.weightKg != nil || $0.skeletalMuscleKg != nil || $0.inBodyScore != nil }?.date
    }

    /// Lo último de la hoja InBody, cada dato con su cambio contra la medición anterior.
    private var inBodyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Composición corporal").font(.title3.bold())
                    if let latest = latestInBody {
                        let days = SistemaCalendar.daysBetween(latest, game.now)
                        Text("Última medición: \(latest.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "es_CR"))))"
                             + (days > 0 ? " · hace \(Format.count(days, "día"))" : " · hoy"))
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    } else {
                        Text("Todavía sin mediciones").font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                }
                Spacer()
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible())],
                      spacing: 10) {
                ForEach(BodyMetric.inBody) { tile($0) }
            }
            Button {
                measuring = true
            } label: {
                Label("Nueva medición", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(.primaryAction)
            .accessibilityIdentifier("body.newMeasurement")
        }
    }

    /// Cifra grande con su cambio. Los datos calculados (grasa en kg) no se tocan.
    private func tile(_ item: BodyMetric) -> some View {
        let trend = BodyTrend.make(item, entries: snapshots)
        let editable = !item.isDerived
        let step = InBodyField.all.first { $0.metric == item }?.step ?? 0.1
        let card = VStack(alignment: .leading, spacing: 3) {
                Text(shortName(item).uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(0.5)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                Text(trend.map { tileValue($0.current, item) } ?? "—")
                    .font(Theme.display(24, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let trend, trend.hasHistory, abs(trend.changeSincePrevious) >= step / 2 {
                    Text((trend.changeSincePrevious > 0 ? "▲ " : "▼ ") + tileValue(abs(trend.changeSincePrevious), item, unit: false))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(InBodyColors.change(trend.changeSincePrevious, item, step: step))
                } else {
                    Text(trend == nil ? (editable ? "Tocá" : "Calculado") : "Sin cambio")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.raised))
        return Group {
            if editable {
                Button { quick = item } label: { card }.buttonStyle(.plain)
            } else {
                card.accessibilityElement(children: .combine)
            }
        }
        .accessibilityIdentifier("body.tile.\(item.id)")
    }

    private func shortName(_ item: BodyMetric) -> String {
        switch item {
        case .muscleMass: return "Músculo"
        case .bodyFat: return "% Grasa"
        case .fatMass: return "Grasa kg"
        case .visceralFat: return "Visceral"
        case .inBodyScore: return "Puntos"
        default: return item.name
        }
    }

    /// Número compacto para la tarjeta: sin repetir "kg" en cada una.
    private func tileValue(_ value: Double, _ item: BodyMetric, unit: Bool = true) -> String {
        switch item {
        case .weight, .muscleMass, .fatMass, .leanMass:
            let shown = weightUnit.fromKg(value)
            return String(format: "%.1f", shown) + (unit ? " \(weightUnit.symbol)" : "")
        case .bodyFat: return String(format: "%.1f", value) + (unit ? " %" : "")
        case .visceralFat, .inBodyScore: return String(Int(value.rounded()))
        case .measure: return String(format: "%.1f", value)
        }
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
        if let muscle = entry.skeletalMuscleKg { parts.append("músculo " + Format.weight(muscle, unit: entry.weightUnit)) }
        if let score = entry.inBodyScore { parts.append("\(score) pts") }
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
    @State private var muscle: Double?
    @State private var visceral: Double?
    @State private var score: Double?
    @State private var loaded = false

    private var hasData: Bool {
        weight != nil || bodyFat != nil || !measures.isEmpty || muscle != nil || visceral != nil || score != nil
    }

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
                numberRow("Masa muscular", unit: "kg", value: $muscle, identifier: "body.muscle")
                numberRow("Grasa visceral", unit: "nivel", value: $visceral, identifier: "body.visceral")
                numberRow("Puntos InBody", unit: "pts", value: $score, identifier: "body.score")
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
                                       bodyFatPercent: bodyFat, measures: measures, notes: notes,
                                       skeletalMuscleKg: muscle, visceralFatLevel: visceral.map { Int($0.rounded()) },
                                       inBodyScore: score.map { Int($0.rounded()) })
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
            muscle = entry.skeletalMuscleKg
            visceral = entry.visceralFatLevel.map(Double.init)
            score = entry.inBodyScore.map(Double.init)
        }
    }
}
