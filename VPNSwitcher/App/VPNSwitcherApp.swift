import AppKit
import SwiftUI

/// Composición de la app: carga la config, crea el engine y conecta los
/// eventos del sistema (wake). Recargable en caliente desde el menú.
@MainActor
@Observable
final class AppContainer {
    let appState: AppState
    private var engine: SwitchEngine?
    private let hotkeys = HotkeyManager()
    private let quickSwitch = QuickSwitchController()

    init() {
        appState = AppState()
        reload()
    }

    /// (Re)carga profiles.yaml y reconstruye el engine. Se usa al arrancar
    /// y desde el botón "Reload config" tras editar el fichero.
    func reload() {
        if let engine {
            Task { await engine.stop() }
        }
        engine = nil
        hotkeys.unregisterAll()

        let result = ConfigLoader.load()
        appState.setConfig(result)
        guard case .loaded(let config) = result else { return }

        let appState = self.appState
        let engine = SwitchEngine(
            profiles: config.profiles,
            pollInterval: config.pollInterval,
            onEvent: { event in
                await MainActor.run { appState.apply(event) }
            }
        )
        self.engine = engine
        Task { await engine.start() }

        registerHotkeys(config)
    }

    /// Atajos globales declarados en el YAML. Un registro rechazado
    /// (atajo ya en uso por otra app) se muestra como aviso en el menú.
    private func registerHotkeys(_ config: ProfilesConfig) {
        for profile in config.profiles {
            guard let hotkey = profile.hotkey else { continue }
            let ok = hotkeys.register(hotkey) { [weak self] in
                self?.activate(profile)
            }
            if !ok {
                appState.addHotkeyWarning(
                    "\(hotkey.display) (\(profile.name)) is already taken by another app"
                )
            }
        }
        if let hotkey = config.disconnectAllHotkey {
            let ok = hotkeys.register(hotkey) { [weak self] in
                self?.disconnectAll()
            }
            if !ok {
                appState.addHotkeyWarning(
                    "\(hotkey.display) (disconnect all) is already taken by another app"
                )
            }
        }
        if let hotkey = config.quickSwitchHotkey {
            let ok = hotkeys.register(hotkey) { [weak self] in
                self?.toggleQuickSwitch()
            }
            if !ok {
                appState.addHotkeyWarning(
                    "\(hotkey.display) (quick switch) is already taken by another app"
                )
            }
        }
    }

    func toggleQuickSwitch() {
        refreshNow()
        quickSwitch.toggle(appState: appState) { [weak self] profile in
            self?.activate(profile)
        }
    }

    func refreshNow() {
        guard let engine else { return }
        Task { await engine.refreshNow() }
    }

    func activate(_ profile: Profile) {
        guard let engine else { return }
        Task { await engine.requestActivate(profile) }
    }

    func disconnectAll() {
        guard let engine else { return }
        Task { await engine.requestDisconnectAll() }
    }

    func createExampleConfig() {
        do {
            try ConfigLoader.createExample()
            NSWorkspace.shared.open(ConfigLoader.configURL)
            reload()
        } catch {
            appState.setConfig(.failed(error.localizedDescription))
        }
    }
}

@main
struct VPNSwitcherApp: App {
    @State private var container = AppContainer()

    init() {
        // Al despertar del sueño el bucle de polling ha estado congelado:
        // refresco inmediato para que el menú no muestre estado viejo.
        let container = _container.wrappedValue
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in container.refreshNow() }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environment(container)
                .environment(container.appState)
        } label: {
            MenuBarLabel(appState: container.appState)
        }
        .menuBarExtraStyle(.window)
    }
}
