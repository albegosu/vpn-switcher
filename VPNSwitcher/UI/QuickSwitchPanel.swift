import AppKit
import SwiftUI

/// Panel flotante de cambio rápido (estilo Spotlight/1Password): se invoca
/// con el atajo global `quick_switch_hotkey`, se escribe para filtrar,
/// flechas para moverse, Enter activa y Esc cierra.
@MainActor
final class QuickSwitchController {
    private var panel: NSPanel?
    private var resignObserver: (any NSObjectProtocol)?

    func toggle(appState: AppState, onActivate: @escaping (Profile) -> Void) {
        if let panel, panel.isVisible {
            hide()
        } else {
            show(appState: appState, onActivate: onActivate)
        }
    }

    func hide() {
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        resignObserver = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func show(appState: AppState, onActivate: @escaping (Profile) -> Void) {
        hide()

        let view = QuickSwitchView(
            appState: appState,
            onActivate: { [weak self] profile in
                self?.hide()
                onActivate(profile)
            },
            onClose: { [weak self] in self?.hide() }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame.size = hosting.fittingSize

        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            // nonactivatingPanel: recibe teclado sin activar la app entera,
            // igual que Quick Access de 1Password o Spotlight.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        position(panel)

        self.panel = panel
        // Clic fuera del panel = perder key = cerrarse, como Spotlight.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
        // Una app LSUIElement no está activa: sin activarla, el panel es key
        // pero el campo de texto no recibe el teclado. Activar la app = poder
        // escribir de inmediato (como Quick Access de 1Password). Al cerrar el
        // panel, macOS devuelve el foco a la app anterior por sí solo.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Centrado horizontal, en el tercio superior de la pantalla.
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + frame.height * 0.7 - size.height / 2
        ))
    }
}

/// Un panel borderless no puede ser key por defecto; sin esto el TextField
/// no recibiría el teclado.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}

private struct QuickSwitchView: View {
    let appState: AppState
    let onActivate: (Profile) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var searchFocused: Bool

    private var filtered: [Profile] {
        let all = appState.groups.flatMap(\.profiles)
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.provider.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Switch VPN…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($searchFocused)
                    .onSubmit(activateSelected)
                    .onKeyPress(.downArrow) {
                        move(1)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        move(-1)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        onClose()
                        return .handled
                    }
            }
            .padding(12)

            Divider()

            if filtered.isEmpty {
                Text("No matching profiles")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, profile in
                                QuickSwitchRow(
                                    profile: profile,
                                    status: appState.status(for: profile.id),
                                    isSelected: index == selection
                                )
                                .id(profile.id)
                                .onTapGesture { onActivate(profile) }
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 280)
                    .onChange(of: selection) { _, newValue in
                        if filtered.indices.contains(newValue) {
                            proxy.scrollTo(filtered[newValue].id)
                        }
                    }
                }
            }
        }
        .frame(width: 380)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .onAppear {
            // Enfocar el buscador en el siguiente ciclo, cuando la ventana ya
            // es key: así escribir tras ⌃⌥V va directo al input, sin clic.
            DispatchQueue.main.async { searchFocused = true }
        }
        .onChange(of: query) { _, _ in selection = 0 }
    }

    private func move(_ delta: Int) {
        let count = filtered.count
        guard count > 0 else { return }
        selection = (selection + delta + count) % count
    }

    private func activateSelected() {
        guard filtered.indices.contains(selection) else { return }
        onActivate(filtered[selection])
    }
}

private struct QuickSwitchRow: View {
    let profile: Profile
    let status: ProfileStatus
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            statusMark
                .frame(width: 16)
            Text(profile.name)
                .font(.callout)
            Spacer()
            Text(ProviderGroup.grouping([profile]).first?.displayName ?? profile.provider)
                .font(.caption)
                .foregroundStyle(isSelected ? .white.opacity(0.8) : Color.secondary)
        }
        .foregroundStyle(isSelected ? .white : Color.primary)
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : .clear)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var statusMark: some View {
        switch status {
        case .active:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(isSelected ? .white : Color.green)
        case .switching:
            ProgressView()
                .controlSize(.small)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .inactive:
            Image(systemName: "circle")
                .foregroundStyle(isSelected ? .white.opacity(0.6) : Color.secondary)
        case .unknown:
            Image(systemName: "circle.dotted")
                .foregroundStyle(isSelected ? .white.opacity(0.6) : Color.secondary)
        }
    }
}
