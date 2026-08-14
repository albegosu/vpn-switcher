import Foundation
import Testing

@Suite("ProfilesConfigParser")
struct ProfilesConfigTests {
    let sample = """
    # Config de ejemplo
    poll_interval: 5

    profiles:
      - name: Cliente A
        provider: tailscale
        activate_cmd: tailscale switch cliente-a.example.ts.net
        status_cmd: tailscale status --json | grep -q '"Name":.*cliente-a'

      - name: "Cliente C"
        provider: wireguard
        activate_cmd: sudo wg-quick up cliente-c
        deactivate_cmd: sudo wg-quick down cliente-c
        status_cmd: test -e /var/run/wireguard/cliente-c.name
    """

    @Test func parsesProfilesAndInterval() throws {
        let config = try ProfilesConfigParser.parse(sample)
        #expect(config.pollInterval == 5)
        #expect(config.profiles.count == 2)

        let a = config.profiles[0]
        #expect(a.name == "Cliente A")
        #expect(a.provider == "tailscale")
        #expect(a.activateCmd == "tailscale switch cliente-a.example.ts.net")
        #expect(a.deactivateCmd == nil)
        // El ":" y el "#"-menos-comentario dentro del comando no lo rompen.
        #expect(a.statusCmd == #"tailscale status --json | grep -q '"Name":.*cliente-a'"#)

        let c = config.profiles[1]
        #expect(c.name == "Cliente C")
        #expect(c.deactivateCmd == "sudo wg-quick down cliente-c")
    }

    @Test func defaultPollInterval() throws {
        let config = try ProfilesConfigParser.parse("""
        profiles:
          - name: X
            provider: tailscale
            activate_cmd: a
            status_cmd: s
        """)
        #expect(config.pollInterval == ProfilesConfig.defaultPollInterval)
    }

    @Test func commentsAndBlankLinesIgnored() throws {
        let config = try ProfilesConfigParser.parse("""
        # cabecera
        profiles:
          # comentario dentro de la lista
          - name: X   # comentario en línea
            provider: tailscale
            activate_cmd: a
            status_cmd: grep -q '#not-a-comment' /tmp/f
        """)
        #expect(config.profiles[0].name == "X")
        // Un "#" pegado a texto (sin espacio antes) no es comentario.
        #expect(config.profiles[0].statusCmd == "grep -q '#not-a-comment' /tmp/f")
    }

    @Test func providerNormalizedToLowercase() throws {
        let config = try ProfilesConfigParser.parse("""
        profiles:
          - name: X
            provider: Tailscale
            activate_cmd: a
            status_cmd: s
        """)
        #expect(config.profiles[0].provider == "tailscale")
    }

    @Test func missingRequiredFieldThrows() {
        #expect(throws: ProfilesConfigError.missingField(profile: "X", field: "status_cmd")) {
            try ProfilesConfigParser.parse("""
            profiles:
              - name: X
                provider: tailscale
                activate_cmd: a
            """)
        }
    }

    @Test func emptyConfigThrows() {
        #expect(throws: ProfilesConfigError.noProfiles) {
            try ProfilesConfigParser.parse("poll_interval: 5\n")
        }
    }

    @Test func unknownKeysIgnored() throws {
        let config = try ProfilesConfigParser.parse("""
        future_option: whatever
        nested_future:
          sub: value
        profiles:
          - name: X
            provider: tailscale
            activate_cmd: a
            status_cmd: s
            future_field: ignored
        """)
        #expect(config.profiles.count == 1)
    }

    @Test func exampleTemplateParses() throws {
        // La plantilla que escribe "Create example config" tiene que ser
        // siempre parseable.
        let config = try ProfilesConfigParser.parse(ConfigLoader.exampleTemplate)
        #expect(config.profiles.count == 3)
        let groups = ProviderGroup.grouping(config.profiles)
        #expect(groups.map(\.provider) == ["tailscale", "wireguard"])
        #expect(groups[0].profiles.count == 2)
    }

    @Test func groupingPreservesConfigOrder() throws {
        let profiles = [
            Profile(name: "W1", provider: "wireguard", activateCmd: "a", deactivateCmd: "d", statusCmd: "s", hotkey: nil),
            Profile(name: "T1", provider: "tailscale", activateCmd: "a", deactivateCmd: nil, statusCmd: "s", hotkey: nil),
            Profile(name: "W2", provider: "wireguard", activateCmd: "a", deactivateCmd: "d", statusCmd: "s", hotkey: nil),
        ]
        let groups = ProviderGroup.grouping(profiles)
        #expect(groups.map(\.provider) == ["wireguard", "tailscale"])
        #expect(groups[0].profiles.map(\.name) == ["W1", "W2"])
        #expect(groups[1].displayName == "Tailscale")
    }
}

@Suite("Hotkey")
struct HotkeyTests {
    @Test func parsesModifiersAndKey() throws {
        let hotkey = try #require(Hotkey(parsing: "cmd+opt+1"))
        #expect(hotkey.keyCode == 18)
        #expect(hotkey.carbonModifiers == 0x0100 | 0x0800)
        #expect(hotkey.display == "⌥⌘1")
    }

    @Test func acceptsAliasesAndCase() throws {
        let a = try #require(Hotkey(parsing: "Command+Alt+T"))
        let b = try #require(Hotkey(parsing: "cmd+opt+t"))
        #expect(a == b)
    }

    @Test func parsesFunctionAndSpaceKeys() throws {
        #expect(Hotkey(parsing: "ctrl+f5")?.keyCode == 96)
        #expect(Hotkey(parsing: "cmd+shift+space")?.display == "⇧⌘Space")
    }

    @Test func rejectsInvalidCombos() {
        // Sin modificador real: secuestraría la escritura normal.
        #expect(Hotkey(parsing: "1") == nil)
        #expect(Hotkey(parsing: "shift+1") == nil)
        // Tecla o modificador desconocidos.
        #expect(Hotkey(parsing: "cmd+enter") == nil)
        #expect(Hotkey(parsing: "hyper+1") == nil)
        #expect(Hotkey(parsing: "") == nil)
    }

    @Test func profileAndTopLevelHotkeysParse() throws {
        let config = try ProfilesConfigParser.parse("""
        disconnect_all_hotkey: cmd+opt+0
        quick_switch_hotkey: cmd+shift+v
        profiles:
          - name: X
            provider: tailscale
            activate_cmd: a
            status_cmd: s
            hotkey: cmd+opt+1
        """)
        #expect(config.disconnectAllHotkey?.display == "⌥⌘0")
        #expect(config.quickSwitchHotkey?.display == "⇧⌘V")
        #expect(config.profiles[0].hotkey?.display == "⌥⌘1")
    }

    @Test func invalidHotkeyThrowsWithContext() {
        #expect(throws: ProfilesConfigError.invalidHotkey(context: "profile \"X\"", value: "1")) {
            try ProfilesConfigParser.parse("""
            profiles:
              - name: X
                provider: tailscale
                activate_cmd: a
                status_cmd: s
                hotkey: 1
            """)
        }
    }
}
