import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Documento JSON para exportar el respaldo.
struct BackupFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

@MainActor
struct SettingsView: View {
    @Environment(GameService.self) private var game
    @Query private var players: [Player]

    @State private var reminder = Date()
    @State private var injuryReason = ""
    @State private var injuryUntil = Date()
    @State private var exportFile: BackupFile?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var confirmImport: Data?
    @State private var resetStep = 0
    @State private var message: String?
    @State private var loaded = false

    var body: some View {
        let _ = game.revision
        Form {
            Section("Recordatorios") {
                DatePicker("Recordatorio de la mañana", selection: $reminder, displayedComponents: .hourAndMinute)
                    .onChange(of: reminder) { _, value in
                        let c = SistemaCalendar.calendar.dateComponents([.hour, .minute], from: value)
                        game.setReminder(hour: c.hour ?? 4, minute: c.minute ?? 30)
                    }
                Text("Aviso a las 9 p. m. si un día planeado sigue sin sesión y 2 días antes de que venza el itinerario.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            .listRowBackground(Theme.panel)

            injurySection
                .listRowBackground(Theme.panel)

            Section("Respaldo") {
                Button {
                    do {
                        exportFile = BackupFile(data: try BackupService.exportData(from: game.context, now: game.now))
                        showExporter = true
                    } catch {
                        message = "No se pudo exportar: \(error.localizedDescription)"
                    }
                } label: {
                    Label("Exportar respaldo JSON", systemImage: "square.and.arrow.up")
                }
                Button {
                    showImporter = true
                } label: {
                    Label("Importar respaldo JSON", systemImage: "square.and.arrow.down")
                }
                Text("Copia automática semanal en Archivos > En mi iPhone > Sistema > Respaldos. Última: \(AutoBackup.latestDate(in: AutoBackup.defaultDirectory)?.formatted(date: .abbreviated, time: .omitted) ?? "todavía ninguna").")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Text("Reinstalar desde Xcode encima de la app conserva los datos. Desinstalarla borra también esas copias: antes de desinstalar o cambiar de teléfono, exportá un respaldo a otro lado.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            .listRowBackground(Theme.panel)

            Section("Peligro") {
                Button("Reiniciar todos los datos", role: .destructive) { resetStep = 1 }
            }
            .listRowBackground(Theme.panel)

            #if DEBUG
            DebugSection()
                .listRowBackground(Theme.panel)
            #endif
        }
        .systemBackground()
        .navigationTitle("Ajustes")
        .onAppear(perform: load)
        .fileExporter(isPresented: $showExporter, document: exportFile, contentType: .json,
                      defaultFilename: BackupService.suggestedFileName(now: game.now)) { result in
            if case .success = result { message = "Respaldo exportado." }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            guard case let .success(url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            confirmImport = try? Data(contentsOf: url)
            if confirmImport == nil { message = "No se pudo leer el archivo." }
        }
        .confirmationDialog("¿Reemplazar todos los datos con el respaldo?",
                            isPresented: Binding(get: { confirmImport != nil }, set: { if !$0 { confirmImport = nil } }),
                            titleVisibility: .visible) {
            Button("Importar y reemplazar", role: .destructive) {
                guard let data = confirmImport else { return }
                do {
                    try BackupService.importData(data, into: game.context)
                    game.save()
                    game.evaluate()
                    message = "Respaldo importado."
                } catch {
                    message = "Respaldo inválido: \(error.localizedDescription)"
                }
                confirmImport = nil
            }
        }
        .confirmationDialog("¿Reiniciar todos los datos?", isPresented: Binding(get: { resetStep == 1 }, set: { if !$0 && resetStep == 1 { resetStep = 0 } }),
                            titleVisibility: .visible) {
            Button("Sí, continuar", role: .destructive) {
                DispatchQueue.main.async { resetStep = 2 }
            }
        } message: {
            Text("Se borrará tu progreso, sesiones, rutinas e itinerarios.")
        }
        .alert("Última confirmación", isPresented: Binding(get: { resetStep == 2 }, set: { if !$0 { resetStep = 0 } })) {
            Button("Borrar todo", role: .destructive) {
                game.resetAll()
                resetStep = 0
            }
            Button("Cancelar", role: .cancel) { resetStep = 0 }
        } message: {
            Text("Esto no se puede deshacer. ¿Exportaste un respaldo?")
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var injurySection: some View {
        Section {
            if let player = players.first, let injury = player.activeInjury(now: game.now) {
                Text("Activo: \(injury.reason)")
                Text("Hasta el \(injury.end.formatted(date: .abbreviated, time: .omitted))")
                    .foregroundStyle(Theme.secondaryText)
                Button("Desactivar modo lesión/enfermo") { game.endInjury() }
                Button("Renovar 14 días más") {
                    game.startInjury(reason: injury.reason, until: SistemaCalendar.addDays(Progression.maxInjuryDays - 1, to: game.now))
                }
            } else {
                TextField("Motivo (ej. esguince de tobillo)", text: $injuryReason)
                DatePicker("Fin estimado", selection: $injuryUntil,
                           in: game.now...SistemaCalendar.addDays(Progression.maxInjuryDays - 1, to: game.now),
                           displayedComponents: .date)
                Button("Activar modo lesión/enfermo") {
                    game.startInjury(reason: injuryReason.trimmingCharacters(in: .whitespaces), until: injuryUntil)
                    injuryReason = ""
                }
                .disabled(injuryReason.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Modo lesión/enfermo")
        } footer: {
            Text("Congela penalizaciones y racha. Máximo \(Progression.maxInjuryDays) días seguidos por activación; renovalo a mano si hace falta.")
        }
    }

    private func load() {
        guard !loaded, let player = players.first else { return }
        loaded = true
        let day = SistemaCalendar.startOfDay(game.now)
        reminder = day.addingTimeInterval(Double(player.reminderHour * 3600 + player.reminderMinute * 60))
        injuryUntil = SistemaCalendar.addDays(3, to: game.now)
    }
}

#if DEBUG
/// Interruptor de depuración (apagado por defecto) para cargar datos de ejemplo.
@MainActor
struct DebugSection: View {
    @Environment(GameService.self) private var game
    @AppStorage("debug.sampleDataEnabled") private var enabled = false

    var body: some View {
        Section("Depuración") {
            Toggle("Herramientas de datos de ejemplo", isOn: $enabled)
            if enabled {
                Button("Cargar datos de ejemplo (3 semanas)") { SampleData.load(into: game) }
                Text("Agrega rutinas, un itinerario y sesiones pasadas. Solo en builds de depuración.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}
#endif
