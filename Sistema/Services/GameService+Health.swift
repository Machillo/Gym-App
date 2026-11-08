import Foundation
import SwiftData

/// Un registro InBody para cargar historial (por ejemplo, las hojas viejas).
struct BodyHistoryImport: Codable, Equatable {
    var date: Date
    var weightKg: Double?
    var bodyFatPercent: Double?
    var skeletalMuscleKg: Double?
    var visceralFatLevel: Int?
    var inBodyScore: Int?
}

extension GameService {
    private static let connectedKey = "health.connected"
    private static let processedWorkoutsKey = "health.processedWorkouts"
    private static let processedSamplesKey = "health.processedSamples"

    /// Hasta cuántos días atrás se leen entrenamientos del Watch.
    static let healthWorkoutLookbackDays = 7
    static let healthBodyLookbackDays = 30

    var healthConnected: Bool {
        get { defaults.bool(forKey: Self.connectedKey) }
        set { defaults.set(newValue, forKey: Self.connectedKey) }
    }

    private func processed(_ key: String) -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    private func markProcessed(_ ids: [String], key: String) {
        guard !ids.isEmpty else { return }
        // Basta con recordar los últimos: lo más viejo queda fuera de la ventana de lectura.
        let all = (defaults.stringArray(forKey: key) ?? []) + ids
        defaults.set(Array(all.suffix(500)), forKey: key)
    }

    // MARK: - Conexión

    func connectHealth() async {
        guard health.isAvailable else { return }
        do {
            try await health.requestAuthorization()
            healthConnected = true
            markHealthAuthorizationCurrent()
            if let player = player() { log(.info, "Conectado con Apple Salud.", player: player) }
            save()
            await syncHealth()
        } catch {
            healthConnected = false
        }
    }

    func requestHealthSync() {
        guard health.isAvailable, healthConnected else { return }
        Task { await syncHealth() }
    }

    /// Manda lo pendiente, trae los entrenamientos del Watch y las medidas de Salud, y lee los aros y pasos.
    func syncHealth() async {
        guard health.isAvailable, healthConnected, !isSyncingHealth, player() != nil else { return }
        isSyncingHealth = true
        defer { isSyncingHealth = false }

        await exportPendingToHealth()
        let since = healthImportStart()
        if let workouts = try? await health.workouts(since: since) {
            importWatchWorkouts(workouts)
        }
        if let samples = try? await health.bodySamples(since: SistemaCalendar.addDays(-Self.healthBodyLookbackDays, to: now)) {
            importBodySamples(samples)
        }
        if let days = try? await health.recoveryDays(since: SistemaCalendar.addDays(-(RecoveryEngine.baselineDays + 7), to: now)) {
            importRecoveryDays(days)
        }
        activity = try? await health.activity(on: now)
        lastHealthSync = now
        save()
    }

    /// No antes de que existiera el jugador: lo anterior no es parte del juego.
    func healthImportStart() -> Date {
        let window = SistemaCalendar.addDays(-Self.healthWorkoutLookbackDays, to: SistemaCalendar.startOfDay(now))
        guard let created = player()?.createdAt else { return window }
        return max(window, SistemaCalendar.startOfDay(created))
    }

    // MARK: - Entrenamientos del Watch

    /// Une cada entrenamiento nuevo a la sesión que ya registraste ese día (mismo tipo) o, si no hay, lo agrega
    /// como sesión propia con su XP. Devuelve cuántas sesiones nuevas creó.
    @discardableResult
    func importWatchWorkouts(_ workouts: [HealthWorkout]) -> Int {
        guard player() != nil else { return 0 }
        let start = healthImportStart()
        var seen = processed(Self.processedWorkoutsKey).union(sessions().compactMap(\.healthWorkoutID))
        var created = 0
        var handled: [String] = []
        for workout in workouts.sorted(by: { $0.start < $1.start }) where workout.start >= start && !seen.contains(workout.id) {
            seen.insert(workout.id)
            handled.append(workout.id)
            if let session = linkableSession(for: workout) {
                attach(workout, to: session)
                if let player = player() {
                    log(.info, "\(workout.sourceName): \(workout.title) unido a \(session.title).", player: player, date: workout.end)
                }
            } else {
                let draft = SessionDraft(title: workout.title, date: workout.start, results: [HealthSync.result(for: workout)],
                                         rpe: 7, notes: "", durationMinutes: (workout.minutes * 10).rounded() / 10)
                if let outcome = logSession(draft, absorbWatch: false) {
                    attach(workout, to: outcome.session)
                    outcome.session.isAutoImported = true
                    created += 1
                }
            }
        }
        markProcessed(handled, key: Self.processedWorkoutsKey)
        save()
        return created
    }

    /// Sesión registrada a mano, del mismo día y tipo, que todavía no tiene entrenamiento del Watch.
    private func linkableSession(for workout: HealthWorkout) -> WorkoutSession? {
        let group = workout.category.group
        guard group != .none else { return nil }
        let day = SistemaCalendar.startOfDay(workout.start)
        return sessions()
            .filter { !$0.isFromWatch && $0.healthWorkoutID == nil
                && SistemaCalendar.startOfDay($0.plannedDay ?? $0.date) == day
                && HealthMatchGroup.of($0.results.map(\.prescribed)) == group }
            .min { abs($0.date.timeIntervalSince(workout.start)) < abs($1.date.timeIntervalSince(workout.start)) }
    }

    private func attach(_ workout: HealthWorkout, to session: WorkoutSession) {
        session.healthWorkoutID = workout.id
        session.watchCategoryRaw = workout.category.raw
        session.watchSource = workout.sourceName
        session.watchKcal = workout.kcal
        session.watchAvgHR = workout.avgHR
        session.watchMaxHR = workout.maxHR
        // Una clase con datos reales del reloj ya no necesita la estimación.
        if session.isClass { session.healthExported = nil }
    }

    /// Al borrar una sesión: si era del Watch, no se vuelve a traer; si había una estimación en Salud, se quita.
    func forgetInHealth(_ session: WorkoutSession) {
        if let id = session.healthWorkoutID { markProcessed([id], key: Self.processedWorkoutsKey) }
        guard session.healthExported == true, health.isAvailable else { return }
        let syncID = HealthSync.sessionSyncID(session.id)
        Task { try? await health.deleteWorkout(syncID: syncID) }
    }

    // MARK: - Medidas desde Salud (balanza)

    /// Peso y grasa de otra app o balanza. Se suman al registro de ese día si todavía no tiene ese dato.
    func importBodySamples(_ samples: [HealthBodySample]) {
        var seen = processed(Self.processedSamplesKey)
        var handled: [String] = []
        for sample in samples.sorted(by: { $0.date < $1.date }) where !seen.contains(sample.id) {
            seen.insert(sample.id)
            handled.append(sample.id)
            let day = SistemaCalendar.startOfDay(sample.date)
            let existing = bodyEntries().last { SistemaCalendar.startOfDay($0.date) == day }
            switch sample.kind {
            case .weight:
                if let existing {
                    guard existing.weightKg == nil else { continue }
                    existing.weightKg = sample.value
                    existing.weightFromHealth = true
                    existing.healthSynced = false
                } else {
                    let entry = BodyEntry(date: sample.date, weightKg: sample.value, weightUnit: .kg, bodyFatPercent: nil,
                                          measures: [:], notes: "Desde Salud")
                    entry.weightFromHealth = true
                    entry.healthSynced = true
                    context.insert(entry)
                }
            case .bodyFat:
                if let existing {
                    guard existing.bodyFatPercent == nil else { continue }
                    existing.bodyFatPercent = sample.value
                    existing.fatFromHealth = true
                    existing.healthSynced = false
                } else {
                    let entry = BodyEntry(date: sample.date, weightKg: nil, weightUnit: .kg, bodyFatPercent: sample.value,
                                          measures: [:], notes: "Desde Salud")
                    entry.fatFromHealth = true
                    entry.healthSynced = true
                    context.insert(entry)
                }
            default:
                continue
            }
        }
        markProcessed(handled, key: Self.processedSamplesKey)
        save()
    }

    // MARK: - Hacia Salud

    /// Peso del cuerpo para estimar calorías: el último registrado hasta esa fecha.
    func bodyWeightKg(at date: Date) -> Double {
        let entries = bodyEntries().filter { $0.weightKg != nil }
        return (entries.last { $0.date <= date } ?? entries.last)?.weightKg ?? 75
    }

    /// Lo que la clase mandaría a Salud: termina al registrar (o a su hora, si fue antes) y nunca en el futuro.
    func healthExport(for session: WorkoutSession) -> HealthWorkoutExport? {
        guard let block = session.results.first(where: { $0.prescribed.kind == .classSession }) else { return nil }
        let minutes = max(session.durationMinutes, block.result(minutesFallback: block.prescribed.klass.minutes))
        var start = session.date
        if start.addingTimeInterval(minutes * 60) > now { start = now.addingTimeInterval(-minutes * 60) }
        let kcal = HealthSync.estimatedKcal(discipline: block.prescribed.klass.discipline, minutes: minutes,
                                            weightKg: bodyWeightKg(at: session.date), rpe: session.rpe)
        return HealthWorkoutExport(syncID: HealthSync.sessionSyncID(session.id), discipline: block.prescribed.klass.discipline,
                                   start: start, end: start.addingTimeInterval(minutes * 60), kcal: kcal)
    }

    func exportPendingToHealth() async {
        for session in sessions() where session.isClass {
            let syncID = HealthSync.sessionSyncID(session.id)
            if session.healthWorkoutID != nil {
                // Tiene datos reales del reloj: no se manda la estimación.
                guard session.healthExported != false else { continue }
                if (try? await health.deleteWorkout(syncID: syncID)) != nil {
                    session.healthExported = false
                    session.estimatedKcal = nil
                }
            } else if session.healthExported != true, let export = healthExport(for: session) {
                if (try? await health.replaceWorkout(export)) != nil {
                    session.healthExported = true
                    session.estimatedKcal = export.kcal
                }
            }
        }
        for entry in bodyEntries() where entry.healthSynced != true {
            let exports = HealthSync.bodyExports(id: entry.id, date: entry.date, weightKg: entry.weightKg,
                                                 bodyFatPercent: entry.bodyFatPercent, waistCm: entry.measures[.waist],
                                                 weightFromHealth: entry.weightFromHealth == true,
                                                 fatFromHealth: entry.fatFromHealth == true)
            if (try? await health.replaceBody(exports, entryID: entry.id)) != nil {
                entry.healthSynced = true
            }
        }
        try? context.save()
    }

    // MARK: - Historial InBody

    /// Carga mediciones viejas. Si ese día ya tiene un registro con peso, no lo repite.
    @discardableResult
    func importBodyHistory(_ items: [BodyHistoryImport]) -> Int {
        var added = 0
        for item in items {
            let day = SistemaCalendar.startOfDay(item.date)
            guard !bodyEntries().contains(where: { SistemaCalendar.startOfDay($0.date) == day && $0.weightKg != nil }) else { continue }
            let entry = BodyEntry(date: item.date, weightKg: item.weightKg, weightUnit: .kg, bodyFatPercent: item.bodyFatPercent,
                                  measures: [:], notes: "InBody")
            entry.skeletalMuscleKg = item.skeletalMuscleKg
            entry.visceralFatLevel = item.visceralFatLevel
            entry.inBodyScore = item.inBodyScore
            context.insert(entry)
            added += 1
        }
        if added > 0 {
            try? context.save()
            if let player = player() {
                log(.info, "Historial InBody cargado: \(added) mediciones.", player: player)
                refreshProfileAndChallenges(player: player)
            }
            save()
            requestHealthSync()
        }
        return added
    }
}

private extension BlockResult {
    func result(minutesFallback: Double) -> Double { minutes ?? minutesFallback }
}
