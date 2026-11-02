import Foundation

/// Convierte el texto de una rutina (escrito o copiado de una captura con Texto en vivo) en días y bloques.
/// Acepta el ejercicio y su medida en la misma línea ("Burpees 45 sec") o en dos líneas seguidas.
enum RoutineTextParser {
    struct Measure: Equatable {
        var reps: Int?
        var seconds: Int?
        var rest: Int?
        var note: String?
    }

    private struct BlockConfig {
        var format: CircuitFormat = .circuit
        var rounds: Int?
        var cap: Double?
        var rest: Int?
        var title: String?

        func merged(with other: BlockConfig, hasFormat: Bool) -> BlockConfig {
            var result = self
            if hasFormat { result.format = other.format }
            result.rounds = other.rounds ?? rounds
            result.cap = other.cap ?? cap
            result.rest = other.rest ?? rest
            result.title = title ?? other.title
            return result
        }
    }

    // MARK: - Programa completo

    static func parseProgram(_ text: String) -> [ProgramDay] {
        var lines = cleanLines(text)
        if let firstDay = lines.firstIndex(where: isDayHeader) { lines.removeFirst(firstDay) }

        var days: [ProgramDay] = []
        var current: ProgramDay?
        var config = BlockConfig()
        var hasHeaderOnly = false
        var pending: [CircuitExercise] = []

        func flushBlock() {
            guard !pending.isEmpty else { return }
            if current == nil { current = ProgramDay(name: "Día \(days.count + 1)", blocks: []) }
            current?.blocks += makeBlocks(config, exercises: pending)
            pending = []
        }

        func flushDay() {
            flushBlock()
            if let day = current, !day.blocks.isEmpty { days.append(day) }
            current = nil
            config = BlockConfig()
            hasHeaderOnly = false
        }

        for (index, line) in lines.enumerated() {
            let nextIsMeasure = index + 1 < lines.count && isMeasureLine(lines[index + 1])

            if isDayHeader(line) {
                flushDay()
                current = ProgramDay(name: dayName(line), blocks: [])
            } else if isFocus(line) {
                if current == nil { current = ProgramDay(name: "Día \(days.count + 1)", blocks: []) }
                current?.focus = trimmedSentence(line).capitalized
            } else if isContinuation(line) {
                continue
            } else if isMeasureLine(line), !pending.isEmpty, let parsed = measure(line)?.measure {
                apply(parsed, to: &pending[pending.count - 1])
            } else if !nextIsMeasure, isBlockHeader(line) {
                let header = blockConfig(line)
                if pending.isEmpty, hasHeaderOnly {
                    config = config.merged(with: header, hasFormat: formatKeyword(line) != nil)
                } else {
                    flushBlock()
                    config = header
                }
                hasHeaderOnly = true
            } else {
                hasHeaderOnly = false
                pending.append(exercise(line, nameOnly: nextIsMeasure))
            }
        }
        flushDay()
        return days
    }

    /// Solo los ejercicios, para agregarlos de una vez a un bloque existente.
    static func exercises(from text: String) -> [CircuitExercise] {
        parseProgram(text).flatMap(\.blocks).flatMap(\.circuit.exercises)
    }

    // MARK: - Bloques

    private static func makeBlocks(_ config: BlockConfig, exercises: [CircuitExercise]) -> [RoutineBlock] {
        let withRest = exercises.map { item -> CircuitExercise in
            var e = item
            e.restSeconds = e.restSeconds ?? config.rest
            return e
        }
        func block(_ items: [CircuitExercise], rounds: Int, title: String?) -> RoutineBlock {
            .circuit(CircuitPrescription(rounds: rounds, exercises: items, format: config.format, title: title,
                                         timeCapMinutes: config.format == .amrap ? (config.cap ?? 15) : nil))
        }
        switch config.format {
        case .biSeries:
            // Cada par de ejercicios es su propia bi-serie, con sus rondas.
            return stride(from: 0, to: withRest.count, by: 2).map { start in
                block(Array(withRest[start..<min(start + 2, withRest.count)]), rounds: config.rounds ?? 3, title: config.title)
            }
        case .tabata:
            return [block(withRest, rounds: config.rounds ?? 4, title: config.title)]
        case .amrap:
            return [block(withRest, rounds: 1, title: config.title)]
        case .circuit:
            let fallback = config.title == nil ? 3 : 1
            return [block(withRest, rounds: config.rounds ?? fallback, title: config.title)]
        }
    }

    private static func isBlockHeader(_ line: String) -> Bool {
        let hasLetters = line.rangeOfCharacter(from: .letters) != nil
        let allCaps = hasLetters && line == line.uppercased()
        let key = normalize(line)
        if startsWithFormatWord(key) { return true }
        guard allCaps else { return false }
        return formatKeyword(line) != nil || structureKeywords.contains { key.contains($0) } || splitInline(line) == nil
    }

    private static let structureKeywords = ["bloque", "block", "rounds", "round", "rondas", "ronda", "min on", "sec on", "seg on"]

    private static func startsWithFormatWord(_ key: String) -> Bool {
        ["bi serie", "bi-serie", "biserie", "superserie", "superset", "tabata", "amrap", "circuito", "circuit "]
            .contains { key.hasPrefix($0) }
    }

    private static func formatKeyword(_ line: String) -> CircuitFormat? {
        let key = normalize(line)
        if ["bi serie", "bi-serie", "biserie", "superserie", "superset"].contains(where: key.contains) { return .biSeries }
        if key.contains("tabata") { return .tabata }
        if key.contains("amrap") || firstInt(#"(\d+)\s*min(?:utos)?\s*on"#, in: key) != nil { return .amrap }
        if key.contains("circuit") { return .circuit }
        return nil
    }

    private static func blockConfig(_ line: String) -> BlockConfig {
        let key = normalize(line)
        var config = BlockConfig()
        let format = formatKeyword(line)
        config.format = format ?? .circuit
        config.rounds = firstInt(#"(\d+)\s*(?:rounds?|rondas?)"#, in: key)
        config.cap = firstInt(#"(\d+)\s*min(?:utos)?\s*on"#, in: key).map(Double.init)
        if let minutes = firstInt(#"(\d+)\s*min(?:utos)?\s*off"#, in: key) {
            config.rest = minutes * 60
        } else {
            config.rest = firstInt(#"(\d+)\s*(?:sec|seg|s)\s*off"#, in: key)
        }
        if let number = firstInt(#"bloque\s*(\d+)"#, in: key) {
            config.title = "Bloque \(number)"
        } else if format == nil {
            config.title = trimmedSentence(line).capitalized
        }
        return config
    }

    // MARK: - Ejercicios

    private static func exercise(_ line: String, nameOnly: Bool) -> CircuitExercise {
        if !nameOnly, let inline = splitInline(line) {
            var e = CircuitExercise(exerciseName: inline.name)
            apply(inline.measure, to: &e)
            return e
        }
        return CircuitExercise(exerciseName: trimmedSentence(line))
    }

    private static func apply(_ measure: Measure, to exercise: inout CircuitExercise) {
        exercise.reps = measure.reps
        exercise.seconds = measure.seconds
        exercise.restSeconds = measure.rest
        exercise.note = measure.note
    }

    /// Separa "Goblet squat KB 45 sec" en nombre y medida. Un número suelto solo cuenta al final de la línea.
    private static func splitInline(_ line: String) -> (name: String, measure: Measure)? {
        let tokens = line.split(separator: " ").map(String.init)
        guard tokens.count > 1 else { return nil }
        for start in 1..<tokens.count {
            let rest = tokens[start...].joined(separator: " ")
            guard let parsed = measure(rest), parsed.explicit || parsed.wholeLine else { continue }
            var name = tokens[..<start].joined(separator: " ")
            for suffix in [" x", " X", " -", ":"] where name.hasSuffix(suffix) { name.removeLast(suffix.count) }
            return (trimmedSentence(name), parsed.measure)
        }
        return nil
    }

    private static func isMeasureLine(_ line: String) -> Bool {
        guard let parsed = measure(line) else { return false }
        return parsed.explicit || parsed.wholeLine
    }

    /// Lee una medida al inicio del texto: "12 Reps c/l", "45 sec 1 min", "3x45sec", "2 min / 20 kcal".
    static func measure(_ text: String) -> (measure: Measure, explicit: Bool, wholeLine: Bool)? {
        let pattern = #"^(?:(\d+)\s*[x×]\s*)?(\d+(?:[.,]\d+)?)\s*(repeticiones|reps?|segundos|secs?|segs?|s|minutos|mins?|')?(?=$|[\s.,/;:)])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func group(_ i: Int) -> String? {
            let r = match.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        guard let value = group(2).flatMap({ Double($0.replacingOccurrences(of: ",", with: ".")) }) else { return nil }
        let multiplier = group(1).flatMap(Int.init)
        let unit = group(3)?.lowercased()
        var result = Measure()
        var notes: [String] = []
        switch unit {
        case let u? where u.hasPrefix("min") || u == "'":
            result.seconds = Int(value * 60) * (multiplier ?? 1)
        case let u? where u.hasPrefix("s"):
            result.seconds = Int(value) * (multiplier ?? 1)
        default:
            result.reps = Int(value)
        }
        if let multiplier { notes.append("\(multiplier)x\(group(2) ?? "")\(unit.map { " \($0)" } ?? "")") }

        var remainder = ns.substring(from: match.range.location + match.range.length)
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,/;:"))
        let wholeLine = remainder.isEmpty
        // El último tiempo de una línea corta es el descanso: "45 sec 1 min".
        if remainder.split(separator: " ").count <= 8,
           let rest = trailingRest(remainder) {
            result.rest = rest.seconds
            remainder = rest.remainder
        }
        if !remainder.isEmpty { notes.append(remainder) }
        result.note = notes.isEmpty ? nil : notes.joined(separator: " · ")
        return (result, unit != nil || multiplier != nil, wholeLine)
    }

    private static func trailingRest(_ text: String) -> (seconds: Int, remainder: String)? {
        let pattern = #"(?:^|\s)(\d+)\s*(segundos|secs?|segs?|s|minutos|mins?)\.?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              let value = Int(ns.substring(with: match.range(at: 1))) else { return nil }
        let unit = ns.substring(with: match.range(at: 2)).lowercased()
        let remainder = ns.substring(to: match.range.location).trimmingCharacters(in: CharacterSet(charactersIn: " .,/;:"))
        return (unit.hasPrefix("min") ? value * 60 : value, remainder)
    }

    // MARK: - Líneas

    private static func cleanLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !isNoise($0) }
    }

    private static func isNoise(_ line: String) -> Bool {
        let key = normalize(line)
        if ["atras", "back", "no exercises available"].contains(trimmedSentence(key)) { return true }
        if key.hasPrefix("fecha de cambio") || key.contains(".com") { return true }
        return firstInt(#"^(\d{1,2}):\d{2}$"#, in: key) != nil
    }

    private static func isDayHeader(_ line: String) -> Bool {
        firstInt(#"^(?:dia|day)\s*(\d+)"#, in: normalize(line)) != nil
    }

    private static func dayName(_ line: String) -> String {
        let name = trimmedSentence(line)
        guard let regex = try? NSRegularExpression(pattern: "^(dia|día|day)", options: .caseInsensitive) else { return name }
        return regex.stringByReplacingMatches(in: name, range: NSRange(location: 0, length: (name as NSString).length),
                                              withTemplate: "Día")
    }

    private static func isFocus(_ line: String) -> Bool {
        ["full body", "upper body", "lower body", "cuerpo completo", "tren superior", "tren inferior", "piernas", "pierna"]
            .contains(trimmedSentence(normalize(line)))
    }

    /// Título de día partido en dos líneas: "x 12 REPS."
    private static func isContinuation(_ line: String) -> Bool {
        firstInt(#"^x\s*(\d+)"#, in: normalize(line)) != nil
    }

    private static func trimmedSentence(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: " .:"))
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CR")).lowercased()
    }

    private static func firstInt(_ pattern: String, in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return Int(ns.substring(with: match.range(at: 1)))
    }
}
