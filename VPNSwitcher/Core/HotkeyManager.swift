import Carbon.HIToolbox
import Foundation

/// Registra atajos globales del sistema con la API de Carbon
/// (RegisterEventHotKey): sin dependencias y sin pedir permisos de
/// Accesibilidad, a diferencia de los monitores de NSEvent.
@MainActor
final class HotkeyManager {
    private var handlerRef: EventHandlerRef?
    private var registered: [UInt32: (ref: EventHotKeyRef, action: () -> Void)] = [:]
    private var nextID: UInt32 = 1

    /// Devuelve false si el sistema rechaza el registro (típicamente:
    /// otra app ya posee ese atajo).
    @discardableResult
    func register(_ hotkey: Hotkey, action: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: nextID)
        let status = RegisterEventHotKey(
            hotkey.keyCode, hotkey.carbonModifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else { return false }
        registered[nextID] = (ref, action)
        nextID += 1
        return true
    }

    /// Al recargar la config se re-registra todo desde cero.
    func unregisterAll() {
        for (_, entry) in registered {
            UnregisterEventHotKey(entry.ref)
        }
        registered = [:]
    }

    private func handle(id: UInt32) {
        registered[id]?.action()
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // El handler de Carbon despacha en el hilo principal de la app;
        // assumeIsolated documenta (y comprueba) esa garantía.
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated {
                    manager.handle(id: hotKeyID.id)
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }

    /// "VPNS" como OSType.
    private static let signature: OSType = {
        var value: OSType = 0
        for byte in "VPNS".utf8 {
            value = value << 8 | OSType(byte)
        }
        return value
    }()
}
