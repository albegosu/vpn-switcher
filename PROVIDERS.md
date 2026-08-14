# Providers cookbook

VPN Switcher knows nothing about specific VPN providers. Every profile is
just three shell commands, so "supporting a provider" means writing a recipe —
no code changes. This file collects tested recipes you can paste straight into
`~/.config/vpn-switcher/profiles.yaml`.

## The contract every recipe follows

Each profile declares:

| Field | Meaning |
|---|---|
| `activate_cmd` | Brings the VPN up. |
| `deactivate_cmd` | Takes it down. Optional, but **required to participate in the "one VPN at a time" exclusivity** and in "Disconnect all". |
| `status_cmd` | **exit 0 = active, exit 1 = inactive, any other code = error** (shown on the row). This is polled every `poll_interval` seconds, so the menu reflects reality even if you change the VPN outside the app. |

Commands run through `/bin/sh -c` with the Homebrew paths (`/opt/homebrew/bin`,
`/usr/local/bin`) prepended, because an app launched from Finder does not
inherit your shell's `PATH`.

Two behaviours worth knowing while writing recipes:

- **Exclusivity**: activating any profile first runs the `deactivate_cmd` of
  every *other* active profile that declares one. Give a provider a
  `deactivate_cmd` if you want "one VPN at a time" to turn it off.
- **Toggle**: activating a profile that is already active runs its
  `deactivate_cmd` (so re-selecting the active VPN disconnects it).

Legend below: ✅ = verified on a real machine · 🧪 = recipe from docs, verify
the exact syntax on your install (CLIs vary between versions).

---

## Tailscale ✅

Fast user switching between tailnets (accounts). One tailnet is active at a
time; `tailscale switch` is how you move between them.

```yaml
- name: Client A
  provider: tailscale
  activate_cmd: tailscale switch client-a.example.ts.net ; tailscale up --accept-routes
  deactivate_cmd: tailscale down
  status_cmd: s=$(tailscale status --json); echo "$s" | grep -q '"BackendState": "Running"' && echo "$s" | grep -A1 '"CurrentTailnet"' | grep -q '"Name": "client-a.example.ts.net"'
```

Notes:

- **Use `;`, not `&&`.** When Tailscale is stopped (e.g. right after the
  exclusivity `tailscale down`), `tailscale switch` still *selects* the account
  but exits non-zero (`Tailscale is stopped`). With `&&` that short-circuits and
  `up` never runs, so the tailnet never actually connects. `;` runs `up`
  regardless.
- **`up` must repeat the profile's saved non-default flags.** `tailscale up`
  refuses to run unless you mention all non-default settings. Run `tailscale up`
  once in a terminal to see what it demands (commonly `--accept-routes`) and put
  those flags in `activate_cmd`.
- **`status_cmd` checks `BackendState`, not just the name.** A tailnet stays
  *selected* even when Tailscale is stopped, so matching the name alone would
  report it active when it is not. Requiring `"BackendState": "Running"` fixes
  that.
- Drop `deactivate_cmd` if you prefer the Tailscale mesh to stay up alongside a
  WireGuard/other tunnel instead of being turned off.

## WireGuard ✅

**Recommended: the official WireGuard app (App Store).** Import the tunnel
there, then drive it with `scutil --nc` — the headless equivalent of the app's
*Activate* button. No `sudo`, no `wg-quick`, no `.conf` handling, and none of
the tunnel's `PreUp`/`PostUp` hooks run. The name must match `scutil --nc list`.

```yaml
- name: Client C
  provider: wireguard
  activate_cmd: scutil --nc start "tunnel-name"
  deactivate_cmd: scutil --nc stop "tunnel-name"
  status_cmd: scutil --nc status "tunnel-name" | head -1 | grep -qx Connected
```

`scutil --nc status` prints `Connected` / `Disconnected` on the first line, so
`grep -qx Connected` gives exit 0 only when connected. It works even with the
WireGuard app window closed — the tunnel is a system Network Extension.

The raw `wg-quick` alternative (only if you are not using the app) is covered in
the [README](README.md#wireguard); it needs a scoped `sudo` rule and runs the
tunnel's hooks as root, so review the `.conf` first.

## Native macOS VPN — IKEv2 / IPsec / L2TP ✅

Any VPN configured in **System Settings → Network** (corporate IKEv2, Cisco
IPsec, L2TP…) is controllable with the *same* `scutil --nc` recipe as WireGuard.
This covers a huge range of corporate VPNs for free — no extra tooling. Find the
service name with `scutil --nc list`.

```yaml
- name: Corp IKEv2
  provider: ipsec
  activate_cmd: scutil --nc start "Corp VPN"
  deactivate_cmd: scutil --nc stop "Corp VPN"
  status_cmd: scutil --nc status "Corp VPN" | head -1 | grep -qx Connected
```

## Mullvad 🧪

Clean CLI. Note Mullvad is a single account, not per-client tunnels.

```yaml
- name: Mullvad
  provider: mullvad
  activate_cmd: mullvad connect
  deactivate_cmd: mullvad disconnect
  status_cmd: mullvad status | grep -q Connected
```

`mullvad status` prints `Connected` / `Disconnected` / `Connecting`; `grep -q
Connected` matches only the connected state.

## Cloudflare WARP 🧪

```yaml
- name: WARP
  provider: cloudflare
  activate_cmd: warp-cli connect
  deactivate_cmd: warp-cli disconnect
  status_cmd: warp-cli status | grep -q Connected
```

## OpenVPN (via Tunnelblick) 🧪

Tunnelblick is the common macOS OpenVPN GUI and is scriptable with AppleScript.
Replace `ConfigName` with the configuration name shown in Tunnelblick.

```yaml
- name: Client OpenVPN
  provider: openvpn
  activate_cmd: osascript -e 'tell application "Tunnelblick" to connect "ConfigName"'
  deactivate_cmd: osascript -e 'tell application "Tunnelblick" to disconnect "ConfigName"'
  status_cmd: osascript -e 'tell application "Tunnelblick" to get state of first configuration where name = "ConfigName"' | grep -qx CONNECTED
```

Tunnelblick's configuration `state` is `CONNECTED` when up (other values:
`EXITING`, `SLEEP`, …). Verify the exact string on your version.

## Vendor clients — Cisco AnyConnect / Palo Alto GlobalProtect 🧪

Both ship a CLI alongside their GUI. Exact flags vary a lot between versions and
deployments, so treat these as starting points and confirm with `--help`:

- **Cisco Secure Client / AnyConnect**: `vpn connect <profile>`, `vpn disconnect`,
  `vpn state` (the `vpn` binary lives under the app bundle).
- **GlobalProtect**: `globalprotect connect --portal <portal>`,
  `globalprotect disconnect`, `globalprotect show --status`.

Map the status output to the exit-code contract with a `grep -q` on the
connected keyword, as in the examples above.

---

## Writing your own

If your VPN can be started, stopped and queried from the command line (or via
`osascript`/`scutil`), it works here. Checklist:

1. Find a **`status_cmd`** that exits **0 when up, 1 when down**. This is the
   most important part — the ✓ in the menu comes from here, not from your last
   click. `grep -q <keyword>` over the tool's status output usually does it.
2. Prefer a mechanism that **doesn't need `sudo`**: `scutil --nc` for anything in
   System Settings, a vendor CLI, or an `osascript` tell. Reach for `sudo` only
   when there is no alternative, and scope it tightly (see the README).
3. Add a **`deactivate_cmd`** if you want the profile to take part in the
   "one VPN at a time" exclusivity and in "Disconnect all".
4. Pick a `provider:` string — it only groups profiles in the menu. Known
   values (`tailscale`, `wireguard`, `ipsec`, `mullvad`, `cloudflare`,
   `openvpn`) get a friendly name and icon; anything else falls back to a
   capitalised name and a generic network icon.

Got a recipe working for a provider not listed here? PRs to this file are
welcome.
