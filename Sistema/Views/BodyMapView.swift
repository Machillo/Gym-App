import SwiftUI

/// Una pieza de la figura. Las coordenadas están en un lienzo de 200 × 420 que luego se escala.
private struct BodyPart: Identifiable {
    let id: String
    let measure: BodyMeasure?
    let rect: CGRect
    let radius: CGFloat
    var rotation: Double = 0
    /// Cuánto se angosta arriba y abajo (fracción del ancho por lado): da forma de músculo.
    var taper: (top: CGFloat, bottom: CGFloat) = (0, 0)

    /// Vista de frente: el lado derecho de la persona queda a la izquierda de la pantalla.
    static let all: [BodyPart] = [
        BodyPart(id: "head", measure: nil, rect: CGRect(x: 80, y: 4, width: 40, height: 46), radius: 20),
        BodyPart(id: "neck", measure: .neck, rect: CGRect(x: 89, y: 53, width: 22, height: 16), radius: 6, taper: (0.08, 0)),
        BodyPart(id: "chest", measure: .chest, rect: CGRect(x: 66, y: 72, width: 68, height: 58), radius: 12, taper: (0, 0.09)),
        BodyPart(id: "shoulderR", measure: .shoulders, rect: CGRect(x: 44, y: 70, width: 32, height: 30), radius: 15),
        BodyPart(id: "shoulderL", measure: .shoulders, rect: CGRect(x: 124, y: 70, width: 32, height: 30), radius: 15),
        BodyPart(id: "waist", measure: .waist, rect: CGRect(x: 72, y: 133, width: 56, height: 45), radius: 10, taper: (0.02, 0.03)),
        BodyPart(id: "hips", measure: .hips, rect: CGRect(x: 66, y: 181, width: 68, height: 42), radius: 14, taper: (0.06, 0)),
        BodyPart(id: "armR", measure: .armRight, rect: CGRect(x: 45, y: 103, width: 22, height: 68), radius: 11, rotation: 7, taper: (0, 0.14)),
        BodyPart(id: "armL", measure: .armLeft, rect: CGRect(x: 133, y: 103, width: 22, height: 68), radius: 11, rotation: -7, taper: (0, 0.14)),
        BodyPart(id: "forearmR", measure: .forearm, rect: CGRect(x: 35, y: 175, width: 20, height: 62), radius: 10, rotation: 9, taper: (0, 0.2)),
        BodyPart(id: "forearmL", measure: .forearm, rect: CGRect(x: 145, y: 175, width: 20, height: 62), radius: 10, rotation: -9, taper: (0, 0.2)),
        BodyPart(id: "handR", measure: nil, rect: CGRect(x: 28, y: 240, width: 20, height: 24), radius: 10, rotation: 9),
        BodyPart(id: "handL", measure: nil, rect: CGRect(x: 152, y: 240, width: 20, height: 24), radius: 10, rotation: -9),
        BodyPart(id: "thighR", measure: .thighRight, rect: CGRect(x: 67, y: 226, width: 32, height: 92), radius: 15, taper: (0, 0.2)),
        BodyPart(id: "thighL", measure: .thighLeft, rect: CGRect(x: 101, y: 226, width: 32, height: 92), radius: 15, taper: (0, 0.2)),
        BodyPart(id: "calfR", measure: .calf, rect: CGRect(x: 70, y: 321, width: 27, height: 78), radius: 13, taper: (0.08, 0.28)),
        BodyPart(id: "calfL", measure: .calf, rect: CGRect(x: 103, y: 321, width: 27, height: 78), radius: 13, taper: (0.08, 0.28)),
        BodyPart(id: "footR", measure: nil, rect: CGRect(x: 64, y: 402, width: 32, height: 13), radius: 6),
        BodyPart(id: "footL", measure: nil, rect: CGRect(x: 104, y: 402, width: 32, height: 13), radius: 6),
    ]
}

/// Figura de frente. Cada zona que tiene medida se pinta; tocarla abre la medida nueva.
struct BodyMapFigure: View {
    var measured: Set<BodyMeasure>
    var selected: BodyMeasure?
    var onSelect: (BodyMeasure) -> Void

    private static let canvas = CGSize(width: 200, height: 420)

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / Self.canvas.width, geo.size.height / Self.canvas.height)
            ZStack(alignment: .topLeading) {
                ForEach(BodyPart.all) { part in
                    piece(part, scale: scale)
                }
                Text("DER.")
                    .position(x: 22 * scale, y: 14 * scale)
                Text("IZQ.")
                    .position(x: 178 * scale, y: 14 * scale)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.secondaryText)
            .frame(width: Self.canvas.width * scale, height: Self.canvas.height * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(Self.canvas.width / Self.canvas.height, contentMode: .fit)
    }

    /// El toque y la accesibilidad se ponen antes de rotar y ubicar la pieza:
    /// después de `.position` la vista ocupa todo el lienzo y cada zona taparía a las demás.
    private func piece(_ part: BodyPart, scale: CGFloat) -> some View {
        let shape = TaperedShape(top: part.taper.top, bottom: part.taper.bottom, radius: part.radius * scale)
        let isSelected = part.measure != nil && part.measure == selected
        let hasValue = part.measure.map(measured.contains) ?? false
        return shape
            .fill(isSelected ? Theme.accent : (hasValue ? Theme.accent.opacity(0.32) : Theme.raised))
            .overlay(shape.stroke(hasValue || isSelected ? Theme.accent : Color.white.opacity(0.10), lineWidth: 1))
            .frame(width: part.rect.width * scale, height: part.rect.height * scale)
            .contentShape(shape)
            .modifier(BodyPartTap(part: part, onSelect: onSelect))
            .rotationEffect(.degrees(part.rotation))
            .position(x: part.rect.midX * scale, y: part.rect.midY * scale)
    }
}

private struct BodyPartTap: ViewModifier {
    let part: BodyPart
    let onSelect: (BodyMeasure) -> Void

    func body(content: Content) -> some View {
        if let measure = part.measure {
            content
                .onTapGesture {
                    Haptics.tap()
                    onSelect(measure)
                }
                .accessibilityElement()
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(measure.name)
                .accessibilityIdentifier("bodymap.\(part.id)")
        } else {
            content.allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

/// Trapecio de esquinas redondeadas; sin angostamiento es un rectángulo redondeado.
private struct TaperedShape: Shape {
    var top: CGFloat
    var bottom: CGFloat
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let t = rect.width * top
        let b = rect.width * bottom
        let corners = [
            CGPoint(x: rect.minX + t, y: rect.minY), CGPoint(x: rect.maxX - t, y: rect.minY),
            CGPoint(x: rect.maxX - b, y: rect.maxY), CGPoint(x: rect.minX + b, y: rect.maxY),
        ]
        let r = max(0, min(radius, rect.width / 2 - max(t, b), rect.height / 2))
        var path = Path()
        path.move(to: CGPoint(x: (corners[3].x + corners[0].x) / 2, y: rect.midY))
        for index in corners.indices {
            path.addArc(tangent1End: corners[index], tangent2End: corners[(index + 1) % corners.count], radius: r)
        }
        path.closeSubpath()
        return path
    }
}

/// Hoja corta para anotar una sola medida y guardarla al toque.
@MainActor
struct BodyValueSheet: View {
    let metric: BodyMetric
    let last: (value: Double, date: Date)?
    var weightUnit: WeightUnit

    @Environment(GameService.self) private var game
    @Environment(\.dismiss) private var dismiss
    @State private var value: Double?
    @State private var unit: WeightUnit = .kg
    @FocusState private var focused: Bool

    private var unitText: String {
        metric == .weight ? unit.symbol : metric.unitSymbol
    }

    private var tip: String? {
        switch metric {
        case let .measure(measure): return measure.tip
        case .weight: return "En ayunas, después de ir al baño, siempre en la misma balanza."
        case .bodyFat: return "Con el mismo método cada vez (balanza, plicómetro o InBody)."
        case .muscleMass: return "En la hoja InBody: masa muscular esquelética."
        case .visceralFat: return "En la hoja InBody: nivel de grasa visceral (de 1 a 20)."
        case .inBodyScore: return "En la hoja InBody: los puntos, de 0 a 100."
        case .leanMass, .fatMass: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(metric.name).font(.title2.bold())
                Text(lastText).font(.subheadline).foregroundStyle(Theme.secondaryText)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField(placeholder, value: $value, format: .number.precision(.fractionLength(0...2)))
                    .font(Theme.display(56, weight: .bold))
                    .keyboardType(.decimalPad)
                    .focused($focused)
                    .accessibilityIdentifier("bodymap.value")
                if case .weight = metric {
                    WeightUnitToggle(unit: $unit)
                } else {
                    Text(unitText).font(.title3.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                }
            }
            if let tip {
                Text(tip).font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
            Button {
                guard let value, value > 0 else { return }
                game.recordBodyValue(metric, value: value, weightUnit: unit)
                Haptics.success()
                dismiss()
            } label: {
                Text("Guardar").frame(maxWidth: .infinity)
            }
            .buttonStyle(.primaryAction)
            .disabled((value ?? 0) <= 0)
            .accessibilityIdentifier("bodymap.save")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationBackground(Theme.background)
        .onAppear {
            unit = weightUnit
            focused = true
        }
    }

    private var placeholder: String {
        guard let last else { return "0" }
        let shown = metric == .weight ? weightUnit.fromKg(last.value) : last.value
        return shown.formatted(.number.precision(.fractionLength(0...1)))
    }

    private var lastText: String {
        guard let last else { return "Primera medida" }
        let date = last.date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "es_CR")))
        return "Última: \(metric.text(last.value, weightUnit: weightUnit)) · \(date)"
    }
}
