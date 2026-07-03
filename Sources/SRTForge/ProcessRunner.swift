import Foundation

final class ProcessRunner {
    private var currentProcess: Process?

    func run(
        executable: String,
        arguments: [String],
        log: @escaping @MainActor (LogEntry.LogLevel, String) -> Void,
        cancellation: @escaping () -> Bool,
        output: (@MainActor (String) async -> Void)? = nil
    ) async throws {
        if cancellation() {
            throw PipelineError.cancelled
        }

        await log(.command, ([executable] + arguments).joined(separator: " "))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let combinedOutput = Pipe()
        process.standardOutput = combinedOutput
        process.standardError = combinedOutput

        currentProcess = process

        try process.run()

        let readTask = Task {
            let handle = combinedOutput.fileHandleForReading
            while true {
                if cancellation() {
                    process.terminate()
                    break
                }

                let data = handle.availableData
                if data.isEmpty {
                    break
                }

                if let text = String(data: data, encoding: .utf8) {
                    await output?(text)

                    let lines = text
                        .replacingOccurrences(of: "\r", with: "\n")
                        .split(separator: "\n")
                        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }

                    for line in lines {
                        await log(.info, line)
                    }
                }
            }
        }

        process.waitUntilExit()
        _ = await readTask.result
        currentProcess = nil

        if cancellation() {
            throw PipelineError.cancelled
        }

        guard process.terminationStatus == 0 else {
            throw PipelineError.commandFailed("Komanda nepavyko. Exit code: \(process.terminationStatus)")
        }
    }

    func cancel() {
        currentProcess?.terminate()
    }
}
