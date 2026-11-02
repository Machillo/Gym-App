import SwiftUI

enum Theme {
    static let background = Color(red: 0.02, green: 0.03, blue: 0.06)
    static let panel = Color(red: 0.04, green: 0.07, blue: 0.13)
    static let accent = Color(red: 0.25, green: 0.70, blue: 1.0)
    static let glow = Color(red: 0.0, green: 0.85, blue: 1.0)
    static let danger = Color(red: 1.0, green: 0.25, blue: 0.36)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.2)
    static let success = Color(red: 0.3, green: 0.95, blue: 0.6)
    static let secondaryText = Color.white.opacity(0.6)

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Ventana estilo "Sistema": panel oscuro con borde y brillo azul.
struct SystemPanel: ViewModifier {
    var tint: Color = Theme.accent

    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.panel.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(tint.opacity(0.85), lineWidth: 1)
            )
            .shadow(color: tint.opacity(0.35), radius: 10)
    }
}

extension View {
    func systemPanel(tint: Color = Theme.accent) -> some View {
        modifier(SystemPanel(tint: tint))
    }
}

struct PanelHeader: View {
    var title: String
    var symbol: String?
    var tint: Color = Theme.glow

    var body: some View {
        HStack(spacing: 8) {
            if let symbol { Image(systemName: symbol) }
            Text(title.uppercased())
                .font(Theme.mono(13, weight: .bold))
                .tracking(2)
            Spacer()
        }
        .foregroundStyle(tint)
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
                    .fill(LinearGradient(colors: [Theme.accent, tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * ratio)
                    .shadow(color: tint.opacity(0.8), radius: 6)
            }
        }
        .frame(height: 10)
        .animation(.easeOut(duration: 0.6), value: current)
    }
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
