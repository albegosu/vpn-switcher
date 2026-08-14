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
            "Cannot parse line \(line): \(content)"
        case .invalidHotkey(let context, let value):
            "Invalid hotkey \"\(value)\" for \(context) — use modifiers+key, e.g. cmd+opt+1"
        }
    }
}

/// Parser del subconjunto de YAML que usa profiles.yaml: claves top-level
/// escalares y una lista `profiles:` de mapas planos. Sin dependencias
/// externas a propósito (misma filosofía que Pocket: cero paquetes).
/// Soporta comentarios (#), valores entrecomillados y claves desconocidas
/// (se ignoran, para compatibilidad hacia delante).
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
                guard let (key, value) = keyValue(trimmed) else {
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
            guard current != nil, let (key, value) = keyValue(content) else {
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
    private static func keyValue(_ text: String) -> (key: String, value: String)? {
        if let range = text.range(of: ": ") {
            let key = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let value = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard isPlainKey(key) else { return nil }
            return (key, unquote(value))
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

    /// Quita un comentario `#` fuera de comillas. Regla YAML: el `#` abre
    /// comentario solo al inicio o precedido de espacio.
    private static func stripComment(_ line: String) -> String {
        var inSingle = false
        var inDouble = false
        var previous: Character?
        for index in line.indices {
            let char = line[index]
            switch char {
            case "'" where !inDouble: inSingle.toggle()
            case "\"" where !inSingle: inDouble.toggle()
            case "#" where !inSingle && !inDouble:
                if previous == nil || previous == " " {
                    return String(line[..<index])
                }
            default: break
            }
            previous = char
        }
        return line
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if (value.hasPrefix("\"") && value.hasSuffix("\""))
            || (value.hasPrefix("'") && value.hasSuffix("'")) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}
