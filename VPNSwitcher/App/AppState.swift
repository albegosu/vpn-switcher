import Foundation
import Observation

/// Fuente de verdad de la UI: grupos de perfiles + estado observado de cada
/// uno. Los grupos cambian solo al (re)cargar la config; los estados los
/// publica el engine.
@MainActor
@Observable
final class AppState {
    enum ConfigState {
        case loaded
        case missing
        case failed(String)
    }

    private(set) var configState: ConfigState = .missing
    private(set) var groups: [ProviderGroup] = []
    private(set) var statuses: [Profile.ID: ProfileStatus] = [:]
    /// Último error de switch, visible en el pie del menú hasta el
    /// siguiente intento.
    private(set) var lastError: String?
    /// Atajos que el sistema rechazó al registrarlos (ya en uso por otra
    /// app). Se rellena al (re)cargar la config.
    private(set) var hotkeyWarnings: [String] = []
    /// Atajo de "Disconnect all" para mostrarlo junto al botón del menú.
    private(set) var disconnectAllHotkey: Hotkey?

    func setConfig(_ result: ConfigLoadResult) {
        statuses = [:]
        lastError = nil
        hotkeyWarnings = []
        disconnectAllHotkey = nil
        switch result {
        case .loaded(let config):
            configState = .loaded
            groups = ProviderGroup.grouping(config.profiles)
            disconnectAllHotkey = config.disconnectAllHotkey
        case .missing:
            configState = .missing
            groups = []
        case .failed(let message):
            configState = .failed(message)
            groups = []
        }
    }

    func addHotkeyWarning(_ warning: String) {
        hotkeyWarnings.append(warning)
    }

    func apply(_ event: SwitchEvent) {
        switch event {
        case .status(let id, let status):
            // Un switch nuevo empieza: el error anterior ya no aplica.
            if status == .switching { lastError = nil }
            statuses[id] = status
        case .switchFailed(let profile, let message):
            lastError = "\(profile): \(message)"
        }
    }

    func status(for id: Profile.ID) -> ProfileStatus {
        statuses[id] ?? .unknown
    }

    /// Cualquier perfil activo enciende el icono de la barra.
    var anyActive: Bool {
        statuses.values.contains(.active)
    }
}
