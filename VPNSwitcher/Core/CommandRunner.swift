import Foundation

struct CommandResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool

    var succeeded: Bool { exitCode == 0 && !timedOut }

    /// Mensaje corto para la UI: stderr si lo hay, si no el código de salida.
    var failureMessage: String {
        if timedOut { return "timed out" }
        let err = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !err.isEmpty { return String(err.prefix(200)) }
        return "exit \(exitCode)"
    }
}

/// Ejecuta comandos de shell (los activate/deactivate/status de los perfiles).
/// Corre `/bin/sh -c` con el PATH de Homebrew por delante, porque una app
/// lanzada desde Finder no hereda el PATH del shell del usuario.
enum CommandRunner {
    static func run(_ command: String, timeout: TimeInterval) async -> CommandResult {
        await Task.detached(priority: .utility) {
            runSync(command, timeout: timeout)
        }.value
    }

    /// Process y Pipe no son Sendable; las cajas @unchecked acotan los dos
    /// únicos cruces de hilo reales: el watchdog del timeout y los lectores
    /// de pipes (leer en paralelo evita el deadlock del buffer de 64 KB).
    private final class ProcessBox: @unchecked Sendable {
        let process: Process
        private let lock = NSLock()
        private var terminatedByWatchdog = false

        init(_ process: Process) { self.process = process }

        func markTimedOut() {
            lock.lock()
            terminatedByWatchdog = true
            lock.unlock()
        }

        var timedOut: Bool {
            lock.lock()
            defer { lock.unlock() }
            return terminatedByWatchdog
        }
    }

    private final class PipeReader: @unchecked Sendable {
        private var data = Data()
        private let done = DispatchSemaphore(value: 0)

        init(_ pipe: Pipe) {
            let handle = pipe.fileHandleForReading
            DispatchQueue.global(qos: .utility).async { [self] in
                data = handle.readDataToEndOfFile()
                done.signal()
            }
        }

        func wait() -> String {
            done.wait()
            return String(data: data, encoding: .utf8) ?? ""
        }
    }

    private static func runSync(_ command: String, timeout: TimeInterval) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]

        var environment = ProcessInfo.processInfo.environment
        let basePath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + basePath
        process.environment = environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return CommandResult(
                exitCode: -1, stdout: "", stderr: error.localizedDescription, timedOut: false
            )
        }

        let outReader = PipeReader(outPipe)
        let errReader = PipeReader(errPipe)

        let box = ProcessBox(process)
        let watchdog = DispatchWorkItem {
            if box.process.isRunning {
                box.markTimedOut()
                box.process.terminate()
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + timeout, execute: watchdog
        )

        process.waitUntilExit()
        watchdog.cancel()

        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: outReader.wait(),
            stderr: errReader.wait(),
            timedOut: box.timedOut
        )
    }
}
