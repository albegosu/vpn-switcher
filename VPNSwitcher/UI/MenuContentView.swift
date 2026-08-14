import AppKit
import SwiftUI

struct MenuContentView: View {
    @Environment(AppContainer.self) private var container
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch appState.configState {
            case .loaded:
                ForEach(appState.groups) { group in
                    ProviderGroupView(group: group)
                    Divider()
                }
                disconnectAllRow
                if let error = appState.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(3)
                }
                ForEach(appState.hotkeyWarnings, id: \.self) { warning in
                    Label(warning, systemImage: "keyboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            case .missing:
                missingConfig
                Divider()
            case .failed(let message):
                brokenConfig(message)
                Divider()
            }
            footer
        }
        .padding(12)
        .frame(width: 300)
        .task {
            // Estado fresco cada vez que se abre el menú.
            container.refreshNow()
        }
    }

    /// Corta todas las VPNs activas que declaren deactivate_cmd. Solo tiene
    /// sentido con algo activo; si no, se muestra deshabilitado.
    private var disconnectAllRow: some View {
        HStack(spacing: 6) {
            Button {
                container.disconnectAll()
            } label: {
                Label("Disconnect all", systemImage: "xmark.shield")
                    .font(.callout)
            }
            .buttonStyle(.borderless)
            .disabled(!appState.anyActive)
            Spacer()
            if let hotkey = appState.disconnectAllHotkey {
                Text(hotkey.display)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var missingConfig: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No profiles configured")
                .font(.headline)
            Text("Create \(ConfigLoader.configURL.path) and reload.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Create example config") {
                container.createExampleConfig()
            }
        }
    }

    private func brokenConfig(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Config error", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Button("Refresh") {
                container.refreshNow()
            }
            Button("Edit config") {
                NSWorkspace.shared.open(ConfigLoader.configURL)
            }
            Button("Reload") {
                container.reload()
            }
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }
}

/// Sección de un provider: cabecera + una fila clicable por perfil.
private struct ProviderGroupView: View {
    @Environment(AppContainer.self) private var container
    @Environment(AppState.self) private var appState
    let group: ProviderGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: group.systemImage)
                    .frame(width: 16)
                Text(group.displayName)
                    .font(.headline)
            }
            ForEach(group.profiles) { profile in
                ProfileRow(
                    profile: profile,
                    status: appState.status(for: profile.id),
                    action: { container.activate(profile) }
                )
            }
        }
    }
}

/// Fila de perfil: marca de estado + nombre. Clic = activar.
private struct ProfileRow: View {
    let profile: Profile
    let status: ProfileStatus
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                statusMark
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.name)
                        .font(.callout)
                    if case .failed(let message) = status {
                        Text(message)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                    }
                }
                Spacer()
                if let hotkey = profile.hotkey {
                    Text(hotkey.display)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(hovering ? Color.primary.opacity(0.08) : .clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(status == .switching)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var statusMark: some View {
        switch status {
        case .active:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .switching:
            ProgressView()
                .controlSize(.small)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .inactive:
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
        case .unknown:
            Image(systemName: "circle.dotted")
                .foregroundStyle(.tertiary)
        }
    }
}
