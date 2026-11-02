import SwiftUI

/// Primer arranque: nombre, primera rutina y primer itinerario.
struct OnboardingView: View {
    @Environment(GameService.self) private var game

    @State private var step = 0
    @State private var name = ""
    @State private var routineName = "Rutina A"
    @State private var blocks: [RoutineBlock] = []
    @State private var itineraryName = "Itinerario 1"
    @State private var weeks = 8
    @State private var trainingDays: Set<Weekday> = AppEnvironment.isUITesting
        ? Set(Weekday.allCases)
        : [.monday, .tuesday, .wednesday, .thursday, .friday]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("[ EL SISTEMA ]")
                        .font(Theme.mono(14, weight: .bold))
                        .tracking(4)
                        .foregroundStyle(Theme.glow)
                    switch step {
                    case 0: nameStep
                    case 1: routineStep
                    default: itineraryStep
                    }
                }
                .padding()
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Registro")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Has sido elegido como jugador.")
                .font(.title2.bold())
            Text("El Sistema medirá cada entrenamiento. Subirás de nivel con constancia y caerás si fallás. ¿Cómo te llamás?")
                .foregroundStyle(Theme.secondaryText)
            TextField("Nombre del jugador", text: $name)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("onboarding.name")
            Button {
                step = 1
            } label: {
                Text("Continuar").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityIdentifier("onboarding.next")
        }
        .systemPanel()
    }

    private var routineStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Primera rutina").font(.title2.bold())
            Text("Agregá bloques. Después podés editarlos con detalle en Entrenar > Rutinas.")
                .foregroundStyle(Theme.secondaryText)
            TextField("Nombre de la rutina", text: $routineName)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("onboarding.routineName")
            HStack {
                ForEach(BlockKind.allCases) { kind in
                    Button {
                        blocks.append(BlockTemplates.defaultBlock(kind))
                    } label: {
                        VStack {
                            Image(systemName: kind.symbol)
                            Text(kind.name).font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("onboarding.add.\(kind.rawValue)")
                }
            }
            ForEach(blocks) { block in
                HStack {
                    Label(block.summary, systemImage: block.kind.symbol).font(.subheadline)
                    Spacer()
                    Button {
                        blocks.removeAll { $0.id == block.id }
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            HStack {
                Button("Atrás") { step = 0 }
                Spacer()
                Button("Continuar") { step = 2 }
                    .buttonStyle(.borderedProminent)
                    .disabled(blocks.isEmpty || routineName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("onboarding.routineNext")
            }
        }
        .systemPanel()
    }

    private var itineraryStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Primer itinerario").font(.title2.bold())
            Text("Elegí qué días entrenás. Los días de descanso nunca penalizan.")
                .foregroundStyle(Theme.secondaryText)
            TextField("Nombre del itinerario", text: $itineraryName)
                .textFieldStyle(.roundedBorder)
            Stepper("Duración: \(weeks) semanas", value: $weeks, in: 1...26)
            HStack(spacing: 6) {
                ForEach(Weekday.allCases) { day in
                    let on = trainingDays.contains(day)
                    Button {
                        if on { trainingDays.remove(day) } else { trainingDays.insert(day) }
                    } label: {
                        Text(day.shortName)
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(on ? Theme.accent.opacity(0.35) : Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("onboarding.day.\(day.rawValue)")
                }
            }
            Text("Empieza hoy. El día de hoy no se penaliza.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            HStack {
                Button("Atrás") { step = 1 }
                Spacer()
                Button("Comenzar") { finish() }
                    .buttonStyle(.borderedProminent)
                    .disabled(trainingDays.isEmpty)
                    .accessibilityIdentifier("onboarding.finish")
            }
        }
        .systemPanel()
    }

    private func finish() {
        game.createPlayer(name: name)
        let routine = game.saveRoutine(nil, name: routineName.trimmingCharacters(in: .whitespaces), blocks: blocks)
        let plan = Weekday.allCases.map { DayPlan(weekday: $0, routineID: trainingDays.contains($0) ? routine.id : nil) }
        let start = game.now
        game.createItinerary(name: itineraryName, start: start, end: SistemaCalendar.addDays(weeks * 7 - 1, to: start), plan: plan)
        game.evaluate()
    }
}
