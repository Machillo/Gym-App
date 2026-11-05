import SwiftUI

enum Theme {
    // Fondo casi negro y superficies planas: el color se reserva para lo que importa.
    static let background = Color(red: 0.039, green: 0.039, blue: 0.043)
    static let panel = Color(red: 0.086, green: 0.086, blue: 0.094)
    static let raised = Color(red: 0.13, green: 0.13, blue: 0.14)
    static let hairline = Color.white.opacity(0.07)
    /// Verde lima de pizarra de gimnasio. Texto encima: negro.
    static let accent = Color(red: 0.80, green: 0.96, blue: 0.29)
    /// Antes era un azul con brillo; ahora es el mismo acento, sin brillo.
    static let glow = accent
    static let danger = Color(red: 0.95, green: 0.33, blue: 0.29)
    static let warning = Color(red: 0.96, green: 0.65, blue: 0.14)
    static let success = accent
    static let secondaryText = Color.white.opacity(0.55)
    static let onAccent = Color.black.opacity(0.88)

    /// Números parejos (no salta el ancho al cambiar), en la letra del sistema.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }

    /// Cifras grandes: condensadas y pesadas, como un marcador.
    static func display(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight).width(.condensed).monospacedDigit()
    }
}

/// Tarjeta plana. Un color distinto al acento marca una alerta con una franja a la izquierda.
struct SystemPanel: ViewModifier {
    var tint: Color = Theme.accent

    private var isAlert: Bool { tint != Theme.accent }

    func body(content: Content) -> some View {
        content
            .padding(16)
            .padding(.leading, isAlert ? 4 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.panel)
            )
            .overlay(alignment: .leading) {
                if isAlert {
                    UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12, style: .continuous)
                        .fill(tint)
                        .frame(width: 4)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.hairline, lineWidth: 1)
            )
    }
}

extension View {
    func systemPanel(tint: Color = Theme.accent) -> some View {
        modifier(SystemPanel(tint: tint))
    }
}

/// Rótulo pequeño de sección. El símbolo se acepta por compatibilidad pero ya no se dibuja.
struct PanelHeader: View {
    var title: String
    var symbol: String?
    var tint: Color = Theme.glow

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(tint == Theme.glow ? Theme.secondaryText : tint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct XPBar: View {
    var current: Int
    var needed: Int
    var tint: Color = Theme.glow

    var body: some View {
        GeometryReader { geo in
            let ratio = needed > 0 ? min(max(Double(current) / Double(needed), 0), 1) : 1
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(tint)
                    .frame(width: max(geo.size.height, geo.size.width * ratio))
                    .opacity(ratio > 0 ? 1 : 0)
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.6), value: current)
    }
}

/// Botón principal: relleno con el color de `.tint` (acento por defecto) y texto oscuro.
struct PrimaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.onAccent)
            .padding(.vertical, 13)
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.tint))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.35)
    }
}

/// Botón secundario: superficie elevada y texto en el color de `.tint`.
struct SecondaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(.tint)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.raised))
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.35)
    }
}

extension ButtonStyle where Self == PrimaryActionStyle {
    static var primaryAction: PrimaryActionStyle { PrimaryActionStyle() }
}

extension ButtonStyle where Self == SecondaryActionStyle {
    static var secondaryAction: SecondaryActionStyle { SecondaryActionStyle() }
}

/// Fondo del Sistema para formularios y listas.
struct SystemBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
    }
}

extension View {
    func systemBackground() -> some View { modifier(SystemBackground()) }
}

extension Binding where Value == Double? {
    /// Expone un Double opcional como no opcional (nil ↔ 0).
    var orZero: Binding<Double> {
        Binding<Double>(
            get: { wrappedValue ?? 0 },
            set: { wrappedValue = $0 == 0 ? nil : $0 }
        )
    }
}

extension Binding where Value == Int? {
    var orZero: Binding<Int> {
        Binding<Int>(
            get: { wrappedValue ?? 0 },
            set: { wrappedValue = $0 == 0 ? nil : $0 }
        )
    }
}

extension Binding where Value == WeightUnit? {
    /// Sin unidad guardada, el peso está en kg.
    var orKg: Binding<WeightUnit> {
        Binding<WeightUnit>(
            get: { wrappedValue ?? .kg },
            set: { wrappedValue = $0 }
        )
    }
}

extension Binding where Value == String? {
    var orEmpty: Binding<String> {
        Binding<String>(
            get: { wrappedValue ?? "" },
            set: { wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}

extension Binding where Value == Double {
    /// Muestra y recibe en la unidad indicada un peso guardado en kg.
    /// Sin peso el campo queda vacío: con un 0 visible, escribir 25 terminaba en 250.
    func inUnit(_ unit: WeightUnit) -> Binding<Double?> {
        Binding<Double?>(
            get: { wrappedValue == 0 ? nil : (unit.fromKg(wrappedValue) * 100).rounded() / 100 },
            set: { wrappedValue = unit.toKg($0 ?? 0) }
        )
    }
}

/// Alterna entre kg y lb. El peso real no cambia: solo cómo se ve y se escribe.
struct WeightUnitToggle: View {
    @Binding var unit: WeightUnit

    var body: some View {
        Button(unit.symbol) { unit = unit.other }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Unidad: \(unit.symbol). Cambiar a \(unit.other.symbol)")
    }
}

/// Campo de peso con selector de unidad.
struct WeightField: View {
    var label: String
    @Binding var kg: Double
    @Binding var unit: WeightUnit
    var identifier: String?

    var body: some View {
        HStack {
            Text(label).foregroundStyle(Theme.secondaryText)
            Spacer()
            TextField("0", value: $kg.inUnit(unit), format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 80)
                .accessibilityIdentifier(identifier ?? label)
            WeightUnitToggle(unit: $unit)
        }
    }
}

/// Campo numérico compacto con etiqueta.
struct NumberField: View {
    var label: String
    @Binding var value: Double
    var identifier: String?

    var body: some View {
        HStack {
            Text(label).foregroundStyle(Theme.secondaryText)
            Spacer()
            TextField(label, value: $value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
                .accessibilityIdentifier(identifier ?? label)
        }
    }
}

struct IntField: View {
    var label: String
    @Binding var value: Int
    var identifier: String?

    var body: some View {
        HStack {
            Text(label).foregroundStyle(Theme.secondaryText)
            Spacer()
            TextField(label, value: $value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
                .accessibilityIdentifier(identifier ?? label)
        }
    }
}
