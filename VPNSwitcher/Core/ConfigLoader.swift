import Foundation

/// Resultado de cargar ~/.config/vpn-switcher/profiles.yaml.
enum ConfigLoadResult: Sendable {
    case loaded(ProfilesConfig)
    case missing
    case failed(String)
}

/// Lee y crea el fichero de configuración. Vive fuera del repo a propósito:
/// las configs reales (nombres de clientes, tailnets, túneles) no se
/// versionan nunca.
enum ConfigLoader {
    static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config/vpn-switcher/profiles.yaml")
    }

    static func load() -> ConfigLoadResult {
        let url = configURL
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        do {
            // El fichero define comandos que la app ejecuta: si otros
            // usuarios pueden escribirlo, negarse a cargarlo (fail-closed).
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let permissions = attributes[.posixPermissions] as? NSNumber,
               permissions.uint16Value & 0o022 != 0 {
                return .failed(
                    "profiles.yaml is writable by other users — run: chmod 600 \(url.path)"
                )
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            return .loaded(try ProfilesConfigParser.parse(text))
        } catch let error as ProfilesConfigError {
            return .failed(error.localizedDescription)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Crea la config de ejemplo si no existe todavía (misma plantilla que
    /// profiles.example.yaml del repo). Directorio 700 y fichero 600: los
    /// nombres de clientes/tailnets son metadatos sensibles, y el fichero
    /// define comandos que la app ejecuta — nadie más debe poder tocarlo.
    static func createExample() throws {
        let url = configURL
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try Data(exampleTemplate.utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: url.path
        )
    }

    static let exampleTemplate = """
    # VPN Switcher profiles — ~/.config/vpn-switcher/profiles.yaml
    #
    # Every profile declares its own shell commands; the app knows nothing
    # about specific providers. status_cmd contract: exit 0 = active,
    # exit 1 = inactive, any other exit code = error (shown on the row).
    #
    # This file defines commands the app runs, so keep it private: chmod 600
    # (the app refuses to load it when other users can write it).
    #
    # Everything below is a PLACEHOLDER — replace the tailnets, tunnel names
    # and hotkeys with your own before use.

    # ------------------------------------------------------------------ #
    # Global options                                                     #
    # ------------------------------------------------------------------ #

    # Seconds between status polls (optional, default 10).
    poll_interval: 10

    # Global hotkey that opens the quick-switch panel (optional): type to
    # filter, arrow keys to move, Enter to activate, Esc to close.
    # Hotkey format: modifiers + key joined by "+". Modifiers: cmd, opt
    # (or alt), ctrl, shift. Key: a letter, a digit, "space" or F1-F12.
    # At least one non-shift modifier is required.
    # NOTE: a global hotkey overrides that combo system-wide, so pick one you
    # do not use anywhere else — ctrl+opt+<key> is usually free.
    quick_switch_hotkey: ctrl+opt+v

    # Global hotkey to disconnect every active VPN that declares a
    # deactivate_cmd (optional).
    disconnect_all_hotkey: ctrl+opt+0

    # ------------------------------------------------------------------ #
    # Profiles — grouped in the menu by `provider`, in file order        #
    # ------------------------------------------------------------------ #

    profiles:
      # --- Tailscale: one account (tailnet) per client -------------------
      # activate: use ';' NOT '&&'. When Tailscale is stopped (e.g. right
      # after the exclusivity `tailscale down`), `switch` still SELECTS the
      # account but exits non-zero ("Tailscale is stopped"), which would
      # short-circuit '&&' and skip `up`. With ';' we always run `up` with
      # the profile's saved non-default flags (run `tailscale up` once to see
      # which it demands — commonly --accept-routes) to bring it online.
      # deactivate: `tailscale down` so activating a different VPN turns
      # Tailscale off (drop it if you prefer the mesh to stay up alongside
      # WireGuard). Switching between two tailnets then does a quick down+up.
      # status_cmd requires BackendState "Running" AND the selected tailnet:
      # a tailnet stays "selected" even when Tailscale is stopped, so checking
      # the name alone would show it active when it is not.
      - name: Client A
        provider: tailscale
        hotkey: ctrl+opt+1
        activate_cmd: tailscale switch client-a.example.ts.net ; tailscale up --accept-routes
        deactivate_cmd: tailscale down
        status_cmd: s=$(tailscale status --json); echo "$s" | grep -q '"BackendState": "Running"' && echo "$s" | grep -A1 '"CurrentTailnet"' | grep -q '"Name": "client-a.example.ts.net"'

      - name: Client B
        provider: tailscale
        hotkey: ctrl+opt+2
        activate_cmd: tailscale switch client-b.example.ts.net ; tailscale up --accept-routes
        deactivate_cmd: tailscale down
        status_cmd: s=$(tailscale status --json); echo "$s" | grep -q '"BackendState": "Running"' && echo "$s" | grep -A1 '"CurrentTailnet"' | grep -q '"Name": "client-b.example.ts.net"'

      # --- WireGuard via the official app (Apple Network Extension) ------
      # RECOMMENDED: install the official WireGuard app (App Store), import
      # your tunnel there, and let vpn-switcher drive it with `scutil --nc`.
      # This is the headless equivalent of the app's Activate button: no
      # sudo, no wg-quick, no .conf handling, and none of the tunnel's
      # PreUp/PostUp hooks run. The name must match `scutil --nc list`.
      - name: Client C
        provider: wireguard
        hotkey: ctrl+opt+3
        activate_cmd: scutil --nc start "client-c-tunnel"
        deactivate_cmd: scutil --nc stop "client-c-tunnel"
        status_cmd: scutil --nc status "client-c-tunnel" | head -1 | grep -qx Connected

      # Alternative — raw wg-quick (only if you are NOT using the app):
      # needs a NOPASSWD sudoers entry scoped to wg-quick, and wg-quick runs
      # the tunnel's PreUp/PostUp hooks as root. See the README for the
      # hardening steps and trade-offs.
      # - name: Client C (wg-quick)
      #   provider: wireguard
      #   activate_cmd: sudo /opt/homebrew/bin/wg-quick up /usr/local/etc/wireguard/client-c.conf
      #   deactivate_cmd: sudo /opt/homebrew/bin/wg-quick down /usr/local/etc/wireguard/client-c.conf
      #   status_cmd: test -e /var/run/wireguard/client-c.name

    """
}
