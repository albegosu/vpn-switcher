# Contributing

Thanks for your interest! VPN Switcher is a small, dependency-free macOS menu
bar app, and the most valuable contributions are usually **new provider
recipes** — no Swift required.

## Adding a provider recipe

The app is declarative: a provider is just three shell commands
(`activate_cmd`, `deactivate_cmd`, `status_cmd`). If your VPN can be
started/stopped/queried from the command line (or via `scutil`/`osascript`),
it works — add a tested recipe to [PROVIDERS.md](PROVIDERS.md) and open a PR.

The only rule for `status_cmd`: it must exit **0 when active, 1 when
inactive**. Mark whether you verified the recipe on a real machine (✅) or it
comes from docs and needs checking (🧪).

Giving a known provider a nicer menu name and icon is a small change in
`ProviderGroup` (`VPNSwitcher/Core/Profile.swift`).

## Building & testing

Requirements: macOS 15+, Xcode 16+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```sh
make gen        # regenerate VPNSwitcher.xcodeproj from project.yml
make build      # build
make test       # run the test suite
make typecheck  # fast type-check without Xcode (Command Line Tools only)
```

The `.xcodeproj` is generated from `project.yml` and is **not** committed —
run `make gen` after cloning (the other targets do it for you).

## Code style

- Match the surrounding code: naming, comment density, and idioms.
- **Swift 6 with strict concurrency** (`SWIFT_STRICT_CONCURRENCY: complete`).
  New code must build clean under it.
- **Zero third-party dependencies.** The YAML is parsed by a small
  purpose-built parser; please keep the project dependency-free.
- Add or update tests in `VPNSwitcherTests` for parser/logic changes. Pure
  logic is factored out so it can be tested without launching the app.

## Pull requests

- Branch off `main`, keep PRs focused, and describe what and why.
- Make sure `make test` passes before opening the PR (CI runs it too).
- Never commit real VPN configs or private keys. `~/.config/vpn-switcher/` is
  outside the repo, and `.gitignore` blocks `profiles.yaml` and `*.conf` as a
  safety net.
