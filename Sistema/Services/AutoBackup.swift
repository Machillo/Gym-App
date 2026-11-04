import Foundation
import SwiftData

/// Copia semanal en la carpeta de la app, visible desde Archivos > En mi iPhone > Sistema.
enum AutoBackup {
    static let intervalDays = 7
    static let keep = 4
    private static let prefix = "sistema-auto-"

    static var defaultDirectory: URL {
        URL.documentsDirectory.appending(path: "Respaldos", directoryHint: .isDirectory)
    }

    static func latestDate(in directory: URL) -> Date? {
        files(in: directory).compactMap(date(of:)).max()
    }

    /// Devuelve el archivo creado, o nil si todavía no toca.
    @discardableResult
    static func runIfDue(context: ModelContext, now: Date, directory: URL = defaultDirectory) throws -> URL? {
        if let last = latestDate(in: directory), SistemaCalendar.daysBetween(last, now) < intervalDays { return nil }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let c = SistemaCalendar.calendar.dateComponents([.year, .month, .day], from: now)
        let name = String(format: "%@%04d-%02d-%02d.json", prefix, c.year ?? 0, c.month ?? 0, c.day ?? 0)
        let url = directory.appending(path: name)
        try BackupService.exportData(from: context, now: now).write(to: url, options: .atomic)
        for old in files(in: directory).sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).dropFirst(keep) {
            try? FileManager.default.removeItem(at: old)
        }
        return url
    }

    private static func files(in directory: URL) -> [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return all.filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "json" }
    }

    private static func date(of file: URL) -> Date? {
        let parts = file.deletingPathExtension().lastPathComponent.dropFirst(prefix.count).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return SistemaCalendar.date(year: parts[0], month: parts[1], day: parts[2])
    }
}
