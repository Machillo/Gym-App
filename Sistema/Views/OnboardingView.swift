import SwiftUI

/// Primer arranque: nombre, la rutina del jugador y su primer itinerario.
@MainActor
struct OnboardingView: View {
    @Environment(GameService.self) private var game

    @State private var step = 0
    @State private var name = ""
    @State private var routineName = ""
    @State private var routineText = ""
    @State private var itineraryName = "Itinerario 1"
    @State private var weeks = 8
    @State private var trainingDays: Set<Weekday> = AppEnvironment.isUITesting
        ? Set(Weekday.allCases)
        : [.monday, .tuesday, .wednesday, .thursday, .friday]

    private var days: [ProgramDay] { RoutineTextParser.parseProgram(routineText) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("EL SISTEMA")
                        .font(.caption.weight(.semibold))
                        .tracking(1.5)
                        .foregroundStyle(Theme.secondaryText)
                    switch step {
                    case 0: nameStep
                    case 1: routineStep
                    default: itineraryStep
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
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
            .buttonStyle(.primaryAction)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityIdentifier("onboarding.next")
        }
        .systemPanel()
    }

    private var routineStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tu rutina").font(.title2.bold())
            Text("Escribí o pegá la rutina que vas a seguir. El Sistema no te da rutinas: le da seguimiento a la tuya.")
                .foregroundStyle(Theme.secondaryText)
            TextField("Nombre de la rutina", text: $routineName)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("onboarding.routineName")
            TextEditor(text: $routineText)
                .font(.footnote)
                .frame(minHeight: 160)
                .scrollContentBackground(.hidden)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("onboarding.routineText")
            Text("Un ejercicio por línea, con su medida. Si tiene varios días, empezá cada uno con «Día 1», «Día 2»…")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                Text(day.name).font(.subheadline.bold()).foregroundStyle(Theme.glow)
                ForEach(day.blocks) { BlockPreview(block: $0) }
            }
            HStack {
                Button("Atrás") { step = 0 }
                Spacer()
                Button("Continuar") {
                    if days.count > 1 { trainingDays = Set(ProgramSchedule.defaultWeekdays(dayCount: days.count)) }
                    step = 2
                }
                .buttonStyle(.primaryAction)
                .disabled(days.isEmpty || routineName.trimmingCharacters(in: .whitespaces).isEmpty)
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
                    .buttonStyle(.primaryAction)
                    .disabled(trainingDays.isEmpty)
                    .accessibilityIdentifier("onboarding.finish")
            }
        }
        .systemPanel()
    }

    private func finish() {
        game.createPlayer(name: name)
        let cleanName = routineName.trimmingCharacters(in: .whitespaces)
        let routineIDs: [UUID]
        if days.count > 1 {
            routineIDs = game.saveProgram(name: cleanName, changeDate: nil, days: days).map(\.id)
        } else {
            routineIDs = [game.saveRoutine(nil, name: cleanName, blocks: days.flatMap(\.blocks)).id]
        }
        let plan = ProgramSchedule.plan(routineIDs: routineIDs, on: trainingDays)
        let start = game.now
        game.createItinerary(name: itineraryName, start: start, end: SistemaCalendar.addDays(weeks * 7 - 1, to: start), plan: plan)
        game.evaluate()
    }
}
