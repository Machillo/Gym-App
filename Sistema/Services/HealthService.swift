import Foundation
import HealthKit

/// Todo lo que el Sistema hace con Apple Salud. Las pruebas usan una versión falsa.
@MainActor
protocol HealthSyncing: AnyObject {
    var isAvailable: Bool { get }
    func requestAuthorization() async throws
    func workouts(since: Date) async throws -> [HealthWorkout]
    func bodySamples(since: Date) async throws -> [HealthBodySample]
    func activity(on day: Date) async throws -> HealthActivitySnapshot?
    func recoveryDays(since: Date) async throws -> [HealthRecoveryDay]
    /// Borra la versión anterior (mismo `syncID`) y guarda la nueva.
    func replaceWorkout(_ workout: HealthWorkoutExport) async throws
    func deleteWorkout(syncID: String) async throws
    func replaceBody(_ samples: [HealthBodyExport], entryID: UUID) async throws
    func deleteBody(entryID: UUID) async throws
}

/// Sin Salud (pruebas, o un dispositivo sin HealthKit).
@MainActor
final class DisabledHealthService: HealthSyncing {
    var isAvailable: Bool { false }
    func requestAuthorization() async throws {}
    func workouts(since: Date) async throws -> [HealthWorkout] { [] }
    func bodySamples(since: Date) async throws -> [HealthBodySample] { [] }
    func activity(on day: Date) async throws -> HealthActivitySnapshot? { nil }
    func recoveryDays(since: Date) async throws -> [HealthRecoveryDay] { [] }
    func replaceWorkout(_ workout: HealthWorkoutExport) async throws {}
    func deleteWorkout(syncID: String) async throws {}
    func replaceBody(_ samples: [HealthBodyExport], entryID: UUID) async throws {}
    func deleteBody(entryID: UUID) async throws {}
}

@MainActor
final class HealthKitService: HealthSyncing {
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private static let energy = HKQuantityType(.activeEnergyBurned)
    private static let heartRate = HKQuantityType(.heartRate)
    private static let steps = HKQuantityType(.stepCount)

    private static func bodyType(_ kind: HealthBodyKind) -> HKQuantityType {
        switch kind {
        case .weight: return HKQuantityType(.bodyMass)
        case .bodyFat: return HKQuantityType(.bodyFatPercentage)
        case .leanMass: return HKQuantityType(.leanBodyMass)
        case .waist: return HKQuantityType(.waistCircumference)
        }
    }

    private static func bodyUnit(_ kind: HealthBodyKind) -> HKUnit {
        switch kind {
        case .weight, .leanMass: return .gramUnit(with: .kilo)
        case .bodyFat: return .percent()
        case .waist: return .meterUnit(with: .centi)
        }
    }

    func requestAuthorization() async throws {
        var share: Set<HKSampleType> = [HKObjectType.workoutType(), Self.energy]
        share.formUnion(HealthBodyKind.allCases.map(Self.bodyType))
        var read: Set<HKObjectType> = [HKObjectType.workoutType(), Self.energy, Self.heartRate, Self.steps,
                                       HKObjectType.activitySummaryType(), HKCategoryType(.sleepAnalysis),
                                       HKQuantityType(.restingHeartRate), HKQuantityType(.heartRateVariabilitySDNN),
                                       HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling),
                                       HKQuantityType(.distanceSwimming)]
        read.formUnion(HealthBodyKind.allCases.map(Self.bodyType))
        try await store.requestAuthorization(toShare: share, read: read)
    }

    // MARK: - Lectura

    func workouts(since: Date) async throws -> [HealthWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil)
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(predicate)], sortDescriptors: [SortDescriptor(\.startDate)])
        let ownBundle = Bundle.main.bundleIdentifier
        return try await descriptor.result(for: store)
            .filter { $0.sourceRevision.source.bundleIdentifier != ownBundle }
            .map(Self.convert)
    }

    private static func convert(_ workout: HKWorkout) -> HealthWorkout {
        let perMinute = HKUnit.count().unitDivided(by: .minute())
        let heart = workout.statistics(for: heartRate)
        let distanceTypes: [HKQuantityType] = [HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling),
                                               HKQuantityType(.distanceSwimming)]
        let meters = distanceTypes.compactMap { workout.statistics(for: $0)?.sumQuantity()?.doubleValue(for: .meter()) }.first
        let product = workout.sourceRevision.productType ?? ""
        let (title, category) = describe(workout.workoutActivityType)
        return HealthWorkout(
            id: workout.uuid.uuidString,
            title: title,
            category: category,
            start: workout.startDate,
            end: workout.endDate,
            kcal: workout.statistics(for: energy)?.sumQuantity()?.doubleValue(for: .kilocalorie()),
            avgHR: heart?.averageQuantity()?.doubleValue(for: perMinute),
            maxHR: heart?.maximumQuantity()?.doubleValue(for: perMinute),
            distanceKm: meters.map { $0 / 1000 },
            sourceName: product.hasPrefix("Watch") ? "Apple Watch" : workout.sourceRevision.source.name
        )
    }

    /// Nombre en español y cómo lo entiende el Sistema.
    static func describe(_ type: HKWorkoutActivityType) -> (String, HealthCategory) {
        switch type {
        case .traditionalStrengthTraining: return ("Fuerza", .strength)
        case .functionalStrengthTraining: return ("Fuerza funcional", .strength)
        case .highIntensityIntervalTraining: return ("HIIT", .strength)
        case .crossTraining: return ("Entrenamiento cruzado", .strength)
        case .coreTraining: return ("Core", .strength)
        case .mixedCardio: return ("Cardio mixto", .strength)
        case .boxing: return ("Box", .fight(.boxing))
        case .kickboxing: return ("Kickboxing", .fight(.muayThai))
        case .martialArts: return ("Artes marciales", .fight(.mma))
        case .wrestling: return ("Lucha", .fight(.mma))
        case .running: return ("Correr", .cardio(.run))
        case .cycling: return ("Bici", .cardio(.bike))
        case .rowing: return ("Remo", .cardio(.row))
        case .swimming: return ("Natación", .cardio(.swim))
        case .jumpRope: return ("Cuerda", .cardio(.rope))
        case .walking: return ("Caminata", .cardio(.other))
        case .hiking: return ("Caminata de montaña", .cardio(.other))
        case .elliptical: return ("Elíptica", .cardio(.other))
        case .stairClimbing, .stairs, .stepTraining: return ("Escaleras", .cardio(.other))
        case .yoga: return ("Yoga", .other)
        case .flexibility, .cooldown: return ("Movilidad", .other)
        case .soccer: return ("Fútbol", .other)
        default: return ("Entrenamiento", .other)
        }
    }

    func bodySamples(since: Date) async throws -> [HealthBodySample] {
        let ownBundle = Bundle.main.bundleIdentifier
        var all: [HealthBodySample] = []
        for kind in [HealthBodyKind.weight, .bodyFat] {
            let type = Self.bodyType(kind)
            let predicate = HKQuery.predicateForSamples(withStart: since, end: nil)
            let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: type, predicate: predicate)],
                                                     sortDescriptors: [SortDescriptor(\.startDate)])
            let samples = try await descriptor.result(for: store)
            for sample in samples where sample.sourceRevision.source.bundleIdentifier != ownBundle {
                var value = sample.quantity.doubleValue(for: Self.bodyUnit(kind))
                if kind == .bodyFat { value *= 100 }
                all.append(HealthBodySample(id: sample.uuid.uuidString, kind: kind, value: value, date: sample.startDate))
            }
        }
        return all
    }

    func activity(on day: Date) async throws -> HealthActivitySnapshot? {
        let start = SistemaCalendar.startOfDay(day)
        let weekStart = SistemaCalendar.addDays(-6, to: start)
        let end = SistemaCalendar.addDays(1, to: start)

        let stepsDescriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: Self.steps, predicate: HKQuery.predicateForSamples(withStart: weekStart, end: end)),
            options: .cumulativeSum, anchorDate: weekStart, intervalComponents: DateComponents(day: 1))
        let collection = try await stepsDescriptor.result(for: store)
        var daily: [Int] = []
        collection.enumerateStatistics(from: weekStart, to: end) { stats, _ in
            daily.append(Int(stats.sumQuantity()?.doubleValue(for: .count()) ?? 0))
        }
        let today = daily.last ?? 0
        let past = daily.dropLast().filter { $0 > 0 }
        let average = past.isEmpty ? today : past.reduce(0, +) / past.count

        let summary = try await rings(on: start)
        return HealthActivitySnapshot(
            steps: today,
            stepsWeekAverage: average,
            moveKcal: summary?.activeEnergyBurned.doubleValue(for: .kilocalorie()) ?? 0,
            moveGoal: summary?.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()) ?? 0,
            exerciseMinutes: summary?.appleExerciseTime.doubleValue(for: .minute()) ?? 0,
            exerciseGoal: summary?.appleExerciseTimeGoal.doubleValue(for: .minute()) ?? 0,
            standHours: summary?.appleStandHours.doubleValue(for: .count()) ?? 0,
            standGoal: summary?.appleStandHoursGoal.doubleValue(for: .count()) ?? 0,
            hasRings: summary != nil
        )
    }

    func recoveryDays(since: Date) async throws -> [HealthRecoveryDay] {
        let first = SistemaCalendar.startOfDay(since)
        let predicate = HKQuery.predicateForSamples(withStart: first.addingTimeInterval(-86_400), end: nil)
        let asleep = HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue)
        let sleep = try await HKSampleQueryDescriptor(predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
                                                      sortDescriptors: [SortDescriptor(\.startDate)]).result(for: store)
        let intervals = sleep.filter { asleep.contains($0.value) }.map { DateInterval(start: $0.startDate, end: max($0.startDate, $0.endDate)) }
        let perMinute = HKUnit.count().unitDivided(by: .minute())
        let heart = try await dailyAverage(.restingHeartRate, unit: perMinute, predicate: predicate)
        let hrv = try await dailyAverage(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), predicate: predicate)

        var days: [HealthRecoveryDay] = []
        var day = first
        let today = SistemaCalendar.startOfDay(Date())
        while day <= today {
            days.append(HealthRecoveryDay(day: day, sleepHours: RecoveryEngine.sleepHours(intervals: intervals, day: day),
                                          restingHR: heart[day], hrv: hrv[day]))
            day = SistemaCalendar.addDays(1, to: day)
        }
        return days
    }

    private func dailyAverage(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, predicate: NSPredicate) async throws -> [Date: Double] {
        let samples = try await HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(identifier), predicate: predicate)],
                                                        sortDescriptors: [SortDescriptor(\.startDate)]).result(for: store)
        return Dictionary(grouping: samples) { SistemaCalendar.startOfDay($0.startDate) }
            .mapValues { group in group.reduce(0) { $0 + $1.quantity.doubleValue(for: unit) } / Double(group.count) }
    }

    private func rings(on day: Date) async throws -> HKActivitySummary? {
        var components = SistemaCalendar.calendar.dateComponents([.era, .year, .month, .day], from: day)
        components.calendar = SistemaCalendar.calendar
        let predicate = HKQuery.predicateForActivitySummary(with: components)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: summaries?.first)
                }
            }
            store.execute(query)
        }
    }

    // MARK: - Escritura

    func replaceWorkout(_ workout: HealthWorkoutExport) async throws {
        try await deleteWorkout(syncID: workout.syncID)
        let configuration = HKWorkoutConfiguration()
        switch workout.discipline {
        case .boxing: configuration.activityType = .boxing
        case .muayThai: configuration.activityType = .kickboxing
        case .mma: configuration.activityType = .martialArts
        }
        configuration.locationType = .indoor
        let version = Int(Date().timeIntervalSince1970)
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: nil)
        try await builder.beginCollection(at: workout.start)
        let energy = HKQuantitySample(type: Self.energy,
                                      quantity: HKQuantity(unit: .kilocalorie(), doubleValue: workout.kcal),
                                      start: workout.start, end: workout.end,
                                      metadata: [HKMetadataKeySyncIdentifier: workout.syncID + ".kcal",
                                                 HKMetadataKeySyncVersion: version])
        try await builder.addSamples([energy])
        try await builder.addMetadata([HKMetadataKeySyncIdentifier: workout.syncID, HKMetadataKeySyncVersion: version,
                                       HKMetadataKeyIndoorWorkout: true])
        try await builder.endCollection(at: workout.end)
        _ = try await builder.finishWorkout()
    }

    func deleteWorkout(syncID: String) async throws {
        try await delete(type: HKObjectType.workoutType(), syncIDs: [syncID])
        try await delete(type: Self.energy, syncIDs: [syncID + ".kcal"])
    }

    func replaceBody(_ samples: [HealthBodyExport], entryID: UUID) async throws {
        try await deleteBody(entryID: entryID)
        guard !samples.isEmpty else { return }
        let version = Int(Date().timeIntervalSince1970)
        let objects = samples.map { sample -> HKQuantitySample in
            let value = sample.kind == .bodyFat ? sample.value / 100 : sample.value
            return HKQuantitySample(type: Self.bodyType(sample.kind),
                                    quantity: HKQuantity(unit: Self.bodyUnit(sample.kind), doubleValue: value),
                                    start: sample.date, end: sample.date,
                                    metadata: [HKMetadataKeySyncIdentifier: sample.syncID, HKMetadataKeySyncVersion: version])
        }
        try await store.save(objects)
    }

    func deleteBody(entryID: UUID) async throws {
        for kind in HealthBodyKind.allCases {
            try await delete(type: Self.bodyType(kind), syncIDs: [HealthSync.bodySyncID(entryID, kind)])
        }
    }

    private func delete(type: HKObjectType, syncIDs: [String]) async throws {
        let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: syncIDs)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.deleteObjects(of: type, predicate: predicate) { _, _, error in
                // Sin permiso de escritura o sin nada que borrar no es un error para el Sistema.
                if let error, (error as? HKError)?.code != .errorAuthorizationDenied, (error as? HKError)?.code != .errorNoData {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
