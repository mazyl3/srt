import Foundation

struct SubtitlePipeline {
    let runner: ProcessRunner

    func run(
        inputFile: URL,
        settings: AppSettings,
        updatePhase: @escaping @MainActor (JobPhase, Double) -> Void,
        log: @escaping @MainActor (LogEntry.LogLevel, String) -> Void,
        cancellation: @escaping () -> Bool
    ) async throws -> PipelineResult {
        await updatePhase(.validating, 0.05)
        await log(.info, "Tikrinamas pasirinktas failas, įrankiai ir modelis.")

        guard FileManager.default.fileExists(atPath: inputFile.path) else {
            throw PipelineError.noInputFile
        }

        let report = DependencyResolver.report(settings: settings)
        guard case .ready(let ffmpegPath) = report.ffmpeg else {
            throw PipelineError.missingDependency("ffmpeg")
        }
        guard case .ready(let whisperPath) = report.whisper else {
            throw PipelineError.missingDependency("whisper.cpp")
        }
        guard case .ready(let modelPath) = report.model else {
            throw PipelineError.missingDependency("Whisper large-v3 modelis")
        }

        if cancellation() {
            throw PipelineError.cancelled
        }

        try FileManager.default.createDirectory(at: AppPaths.jobsDirectory, withIntermediateDirectories: true)

        let jobDirectory = AppPaths.jobsDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: jobDirectory, withIntermediateDirectories: true)

        let safeInput = jobDirectory.appendingPathComponent(inputFile.lastPathComponent)
        let preparedAudio = jobDirectory.appendingPathComponent("prepared-16khz-mono.wav")

        let outputDirectory = settings.outputFolder ?? inputFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let outputBase = outputDirectory
            .appendingPathComponent(inputFile.deletingPathExtension().lastPathComponent)
        let wantsLithuanian = settings.subtitleOutputMode != .englishOnly
        let wantsEnglish = settings.subtitleOutputMode != .lithuanianOnly
        let sourceLanguage = settings.autoDetectLanguage ? "auto" : settings.languageCode
        let lithuanianOutputBase = wantsEnglish ? outputBase.appendingPathExtension("lt") : outputBase
        let lithuanianSRT = lithuanianOutputBase.appendingPathExtension("srt")
        let englishOutputBase = outputBase.appendingPathExtension("en")
        let englishSRT = englishOutputBase.appendingPathExtension("srt")
        let burnedVideo = outputBase.appendingPathExtension("subtitled").appendingPathExtension("mp4")

        for url in [lithuanianSRT, englishSRT, burnedVideo] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        await updatePhase(.copying, 0.15)
        await log(.info, "Originalas nebus keičiamas. Kuriama saugi darbo kopija.")
        if FileManager.default.fileExists(atPath: safeInput.path) {
            try FileManager.default.removeItem(at: safeInput)
        }
        try FileManager.default.copyItem(at: inputFile, to: safeInput)

        if cancellation() {
            throw PipelineError.cancelled
        }

        await updatePhase(.converting, 0.32)
        await log(.info, "Garsas konvertuojamas į 16 kHz mono WAV formatą, kurį stabiliai skaito Whisper.")
        try await runner.run(
            executable: ffmpegPath,
            arguments: [
                "-y",
                "-i", safeInput.path,
                "-map", "0:a:0",
                "-vn",
                "-ar", "16000",
                "-ac", "1",
                "-c:a", "pcm_s16le",
                "-bitexact",
                "-f", "wav",
                preparedAudio.path
            ],
            log: log,
            cancellation: cancellation
        )

        guard Self.fileSize(at: preparedAudio) > 1_000 else {
            throw PipelineError.commandFailed("Paruoštas WAV failas tuščias arba sugadintas: \(preparedAudio.path)")
        }

        if cancellation() {
            throw PipelineError.cancelled
        }

        if wantsLithuanian {
            await updatePhase(.transcribing, 0.58)
            await log(.info, "Paleidžiamas Whisper lietuviškam SRT. Šis etapas gali užtrukti, ypač su large-v3 modeliu.")

            try await Self.runWhisper(
                runner: runner,
                whisperPath: whisperPath,
                modelPath: modelPath,
                preparedAudio: preparedAudio,
                outputBase: lithuanianOutputBase,
                settings: settings,
                translateToEnglish: false,
                languageCode: sourceLanguage,
                expectedSRT: lithuanianSRT,
                updatePhase: updatePhase,
                log: log,
                cancellation: cancellation,
                progressStart: 0.58,
                progressSpan: wantsEnglish ? 0.20 : 0.32
            )

            guard FileManager.default.fileExists(atPath: lithuanianSRT.path) else {
                throw PipelineError.commandFailed("Whisper baigė darbą, bet lietuviškas SRT failas nerastas: \(lithuanianSRT.path)")
            }
            let report = try Self.cleanSRT(at: lithuanianSRT, settings: settings)
            await Self.logQualityReport(report, fileName: lithuanianSRT.lastPathComponent, log: log)
            await log(.success, "Lietuviškas SRT sukurtas: \(lithuanianSRT.path)")
        }

        if wantsEnglish {
            if cancellation() {
                throw PipelineError.cancelled
            }

            await updatePhase(.transcribing, wantsLithuanian ? 0.80 : 0.58)
            await log(.info, wantsLithuanian ? "Kuriamas papildomas angliškas SRT vertimas." : "Kuriamas angliškas SRT vertimas.")

            try await Self.runWhisper(
                runner: runner,
                whisperPath: whisperPath,
                modelPath: modelPath,
                preparedAudio: preparedAudio,
                outputBase: englishOutputBase,
                settings: settings,
                translateToEnglish: true,
                languageCode: sourceLanguage,
                expectedSRT: englishSRT,
                updatePhase: updatePhase,
                log: log,
                cancellation: cancellation,
                progressStart: wantsLithuanian ? 0.80 : 0.58,
                progressSpan: wantsLithuanian ? 0.10 : 0.32
            )

            guard FileManager.default.fileExists(atPath: englishSRT.path) else {
                throw PipelineError.commandFailed("Whisper baigė vertimą, bet angliškas SRT failas nerastas: \(englishSRT.path)")
            }
            let report = try Self.cleanSRT(at: englishSRT, settings: settings)
            await Self.logQualityReport(report, fileName: englishSRT.lastPathComponent, log: log)
            await log(.success, "Angliškas SRT sukurtas: \(englishSRT.path)")
        }

        await updatePhase(.finishing, 0.92)

        var createdSRTs = [lithuanianSRT, englishSRT].filter { FileManager.default.fileExists(atPath: $0.path) }
        let subtitleForVideo = wantsLithuanian && FileManager.default.fileExists(atPath: lithuanianSRT.path)
            ? lithuanianSRT
            : englishSRT
        var createdVideo: URL?

        if settings.videoExportMode != .srtOnly {
            guard FileManager.default.fileExists(atPath: subtitleForVideo.path) else {
                throw PipelineError.commandFailed("Video eksportui nerastas SRT failas: \(subtitleForVideo.path)")
            }

            if cancellation() {
                throw PipelineError.cancelled
            }

            await updatePhase(.renderingVideo, 0.94)
            await log(.info, "Kuriama nauja MP4 kopija su vidiniu subtitle track. Originalus video nebus keičiamas.")
            try await Self.createVideoWithSubtitleTrack(
                runner: runner,
                ffmpegPath: ffmpegPath,
                inputVideo: safeInput,
                subtitleFile: subtitleForVideo,
                outputVideo: burnedVideo,
                languageCode: settings.languageCode,
                log: log,
                cancellation: cancellation
            )
            createdVideo = burnedVideo
            await log(.success, "MP4 su subtitle track sukurtas: \(burnedVideo.path)")

            if settings.videoExportMode == .videoOnly {
                for srt in createdSRTs {
                    try? FileManager.default.removeItem(at: srt)
                }
                createdSRTs.removeAll()
                await log(.info, "Pasirinktas tik video eksportas, todėl tarpinis SRT failas pašalintas.")
            }
        }

        if !settings.keepWorkingFiles {
            try? FileManager.default.removeItem(at: jobDirectory)
        } else {
            await log(.info, "Darbiniai failai palikti: \(jobDirectory.path)")
        }

        await updatePhase(.complete, 1.0)
        if createdVideo != nil && settings.videoExportMode == .videoOnly {
            await log(.success, "MP4 eksportas baigtas: \(burnedVideo.lastPathComponent)")
        } else if createdVideo != nil {
            await log(.success, "SRT ir MP4 eksportas baigtas: \(burnedVideo.lastPathComponent)")
        } else if wantsLithuanian && wantsEnglish {
            await log(.success, "SRT pora sukurta: \(lithuanianSRT.lastPathComponent) ir \(englishSRT.lastPathComponent)")
        } else if wantsEnglish {
            await log(.success, "Angliškas SRT failas sukurtas: \(englishSRT.path)")
        } else {
            await log(.success, "SRT failas sukurtas: \(lithuanianSRT.path)")
        }

        let visibleSRTs = createdSRTs
        let primary = createdVideo ?? (wantsLithuanian ? lithuanianSRT : englishSRT)
        return PipelineResult(primaryFile: primary, srtFiles: visibleSRTs, videoFile: createdVideo)
    }

    private static func createVideoWithSubtitleTrack(
        runner: ProcessRunner,
        ffmpegPath: String,
        inputVideo: URL,
        subtitleFile: URL,
        outputVideo: URL,
        languageCode: String,
        log: @escaping @MainActor (LogEntry.LogLevel, String) -> Void,
        cancellation: @escaping () -> Bool
    ) async throws {
        try await runner.run(
            executable: ffmpegPath,
            arguments: [
                "-y",
                "-i", inputVideo.path,
                "-i", subtitleFile.path,
                "-map", "0:v:0",
                "-map", "0:a?",
                "-map", "1:0",
                "-c:v", "copy",
                "-c:a", "copy",
                "-c:s", "mov_text",
                "-metadata:s:s:0", "language=\(subtitleLanguageCode(languageCode))",
                "-movflags", "+faststart",
                outputVideo.path
            ],
            log: log,
            cancellation: cancellation
        )

        guard FileManager.default.fileExists(atPath: outputVideo.path),
              fileSize(at: outputVideo) > 10_000 else {
            throw PipelineError.commandFailed("MP4 su subtitrais nebuvo sukurtas arba yra per mažas: \(outputVideo.path)")
        }
    }

    private static func subtitleLanguageCode(_ languageCode: String) -> String {
        switch languageCode.lowercased() {
        case "lt":
            return "lit"
        case "en":
            return "eng"
        case "de":
            return "deu"
        case "es":
            return "spa"
        case "pl":
            return "pol"
        case "ru":
            return "rus"
        default:
            return languageCode
        }
    }

    private static func runWhisper(
        runner: ProcessRunner,
        whisperPath: String,
        modelPath: String,
        preparedAudio: URL,
        outputBase: URL,
        settings: AppSettings,
        translateToEnglish: Bool,
        languageCode: String,
        expectedSRT: URL,
        updatePhase: @escaping @MainActor (JobPhase, Double) -> Void,
        log: @escaping @MainActor (LogEntry.LogLevel, String) -> Void,
        cancellation: @escaping () -> Bool,
        progressStart: Double,
        progressSpan: Double
    ) async throws {
        var whisperArguments = Self.whisperArguments(
            modelPath: modelPath,
            preparedAudio: preparedAudio,
            outputBase: outputBase,
            settings: settings,
            forceCPU: false,
            translateToEnglish: translateToEnglish,
            languageCode: languageCode
        )

        do {
            try await runner.run(
                executable: whisperPath,
                arguments: whisperArguments,
                log: log,
                cancellation: cancellation,
                output: { text in
                    if let percent = Self.parseWhisperProgress(from: text) {
                        updatePhase(.transcribing, progressStart + (percent * progressSpan))
                    }
                }
            )
        } catch PipelineError.commandFailed(let message)
            where settings.useGPU && message.contains("Exit code: 139") {
            await log(.warning, "Whisper GPU/Metal režimas nulūžo. Programa automatiškai bando dar kartą CPU režimu.")
            if FileManager.default.fileExists(atPath: expectedSRT.path) {
                try? FileManager.default.removeItem(at: expectedSRT)
            }
            whisperArguments = Self.whisperArguments(
                modelPath: modelPath,
                preparedAudio: preparedAudio,
                outputBase: outputBase,
                settings: settings,
                forceCPU: true,
                translateToEnglish: translateToEnglish,
                languageCode: languageCode
            )

            try await runner.run(
                executable: whisperPath,
                arguments: whisperArguments,
                log: log,
                cancellation: cancellation,
                output: { text in
                    if let percent = Self.parseWhisperProgress(from: text) {
                        updatePhase(.transcribing, progressStart + (percent * progressSpan))
                    }
                }
            )
        }
    }

    private static func whisperArguments(
        modelPath: String,
        preparedAudio: URL,
        outputBase: URL,
        settings: AppSettings,
        forceCPU: Bool,
        translateToEnglish: Bool,
        languageCode: String
    ) -> [String] {
        var arguments = [
            "-m", modelPath,
            "-f", preparedAudio.path,
            "-osrt",
            "-pp",
            "-of", outputBase.path,
            "-t", "\(settings.threadCount)",
            "-l", languageCode,
            "-ml", "\(settings.maxSegmentLength)",
            "-bo", "\(settings.bestOf)",
            "-bs", "\(settings.beamSize)",
            "-nth", String(format: "%.2f", settings.noSpeechThreshold)
        ]

        if settings.splitOnWord {
            arguments.append("-sow")
        }

        if settings.suppressNonSpeechTokens {
            arguments.append("-sns")
        }

        if forceCPU || !settings.useGPU {
            arguments.append("-ng")
        }

        if translateToEnglish {
            arguments.append("-tr")
        }

        return arguments
    }

    private static func parseWhisperProgress(from text: String) -> Double? {
        let pattern = #"(\d{1,3})%"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
            let range = Range(match.range(at: 1), in: text),
            let value = Double(text[range])
        else {
            return nil
        }

        return min(max(value / 100.0, 0.0), 1.0)
    }

    private static func cleanSRT(at url: URL, settings: AppSettings) throws -> SubtitleQualityReport {
        let content = try String(contentsOf: url, encoding: .utf8)
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var report = SubtitleQualityReport()
        let blocks = normalized
            .components(separatedBy: "\n\n")
            .compactMap { parseSRTBlock($0, settings: settings, report: &report) }

        let splitBlocks = splitBlocksByLineLimit(blocks, settings: settings, report: &report)
        let repaired = repairSubtitleTiming(splitBlocks, settings: settings, report: &report)
        let cleaned = repaired
            .enumerated()
            .map { index, block in
                renderSRTBlock(block, number: index + 1)
            }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"

        try cleaned.write(to: url, atomically: true, encoding: .utf8)
        report.blocks = repaired.count
        return report
    }

    private static func parseSRTBlock(_ block: String, settings: AppSettings, report: inout SubtitleQualityReport) -> SubtitleBlock? {
        let rawLines = block
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard let timeIndex = rawLines.firstIndex(where: { $0.contains("-->") }) else {
            report.droppedBlocks += 1
            return nil
        }

        let timing = rawLines[timeIndex]
        let timingParts = timing.components(separatedBy: "-->")
        guard timingParts.count == 2,
              let start = parseSRTTimestamp(timingParts[0]),
              let end = parseSRTTimestamp(timingParts[1]) else {
            report.droppedBlocks += 1
            return nil
        }

        let textLines = Array(rawLines.dropFirst(timeIndex + 1))
        var cleanedText = cleanSubtitleTextLines(textLines, settings: settings)
        cleanedText = wrapSubtitleLines(cleanedText, settings: settings, report: &report)

        guard !cleanedText.isEmpty else {
            report.droppedBlocks += 1
            return nil
        }

        return SubtitleBlock(start: start, end: max(end, start), lines: cleanedText)
    }

    private static func cleanSubtitleTextLines(_ lines: [String], settings: AppSettings) -> [String] {
        let trimmed = lines
            .map(normalizeTextSpacing)
            .filter { !$0.isEmpty }

        let dialogueAware = settings.formatDialogueLines
            ? trimmed.flatMap(splitDialogueLine)
            : trimmed

        let hasDialogue = dialogueAware.contains { isDialogueLine($0) }

        return dialogueAware.map { line in
            var value = normalizeTextSpacing(line)
            if settings.formatDialogueLines {
                value = normalizeDialogueDash(value)
            }
            if hasDialogue, !isDialogueLine(value), dialogueAware.count > 1 {
                value = "- \(value)"
            }
            if settings.normalizePunctuation {
                value = ensureTerminalPunctuation(value)
            }
            return value
        }
    }

    private static func normalizeTextSpacing(_ line: String) -> String {
        var value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(of: #"[\t ]+"#, with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\s+([,.;:!?])"#, with: "$1", options: .regularExpression)
        value = value.replacingOccurrences(of: #"([¿¡])\s+"#, with: "$1", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\s+([)\]»”])"#, with: "$1", options: .regularExpression)
        value = value.replacingOccurrences(of: #"([(\[«“])\s+"#, with: "$1", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func splitDialogueLine(_ line: String) -> [String] {
        let normalized = normalizeDialogueDash(line)
        if isDialogueLine(normalized) {
            let body = String(normalized.dropFirst()).trimmingCharacters(in: .whitespaces)
            let parts = body.components(separatedBy: " - ")
            if parts.count > 1 {
                return parts.map { "- \(normalizeTextSpacing($0))" }.filter { $0 != "- " }
            }
            return [normalized]
        }

        let dialogueSeparators = [" — ", " – ", " - "]
        for separator in dialogueSeparators where normalized.contains(separator) {
            let parts = normalized.components(separatedBy: separator)
                .map(normalizeTextSpacing)
                .filter { !$0.isEmpty }
            if parts.count > 1 {
                return parts.map { "- \($0)" }
            }
        }

        return [normalized]
    }

    private static func normalizeDialogueDash(_ line: String) -> String {
        var value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("–") || value.hasPrefix("—") {
            value.removeFirst()
            return "- \(normalizeTextSpacing(value))"
        }
        if value.hasPrefix("-") {
            value.removeFirst()
            return "- \(normalizeTextSpacing(value))"
        }
        return value
    }

    private static func isDialogueLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("- ")
    }

    private static func ensureTerminalPunctuation(_ line: String) -> String {
        var value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return value }

        let closingCharacters = CharacterSet(charactersIn: "\"'”’»)]}")
        let terminalCharacters = CharacterSet(charactersIn: ".!?…:;")

        for scalar in value.unicodeScalars.reversed() {
            if closingCharacters.contains(scalar) {
                continue
            }
            if terminalCharacters.contains(scalar) {
                return value
            }
            break
        }

        value.append(".")
        return value
    }

    private static func wrapSubtitleLines(_ lines: [String], settings: AppSettings, report: inout SubtitleQualityReport) -> [String] {
        let maxLength = max(16, settings.maxSubtitleLineLength)
        let maxLines = max(1, settings.maxSubtitleLines)
        let normalizedLines = lines.map(normalizeTextSpacing).filter { !$0.isEmpty }

        if normalizedLines.count > maxLines {
            report.lineWraps += 1
        }

        let dialogueLines = normalizedLines.filter(isDialogueLine)
        if !dialogueLines.isEmpty {
            let wrappedDialogue = dialogueLines.flatMap { line in
                wrapSingleLine(line, maxLength: maxLength)
            }
            if wrappedDialogue.count > maxLines {
                report.longLineWarnings += 1
            }
            return wrappedDialogue
        }

        let text = normalizedLines.joined(separator: " ")
        let wrapped = wrapSingleLine(text, maxLength: maxLength)
        if wrapped.count != normalizedLines.count || wrapped.contains(where: { $0.count > maxLength }) {
            report.lineWraps += 1
        }
        if wrapped.count > maxLines {
            report.longLineWarnings += 1
        }
        return wrapped
    }

    private static func wrapSingleLine(_ line: String, maxLength: Int) -> [String] {
        let prefix = isDialogueLine(line) ? "- " : ""
        let body = prefix.isEmpty ? line : String(line.dropFirst(2))
        let words = body.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }

        var lines: [String] = []
        var current = prefix

        for word in words {
            let candidate = current == prefix ? current + word : current + " " + word
            if candidate.count <= maxLength || current == prefix {
                current = candidate
            } else {
                lines.append(current)
                current = prefix + word
            }
        }

        if current != prefix {
            lines.append(current)
        }

        return lines
    }

    private static func splitBlocksByLineLimit(_ blocks: [SubtitleBlock], settings: AppSettings, report: inout SubtitleQualityReport) -> [SubtitleBlock] {
        let maxLines = max(1, settings.maxSubtitleLines)
        var result: [SubtitleBlock] = []

        for block in blocks {
            guard block.lines.count > maxLines else {
                result.append(block)
                continue
            }

            let chunks = stride(from: 0, to: block.lines.count, by: maxLines).map { startIndex in
                Array(block.lines[startIndex..<min(startIndex + maxLines, block.lines.count)])
            }
            let duration = max(0.1, block.end - block.start)
            let chunkDuration = duration / Double(chunks.count)

            for (index, lines) in chunks.enumerated() {
                let start = block.start + (Double(index) * chunkDuration)
                let end = index == chunks.count - 1 ? block.end : start + chunkDuration
                result.append(SubtitleBlock(start: start, end: end, lines: lines))
            }

            report.blockSplits += max(0, chunks.count - 1)
        }

        return result
    }

    private static func repairSubtitleTiming(_ blocks: [SubtitleBlock], settings: AppSettings, report: inout SubtitleQualityReport) -> [SubtitleBlock] {
        let sorted = blocks.sorted { $0.start < $1.start }
        var repaired: [SubtitleBlock] = []
        let minGap = max(0.02, settings.minimumSubtitleGap)
        let minDuration = max(0.20, settings.minimumSubtitleDuration)
        let maxDuration = max(minDuration, settings.maximumSubtitleDuration)

        for block in sorted {
            var current = block
            if let previous = repaired.last {
                let minimumStart = previous.end + minGap
                if current.start < minimumStart {
                    report.overlapFixes += 1
                    current.start = minimumStart
                }
            }

            if current.end <= current.start {
                report.durationFixes += 1
                current.end = current.start + minDuration
            }

            let duration = current.end - current.start
            if duration < minDuration {
                report.durationFixes += 1
                current.end = current.start + minDuration
            } else if duration > maxDuration {
                report.durationFixes += 1
                current.end = current.start + maxDuration
            }

            let cps = charactersPerSecond(current)
            if cps > settings.maxCharactersPerSecond {
                report.cpsWarnings += 1
                let desiredDuration = min(maxDuration, Double(current.characterCount) / max(1, settings.maxCharactersPerSecond))
                if desiredDuration > current.end - current.start {
                    current.end = current.start + desiredDuration
                    report.durationFixes += 1
                }
            }

            if let previous = repaired.last,
               previous.end + minGap > current.start {
                current.start = previous.end + minGap
                current.end = max(current.end, current.start + minDuration)
                report.overlapFixes += 1
            }

            repaired.append(current)
        }

        return repaired
    }

    private static func charactersPerSecond(_ block: SubtitleBlock) -> Double {
        let duration = max(0.1, block.end - block.start)
        return Double(block.characterCount) / duration
    }

    private static func renderSRTBlock(_ block: SubtitleBlock, number: Int) -> String {
        ([String(number), "\(formatSRTTimestamp(block.start)) --> \(formatSRTTimestamp(block.end))"] + block.lines)
            .joined(separator: "\n")
    }

    private static func parseSRTTimestamp(_ raw: String) -> Double? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"(\d{2}):(\d{2}):(\d{2}),(\d{3})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.numberOfRanges == 5 else {
            return nil
        }

        func int(_ index: Int) -> Int? {
            guard let range = Range(match.range(at: index), in: value) else { return nil }
            return Int(value[range])
        }

        guard let hours = int(1),
              let minutes = int(2),
              let seconds = int(3),
              let milliseconds = int(4) else {
            return nil
        }

        return Double(hours * 3600 + minutes * 60 + seconds) + Double(milliseconds) / 1000.0
    }

    private static func formatSRTTimestamp(_ value: Double) -> String {
        let totalMilliseconds = max(0, Int((value * 1000.0).rounded()))
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds % 3_600_000) / 60_000
        let seconds = (totalMilliseconds % 60_000) / 1000
        let milliseconds = totalMilliseconds % 1000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }

    @MainActor
    private static func logQualityReport(
        _ report: SubtitleQualityReport,
        fileName: String,
        log: @escaping @MainActor (LogEntry.LogLevel, String) -> Void
    ) async {
        let summary = "SRT kokybės patikra \(fileName): \(report.blocks) blokai, \(report.blockSplits) blokų skaidymų, \(report.overlapFixes) laiko persidengimų pataisyta, \(report.durationFixes) trukmių pataisyta, \(report.lineWraps) eilučių pervyniota, \(report.cpsWarnings) per greitų subtitrų įspėjimai."
        log(report.hasWarnings ? .warning : .success, summary)

        if report.droppedBlocks > 0 {
            log(.warning, "Pašalinta netinkamų SRT blokų: \(report.droppedBlocks).")
        }
        if report.longLineWarnings > 0 {
            log(.warning, "Yra subtitrų, kuriuos reikėjo skaidyti dėl eilučių ribų: \(report.longLineWarnings).")
        }
    }

    private static func fileSize(at url: URL) -> Int {
        ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize) ?? 0
    }
}

private struct SubtitleBlock {
    var start: Double
    var end: Double
    var lines: [String]

    var characterCount: Int {
        lines.joined(separator: " ").count
    }
}

private struct SubtitleQualityReport {
    var blocks = 0
    var droppedBlocks = 0
    var overlapFixes = 0
    var durationFixes = 0
    var lineWraps = 0
    var blockSplits = 0
    var longLineWarnings = 0
    var cpsWarnings = 0

    var hasWarnings: Bool {
        droppedBlocks > 0
            || overlapFixes > 0
            || durationFixes > 0
            || blockSplits > 0
            || longLineWarnings > 0
            || cpsWarnings > 0
    }
}
