import SwiftUI

/// Icono de la barra de menús: escudo relleno si hay alguna VPN activa.
///
/// OJO: nada de TimelineView aquí — el host de la etiqueta de MenuBarExtra
/// re-arma el timeline en un bucle de invalidación infinito (ver Pocket).
struct MenuBarLabel: View {
    let appState: AppState

    var body: some View {
        Image(systemName: appState.anyActive ? "lock.shield.fill" : "lock.shield")
    }
}
