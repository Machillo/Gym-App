import SwiftUI
import UIKit

/// Rango y paso de cada dato de la hoja InBody, en kg, % o puntos.
struct InBodyField {
    let metric: BodyMetric
    let range: ClosedRange<Double>
    let step: Double
    /// Separación entre rayitas de la regla.
    let spacing: CGFloat
    /// Cada cuántas rayitas va un número.
    let labelEvery: Int
    let fallback: Double
    let hint: String

    var decimals: Int { step < 1 ? 1 : 0 }

    static let all: [InBodyField] = [
        InBodyField(metric: .weight, range: 30...200, step: 0.1, spacing: 9, labelEvery: 10, fallback: 75,
                    hint: "Arriba de todo en la hoja: Peso."),
        InBodyField(metric: .muscleMass, range: 10...70, step: 0.1, spacing: 9, labelEvery: 10, fallback: 30,
                    hint: "Masa muscular esquelética, en kg."),
        InBodyField(metric: .bodyFat, range: 3...60, step: 0.1, spacing: 9, labelEvery: 10, fallback: 25,
                    hint: "Porcentaje de grasa corporal. Los kilos de grasa se calculan solos."),
        InBodyField(metric: .visceralFat, range: 1...20, step: 1, spacing: 34, labelEvery: 1, fallback: 8,
                    hint: "Nivel de grasa visceral, de 1 a 20."),
        InBodyField(metric: .inBodyScore, range: 30...100, step: 1, spacing: 16, labelEvery: 5, fallback: 70,
                    hint: "Los puntos InBody, abajo a la derecha."),
    ]

    func clamp(_ value: Double) -> Double {
        let snapped = (value / step).rounded() * step
        return min(max(snapped, range.lowerBound), range.upperBound)
    }

    func text(_ value: Double) -> String {
        decimals == 0 ? String(Int(value.rounded())) : String(format: "%.1f", value)
    }
}

/// Regla horizontal: se arrastra con el dedo y vibra en cada rayita, como la balanza de Salud.
struct RulerPicker: View {
    @Binding var value: Double
    let field: InBodyField
    var tint: Color = Theme.accent

    @State private var dragStart: Double?
    private let haptic = UISelectionFeedbackGenerator()

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            Canvas { context, size in
                let center = width / 2
                let visible = Int(width / field.spacing / 2) + 2
                let currentIndex = Int(((value - field.range.lowerBound) / field.step).rounded())
                let offset = CGFloat((value - field.range.lowerBound) / field.step - Double(currentIndex)) * field.spacing
                for delta in -visible...visible {
                    let index = currentIndex + delta
                    let tickValue = field.range.lowerBound + Double(index) * field.step
                    guard tickValue >= field.range.lowerBound - 0.0001, tickValue <= field.range.upperBound + 0.0001 else { continue }
                    let x = center + CGFloat(delta) * field.spacing - offset
                    let major = index % field.labelEvery == 0
                    let half = field.labelEvery >= 10 && index % (field.labelEvery / 2) == 0
                    let height: CGFloat = major ? 34 : (half ? 24 : 14)
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: 8))
                    tick.addLine(to: CGPoint(x: x, y: 8 + height))
                    context.stroke(tick, with: .color(.white.opacity(major ? 0.7 : 0.28)), lineWidth: major ? 2 : 1)
                    if major {
                        context.draw(Text(field.text(tickValue)).font(Theme.mono(13, weight: .semibold))
                                        .foregroundStyle(Theme.secondaryText),
                                     at: CGPoint(x: x, y: size.height - 12))
                    }
                }
            }
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18),
                                         .init(color: .black, location: 0.82), .init(color: .clear, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
            .overlay {
                Capsule().fill(tint).frame(width: 4, height: 50).offset(y: -12)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let start = dragStart ?? value
                        if dragStart == nil { dragStart = value; haptic.prepare() }
                        let next = field.clamp(start - Double(gesture.translation.width / field.spacing) * field.step)
                        if next != value {
                            value = next
                            haptic.selectionChanged()
                        }
                    }
                    .onEnded { _ in dragStart = nil }
            )
        }
        .frame(height: 84)
        .accessibilityElement()
        .accessibilityLabel(field.metric.name)
        .accessibilityValue("\(field.text(value)) \(field.metric.unitSymbol)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = field.clamp(value + field.step)
            case .decrement: value = field.clamp(value - field.step)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("inbody.ruler")
    }
}

/// Medición InBody paso a paso: un dato por pantalla, número grande, regla y comparación con la anterior.
@MainActor
struct InBodyFlowView: View {
    @Environment(GameService.self) private var game
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var values: [String: Double] = [:]
    @State private var skipped: Set<String> = []
    @State private var date = Date()
    @State private var typing = false
    @State private var typed: Double?
    @FocusState private var typingFocused: Bool
    @State private var loaded = false

    private let fields = InBodyField.all
    private var isSummary: Bool { step >= fields.count }
    private var snapshots: [BodySnapshot] { game.bodyEntries().map(\.snapshot) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isSummary {
                summary.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))
            } else {
                page(fields[step])
                    .id(step)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear(perform: load)
    }

    // MARK: - Partes

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                if step > 0 { withAnimation(.snappy) { step -= 1 } } else { dismiss() }
            } label: {
                Image(systemName: step > 0 ? "chevron.left" : "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.raised))
            }
            .foregroundStyle(.white)
            .accessibilityLabel(step > 0 ? "Atrás" : "Cerrar")
            HStack(spacing: 5) {
                ForEach(0...fields.count, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Theme.accent : Color.white.opacity(0.12))
                        .frame(height: 4)
                }
            }
            Text(isSummary ? "Listo" : "\(step + 1)/\(fields.count)")
                .font(Theme.mono(13, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func page(_ field: InBodyField) -> some View {
        let key = field.metric.id
        let binding = Binding<Double>(get: { values[key] ?? field.fallback }, set: { values[key] = $0 })
        let previous = BodyTrend.make(field.metric, entries: snapshots)
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("MEDICIÓN INBODY")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.secondaryText)
                Text(field.metric.name)
                    .font(Theme.display(40, weight: .black))
                Text(field.hint)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 28)

            Spacer(minLength: 12)

            Button {
                typed = nil
                typing = true
                typingFocused = true
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(field.text(binding.wrappedValue))
                        .font(Theme.display(104, weight: .black))
                        .contentTransition(.numericText(value: binding.wrappedValue))
                        .animation(.snappy(duration: 0.15), value: binding.wrappedValue)
                    Text(field.metric.unitSymbol)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            }
            .accessibilityLabel("Escribir \(field.metric.name)")
            .accessibilityIdentifier("inbody.value")

            deltaChip(field: field, value: binding.wrappedValue, previous: previous)
                .padding(.top, 6)

            Spacer(minLength: 12)

            HStack(spacing: 14) {
                nudge("minus", field: field, by: -field.step, value: binding)
                RulerPicker(value: binding, field: field)
                nudge("plus", field: field, by: field.step, value: binding)
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 20)

            HStack(spacing: 12) {
                Button {
                    skipped.insert(key)
                    advance()
                } label: {
                    Text("No la tengo").frame(maxWidth: .infinity)
                }
                .buttonStyle(.secondaryAction)
                .tint(.white)
                .accessibilityIdentifier("inbody.skip")
                Button {
                    skipped.remove(key)
                    values[key] = binding.wrappedValue
                    advance()
                } label: {
                    Text("Siguiente").frame(maxWidth: .infinity)
                }
                .buttonStyle(.primaryAction)
                .accessibilityIdentifier("inbody.next")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .overlay(alignment: .bottom) {
            if typing { typingBar(field: field, value: binding) }
        }
    }

    private func typingBar(field: InBodyField, value: Binding<Double>) -> some View {
        HStack(spacing: 12) {
            TextField(field.text(value.wrappedValue), value: $typed, format: .number.precision(.fractionLength(0...field.decimals)))
                .keyboardType(field.decimals == 0 ? .numberPad : .decimalPad)
                .focused($typingFocused)
                .font(Theme.display(28, weight: .bold))
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.raised))
                .accessibilityIdentifier("inbody.typed")
            Button {
                if let typed { value.wrappedValue = field.clamp(typed) }
                typing = false
                typingFocused = false
            } label: {
                Text("Listo").frame(height: 26)
            }
            .buttonStyle(.primaryAction)
            .accessibilityIdentifier("inbody.typedDone")
        }
        .padding(16)
        .background(Theme.panel.ignoresSafeArea(edges: .bottom))
    }

    private func nudge(_ symbol: String, field: InBodyField, by amount: Double, value: Binding<Double>) -> some View {
        Button {
            value.wrappedValue = field.clamp(value.wrappedValue + amount)
            Haptics.tap()
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.bold))
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.raised))
        }
        .foregroundStyle(.white)
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(amount > 0 ? "Subir" : "Bajar")
    }

    @ViewBuilder
    private func deltaChip(field: InBodyField, value: Double, previous: BodyTrend?) -> some View {
        if let previous, let when = previous.date {
            let change = value - previous.current
            let date = when.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "es_CR")))
            HStack(spacing: 6) {
                if abs(change) >= field.step / 2 {
                    Image(systemName: change > 0 ? "arrow.up.right" : "arrow.down.right")
                    Text("\(field.text(abs(change))) \(field.metric.unitSymbol)")
                } else {
                    Text("Igual")
                }
                Text("vs \(date)").foregroundStyle(Theme.secondaryText)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(InBodyColors.change(change, field.metric, step: field.step))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Theme.raised))
        } else {
            Text("Primera medición")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    // MARK: - Resumen

    private var summary: some View {
        let recorded = fields.filter { !skipped.contains($0.metric.id) && values[$0.metric.id] != nil }
        let draft = draftSnapshot
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("RESUMEN")
                        .font(.caption.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(Theme.secondaryText)
                    Text("Así vas")
                        .font(Theme.display(40, weight: .black))
                }
                DatePicker("Fecha de la medición", selection: $date, in: ...game.now)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.panel))

                VStack(spacing: 0) {
                    ForEach(Array(summaryRows(draft: draft).enumerated()), id: \.offset) { index, row in
                        if index > 0 { Divider().overlay(Theme.hairline) }
                        summaryRow(row)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.panel))

                Text("Grasa en kg y masa magra salen del peso y el porcentaje. Peso, grasa y masa magra también se guardan en Salud.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: save) {
                Text("Guardar medición").frame(maxWidth: .infinity)
            }
            .buttonStyle(.primaryAction)
            .disabled(recorded.isEmpty)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Theme.background)
            .accessibilityIdentifier("inbody.save")
        }
    }

    private struct SummaryRow {
        var metric: BodyMetric
        var value: Double
        var change: Double?
        var step: Double
    }

    private var draftSnapshot: BodySnapshot {
        func v(_ metric: BodyMetric) -> Double? { skipped.contains(metric.id) ? nil : values[metric.id] }
        return BodySnapshot(date: date, weightKg: v(.weight), bodyFatPercent: v(.bodyFat), measures: [:],
                            skeletalMuscleKg: v(.muscleMass), visceralFatLevel: v(.visceralFat), inBodyScore: v(.inBodyScore))
    }

    private func summaryRows(draft: BodySnapshot) -> [SummaryRow] {
        let before = snapshots.filter { SistemaCalendar.startOfDay($0.date) < SistemaCalendar.startOfDay(date) }
        return (BodyMetric.inBody + [.leanMass]).compactMap { metric in
            guard let value = draft.value(metric) else { return nil }
            let last = BodyTrend.make(metric, entries: before)?.current
            return SummaryRow(metric: metric, value: value, change: last.map { value - $0 },
                              step: fields.first { $0.metric == metric }?.step ?? 0.1)
        }
    }

    private func summaryRow(_ row: SummaryRow) -> some View {
        HStack {
            Text(row.metric.name)
            Spacer()
            if let change = row.change, abs(change) >= row.step / 2 {
                Text((change > 0 ? "+" : "−") + row.metric.text(abs(change), weightUnit: .kg))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(InBodyColors.change(change, row.metric, step: row.step))
            }
            Text(row.metric.text(row.value, weightUnit: .kg))
                .font(Theme.mono(17, weight: .bold))
                .frame(minWidth: 86, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    // MARK: - Acciones

    private func load() {
        guard !loaded else { return }
        loaded = true
        date = game.now
        // Arranca en lo último que mediste: casi siempre se mueve poco.
        for field in fields {
            if let last = BodyTrend.make(field.metric, entries: snapshots)?.current { values[field.metric.id] = field.clamp(last) }
        }
    }

    private func advance() {
        typing = false
        Haptics.tap()
        withAnimation(.snappy) { step += 1 }
    }

    private func save() {
        let draft = draftSnapshot
        let day = SistemaCalendar.startOfDay(date)
        let existing = game.bodyEntries().last { SistemaCalendar.startOfDay($0.date) == day }
        game.saveBodyEntry(existing, date: existing?.date ?? date,
                           weightKg: draft.weightKg ?? existing?.weightKg,
                           weightUnit: existing?.weightUnit ?? .kg,
                           bodyFatPercent: draft.bodyFatPercent ?? existing?.bodyFatPercent,
                           measures: existing?.measures ?? [:],
                           notes: existing?.notes ?? "InBody",
                           skeletalMuscleKg: draft.skeletalMuscleKg ?? existing?.skeletalMuscleKg,
                           visceralFatLevel: draft.visceralFatLevel.map { Int($0.rounded()) } ?? existing?.visceralFatLevel,
                           inBodyScore: draft.inBodyScore.map { Int($0.rounded()) } ?? existing?.inBodyScore)
        Haptics.success()
        dismiss()
    }
}

enum InBodyColors {
    /// Verde si el cambio va en la buena dirección, rojo si no, gris si es neutro o no hay cambio.
    static func change(_ change: Double, _ metric: BodyMetric, step: Double = 0.1) -> Color {
        guard abs(change) >= step / 2, let upIsGood = metric.upIsGood else { return Theme.secondaryText }
        return (change > 0) == upIsGood ? Theme.accent : Theme.danger
    }
}
