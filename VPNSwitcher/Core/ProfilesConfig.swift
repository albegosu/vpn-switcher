import Foundation

/// Configuración declarativa completa (profiles.yaml parseado).
struct ProfilesConfig: Sendable, Equatable {
    static let defaultPollInterval: TimeInterval = 10

    var pollInterval: TimeInterval
    var profiles: [Profile]
    /// Atajo global opcional para cortar todas las VPNs activas
    /// ("disconnect_all_hotkey: cmd+opt+0").
    var disconnectAllHotkey: Hotkey?
    /// Atajo global opcional que abre el panel flotante de cambio rápido
    /// ("quick_switch_hotkey: cmd+shift+v").
    var quickSwitchHotkey: Hotkey?
}

enum ProfilesConfigError: Error, Equatable, LocalizedError {
    case noProfiles
    case missingField(profile: String, field: String)
    case invalidLine(line: Int, content: String)
    case invalidHotkey(context: String, value: String)

    var errorDescription: String? {
        switch self {
        case .noProfiles:
            "No profiles defined (expected a top-level `profiles:` list)"
        case .missingField(let profile, let field):
            "Profile \"\(profile)\" is missing required field `\(field)`"
        case .invalidLine(let line, let content):
            "Cannot parse line \(line): \(content) — subset YAML only (no folded/literal scalars `>` / `|`; use a single-line value)"
        case .invalidHotkey(let context, let value):
            "Invalid hotkey \"\(value)\" for \(context) — use modifiers+key, e.g. cmd+opt+1"
        }
    }
}

/// Parser del subconjunto de YAML que usa profiles.yaml: claves top-level
/// escalares y una lista `profiles:` de mapas planos. Sin dependencias
/// externas a propósito (misma filosofía que Pocket: cero paquetes).
/// Soporta comentarios (#), valores entrecomillados (doble: `\"` / `\\`;
/// simple: `''` → `'`) y claves desconocidas (se ignoran, para
/// compatibilidad hacia delante). No soporta escalares multilínea / folded
/// (`>` / `|`) — usar un valor en una sola línea.
enum ProfilesConfigParser {
    static func parse(_ text: String) throws -> ProfilesConfig {
        var pollInterval = ProfilesConfig.defaultPollInterval
        var disconnectAllHotkey: Hotkey?
        var quickSwitchHotkey: Hotkey?
        var profiles: [Profile] = []
        var current: [String: String]?
        var currentFirstLine = 0
        var inProfiles = false

        func flush() throws {
            guard let fields = current else { return }
            profiles.append(try makeProfile(fields, line: currentFirstLine))
            current = nil
        }

        for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let lineNumber = index + 1
            let line = stripComment(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let indent = line.prefix(while: { $0 == " " }).count

            if indent == 0 {
                try flush()
                if trimmed == "profiles:" {
                    inProfiles = true
                    continue
                }
                inProfiles = false
                guard let (key, value) = try keyValue(trimmed, line: lineNumber) else {
                    throw ProfilesConfigError.invalidLine(line: lineNumber, content: trimmed)
                }
                if key == "poll_interval", let seconds = TimeInterval(value), seconds >= 1 {
                    pollInterval = seconds
                }
                if key == "disconnect_all_hotkey", !value.isEmpty {
                    guard let hotkey = Hotkey(parsing: value) else {
                        throw ProfilesConfigError.invalidHotkey(
                            context: "disconnect_all_hotkey", value: value
                        )
                    }
                    disconnectAllHotkey = hotkey
                }
                if key == "quick_switch_hotkey", !value.isEmpty {
                    guard let hotkey = Hotkey(parsing: value) else {
                        throw ProfilesConfigError.invalidHotkey(
                            context: "quick_switch_hotkey", value: value
                        )
                    }
                    quickSwitchHotkey = hotkey
                }
                // Claves top-level desconocidas: ignoradas.
                continue
            }

            // Contenido anidado bajo una clave top-level que no es profiles:
            // se ignora entero (compatibilidad hacia delante).
            guard inProfiles else { continue }

            var content = trimmed
            if content == "-" {
                try flush()
                current = [:]
                currentFirstLine = lineNumber
                continue
            }
            if content.hasPrefix("- ") {
                try flush()
                current = [:]
                currentFirstLine = lineNumber
                content = String(content.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
            guard current != nil, let (key, value) = try keyValue(content, line: lineNumber) else {
                throw ProfilesConfigError.invalidLine(line: lineNumber, content: trimmed)
            }
            current?[key] = value
        }
        try flush()

        guard !profiles.isEmpty else { throw ProfilesConfigError.noProfiles }
        return ProfilesConfig(
            pollInterval: pollInterval,
            profiles: profiles,
            disconnectAllHotkey: disconnectAllHotkey,
            quickSwitchHotkey: quickSwitchHotkey
        )
    }

    private static func makeProfile(_ fields: [String: String], line: Int) throws -> Profile {
        let name = fields["name"] ?? ""
        func require(_ field: String) throws -> String {
            guard let value = fields[field], !value.isEmpty else {
                throw ProfilesConfigError.missingField(
                    profile: name.isEmpty ? "line \(line)" : name, field: field
                )
            }
            return value
        }
        var hotkey: Hotkey?
        if let raw = fields["hotkey"], !raw.isEmpty {
            guard let parsed = Hotkey(parsing: raw) else {
                throw ProfilesConfigError.invalidHotkey(
                    context: "profile \"\(name)\"", value: raw
                )
            }
            hotkey = parsed
        }
        return Profile(
            name: try require("name"),
            provider: try require("provider").lowercased(),
            activateCmd: try require("activate_cmd"),
            deactivateCmd: fields["deactivate_cmd"].flatMap { $0.isEmpty ? nil : $0 },
            statusCmd: try require("status_cmd"),
            hotkey: hotkey
        )
    }

    /// Separa "key: value" en la primera aparición de ": " (o ":" final).
    /// Los dos puntos posteriores quedan dentro del valor, así los comandos
    /// con URLs o `sh -c 'a: b'` no se rompen.
    /// Lanza `invalidLine` si el valor es un indicador de escalar folded/literal
    /// (`>` / `|`), no soportado por este subconjunto.
    private static func keyValue(_ text: String, line: Int) throws -> (key: String, value: String)? {
        if let range = text.range(of: ": ") {
            let key = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let raw = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard isPlainKey(key) else { return nil }
            if isUnsupportedBlockScalar(raw) {
                throw ProfilesConfigError.invalidLine(
                    line: line,
                    content: "\(text) — folded/literal scalars (`>` / `|`) are unsupported; use a single-line value"
                )
            }
            return (key, unquote(raw))
        }
        if text.hasSuffix(":") {
            let key = String(text.dropLast()).trimmingCharacters(in: .whitespaces)
            guard isPlainKey(key) else { return nil }
            return (key, "")
        }
        return nil
    }

    /// Una clave YAML de las nuestras: identificador simple, sin espacios.
    /// Evita partir por el ":" de un comando tipo `echo foo: bar` sin clave.
    private static func isPlainKey(_ key: String) -> Bool {
        !key.isEmpty && key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
    }

    /// Detecta indicadores de block scalar YAML (`>`, `|`, `|-`, `>+`, `>2`…).
    /// Solo aplica a valores sin comillas; `">"` / `'>'` son literales válidos.
    private static func isUnsupportedBlockScalar(_ raw: String) -> Bool {
        guard let first = raw.first, first == ">" || first == "|" else { return false }
        if raw.hasPrefix("\"") || raw.hasPrefix("'") { return false }
        // YAML 1.2: optional chomping (+/-) and/or indentation digits, either order.
        let rest = raw.dropFirst()
        if rest.isEmpty { return true }
        let ok = rest.allSatisfy { $0 == "+" || $0 == "-" || $0.isNumber }
        return ok && rest.filter({ $0 == "+" || $0 == "-" }).count <= 1
    }

    /// Quita un comentario `#` fuera de comillas. Regla YAML: el `#` abre
    /// comentario solo al inicio o precedido de espacio. Dentro de dobles
    /// comillas, `\"` y `\\` no cierran / no escapan mal el estado.
    private static func stripComment(_ line: String) -> String {
        var inSingle = false
        var inDouble = false
        var previous: Character?
        var index = line.startIndex
        while index < line.endIndex {
            let char = line[index]
            if inDouble && char == "\\" {
                let next = line.index(after: index)
                if next < line.endIndex {
                    previous = line[next]
                    index = line.index(after: next)
                    continue
                }
            }
            switch char {
            case "'" where !inDouble:
                if inSingle {
                    // YAML '' inside single-quoted: stay in single quotes.
                    let next = line.index(after: index)
                    if next < line.endIndex, line[next] == "'" {
                        previous = "'"
                        index = line.index(after: next)
                        continue
                    }
                }
                inSingle.toggle()
            case "\"" where !inSingle:
                inDouble.toggle()
            case "#" where !inSingle && !inDouble:
                if previous == nil || previous == " " {
                    return String(line[..<index])
                }
            default: break
            }
            previous = char
            index = line.index(after: index)
        }
        return line
    }

    /// Quita comillas externas y aplica escapes del subconjunto YAML:
    /// - Doble: `\"` → `"`, `\\` → `\`
    /// - Simple: `''` → `'` (único escape en single-quoted YAML)
    private static func unquote(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if value.hasPrefix("\"") && value.hasSuffix("\"") {
            return unescapeDoubleQuoted(String(value.dropFirst().dropLast()))
        }
        if value.hasPrefix("'") && value.hasSuffix("'") {
            return String(value.dropFirst().dropLast())
                .replacingOccurrences(of: "''", with: "'")
        }
        return value
    }

    private static func unescapeDoubleQuoted(_ text: String) -> String {
        var result = String()
        result.reserveCapacity(text.count)
        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]
            if char == "\\" {
                let next = text.index(after: index)
                if next < text.endIndex {
                    let escaped = text[next]
                    switch escaped {
                    case "\\", "\"":
                        result.append(escaped)
                        index = text.index(after: next)
                        continue
                    default:
                        // Solo soportamos \\ y \"; el resto se deja literal.
                        result.append(char)
                        index = next
                        continue
                    }
                }
            }
            result.append(char)
            index = text.index(after: index)
        }
        return result
    }
}
