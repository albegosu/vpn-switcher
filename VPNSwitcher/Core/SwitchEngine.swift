import Foundation

/// Eventos del engine hacia la UI (vía callback que salta al MainActor).
enum SwitchEvent: Sendable {
    case status(id: Profile.ID, ProfileStatus)
    case switchFailed(profile: String, message: String)
}

/// Coordina los perfiles: un bucle de polling de los status_cmd y la
/// ejecución de los switches. El estado que publica sale siempre del
/// status_cmd, no del último clic — si el usuario cambia de VPN fuera de
/// la app, el siguiente sondeo lo refleja.
actor SwitchEngine {
    static let statusTimeout: TimeInterval = 10
    static let switchTimeout: TimeInterval = 60

    private let profiles: [Profile]
    private let pollInterval: TimeInterval
    private let onEvent: @Sendable (SwitchEvent) async -> Void

    private var statuses: [Profile.ID: ProfileStatus] = [:]
    private var pollLoop: Task<Void, Never>?
    private var isSwitching = false

    init(
        profiles: [Profile],
        pollInterval: TimeInterval,
        onEvent: @escaping @Sendable (SwitchEvent) async -> Void
    ) {
        self.profiles = profiles
        self.pollInterval = pollInterval
        self.onEvent = onEvent
    }

    func start() {
        pollLoop?.cancel()
        pollLoop = Task {
            while !Task.isCancelled {
                await self.pollAll()
                try? await Task.sleep(
                    for: .seconds(pollInterval), tolerance: .seconds(pollInterval * 0.1)
                )
            }
        }
    }

    func stop() {
        pollLoop?.cancel()
        pollLoop = nil
    }

    /// Refresco inmediato (apertura del menú, wake-from-sleep, botón Refresh).
    func refreshNow() async {
        await pollAll()
    }

    /// Lanza el switch en un Task propio del actor: el Task de la vista que
    /// lo pide muere cuando el menú se cierra, y el cambio no debe abortarse
    /// a medias por eso.
    func requestActivate(_ target: Profile) {
        guard !isSwitching else { return }
        isSwitching = true
        Task { await self.performSwitch(target) }
    }

    /// Corta todas las VPNs activas que declaren deactivate_cmd (menú o
    /// atajo global). Los perfiles sin deactivate_cmd no se tocan.
    func requestDisconnectAll() {
        guard !isSwitching else { return }
        isSwitching = true
        Task { await self.performDisconnectAll() }
    }

    private func performDisconnectAll() async {
        let active = profiles.filter {
            statuses[$0.id] == .active && $0.deactivateCmd != nil
        }
        for profile in active {
            await publish(profile.id, .switching)
        }
        for profile in active {
            guard let cmd = profile.deactivateCmd else { continue }
            let result = await CommandRunner.run(cmd, timeout: Self.switchTimeout)
            if !result.succeeded {
                await onEvent(.switchFailed(profile: profile.name, message: result.failureMessage))
            }
        }
        isSwitching = false
        await pollAll()
    }

    private func performSwitch(_ target: Profile) async {
        // Toggle: activar un perfil que ya está activo lo desactiva (si sabe
        // cómo). Vale para clic en el menú, atajo y panel ⌃⌥V por igual.
        if statuses[target.id] == .active, let cmd = target.deactivateCmd {
            await publish(target.id, .switching)
            let result = await CommandRunner.run(cmd, timeout: Self.switchTimeout)
            if !result.succeeded {
                await onEvent(.switchFailed(profile: target.name, message: result.failureMessage))
            }
            isSwitching = false
            await pollAll()
            return
        }

        await publish(target.id, .switching)

        // Exclusividad global: una sola VPN activa a la vez. Al activar un
        // perfil se desactiva CUALQUIER otro que esté activo y sepa
        // desactivarse (scutil stop, tailscale down…), sea del provider que
        // sea. Los que no declaran deactivate_cmd se dejan como están —
        // p. ej. Tailscale entre tailnets: `switch` es atómico y no necesita
        // un `down` previo.
        for profile in profiles
        where profile.id != target.id && statuses[profile.id] == .active {
            guard let cmd = profile.deactivateCmd else { continue }
            await publish(profile.id, .switching)
            let result = await CommandRunner.run(cmd, timeout: Self.switchTimeout)
            if !result.succeeded {
                await onEvent(.switchFailed(profile: profile.name, message: result.failureMessage))
            }
        }

        let result = await CommandRunner.run(target.activateCmd, timeout: Self.switchTimeout)
        if !result.succeeded {
            await onEvent(.switchFailed(profile: target.name, message: result.failureMessage))
        }

        // Estado real tras el cambio, venga bien o mal la activación.
        isSwitching = false
        await pollAll()
    }

    private func pollAll() async {
        guard !isSwitching else { return }
        await withTaskGroup(of: (Profile.ID, ProfileStatus).self) { group in
            for profile in profiles {
                group.addTask { (profile.id, await Self.probe(profile)) }
            }
            for await (id, status) in group {
                // Un switch puede haber empezado mientras sondeábamos:
                // no pisar su estado transitorio.
                guard !isSwitching else { continue }
                await publish(id, status)
            }
        }
    }

    private func publish(_ id: Profile.ID, _ status: ProfileStatus) async {
        guard statuses[id] != status else { return }
        statuses[id] = status
        await onEvent(.status(id: id, status))
    }

    /// Contrato del status_cmd: exit 0 = activo, exit 1 = inactivo
    /// (la convención de grep/test), cualquier otra cosa = error real.
    private static func probe(_ profile: Profile) async -> ProfileStatus {
        let result = await CommandRunner.run(profile.statusCmd, timeout: statusTimeout)
        if result.timedOut { return .failed("status check timed out") }
        switch result.exitCode {
        case 0: return .active
        case 1: return .inactive
        default: return .failed(result.failureMessage)
        }
    }
}
