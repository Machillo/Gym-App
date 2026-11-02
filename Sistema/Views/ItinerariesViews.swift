import SwiftData
import SwiftUI

@MainActor
struct ItinerariesView: View {
    @Environment(GameService.self) private var game
    @Query(sort: \Itinerary.startDate, order: .reverse) private var itineraries: [Itinerary]
    @Query private var routines: [Routine]

    var body: some View {
        List {
            if let active = itineraries.first(where: \.isActive) {
                Section("Activo") {
                    NavigationLink {
                        ItineraryEditorView(itinerary: active)
                    } label: {
                        ItineraryRow(itinerary: active, routines: routines)
                    }
                }
                .listRowBackground(Theme.panel)
            }
            let past = itineraries.filter { !$0.isActive }
            if !past.isEmpty {
                Section("Histórico") {
                    ForEach(past) { itinerary in
                        ItineraryRow(itinerary: itinerary, routines: routines)
                    }
                }
                .listRowBackground(Theme.panel)
            }
        }
        .systemBackground()
        .navigationTitle("Itinerarios")
        .toolbar {
            NavigationLink {
                ItineraryEditorView(itinerary: nil)
            } label: {
                Image(systemName: "plus")
            }
        }
        .overlay {
            if itineraries.isEmpty { ContentUnavailableView("Sin itinerarios", systemImage: "calendar") }
        }
    }
}

struct ItineraryRow: View {
    let itinerary: Itinerary
    let routines: [Routine]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(itinerary.name).font(.headline)
            Text("\(itinerary.startDate.formatted(date: .abbreviated, time: .omitted)) → \(itinerary.endDate.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            HStack(spacing: 6) {
                ForEach(itinerary.plan) { plan in
                    VStack(spacing: 2) {
                        Text(plan.weekday.shortName).font(.caption2.bold())
                        Image(systemName: plan.isRest ? "moon.zzz" : "bolt.fill")
                            .font(.caption2)
                            .foregroundStyle(plan.isRest ? Theme.secondaryText : Theme.glow)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            ForEach(itinerary.plan.filter { !$0.isRest }) { plan in
                Text("\(plan.weekday.name): \(routines.first { $0.id == plan.routineID }?.name ?? "—")")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

@MainActor
struct ItineraryEditorView: View {
    let itinerary: Itinerary?
    /// Días de un programa para precargar el plan semanal de un itinerario nuevo.
    var program: [Routine] = []

    @Environment(GameService.self) private var game
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Routine.name) private var routines: [Routine]
    @State private var name = ""
    @State private var start = Date()
    @State private var end = Date()
    @State private var plan: [DayPlan] = Weekday.allCases.map { DayPlan(weekday: $0) }
    @State private var loaded = false

    var body: some View {
        Form {
            Section("Itinerario") {
                TextField("Nombre", text: $name)
                DatePicker("Inicio", selection: $start, displayedComponents: .date)
                DatePicker("Fin", selection: $end, in: start..., displayedComponents: .date)
            }
            Section {
                ForEach($plan) { $day in
                    Picker(day.weekday.name, selection: $day.routineID) {
                        Text("Descanso").tag(UUID?.none)
                        ForEach(routines) { r in Text(r.name).tag(UUID?.some(r.id)) }
                    }
                }
            } header: {
                Text("Plan semanal")
            } footer: {
                Text("Los días de descanso nunca penalizan. Solo puede haber un itinerario activo: guardar uno nuevo archiva el anterior.")
            }
            if routines.isEmpty {
                Section {
                    NavigationLink("Crear una rutina primero") { RoutineEditorView(routine: nil) }
                }
            }
        }
        .systemBackground()
        .navigationTitle(itinerary == nil ? "Nuevo itinerario" : "Editar itinerario")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") {
                    let cleanName = name.trimmingCharacters(in: .whitespaces)
                    if let itinerary {
                        game.updateItinerary(itinerary, name: cleanName, start: start, end: end, plan: plan)
                    } else {
                        game.createItinerary(name: cleanName, start: start, end: end, plan: plan)
                        game.evaluate()
                    }
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let now = game.now
            if let itinerary {
                name = itinerary.name
                start = itinerary.startDate
                end = itinerary.endDate
                plan = itinerary.plan
            } else {
                name = "Itinerario \(game.itineraries().count + 1)"
                start = now
                end = SistemaCalendar.addDays(56, to: now)
                if let previous = game.itineraries().first { plan = previous.plan }
                if let first = program.first {
                    name = first.programName ?? name
                    if let change = first.programChangeDate, change > now { end = change }
                    let weekdays = ProgramSchedule.defaultWeekdays(dayCount: program.count)
                    plan = ProgramSchedule.plan(routineIDs: program.map(\.id), on: Set(weekdays))
                }
            }
        }
    }
}
