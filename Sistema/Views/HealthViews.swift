import SwiftUI

/// Colores de los aros de Fitness, para que se reconozcan al toque.
private enum RingColor {
    static let move = Color(red: 0.98, green: 0.07, blue: 0.31)
    static let exercise = Color(red: 0.65, green: 1.0, blue: 0.0)
    static let stand = Color(red: 0.0, green: 0.94, blue: 1.0)
}

/// Un aro que puede pasar de la vuelta, como en Fitness.
struct ActivityRing: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if progress > 1 {
                Circle()
                    .trim(from: 0, to: min(progress - 1, 1))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .brightness(-0.15)
            }
        }
        .padding(lineWidth / 2)
    }
}

/// Aros y pasos de hoy en la pantalla Estado. Si Salud no está conectada, invita a conectarla.
@MainActor
struct ActivityTodayCard: View {
    @Environment(GameService.self) private var game

    var body: some View {
        if !game.health.isAvailable {
            EmptyView()
        } else if !game.healthConnected {
            connectCard
        } else if let activity = game.activity {
            summary(activity)
        } else {
            HStack {
                ProgressView()
                Text("Leyendo Salud…").foregroundStyle(Theme.secondaryText)
            }
            .systemPanel()
        }
    }

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelHeader(title: "Apple Salud")
            Text("Conectá Salud para traer solos tus entrenamientos del Watch, tus pasos y tus aros, y mandar tus clases de pelea y tus medidas.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            Button {
                Task { await game.connectHealth() }
            } label: {
                Label("Conectar con Salud", systemImage: "heart.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.primaryAction)
            .accessibilityIdentifier("health.connect")
        }
        .systemPanel()
    }

    private func summary(_ activity: HealthActivitySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelHeader(title: "Actividad de hoy")
            HStack(spacing: 16) {
                if activity.hasRings {
                    ZStack {
                        ActivityRing(progress: ratio(activity.moveKcal, activity.moveGoal), color: RingColor.move, lineWidth: 10)
                        ActivityRing(progress: ratio(activity.exerciseMinutes, activity.exerciseGoal), color: RingColor.exercise, lineWidth: 10)
                            .padding(12)
                        ActivityRing(progress: ratio(activity.standHours, activity.standGoal), color: RingColor.stand, lineWidth: 10)
                            .padding(24)
                    }
                    .frame(width: 86, height: 86)
                    .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    if activity.hasRings {
                        ringLine("Moverse", "\(Int(activity.moveKcal))/\(Int(activity.moveGoal)) kcal", RingColor.move)
                        ringLine("Ejercicio", "\(Int(activity.exerciseMinutes))/\(Int(activity.exerciseGoal)) min", RingColor.exercise)
                        ringLine("De pie", "\(Int(activity.standHours))/\(Int(activity.standGoal)) h", RingColor.stand)
                    }
                }
                Spacer(minLength: 0)
            }
            Divider().overlay(Theme.hairline)
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "figure.walk").foregroundStyle(Theme.accent)
                Text(activity.steps.formatted(.number.locale(Locale(identifier: "es_CR"))))
                    .font(Theme.display(28, weight: .bold))
                Text("pasos").foregroundStyle(Theme.secondaryText)
                Spacer()
                Text("Promedio 7 días: \(activity.stepsWeekAverage.formatted(.number.locale(Locale(identifier: "es_CR"))))")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            .accessibilityElement(children: .combine)
        }
        .systemPanel()
        .accessibilityIdentifier("health.activity")
    }

    private func ringLine(_ name: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Text(name).font(.subheadline).foregroundStyle(Theme.secondaryText)
            Text(value).font(Theme.mono(15, weight: .bold)).foregroundStyle(color)
        }
    }

    private func ratio(_ value: Double, _ goal: Double) -> Double { goal > 0 ? value / goal : 0 }
}

/// Sección de Ajustes con lo que se comparte y el botón para sincronizar.
@MainActor
struct HealthSettingsSection: View {
    @Environment(GameService.self) private var game

    var body: some View {
        Section {
            if !game.health.isAvailable {
                Text("Salud no está disponible en este dispositivo.").foregroundStyle(Theme.secondaryText)
            } else if game.healthConnected {
                Button {
                    Task { await game.syncHealth() }
                } label: {
                    HStack {
                        Label("Sincronizar ahora", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        if game.isSyncingHealth { ProgressView() }
                    }
                }
                .disabled(game.isSyncingHealth)
                if let last = game.lastHealthSync {
                    LabeledContent("Última vez", value: last.formatted(date: .omitted, time: .shortened))
                }
            } else {
                Button {
                    Task { await game.connectHealth() }
                } label: {
                    Label("Conectar con Salud", systemImage: "heart.fill")
                }
            }
        } header: {
            Text("Apple Salud")
        } footer: {
            Text("""
            Se traen solos los entrenamientos del Watch de los últimos \(GameService.healthWorkoutLookbackDays) días: si ese día ya registraste una \
            sesión del mismo tipo se unen; si no, se agregan con su XP. Si después registrás esa sesión, se une a la del Watch sin \
            duplicar. A Salud van tus clases de box, muay thai y MMA (calorías estimadas) y tu peso, grasa, masa magra y cintura. \
            Los permisos se cambian en Ajustes > Salud > Acceso a datos.
            """)
        }
    }
}

/// Calorías y pulso de una sesión, para el historial.
struct SessionHealthLine: View {
    let session: WorkoutSession

    var body: some View {
        if let text {
            Label(text, systemImage: session.healthWorkoutID != nil ? "applewatch" : "flame")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var text: String? {
        if session.healthWorkoutID != nil {
            var parts = [session.watchSource ?? "Apple Watch"]
            if let kcal = session.watchKcal { parts.append("\(Int(kcal)) kcal") }
            if let avg = session.watchAvgHR {
                parts.append("♥ \(Int(avg))" + (session.watchMaxHR.map { " · máx \(Int($0))" } ?? "") + " lpm")
            }
            return parts.joined(separator: " · ")
        }
        if let kcal = session.estimatedKcal { return "≈ \(Int(kcal)) kcal estimadas · en Salud" }
        return nil
    }
}
