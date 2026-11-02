import SwiftUI

/// Crea un programa completo (varios días, con sus bloques) a partir de un solo texto.
@MainActor
struct ProgramImportView: View {
    @Environment(GameService.self) private var game
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var hasChangeDate = true
    @State private var changeDate = Date()
    @State private var text = ""
    @State private var loaded = false

    private var days: [ProgramDay] { RoutineTextParser.parseProgram(text) }

    private static let example = """
    Día 1 - Bi Series
    BI SERIES X 3 ROUNDS
    Trap bar deadlift 6 reps
    Push up 10 reps

    Día 2 - Circuito
    TABATA - 45 SEC ON X 1 MIN OFF X 4 ROUNDS
    Goblet squat KB 45 sec
    """

    var body: some View {
        Form {
            Section("Programa") {
                TextField("Nombre (ej. PED-FighterWOD)", text: $name)
                    .accessibilityIdentifier("program.name")
                Toggle("Tiene fecha de cambio", isOn: $hasChangeDate)
                if hasChangeDate {
                    DatePicker("Cambio de rutina", selection: $changeDate, displayedComponents: .date)
                }
            }
            Section {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(Self.example)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText.opacity(0.6))
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .font(.footnote)
                        .frame(minHeight: 200)
                        .scrollContentBackground(.hidden)
                        .accessibilityIdentifier("program.text")
                }
            } header: {
                Text("Rutina completa")
            } footer: {
                Text("Escribila o pegala. Desde una captura: en Fotos mantené presionado el texto, tocá Copiar y pegalo acá. Revisá abajo cómo quedó antes de guardar.")
            }
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                Section(day.name) {
                    ForEach(day.blocks) { BlockPreview(block: $0) }
                }
            }
        }
        .systemBackground()
        .navigationTitle("Nuevo programa")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") {
                    game.saveProgram(name: name.trimmingCharacters(in: .whitespaces),
                                     changeDate: hasChangeDate ? SistemaCalendar.startOfDay(changeDate) : nil,
                                     days: days)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || days.isEmpty)
                .accessibilityIdentifier("program.save")
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            changeDate = SistemaCalendar.addDays(28, to: game.now)
        }
    }
}

/// Cómo se interpretó un bloque escrito o pegado.
struct BlockPreview: View {
    let block: RoutineBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(block.summary).font(.subheadline.bold())
            ForEach(block.circuit.exercises) { exercise in
                Text("\(exercise.exerciseName): \(exercise.prescriptionText.isEmpty ? "sin medida" : exercise.prescriptionText)")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}
