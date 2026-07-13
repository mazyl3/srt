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
        let lithuanianTXT = lithuanianOutputBase.appendingPathExtension("txt")
        let lithuanianVTT = lithuanianOutputBase.appendingPathExtension("vtt")
        let lithuanianASS = lithuanianOutputBase.appendingPathExtension("ass")
        let englishOutputBase = outputBase.appendingPathExtension("en")
        let englishSRT = englishOutputBase.appendingPathExtension("srt")
        let englishTXT = englishOutputBase.appendingPathExtension("txt")
        let englishVTT = englishOutputBase.appendingPathExtension("vtt")
        let englishASS = englishOutputBase.appendingPathExtension("ass")
        let subtitleTrackVideo = outputBase.appendingPathExtension("subtitled").appendingPathExtension("mp4")
        let burnedInVideo = outputBase.appendingPathExtension("burned").appendingPathExtension("mp4")

        for url in [lithuanianSRT, lithuanianTXT, lithuanianVTT, lithuanianASS, englishSRT, englishTXT, englishVTT, englishASS, subtitleTrackVideo, burnedInVideo] where FileManager.default.fileExists(atPath: url.path) {
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
        let audioStreamCount = Self.audioStreamCount(inputFile: safeInput, ffmpegPath: ffmpegPath)
        let selectedAudioTrack = Self.selectedAudioTrack(
            inputFile: safeInput,
            ffmpegPath: ffmpegPath,
            settings: settings,
            audioStreamCount: audioStreamCount
        )
        let selectedAudioChannel = Self.selectedAudioChannel(
            inputFile: safeInput,
            ffmpegPath: ffmpegPath,
            settings: settings,
            audioStreamCount: audioStreamCount,
            selectedAudioTrack: selectedAudioTrack
        )
        let selectedTrackChannelCount = Self.audioChannelCount(
            inputFile: safeInput,
            ffmpegPath: ffmpegPath,
            audioTrackIndex: selectedAudioTrack ?? 0
        )
        let usesPolyWAVProfile = audioStreamCount == 1 && selectedTrackChannelCount > 1
        let effectiveNoSpeechThreshold = usesPolyWAVProfile
            ? max(settings.noSpeechThreshold, 0.75)
            : settings.noSpeechThreshold
        let sourceLabel = selectedAudioChannel.map { "Track \((selectedAudioTrack ?? 0) + 1), Ch \($0 + 1)" }
            ?? selectedAudioTrack.map { "Track \($0 + 1)" }
            ?? "mix"
        await log(.info, "Rasta audio trackų: \(audioStreamCount). Režimas: \(settings.audioInputMode.rawValue). Naudojamas šaltinis: \(sourceLabel).")
        if usesPolyWAVProfile {
            await log(
                .info,
                "PolyWAV režimas: aptikta \(selectedTrackChannelCount) kanalų viename WAV tracke. Whisper promptas išjungiamas, no-speech slenkstis: \(String(format: "%.2f", effectiveNoSpeechThreshold))."
            )
        }
        try await runner.run(
            executable: ffmpegPath,
            arguments: Self.audioPreparationArguments(
                inputFile: safeInput,
                outputFile: preparedAudio,
                settings: settings,
                audioStreamCount: audioStreamCount,
                selectedAudioTrack: selectedAudioTrack,
                selectedAudioChannel: selectedAudioChannel
            ),
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
                allowLanguagePrompt: !usesPolyWAVProfile,
                noSpeechThreshold: effectiveNoSpeechThreshold,
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
            try Self.writeTranscriptText(from: lithuanianSRT, to: lithuanianTXT)
            try Self.writeWebVTT(from: lithuanianSRT, to: lithuanianVTT)
            try Self.writeAdvancedSubStation(from: lithuanianSRT, to: lithuanianASS)
            await Self.logQualityReport(report, fileName: lithuanianSRT.lastPathComponent, log: log)
            await log(.success, "Lietuviškas SRT sukurtas: \(lithuanianSRT.path)")
            await log(.success, "Lietuviškas TXT transcript sukurtas: \(lithuanianTXT.path)")
            await log(.success, "Lietuviškas VTT sukurtas: \(lithuanianVTT.path)")
            await log(.success, "Lietuviškas ASS sukurtas: \(lithuanianASS.path)")
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
                allowLanguagePrompt: !usesPolyWAVProfile,
                noSpeechThreshold: effectiveNoSpeechThreshold,
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
            try Self.writeTranscriptText(from: englishSRT, to: englishTXT)
            try Self.writeWebVTT(from: englishSRT, to: englishVTT)
            try Self.writeAdvancedSubStation(from: englishSRT, to: englishASS)
            await Self.logQualityReport(report, fileName: englishSRT.lastPathComponent, log: log)
            await log(.success, "Angliškas SRT sukurtas: \(englishSRT.path)")
            await log(.success, "Angliškas TXT transcript sukurtas: \(englishTXT.path)")
            await log(.success, "Angliškas VTT sukurtas: \(englishVTT.path)")
            await log(.success, "Angliškas ASS sukurtas: \(englishASS.path)")
        }

        await updatePhase(.finishing, 0.92)

        var createdSRTs = [lithuanianSRT, englishSRT].filter { FileManager.default.fileExists(atPath: $0.path) }
        var createdTranscripts = [lithuanianTXT, englishTXT].filter { FileManager.default.fileExists(atPath: $0.path) }
        var createdVTTs = [lithuanianVTT, englishVTT].filter { FileManager.default.fileExists(atPath: $0.path) }
        var createdASSs = [lithuanianASS, englishASS].filter { FileManager.default.fileExists(atPath: $0.path) }
        let subtitleForVideo = wantsLithuanian && FileManager.default.fileExists(atPath: lithuanianSRT.path)
            ? lithuanianSRT
            : englishSRT
        var createdVideo: URL?

        if settings.videoExportMode.createsVideo {
            guard FileManager.default.fileExists(atPath: subtitleForVideo.path) else {
                throw PipelineError.commandFailed("Video eksportui nerastas SRT failas: \(subtitleForVideo.path)")
            }

            if cancellation() {
                throw PipelineError.cancelled
            }

            await updatePhase(.renderingVideo, 0.94)
            if settings.videoExportMode.burnsSubtitlesIntoVideo {
                await log(.info, "Kuriama nauja MP4 kopija su įkeptais subtitrais. Originalus video nebus keičiamas.")
                try await Self.createBurnedInSubtitleVideo(
                    runner: runner,
                    ffmpegPath: ffmpegPath,
                    inputVideo: safeInput,
                    subtitleFile: subtitleForVideo,
                    outputVideo: burnedInVideo,
                    style: settings.burnedSubtitleStyle,
                    log: log,
                    cancellation: cancellation
                )
                createdVideo = burnedInVideo
                await log(.success, "MP4 su įkeptais subtitrais sukurtas: \(burnedInVideo.path)")
            } else {
                await log(.info, "Kuriama nauja MP4 kopija su vidiniu subtitle track. Originalus video nebus keičiamas.")
                try await Self.createVideoWithSubtitleTrack(
                    runner: runner,
                    ffmpegPath: ffmpegPath,
                    inputVideo: safeInput,
                    subtitleFile: subtitleForVideo,
                    outputVideo: subtitleTrackVideo,
                    languageCode: settings.languageCode,
                    log: log,
                    cancellation: cancellation
                )
                createdVideo = subtitleTrackVideo
                await log(.success, "MP4 su subtitle track sukurtas: \(subtitleTrackVideo.path)")
            }

            if !settings.videoExportMode.keepsSRTOutput {
                for srt in createdSRTs {
                    try? FileManager.default.removeItem(at: srt)
                }
                for transcript in createdTranscripts {
                    try? FileManager.default.removeItem(at: transcript)
                }
                for vtt in createdVTTs {
                    try? FileManager.default.removeItem(at: vtt)
                }
                for ass in createdASSs {
                    try? FileManager.default.removeItem(at: ass)
                }
                createdSRTs.removeAll()
                createdTranscripts.removeAll()
                createdVTTs.removeAll()
                createdASSs.removeAll()
                await log(.info, "Pasirinktas tik video eksportas, todėl tarpiniai SRT/TXT/VTT/ASS failai pašalinti.")
            }
        }

        if !settings.keepWorkingFiles {
            try? FileManager.default.removeItem(at: jobDirectory)
        } else {
            await log(.info, "Darbiniai failai palikti: \(jobDirectory.path)")
        }

        await updatePhase(.complete, 1.0)
        if createdVideo != nil && settings.videoExportMode == .videoOnly {
            await log(.success, "MP4 eksportas baigtas: \(createdVideo?.lastPathComponent ?? "video.mp4")")
        } else if createdVideo != nil && settings.videoExportMode == .burnedVideoOnly {
            await log(.success, "Burned MP4 eksportas baigtas: \(createdVideo?.lastPathComponent ?? "video.mp4")")
        } else if createdVideo != nil {
            await log(.success, "SRT ir MP4 eksportas baigtas: \(createdVideo?.lastPathComponent ?? "video.mp4")")
        } else if wantsLithuanian && wantsEnglish {
            await log(.success, "SRT pora sukurta: \(lithuanianSRT.lastPathComponent) ir \(englishSRT.lastPathComponent)")
        } else if wantsEnglish {
            await log(.success, "Angliškas SRT failas sukurtas: \(englishSRT.path)")
        } else {
            await log(.success, "SRT failas sukurtas: \(lithuanianSRT.path)")
        }

        let visibleSRTs = createdSRTs
        let primary = createdVideo ?? (wantsLithuanian ? lithuanianSRT : englishSRT)
        return PipelineResult(primaryFile: primary, srtFiles: visibleSRTs, transcriptFiles: createdTranscripts, vttFiles: createdVTTs, assFiles: createdASSs, videoFile: createdVideo)
    }

    private static func audioPreparationArguments(
        inputFile: URL,
        outputFile: URL,
        settings: AppSettings,
        audioStreamCount: Int,
        selectedAudioTrack: Int?,
        selectedAudioChannel: Int?
    ) -> [String] {
        let filter = speechAudioFilter(settings: settings)
        let shouldMix = settings.audioInputMode == .mixAllTracks && audioStreamCount > 1

        if shouldMix {
            let inputs = (0..<audioStreamCount).map { "[0:a:\($0)]" }.joined()
            let filterComplex = "\(inputs)amix=inputs=\(audioStreamCount):duration=longest:normalize=1,\(filter)[outa]"
            return [
                "-y",
                "-i", inputFile.path,
                "-filter_complex", filterComplex,
                "-map", "[outa]",
                "-vn",
                "-ar", "16000",
                "-ac", "1",
                "-c:a", "pcm_s16le",
                "-f", "wav",
                outputFile.path
            ]
        }

        if let selectedAudioChannel {
            return [
                "-y",
                "-i", inputFile.path,
                "-map", "0:a:\(selectedAudioTrack ?? 0)",
                "-vn",
                "-af", "pan=mono|c0=c\(selectedAudioChannel),\(filter)",
                "-ar", "16000",
                "-ac", "1",
                "-c:a", "pcm_s16le",
                "-f", "wav",
                outputFile.path
            ]
        }

        return [
            "-y",
            "-i", inputFile.path,
            "-map", "0:a:\(selectedAudioTrack ?? 0)",
            "-vn",
            "-af", filter,
            "-ar", "16000",
            "-ac", "1",
            "-c:a", "pcm_s16le",
            "-f", "wav",
            outputFile.path
        ]
    }

    private static func selectedAudioTrack(
        inputFile: URL,
        ffmpegPath: String,
        settings: AppSettings,
        audioStreamCount: Int
    ) -> Int? {
        switch settings.audioInputMode {
        case .mixAllTracks:
            return nil
        case .firstTrack:
            return 0
        case .manualTrack:
            guard let manual = settings.manualAudioTrackPosition else { return 0 }
            return min(max(0, manual), max(0, audioStreamCount - 1))
        case .autoBestTrack:
            guard audioStreamCount > 1 else { return 0 }
            return bestAudioTrack(inputFile: inputFile, ffmpegPath: ffmpegPath, audioStreamCount: audioStreamCount) ?? 0
        }
    }

    private static func selectedAudioChannel(
        inputFile: URL,
        ffmpegPath: String,
        settings: AppSettings,
        audioStreamCount: Int,
        selectedAudioTrack: Int?
    ) -> Int? {
        guard settings.audioInputMode != .mixAllTracks else { return nil }
        let track = selectedAudioTrack ?? 0
        let channelCount = audioChannelCount(inputFile: inputFile, ffmpegPath: ffmpegPath, audioTrackIndex: track)
        guard channelCount > 1 else { return nil }

        if settings.audioInputMode == .manualTrack, let manualChannel = settings.manualAudioChannelIndex {
            return min(max(0, manualChannel), channelCount - 1)
        }

        if settings.audioInputMode == .autoBestTrack, audioStreamCount == 1 {
            return bestAudioChannel(inputFile: inputFile, ffmpegPath: ffmpegPath, channelCount: channelCount)
        }

        return nil
    }

    private static func bestAudioTrack(inputFile: URL, ffmpegPath: String, audioStreamCount: Int) -> Int? {
        let candidates = (0..<audioStreamCount).compactMap { index -> AudioTrackScore? in
            guard let meanVolume = meanVolumeDB(inputFile: inputFile, ffmpegPath: ffmpegPath, audioTrackIndex: index) else {
                return nil
            }
            return AudioTrackScore(index: index, meanVolumeDB: meanVolume)
        }

        return candidates
            .sorted { $0.meanVolumeDB > $1.meanVolumeDB }
            .first?
            .index
    }

    private static func meanVolumeDB(inputFile: URL, ffmpegPath: String, audioTrackIndex: Int) -> Double? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-hide_banner",
            "-t", "30",
            "-i", inputFile.path,
            "-map", "0:a:\(audioTrackIndex)",
            "-af", "volumedetect",
            "-f", "null",
            "-"
        ]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let pattern = #"mean_volume:\s*(-?\d+(?:\.\d+)?)\s*dB"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output) else {
            return nil
        }

        return Double(output[range])
    }

    private static func bestAudioChannel(inputFile: URL, ffmpegPath: String, channelCount: Int) -> Int? {
        let labels = audioChannelLabels(inputFile: inputFile, channelCount: channelCount)
        let candidates = (0..<channelCount).compactMap { index -> AudioChannelScore? in
            guard let meanVolume = channelMeanVolumeDB(inputFile: inputFile, ffmpegPath: ffmpegPath, channelIndex: index) else {
                return nil
            }
            let label = labels[index, default: ""]
            return AudioChannelScore(
                index: index,
                meanVolumeDB: meanVolume,
                adjustedScore: meanVolume + channelLabelScoreAdjustment(label)
            )
        }

        return candidates
            .sorted {
                if $0.adjustedScore == $1.adjustedScore {
                    return $0.meanVolumeDB > $1.meanVolumeDB
                }
                return $0.adjustedScore > $1.adjustedScore
            }
            .first?
            .index
    }

    private static func audioChannelLabels(inputFile: URL, channelCount: Int) -> [Int: String] {
        guard let handle = try? FileHandle(forReadingFrom: inputFile) else {
            return [:]
        }
        defer { try? handle.close() }

        let data = handle.readData(ofLength: 262_144)
        let content = String(data: data, encoding: .isoLatin1) ?? ""
        let pattern = #"s?TRK(\d+)="#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }

        let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
        let parsed = matches.compactMap { match -> (Int, String)? in
            guard
                let numberRange = Range(match.range(at: 1), in: content),
                let fullRange = Range(match.range(at: 0), in: content),
                let number = Int(content[numberRange])
            else {
                return nil
            }
            let label = metadataValue(after: fullRange, in: content)
            guard !label.isEmpty else { return nil }
            return (number - 1, label)
        }

        if parsed.isEmpty {
            return [:]
        }

        var labels: [Int: String] = [:]
        for (index, label) in parsed where labels[index] == nil {
            labels[index] = label
        }
        let orderedLabels = parsed.sorted { $0.0 < $1.0 }.map(\.1)
        for index in 0..<channelCount where labels[index] == nil && index < orderedLabels.count {
            labels[index] = orderedLabels[index]
        }
        return labels
    }

    private static func metadataValue(after range: Range<String.Index>, in content: String) -> String {
        let suffix = content[range.upperBound...]
        let raw = suffix.prefix { char in
            char != "\n" && char != "\r" && char != "\0"
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func channelLabelScoreAdjustment(_ label: String) -> Double {
        let normalized = label.lowercased()
        var adjustment = 0.0

        if normalized.contains("mix") {
            adjustment -= 8.0
        }
        if normalized.contains("boom") {
            adjustment += 4.0
        }
        if normalized.contains("lav") || normalized.contains("lavalier") {
            adjustment += 3.0
        }
        if !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !normalized.contains("mix") {
            adjustment += 1.0
        }

        return adjustment
    }

    private static func channelMeanVolumeDB(inputFile: URL, ffmpegPath: String, channelIndex: Int) -> Double? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-hide_banner",
            "-t", "30",
            "-i", inputFile.path,
            "-af", "pan=mono|c0=c\(channelIndex),volumedetect",
            "-f", "null",
            "-"
        ]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let pattern = #"mean_volume:\s*(-?\d+(?:\.\d+)?)\s*dB"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output) else {
            return nil
        }

        return Double(output[range])
    }

    private static func speechAudioFilter(settings: AppSettings) -> String {
        guard settings.enhanceSpeechAudio else {
            return "aresample=16000"
        }

        return [
            "highpass=f=80",
            "lowpass=f=7600",
            "afftdn=nr=10:nf=-45",
            "loudnorm=I=-18:LRA=11:TP=-1.5",
            "aresample=16000"
        ].joined(separator: ",")
    }

    private static func audioStreamCount(inputFile: URL, ffmpegPath: String) -> Int {
        let ffprobePath = ffprobePath(for: ffmpegPath)
        guard FileManager.default.isExecutableFile(atPath: ffprobePath) else {
            return 1
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobePath)
        process.arguments = [
            "-v", "error",
            "-select_streams", "a",
            "-show_entries", "stream=index",
            "-of", "csv=p=0",
            inputFile.path
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return 1
        }

        guard process.terminationStatus == 0 else {
            return 1
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let count = output
            .split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
        return max(1, count)
    }

    private static func audioChannelCount(inputFile: URL, ffmpegPath: String, audioTrackIndex: Int) -> Int {
        let ffprobePath = ffprobePath(for: ffmpegPath)
        guard FileManager.default.isExecutableFile(atPath: ffprobePath) else {
            return 1
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobePath)
        process.arguments = [
            "-v", "error",
            "-select_streams", "a:\(audioTrackIndex)",
            "-show_entries", "stream=channels",
            "-of", "csv=p=0",
            inputFile.path
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return 1
        }

        guard process.terminationStatus == 0 else { return 1 }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return max(1, Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1)
    }

    private static func ffprobePath(for ffmpegPath: String) -> String {
        let url = URL(fileURLWithPath: ffmpegPath)
        if ffmpegPath != "auto", !url.deletingLastPathComponent().path.isEmpty {
            return url.deletingLastPathComponent().appendingPathComponent("ffprobe").path
        }
        if FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ffprobe") {
            return "/opt/homebrew/bin/ffprobe"
        }
        if FileManager.default.isExecutableFile(atPath: "/usr/local/bin/ffprobe") {
            return "/usr/local/bin/ffprobe"
        }
        return "/usr/bin/ffprobe"
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

    private static func createBurnedInSubtitleVideo(
        runner: ProcessRunner,
        ffmpegPath: String,
        inputVideo: URL,
        subtitleFile: URL,
        outputVideo: URL,
        style: BurnedSubtitleStyle,
        log: @escaping @MainActor (LogEntry.LogLevel, String) -> Void,
        cancellation: @escaping () -> Bool
    ) async throws {
        guard ffmpegSupportsVideoFilter("subtitles", ffmpegPath: ffmpegPath) else {
            throw PipelineError.commandFailed("Šis ffmpeg neturi subtitles/libass filtro, todėl negali įkepti subtitrų į video. Įdiek ffmpeg build su libass palaikymu arba rinkis Track MP4.")
        }

        try await runner.run(
            executable: ffmpegPath,
            arguments: [
                "-y",
                "-i", inputVideo.path,
                "-vf", "subtitles=\(ffmpegFilterEscapedPath(subtitleFile.path)):force_style='\(style.ffmpegForceStyle)'",
                "-map", "0:v:0",
                "-map", "0:a?",
                "-c:v", "libx264",
                "-preset", "medium",
                "-crf", "18",
                "-pix_fmt", "yuv420p",
                "-c:a", "copy",
                "-movflags", "+faststart",
                outputVideo.path
            ],
            log: log,
            cancellation: cancellation
        )

        guard FileManager.default.fileExists(atPath: outputVideo.path),
              fileSize(at: outputVideo) > 10_000 else {
            throw PipelineError.commandFailed("Burned MP4 nebuvo sukurtas arba yra per mažas: \(outputVideo.path)")
        }
    }

    private static func ffmpegSupportsVideoFilter(_ name: String, ffmpegPath: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = ["-hide_banner", "-filters"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }

        guard process.terminationStatus == 0 else { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output
            .split(whereSeparator: \.isNewline)
            .contains { line in
                line.split(separator: " ").contains(name[...])
            }
    }

    private static func ffmpegFilterEscapedPath(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ":", with: "\\:")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: ",", with: "\\,")
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
        allowLanguagePrompt: Bool,
        noSpeechThreshold: Double,
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
            languageCode: languageCode,
            allowLanguagePrompt: allowLanguagePrompt,
            noSpeechThreshold: noSpeechThreshold
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
                languageCode: languageCode,
                allowLanguagePrompt: allowLanguagePrompt,
                noSpeechThreshold: noSpeechThreshold
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
        languageCode: String,
        allowLanguagePrompt: Bool,
        noSpeechThreshold: Double
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
            "-nth", String(format: "%.2f", noSpeechThreshold)
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

        if allowLanguagePrompt && settings.useWhisperLanguagePrompt, let prompt = whisperPrompt(languageCode: languageCode, translateToEnglish: translateToEnglish) {
            arguments.append("--prompt")
            arguments.append(prompt)
            arguments.append("--carry-initial-prompt")
        }

        return arguments
    }

    private static func whisperPrompt(languageCode: String, translateToEnglish: Bool) -> String? {
        if translateToEnglish {
            return "Clear speech transcription translated into natural English subtitles with punctuation."
        }

        switch languageCode.lowercased() {
        case "lt":
            return "Aiški lietuvių kalba. Tvarkinga transkripcija su lietuviška skyryba, sakiniais ir dialogais."
        case "en":
            return "Clear English speech transcription with punctuation and readable subtitle sentences."
        case "auto":
            return nil
        default:
            return "Clear speech transcription with punctuation and readable subtitle sentences."
        }
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

        let sentenceBlocks = settings.splitOnSentenceBoundaries
            ? splitBlocksBySentenceBoundaries(blocks, settings: settings, report: &report)
            : blocks
        let wrappedBlocks = wrapBlocks(sentenceBlocks, settings: settings, report: &report)
        let splitBlocks = splitBlocksByLineLimit(wrappedBlocks, settings: settings, report: &report)
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
        report.remainingCPSWarnings = repaired.filter {
            charactersPerSecond($0) > settings.maxCharactersPerSecond
        }.count
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
        let cleanedText = cleanSubtitleTextLines(textLines, settings: settings)

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
            .filter { !settings.removeASRArtifacts || !isPromptLeakageText($0) }
            .map { settings.removeASRArtifacts ? collapseRepeatedPhrases(in: $0) : $0 }
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

    private static func isPromptLeakageText(_ line: String) -> Bool {
        let normalized = normalizedASRText(line)
        let markers = [
            "tvarkinga transkripcija",
            "lietuviska skyryba",
            "sakiniais ir dialogais",
            "clear speech transcription",
            "readable subtitle",
            "punctuation and readable",
            "translated into natural english"
        ]
        return markers.contains { normalized.contains($0) }
    }

    private static func collapseRepeatedPhrases(in line: String) -> String {
        let words = line.split(separator: " ").map(String.init)
        guard words.count >= 6 else { return line }

        var cleaned = words
        var changed = true

        while changed {
            changed = false
            let maxLength = min(8, cleaned.count / 2)
            guard maxLength >= 2 else { break }

            for length in stride(from: maxLength, through: 2, by: -1) {
                guard cleaned.count >= length * 2 else { continue }
                var index = 0
                while index <= cleaned.count - length * 2 {
                    let first = Array(cleaned[index..<(index + length)]).map(normalizedASRText)
                    let second = Array(cleaned[(index + length)..<(index + length * 2)]).map(normalizedASRText)
                    if first == second {
                        cleaned.removeSubrange((index + length)..<(index + length * 2))
                        changed = true
                    } else {
                        index += 1
                    }
                }
            }
        }

        return normalizeTextSpacing(cleaned.joined(separator: " "))
    }

    private static func normalizedASRText(_ text: String) -> String {
        text
            .lowercased()
            .folding(options: [.diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^a-z0-9ąčęėįšųūžĄČĘĖĮŠŲŪŽ ]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

        if prefix.isEmpty, let balanced = balancedTwoLineWrap(words: words, maxLength: maxLength) {
            return balanced
        }

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

    private static func balancedTwoLineWrap(words: [String], maxLength: Int) -> [String]? {
        guard words.count > 2 else { return nil }
        let full = words.joined(separator: " ")
        guard full.count > maxLength, full.count <= maxLength * 2 else { return nil }

        var best: ([String], Int)?
        for splitIndex in 1..<words.count {
            let first = words[..<splitIndex].joined(separator: " ")
            let second = words[splitIndex...].joined(separator: " ")
            guard first.count <= maxLength, second.count <= maxLength else { continue }
            let penalty = abs(first.count - second.count)
            if best == nil || penalty < best!.1 {
                best = ([first, second], penalty)
            }
        }

        return best?.0
    }

    private static func splitBlocksBySentenceBoundaries(_ blocks: [SubtitleBlock], settings: AppSettings, report: inout SubtitleQualityReport) -> [SubtitleBlock] {
        var result: [SubtitleBlock] = []

        for block in blocks {
            if block.lines.contains(where: isDialogueLine) {
                result.append(block)
                continue
            }

            let text = normalizeTextSpacing(block.lines.joined(separator: " "))
            let sentences = splitTextIntoSentenceChunks(text)
            guard sentences.count > 1 else {
                result.append(block)
                continue
            }

            let duration = max(0.1, block.end - block.start)
            let totalCharacters = max(1, sentences.map(\.count).reduce(0, +))
            var cursor = block.start

            for (index, sentence) in sentences.enumerated() {
                let ratio = Double(sentence.count) / Double(totalCharacters)
                let chunkDuration = index == sentences.count - 1
                    ? block.end - cursor
                    : max(0.1, duration * ratio)
                let end = index == sentences.count - 1 ? block.end : min(block.end, cursor + chunkDuration)
                result.append(SubtitleBlock(start: cursor, end: max(end, cursor + 0.1), lines: [sentence]))
                cursor = end
            }

            report.sentenceSplits += sentences.count - 1
        }

        return result
    }

    private static func splitTextIntoSentenceChunks(_ text: String) -> [String] {
        let value = normalizeTextSpacing(text)
        guard value.count > 0 else { return [] }

        let pattern = #"(?<=[.!?…])\s+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [value]
        }

        let nsRange = NSRange(value.startIndex..., in: value)
        var chunks: [String] = []
        var start = value.startIndex

        for match in regex.matches(in: value, range: nsRange) {
            guard let range = Range(match.range, in: value) else { continue }
            let chunk = String(value[start..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty {
                chunks.append(chunk)
            }
            start = range.upperBound
        }

        let last = String(value[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !last.isEmpty {
            chunks.append(last)
        }

        if chunks.count <= 1, value.count > 90 {
            return splitLongPhrase(value)
        }

        return chunks
    }

    private static func splitLongPhrase(_ text: String) -> [String] {
        let separators = [", ", "; ", ": ", " – ", " — "]
        for separator in separators where text.contains(separator) {
            let parts = text.components(separatedBy: separator)
                .map(normalizeTextSpacing)
                .filter { !$0.isEmpty }
            if parts.count > 1 {
                return parts
            }
        }
        return [text]
    }

    private static func wrapBlocks(_ blocks: [SubtitleBlock], settings: AppSettings, report: inout SubtitleQualityReport) -> [SubtitleBlock] {
        blocks.compactMap { block in
            var copy = block
            copy.lines = wrapSubtitleLines(block.lines, settings: settings, report: &report)
            return copy.lines.isEmpty ? nil : copy
        }
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
                    if repaired.count > 0,
                       current.start - minGap - previous.start >= minDuration {
                        repaired[repaired.count - 1].end = current.start - minGap
                        report.overlapFixes += 1
                    } else {
                        report.overlapFixes += 1
                        current.start = minimumStart
                    }
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
                if repaired.count > 0,
                   current.start - minGap - previous.start >= minDuration {
                    repaired[repaired.count - 1].end = current.start - minGap
                } else {
                    current.start = previous.end + minGap
                    current.end = max(current.end, current.start + minDuration)
                }
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

    private static func writeTranscriptText(from srtURL: URL, to txtURL: URL) throws {
        let content = try String(contentsOf: srtURL, encoding: .utf8)
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let paragraphs = normalized
            .components(separatedBy: "\n\n")
            .compactMap { block -> String? in
                let lines = block
                    .components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .filter { !$0.contains("-->") }
                    .filter { Int($0) == nil }

                let text = lines
                    .joined(separator: " ")
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            }

        let transcript = paragraphs
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        try transcript.write(to: txtURL, atomically: true, encoding: .utf8)
    }

    private static func writeWebVTT(from srtURL: URL, to vttURL: URL) throws {
        let content = try String(contentsOf: srtURL, encoding: .utf8)
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let cues = normalized
            .components(separatedBy: "\n\n")
            .compactMap { block -> String? in
                let lines = block
                    .components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }

                guard let timeIndex = lines.firstIndex(where: { $0.contains("-->") }) else {
                    return nil
                }

                let timing = lines[timeIndex]
                    .replacingOccurrences(of: ",", with: ".")
                let textLines = Array(lines.dropFirst(timeIndex + 1))
                guard !textLines.isEmpty else { return nil }
                return ([timing] + textLines).joined(separator: "\n")
            }

        let vtt = "WEBVTT\n\n" + cues.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        try vtt.write(to: vttURL, atomically: true, encoding: .utf8)
    }

    private static func writeAdvancedSubStation(from srtURL: URL, to assURL: URL) throws {
        let content = try String(contentsOf: srtURL, encoding: .utf8)
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let events = normalized
            .components(separatedBy: "\n\n")
            .compactMap { block -> String? in
                let lines = block
                    .components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }

                guard let timeIndex = lines.firstIndex(where: { $0.contains("-->") }) else {
                    return nil
                }

                let timingParts = lines[timeIndex].components(separatedBy: "-->")
                guard timingParts.count == 2,
                      let start = parseSRTTimestamp(timingParts[0]),
                      let end = parseSRTTimestamp(timingParts[1]) else {
                    return nil
                }

                let text = Array(lines.dropFirst(timeIndex + 1))
                    .map(escapeASSText)
                    .joined(separator: "\\N")
                guard !text.isEmpty else { return nil }
                return "Dialogue: 0,\(formatASSTimestamp(start)),\(formatASSTimestamp(end)),Default,,0,0,0,,\(text)"
            }

        let ass = """
        [Script Info]
        ScriptType: v4.00+
        WrapStyle: 0
        ScaledBorderAndShadow: yes
        YCbCr Matrix: TV.709
        PlayResX: 1920
        PlayResY: 1080

        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        Style: Default,Helvetica,54,&H00FFFFFF,&H000000FF,&HAA000000,&H00000000,-1,0,0,0,100,100,0,0,1,3,0,2,80,80,68,1

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        \(events.joined(separator: "\n"))
        """
        try (ass.trimmingCharacters(in: .whitespacesAndNewlines) + "\n").write(to: assURL, atomically: true, encoding: .utf8)
    }

    private static func formatASSTimestamp(_ value: Double) -> String {
        let centiseconds = max(0, Int((value * 100.0).rounded()))
        let hours = centiseconds / 360_000
        let minutes = (centiseconds % 360_000) / 6_000
        let seconds = (centiseconds % 6_000) / 100
        let cs = centiseconds % 100
        return String(format: "%d:%02d:%02d.%02d", hours, minutes, seconds, cs)
    }

    private static func escapeASSText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "{", with: "\\{")
            .replacingOccurrences(of: "}", with: "\\}")
            .replacingOccurrences(of: "\n", with: "\\N")
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
        let summary = "SRT kokybės patikra \(fileName): \(report.blocks) blokai, \(report.sentenceSplits) sakinio/frazės skaidymų, \(report.blockSplits) blokų skaidymų, \(report.overlapFixes) laiko persidengimų pataisyta, \(report.durationFixes) trukmių pataisyta, \(report.lineWraps) eilučių pervyniota, \(report.cpsWarnings) CPS pataisymų, \(report.remainingCPSWarnings) likusių CPS įspėjimų."
        log(report.hasWarnings ? .warning : .success, summary)

        if report.droppedBlocks > 0 {
            log(.warning, "Pašalinta netinkamų SRT blokų: \(report.droppedBlocks).")
        }
        if report.longLineWarnings > 0 {
            log(.warning, "Yra subtitrų, kuriuos reikėjo skaidyti dėl eilučių ribų: \(report.longLineWarnings).")
        }
        if report.remainingCPSWarnings > 0 {
            log(.warning, "Kai kurie subtitrai vis dar gali būti per greiti skaitymui: \(report.remainingCPSWarnings). Vėliau juos rodysime SRT peržiūroje su „Fix All“.")
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
    var sentenceSplits = 0
    var blockSplits = 0
    var longLineWarnings = 0
    var cpsWarnings = 0
    var remainingCPSWarnings = 0

    var hasWarnings: Bool {
        droppedBlocks > 0
            || overlapFixes > 0
            || durationFixes > 0
            || sentenceSplits > 0
            || blockSplits > 0
            || longLineWarnings > 0
            || cpsWarnings > 0
            || remainingCPSWarnings > 0
    }
}

private struct AudioTrackScore {
    let index: Int
    let meanVolumeDB: Double
}

private struct AudioChannelScore {
    let index: Int
    let meanVolumeDB: Double
    let adjustedScore: Double
}
