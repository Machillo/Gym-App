import Foundation
import SwiftData

/// Datos del día leídos de Salud.
struct HealthRecoveryDay: Equatable {
    var day: Date
    var sleepHours: Double?
    var restingHR: Double?
    var hrv: Double?
}

/// Lo que muestra la tarjeta "Estado del cazador".
struct HunterState: Equatable {
    var report: RecoveryReport?
    var today: RecoveryDay?
    var sleepDebt: Double
    var sleepStreak: Int
    var isRested: Bool
    var hasDebuff: Bool
    var bedtime: Date
    var wakeIsSet: Bool
    var fight: FightMode?
}

extension GameService {
    private static let authVersionKey = "health.authVersion"
    static let currentHealthAuthVersion = 2

    /// Sueño, pulso y HRV se agregaron después: quien ya conectó Salud tiene que autorizarlos.
    var needsRecoveryPermission: Bool {
        health.isAvailable && healthConnected && defaults.integer(forKey: Self.authVersionKey) < Self.currentHealthAuthVersion
    }

    func markHealthAuthorizationCurrent() {
        defaults.set(Self.currentHealthAuthVersion, forKey: Self.authVersionKey)
    }

    // MARK: - Lecturas

    func recoveryRecords() -> [DailyRecovery] {
        (try? context.fetch(FetchDescriptor<DailyRecovery>(sortBy: [SortDescriptor(\.day)]))) ?? []
    }

    func recoveryRecord(for date: Date) -> DailyRecovery? {
        let day = SistemaCalendar.startOfDay(date)
        return recoveryRecords().first { $0.day == day }
    }

    private func findOrCreateRecord(day date: Date) -> DailyRecovery {
        if let record = recoveryRecord(for: date) { return record }
        let record = DailyRecovery(day: SistemaCalendar.startOfDay(date))
        context.insert(record)
        return record
    }

    func fightMode() -> FightMode? {
        guard let date = player()?.fightDate else { return nil }
        return FightMode(daysLeft: SistemaCalendar.daysBetween(now, date))
    }

    /// Hora de levantarse: la que definiste o, mientras tanto, la del recordatorio de la mañana.
    func wakeTime() -> (hour: Int, minute: Int) {
        guard let player = player() else { return (4, 30) }
        return (player.wakeHour ?? player.reminderHour, player.wakeMinute ?? player.reminderMinute)
    }

    private func sleepTarget() -> Double {
        fightMode()?.isActive == true ? RecoveryEngine.fightSleepTargetHours : RecoveryEngine.sleepTargetHours
    }

    /// Minutos × RPE por día: junta pesas, cardio y sparring en una sola medida de carga.
    func dailyTrainingLoad() -> [Date: Double] {
        var load: [Date: Double] = [:]
        for session in sessions() {
            load[SistemaCalendar.startOfDay(session.date), default: 0] += session.durationMinutes * Double(session.rpe)
        }
        return load
    }

    /// Próxima hora de acostarse: esta noche, o la de hoy si todavía no pasó la de levantarse.
    func nextBedtime(debt: Double) -> Date {
        let wake = wakeTime()
        let today = SistemaCalendar.startOfDay(now).addingTimeInterval(Double(wake.hour * 3600 + wake.minute * 60))
        let nextWake = today > now ? today : SistemaCalendar.addDays(1, to: today)
        let bedtime = RecoveryEngine.bedtime(wake: nextWake, debt: debt, target: sleepTarget())
        return bedtime
    }

    func hunterState() -> HunterState {
        let days = recoveryRecords().map(\.snapshot)
        let start = SistemaCalendar.startOfDay(now)
        let today = days.first { $0.day == start }
        let debt = RecoveryEngine.sleepDebt(days: days, today: now, target: sleepTarget())
        let fight = fightMode()
        let report = today.flatMap { RecoveryEngine.report(today: $0, history: days, dailyLoad: dailyTrainingLoad(), fight: fight) }
        return HunterState(report: report, today: today, sleepDebt: debt,
                           sleepStreak: RecoveryEngine.sleepStreak(days: days, today: now),
                           isRested: (today?.sleepHours ?? 0) >= RecoveryEngine.sleepGoalHours,
                           hasDebuff: debt >= RecoveryEngine.sleepDebtDebuffHours,
                           bedtime: nextBedtime(debt: debt), wakeIsSet: player()?.wakeHour != nil, fight: fight)
    }

    /// Bono de XP de las sesiones del día si esa noche dormiste la meta. La deuda no resta XP.
    func recoveryXPMultiplier(_ date: Date) -> Double {
        (recoveryRecord(for: date)?.sleepHours ?? 0) >= RecoveryEngine.sleepGoalHours ? 1 + RecoveryEngine.restedXPBonus : 1
    }

    /// XP ya ganado en el día o la semana, misiones de descanso incluidas, para respetar los topes.
    /// Lo que cuenta para los topes: el premio de una pelea va aparte.
    func xpEarned(day date: Date, excluding sessionID: UUID? = nil) -> Int {
        let day = SistemaCalendar.startOfDay(date)
        return sessions().filter { $0.id != sessionID && SistemaCalendar.startOfDay($0.date) == day }.reduce(0) { $0 + $1.cappedXP }
            + recoveryRecords().filter { $0.day == day }.reduce(0) { $0 + ($1.missionXP ?? 0) }
    }

    func xpEarned(week date: Date, excluding sessionID: UUID? = nil) -> Int {
        let week = SistemaCalendar.startOfWeek(date)
        return sessions().filter { $0.id != sessionID && SistemaCalendar.startOfWeek($0.date) == week }.reduce(0) { $0 + $1.cappedXP }
            + recoveryRecords().filter { SistemaCalendar.startOfWeek($0.day) == week }.reduce(0) { $0 + ($1.missionXP ?? 0) }
    }

    // MARK: - Escritura

    /// `manualSleepHours` solo se usa si Salud no trajo el sueño de esa noche.
    func saveCheckIn(_ checkIn: RecoveryCheckIn, manualSleepHours: Double?) {
        let record = findOrCreateRecord(day: now)
        record.checkIn = checkIn
        if let manualSleepHours, record.sleepFromHealth != true { record.sleepHours = manualSleepHours }
        settleSleepRewards()
        save()
    }

    func setWakeTime(hour: Int, minute: Int) {
        guard let player = player() else { return }
        player.wakeHour = hour
        player.wakeMinute = minute
        save()
        rescheduleNotifications()
    }

    func setFightDate(_ date: Date?) {
        guard let player = player() else { return }
        player.fightDate = date.map(SistemaCalendar.startOfDay)
        save()
        rescheduleNotifications()
    }

    func importRecoveryDays(_ days: [HealthRecoveryDay]) {
        for item in days where item.sleepHours != nil || item.restingHR != nil || item.hrv != nil {
            let record = findOrCreateRecord(day: item.day)
            if let hours = item.sleepHours {
                record.sleepHours = hours
                record.sleepFromHealth = true
            }
            if let heart = item.restingHR { record.restingHR = heart }
            if let hrv = item.hrv { record.hrv = hrv }
        }
        settleSleepRewards()
        save()
    }

    /// Misión de descanso de hoy y ayer (una vez por noche, dentro de los topes) y logros de racha.
    private func settleSleepRewards() {
        guard let player = player() else { return }
        try? context.save()
        let created = SistemaCalendar.startOfDay(player.createdAt)
        let today = SistemaCalendar.startOfDay(now)
        for day in [SistemaCalendar.addDays(-1, to: today), today] where day >= created {
            guard let record = recoveryRecord(for: day), record.missionXP == nil,
                  (record.sleepHours ?? 0) >= RecoveryEngine.sleepGoalHours else { continue }
            let xp = XPEngine.cappedXP(raw: RecoveryEngine.sleepMissionXP, earnedToday: xpEarned(day: day), earnedThisWeek: xpEarned(week: day))
            record.missionXP = xp
            guard xp > 0 else { continue }
            var progress = player.progress
            let events = progress.applyGain(xp, now: now)
            player.progress = progress
            log(.gain, String(format: "Misión de recuperación cumplida: %.1f h de sueño. +%d XP.", record.sleepHours ?? 0, xp), xpDelta: xp, player: player)
            announce(events, player: player)
        }

        let streak = RecoveryEngine.sleepStreak(days: recoveryRecords().map(\.snapshot), today: now)
        let earned = Set(awards().map(\.key))
        for milestone in RecoveryEngine.sleepStreakMilestones where streak >= milestone && !earned.contains("sleep-\(milestone)") {
            let title = "\(milestone) noches de buen sueño"
            context.insert(ChallengeAward(key: "sleep-\(milestone)", title: title, detail: "Racha de 7 horas o más.", date: now))
            announcements.append(Announcement(headline: "LOGRO DE DESCANSO", message: title, positive: true))
        }
    }

    // MARK: - Aviso y patrones

    /// Aviso 30 minutos antes de acostarse, las próximas noches. Solo si definiste a qué hora te levantás.
    func bedtimeNotices() -> [LocalNotification] {
        guard let player = player(), let hour = player.wakeHour, let minute = player.wakeMinute else { return [] }
        let debt = RecoveryEngine.sleepDebt(days: recoveryRecords().map(\.snapshot), today: now, target: sleepTarget())
        let today = SistemaCalendar.startOfDay(now)
        return (0..<7).compactMap { offset in
            let wake = SistemaCalendar.addDays(offset, to: today).addingTimeInterval(Double(hour * 3600 + minute * 60))
            let bedtime = RecoveryEngine.bedtime(wake: wake, debt: debt, target: sleepTarget())
            let notice = bedtime.addingTimeInterval(-30 * 60)
            guard notice > now else { return nil }
            let style = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: SistemaCalendar.timeZone)
            return LocalNotification(id: "bedtime-\(offset)-\(Int(wake.timeIntervalSince1970))", date: notice, title: "Hora de ir cerrando",
                                     body: "Para levantarte a las \(wake.formatted(style)), acostate a las \(bedtime.formatted(style)).")
        }
    }

    func sleepPatterns() -> SleepPatterns {
        let hours = Dictionary(recoveryRecords().compactMap { r in r.sleepHours.map { (r.day, $0) } }, uniquingKeysWith: max)
        var improvements: [UUID: Int] = [:]
        for log in exerciseLogs() where log.isImprovement { improvements[log.sessionID, default: 0] += 1 }
        return RecoveryEngine.patterns(sessions().compactMap { session in
            guard !session.isPunishment, let night = hours[SistemaCalendar.startOfDay(session.date)] else { return nil }
            return SleepPatternSample(sleepHours: night, compliance: session.compliance, improvements: improvements[session.id] ?? 0,
                                      isClass: session.isClass, rpe: session.rpe)
        })
    }

    /// Días con marca nueva, para señalarlos sobre el gráfico de sueño.
    func daysWithRecords() -> Set<Date> {
        Set(exerciseLogs().filter(\.isImprovement).map { SistemaCalendar.startOfDay($0.date) })
    }
}
