import Foundation

/// Un perfil de VPN declarado en profiles.yaml. La app no sabe nada de
/// Tailscale ni WireGuard: solo ejecuta los comandos que el perfil declara.
/// Añadir un cliente nuevo = añadir un bloque al YAML, sin tocar código.
struct Profile: Identifiable, Hashable, Sendable {
    let name: String
    /// Agrupa perfiles en el menú y delimita la exclusión mutua: al activar
    /// un perfil se desactiva el que estuviera activo del mismo provider
    /// (si declara deactivate_cmd).
    let provider: String
    let activateCmd: String
    /// Opcional: Tailscale no lo necesita (switch es atómico); WireGuard sí.
    let deactivateCmd: String?
    /// Contrato: exit 0 = activo, exit 1 = inactivo, otro = error.
    let statusCmd: String
    /// Atajo global opcional para activar este perfil ("hotkey: cmd+opt+1").
    let hotkey: Hotkey?

    var id: String { "\(provider)/\(name)" }
}

/// Estado observado de un perfil. Sale del status_cmd (polling), no del
/// último clic: si el usuario cambia de VPN fuera de la app, esto lo refleja.
enum ProfileStatus: Sendable, Equatable {
    case unknown
    case active
    case inactive
    /// Transición en curso (activate/deactivate lanzado, esperando resultado).
    case switching
    /// El status_cmd falló de verdad (comando no encontrado, timeout…),
    /// distinto de "inactivo".
    case failed(String)
}

/// Sección del menú: perfiles agrupados por provider en orden de aparición
/// en el YAML.
struct ProviderGroup: Identifiable, Sendable {
    let provider: String
    let profiles: [Profile]

    var id: String { provider }

    // Nombres e iconos de los providers conocidos (ver PROVIDERS.md). Un
    // provider desconocido no es un error: cae en el genérico (nombre
    // capitalizado + icono de red).
    var displayName: String {
        switch provider.lowercased() {
        case "tailscale": "Tailscale"
        case "wireguard": "WireGuard"
        case "ipsec", "ikev2", "l2tp": "Native VPN"
        case "mullvad": "Mullvad"
        case "cloudflare", "warp": "Cloudflare WARP"
        case "openvpn": "OpenVPN"
        default: provider.prefix(1).uppercased() + provider.dropFirst()
        }
    }

    var systemImage: String {
        switch provider.lowercased() {
        case "tailscale": "point.3.connected.trianglepath.dotted"
        case "wireguard": "lock.shield"
        case "ipsec", "ikev2", "l2tp": "building.2"
        case "mullvad": "shield.lefthalf.filled"
        case "cloudflare", "warp": "cloud.fill"
        case "openvpn": "lock.rotation"
        default: "network"
        }
    }

    /// Construye los grupos preservando el orden del fichero de config.
    static func grouping(_ profiles: [Profile]) -> [ProviderGroup] {
        var order: [String] = []
        var byProvider: [String: [Profile]] = [:]
        for profile in profiles {
            if byProvider[profile.provider] == nil {
                order.append(profile.provider)
            }
            byProvider[profile.provider, default: []].append(profile)
        }
        return order.map { ProviderGroup(provider: $0, profiles: byProvider[$0] ?? []) }
    }
}
