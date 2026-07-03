import Foundation

enum DependencyResolver {
    static func report(settings: AppSettings) -> DependencyReport {
        let ffmpegPath = resolveBinary(preferred: settings.ffmpegPath, names: ["ffmpeg"])
        let whisperPath = resolveBinary(preferred: settings.whisperPath, names: ["whisper-cli", "whisper-cpp", "main"])
        let modelURL = URL(fileURLWithPath: settings.modelPath.expandingTilde)

        let modelState: DependencyState
        if FileManager.default.fileExists(atPath: modelURL.path) {
            modelState = isModelComplete(at: modelURL)
                ? .ready(modelURL.path)
                : .missing("Modelio failas nebaigtas arba per mažas: \(modelURL.path)")
        } else {
            modelState = .missing("Modelio failas nerastas: \(modelURL.path)")
        }

        return DependencyReport(
            ffmpeg: ffmpegPath.map { .ready($0) } ?? .missing("ffmpeg nerastas"),
            whisper: whisperPath.map { .ready($0) } ?? .missing("Whisper variklis nerastas"),
            model: modelState
        )
    }

    static func resolveBinary(preferred: String, names: [String]) -> String? {
        if preferred != "auto" {
            let expanded = preferred.expandingTilde
            if FileManager.default.isExecutableFile(atPath: expanded) {
                return expanded
            }
            return nil
        }

        let directories = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/opt/local/bin"
        ]

        for directory in directories {
            for name in names {
                let candidate = "\(directory)/\(name)"
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }

        return nil
    }

    static func isModelComplete(at url: URL) -> Bool {
        guard
            let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
            let fileSize = values.fileSize
        else {
            return false
        }

        if url.lastPathComponent == "ggml-large-v3.bin" {
            return fileSize >= 3_000_000_000
        }

        return fileSize > 1_000_000
    }
}

extension String {
    var expandingTilde: String {
        (self as NSString).expandingTildeInPath
    }
}
