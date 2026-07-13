import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedFile: URL?
    @Published var resultFile: URL?
    @Published var resultFiles: [URL] = []
    @Published var qualityReport: SRTQAReport?
    @Published var audioDiagnosticReport: AudioDiagnosticReport?
    @Published var isAnalyzingAudio = false
    @Published var jobs: [TranscriptionJob] = []
    @Published var deviceProfile = DeviceProfiler.current()
    @Published var maxParallelJobs = DeviceProfiler.current().recommendedParallelJobs
    @Published var performanceMode: PerformanceMode = .recommended
    @Published var settings = AppSettings()
    @Published var mode: WorkMode = .minimal
    @Published var phase: JobPhase = .idle
    @Published var progress: Double = 0
    @Published var logs: [LogEntry] = []
    @Published var dependencies = DependencyReport()
    @Published var isRunning = false
    @Published var isDownloadingModel = false
    @Published var isPreparingTools = false
    @Published var isCheckingForUpdates = false
    @Published var updateStatusMessage = "Atnaujinimai dar netikrinti."
    @Published var availableUpdate: AppUpdate?
    @Published var statusMessage = "Pasirink video arba audio failą, iš kurio reikia sukurti subtitrus."

    private let runner = ProcessRunner()
    private var activeRunners: [UUID: ProcessRunner] = [:]
    private var cancellation = CancellationBox()

    var isBusy: Bool {
        isRunning || isDownloadingModel || isPreparingTools
    }

    var canStart: Bool {
        (selectedFile != nil || !jobs.isEmpty)
            && dependencies.ffmpeg.isReady
            && dependencies.whisper.isReady
            && dependencies.model.isReady
            && videoExportInputIsValid
            && !isBusy
    }

    var offlineReady: Bool {
        dependencies.ffmpeg.isReady
            && dependencies.whisper.isReady
            && dependencies.model.isReady
    }

    var offlineStatusMessage: String {
        if offlineReady {
            return "Pilnai paruošta darbui be interneto. Transkripcija, LT/EN SRT ir vertimas vyksta lokaliai šiame Mac."
        }
        return "Offline darbui dar trūksta vietinių komponentų. Pirmą kartą reikia turėti ffmpeg, whisper.cpp ir modelio failą šiame Mac."
    }

    var primaryBlocker: String? {
        if selectedFile == nil {
            return "Pirmiausia pasirink video arba audio failą."
        }
        if !dependencies.ffmpeg.isReady {
            return "Trūksta ffmpeg. Spausk „Paruošti programą“."
        }
        if !dependencies.whisper.isReady {
            return "Trūksta Whisper variklio. Spausk „Paruošti programą“."
        }
        if !dependencies.model.isReady {
            return "Trūksta pilno large-v3 modelio. Spausk „Atsisiųsti large-v3“."
        }
        if !videoExportInputIsValid {
            return "MP4 eksportui reikia video failo. Audio failams rinkis SRT eksportą."
        }
        if isBusy {
            return "Palauk, kol baigsis dabartinis darbas."
        }
        return nil
    }

    var readinessScore: Int {
        [(selectedFile != nil || !jobs.isEmpty), dependencies.ffmpeg.isReady, dependencies.whisper.isReady, dependencies.model.isReady, videoExportInputIsValid]
            .filter { $0 }
            .count
    }

    init() {
        createSupportFolders()
        applyRecommendedPerformance()
        refreshDependencies()
    }

    func createSupportFolders() {
        try? FileManager.default.createDirectory(at: AppPaths.modelsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: AppPaths.jobsDirectory, withIntermediateDirectories: true)
    }

    func refreshDependencies() {
        deviceProfile = DeviceProfiler.current()
        dependencies = DependencyResolver.report(settings: settings)
        updateInitialSetupMessage()
    }

    private func updateInitialSetupMessage() {
        guard phase == .idle, selectedFile == nil, jobs.isEmpty, !isBusy else { return }

        if offlineReady {
            statusMessage = "Offline režimas paruoštas. Pasirink video arba audio failą ir kurk SRT be interneto."
        } else {
            statusMessage = "Pirmam paruošimui prisijunk prie interneto ir spausk „Internetinis paruošimas“. Po to appas veiks offline."
        }
    }

    func applyRecommendedPerformance() {
        deviceProfile = DeviceProfiler.current()
        performanceMode = .recommended
        maxParallelJobs = deviceProfile.recommendedParallelJobs
        settings.threadCount = deviceProfile.recommendedThreadsPerJob
        settings.useGPU = true
    }

    func applyWorkMode(_ newMode: WorkMode) {
        mode = newMode

        if newMode != .advanced, let selectedFile {
            jobs = [TranscriptionJob(inputFile: selectedFile)]
        }

        switch newMode {
        case .minimal:
            settings.languageCode = "lt"
            settings.autoDetectLanguage = false
            settings.subtitleOutputMode = .lithuanianOnly
            settings.videoExportMode = .srtOnly
            settings.keepWorkingFiles = false
            settings.splitOnWord = true
            settings.normalizePunctuation = true
            settings.formatDialogueLines = true
            settings.suppressNonSpeechTokens = true
            settings.maxSegmentLength = 42
        case .simple:
            settings.keepWorkingFiles = false
            settings.normalizePunctuation = true
            settings.formatDialogueLines = true
            settings.suppressNonSpeechTokens = true
        case .power, .advanced:
            break
        }
    }

    func applyPerformanceMode(_ mode: PerformanceMode) {
        deviceProfile = DeviceProfiler.current()
        performanceMode = mode

        switch mode {
        case .safe:
            maxParallelJobs = 1
            settings.threadCount = max(2, min(4, deviceProfile.activeCores / 2))
            settings.useGPU = true
        case .recommended:
            maxParallelJobs = deviceProfile.recommendedParallelJobs
            settings.threadCount = deviceProfile.recommendedThreadsPerJob
            settings.useGPU = true
        case .maximum:
            settings.threadCount = max(2, deviceProfile.activeCores)
            settings.useGPU = true
            maxParallelJobs = maxHardwareParallelJobs
        }
    }

    func selectManualAudioTrack(_ track: AudioTrackDiagnostic) {
        settings.audioInputMode = .manualTrack
        settings.manualAudioTrackPosition = track.audioPosition
        settings.manualAudioChannelIndex = nil
        append(.info, "Rankiniu būdu pasirinktas audio Track \(track.audioPosition + 1) Whisper atpažinimui.")
    }

    func selectManualAudioChannel(_ channel: AudioChannelDiagnostic) {
        settings.audioInputMode = .manualTrack
        settings.manualAudioTrackPosition = 0
        settings.manualAudioChannelIndex = channel.channelIndex
        append(.info, "Rankiniu būdu pasirinktas WAV Ch \(channel.channelIndex + 1) Whisper atpažinimui.")
    }

    var maxHardwareParallelJobs: Int {
        max(1, min(4, max(deviceProfile.recommendedParallelJobs, deviceProfile.memoryGB / 8)))
    }

    var readinessTotal: Int {
        settings.videoExportMode.createsVideo ? 5 : 4
    }

    var videoExportInputIsValid: Bool {
        guard settings.videoExportMode.createsVideo else { return true }
        let inputs = jobs.isEmpty ? [selectedFile].compactMap { $0 } : jobs.map(\.inputFile)
        guard !inputs.isEmpty else { return true }
        return inputs.allSatisfy(Self.isLikelyVideoFile)
    }

    var performanceWarning: String {
        switch performanceMode {
        case .safe:
            return "Saugus režimas palieka daugiau resursų kitoms programoms."
        case .recommended:
            return deviceProfile.recommendation
        case .maximum:
            return "Iki galo režimas apkraus M1 Pro stipriau. Jei Mac pradės strigti arba kaisti, grįžk į rekomenduojamą režimą."
        }
    }

    func selectInputFile() {
        let panel = NSOpenPanel()
        panel.title = "Pasirink video arba audio failą"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = mode == .advanced
        panel.allowedContentTypes = [.movie, .audio, .mpeg4Movie, .quickTimeMovie, .mp3, .wav, .mpeg4Audio]

        if panel.runModal() == .OK {
            setInputFiles(panel.urls)
        }
    }

    func setInputFile(_ url: URL) {
        setInputFiles([url])
    }

    func setInputFiles(_ urls: [URL]) {
        let files = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !files.isEmpty else { return }

        selectedFile = files.first
        jobs = files.map { TranscriptionJob(inputFile: $0) }
        resultFile = nil
        resultFiles = []
        qualityReport = nil
        audioDiagnosticReport = nil
        phase = .idle
        progress = 0
        statusMessage = files.count == 1
            ? "Failas pasirinktas. Dabar gali kurti SRT."
            : "Pasirinkta \(files.count) failų. Advanced režimas apdoros juos pagal kompiuterio pajėgumą."

        for url in files {
            append(.info, "Pasirinktas failas: \(url.path)")
        }

        analyzeSelectedAudioIfPossible()
    }

    func selectOutputFolder() {
        let panel = NSOpenPanel()
        panel.title = "Pasirink, kur išsaugoti SRT"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            settings.outputFolder = url
            append(.info, "SRT bus išsaugotas: \(url.path)")
        }
    }

    func selectModelFile() {
        let panel = NSOpenPanel()
        panel.title = "Pasirink Whisper large-v3 modelio failą"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.data]

        if panel.runModal() == .OK, let url = panel.url {
            settings.modelPath = url.path
            refreshDependencies()
            append(.info, "Modelis pasirinktas: \(url.path)")
        }
    }

    func selectFFmpegBinary() {
        selectExecutable(title: "Pasirink ffmpeg") { [weak self] url in
            self?.settings.ffmpegPath = url.path
            self?.refreshDependencies()
            self?.append(.info, "ffmpeg: \(url.path)")
        }
    }

    func selectWhisperBinary() {
        selectExecutable(title: "Pasirink whisper.cpp CLI") { [weak self] url in
            self?.settings.whisperPath = url.path
            self?.refreshDependencies()
            self?.append(.info, "whisper.cpp: \(url.path)")
        }
    }

    private func selectExecutable(title: String, onPick: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            onPick(url)
        }
    }

    func start() {
        guard !isRunning, !isDownloadingModel, !isPreparingTools else { return }

        if mode == .advanced && jobs.count > 1 {
            startBatch()
            return
        }

        guard let selectedFile else {
            statusMessage = "Pirma pasirink failą."
            append(.warning, "Bandymas pradėti be failo.")
            return
        }

        refreshDependencies()
        cancellation = CancellationBox()
        isRunning = true
        resultFile = nil
        resultFiles = []
        qualityReport = nil
        logs.removeAll()
        append(.info, "Darbas pradėtas.")

        let pipeline = SubtitlePipeline(runner: runner)
        let localSettings = settings
        let token = cancellation

        Task {
            do {
                let result = try await pipeline.run(
                    inputFile: selectedFile,
                    settings: localSettings,
                    updatePhase: { [weak self] phase, progress in
                        self?.phase = phase
                        self?.progress = progress
                        self?.statusMessage = phase.rawValue
                    },
                    log: { [weak self] level, message in
                        self?.append(level, message)
                    },
                    cancellation: {
                        token.isCancelled
                    }
                )

                resultFile = result.primaryFile
                resultFiles = result.allFiles
                qualityReport = analyzeSRTFiles(result.srtFiles, settings: localSettings)
                phase = .complete
                progress = 1
                statusMessage = completionMessage(for: result)
            } catch PipelineError.cancelled {
                phase = .cancelled
                progress = 0
                statusMessage = "Darbas nutrauktas."
                append(.warning, "Darbas nutrauktas vartotojo.")
            } catch {
                phase = .failed
                statusMessage = error.localizedDescription
                append(.error, error.localizedDescription)
            }

            isRunning = false
            refreshDependencies()
        }
    }

    func startBatch() {
        guard !isRunning, !isDownloadingModel, !isPreparingTools else { return }
        guard !jobs.isEmpty else {
            statusMessage = "Pirma pasirink vieną ar kelis failus."
            append(.warning, "Bandymas pradėti be failų.")
            return
        }

        refreshDependencies()
        guard dependencies.ffmpeg.isReady, dependencies.whisper.isReady, dependencies.model.isReady else {
            statusMessage = primaryBlocker ?? "Trūksta paruošimo."
            append(.warning, statusMessage)
            return
        }

        cancellation = CancellationBox()
        activeRunners.removeAll()
        isRunning = true
        resultFile = nil
        resultFiles = []
        qualityReport = nil
        phase = .validating
        progress = 0
        logs.removeAll()

        let localSettings = settings
        let token = cancellation
        let items = jobs
        let allowedParallelJobs = performanceMode == .maximum ? maxHardwareParallelJobs : deviceProfile.recommendedParallelJobs
        let limit = max(1, min(maxParallelJobs, allowedParallelJobs, items.count))

        append(.info, "Advanced režimas pradeda \(items.count) failų eilę. Vienu metu bus vykdoma iki \(limit) darbų.")

        Task {
            await withTaskGroup(of: Void.self) { group in
                var iterator = items.makeIterator()

                func enqueue(_ item: TranscriptionJob) {
                    group.addTask {
                        await self.runBatchJob(item: item, settings: localSettings, token: token)
                    }
                }

                for _ in 0..<limit {
                    if let item = iterator.next() {
                        enqueue(item)
                    }
                }

                while await group.next() != nil {
                    if token.isCancelled {
                        continue
                    }
                    if let item = iterator.next() {
                        enqueue(item)
                    }
                }
            }

            let completed = jobs.filter { $0.state == .complete }.count
            let failed = jobs.filter { $0.state == .failed }.count
            let cancelled = jobs.filter { $0.state == .cancelled }.count

            isRunning = false
            activeRunners.removeAll()
            progress = jobs.isEmpty ? 0 : jobs.map(\.progress).reduce(0, +) / Double(jobs.count)

            if token.isCancelled || cancelled > 0 {
                phase = .cancelled
                statusMessage = "Eilė nutraukta. Baigta: \(completed), klaidos: \(failed)."
            } else if failed > 0 {
                phase = .failed
                statusMessage = "Eilė baigta su klaidomis. Baigta: \(completed), klaidos: \(failed)."
            } else {
                phase = .complete
                progress = 1
                statusMessage = "Visi darbai baigti."
            }

            refreshDependencies()
        }
    }

    private func runBatchJob(item: TranscriptionJob, settings: AppSettings, token: CancellationBox) async {
        let jobRunner = ProcessRunner()
        await MainActor.run {
            activeRunners[item.id] = jobRunner
            updateJob(item.id) {
                $0.state = .running
                $0.phase = .validating
                $0.progress = 0.05
                $0.statusMessage = "Darbas pradėtas."
            }
        }

        let pipeline = SubtitlePipeline(runner: jobRunner)

        do {
            let result = try await pipeline.run(
                inputFile: item.inputFile,
                settings: settings,
                updatePhase: { phase, progress in
                    self.updateJob(item.id) {
                        $0.phase = phase
                        $0.progress = progress
                        $0.statusMessage = phase.rawValue
                    }
                    self.updateAggregateProgress()
                },
                log: { level, message in
                    self.appendJobLog(item.id, level, message)
                },
                cancellation: {
                    token.isCancelled
                }
            )

            updateJob(item.id) {
                $0.resultFile = result.primaryFile
                $0.phase = .complete
                $0.state = .complete
                $0.progress = 1
                $0.statusMessage = completionMessage(for: result)
            }
        } catch PipelineError.cancelled {
            updateJob(item.id) {
                $0.phase = .cancelled
                $0.state = .cancelled
                $0.statusMessage = "Nutraukta."
            }
        } catch {
            updateJob(item.id) {
                $0.phase = .failed
                $0.state = .failed
                $0.statusMessage = error.localizedDescription
            }
            appendJobLog(item.id, .error, error.localizedDescription)
        }

        activeRunners[item.id] = nil
        updateAggregateProgress()
    }

    private func updateJob(_ id: UUID, mutate: (inout TranscriptionJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&jobs[index])
    }

    private func appendJobLog(_ id: UUID, _ level: LogEntry.LogLevel, _ message: String) {
        updateJob(id) {
            $0.logs.append(LogEntry(level: level, message: message))
            if $0.logs.count > 120 {
                $0.logs.removeFirst($0.logs.count - 120)
            }
        }
        append(level, "\(jobs.first(where: { $0.id == id })?.displayName ?? "Darbas"): \(message)")
    }

    private func updateAggregateProgress() {
        guard !jobs.isEmpty else { return }
        progress = jobs.map(\.progress).reduce(0, +) / Double(jobs.count)
        if jobs.contains(where: { $0.state == .running }) {
            phase = .transcribing
            statusMessage = "Advanced režimas apdoroja \(jobs.filter { $0.state == .running }.count) darbą(-us) vienu metu."
        }
    }

    func cancel() {
        cancellation.cancel()
        runner.cancel()
        for activeRunner in activeRunners.values {
            activeRunner.cancel()
        }
        append(.warning, "Siunčiama nutraukimo komanda.")
    }

    func openResult() {
        guard let resultFile else { return }
        NSWorkspace.shared.open(resultFile)
    }

    func revealResult() {
        guard let resultFile else { return }
        NSWorkspace.shared.activateFileViewerSelecting([resultFile])
    }

    func revealAllResults() {
        let files = resultFiles.isEmpty ? [resultFile].compactMap { $0 } : resultFiles
        guard !files.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(files)
    }

    func openJobResult(_ job: TranscriptionJob) {
        guard let resultFile = job.resultFile else { return }
        NSWorkspace.shared.open(resultFile)
    }

    func revealJobResult(_ job: TranscriptionJob) {
        guard let resultFile = job.resultFile else { return }
        NSWorkspace.shared.activateFileViewerSelecting([resultFile])
    }

    func openModelsFolder() {
        NSWorkspace.shared.open(AppPaths.modelsDirectory)
    }

    var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    var updateManifestURLString: String {
        Bundle.main.object(forInfoDictionaryKey: "SRTForgeUpdateManifestURL") as? String ?? ""
    }

    func checkForUpdates() {
        guard !isCheckingForUpdates else { return }

        let manifestString = updateManifestURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !manifestString.isEmpty, let manifestURL = URL(string: manifestString) else {
            updateStatusMessage = "Atnaujinimų URL dar nesukonfigūruotas. Kai turėsime release vietą, įrašysime manifest URL į build."
            append(.warning, updateStatusMessage)
            return
        }

        isCheckingForUpdates = true
        availableUpdate = nil
        updateStatusMessage = "Tikrinami atnaujinimai..."
        append(.info, "Tikrinamas atnaujinimų manifestas: \(manifestURL.absoluteString)")

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: manifestURL)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    if http.statusCode == 404 {
                        throw PipelineError.commandFailed("Atnaujinimų manifestas nerastas GitHub'e (HTTP 404). Patikrink, ar version.json yra nupushintas į main šaką ir ar URL teisingas.")
                    }
                    throw PipelineError.commandFailed("Atnaujinimų serveris grąžino HTTP \(http.statusCode).")
                }

                let update = try JSONDecoder().decode(AppUpdate.self, from: data)

                if Self.isUpdate(update, newerThanVersion: currentShortVersion, currentBuild: currentBuildNumber) {
                    availableUpdate = update
                    let buildLabel = update.build.map { " (\($0))" } ?? ""
                    updateStatusMessage = "Yra nauja versija \(update.version)\(buildLabel)."
                    append(.success, "Rastas atnaujinimas: \(update.version)\(buildLabel)")
                } else {
                    availableUpdate = nil
                    updateStatusMessage = "Naudoji naujausią versiją \(currentShortVersion) (\(currentBuildNumber))."
                    append(.success, "Atnaujinimų nėra.")
                }
            } catch {
                availableUpdate = nil
                updateStatusMessage = "Atnaujinimų patikra nepavyko: \(error.localizedDescription)"
                append(.error, updateStatusMessage)
            }

            isCheckingForUpdates = false
        }
    }

    func openAvailableUpdate() {
        guard let availableUpdate else { return }
        NSWorkspace.shared.open(availableUpdate.downloadURL)
    }

    var primaryActionTitle: String {
        switch settings.videoExportMode {
        case .srtOnly:
            return "Kurti SRT"
        case .videoOnly:
            return "Kurti Track MP4"
        case .srtAndVideo:
            return "Kurti SRT + Track"
        case .burnedVideoOnly:
            return "Kurti Burned MP4"
        case .srtAndBurnedVideo:
            return "Kurti SRT + Burned"
        }
    }

    var primaryActionSystemImage: String {
        if !canStart { return "lock.fill" }
        switch settings.videoExportMode {
        case .srtOnly:
            return "bolt.fill"
        case .videoOnly:
            return "film.fill"
        case .srtAndVideo:
            return "captions.bubble.fill"
        case .burnedVideoOnly:
            return "flame.fill"
        case .srtAndBurnedVideo:
            return "text.below.photo.fill"
        }
    }

    private func completionMessage(for result: PipelineResult) -> String {
        if result.videoFile != nil && !result.srtFiles.isEmpty {
            return "SRT ir MP4 su subtitrais sukurti."
        }
        if result.videoFile != nil {
            return "MP4 su subtitrais sukurtas."
        }
        if result.srtFiles.count > 1 {
            return "SRT failai sukurti."
        }
        return "SRT failas sukurtas."
    }

    private func analyzeSRTFiles(_ files: [URL], settings: AppSettings) -> SRTQAReport? {
        let reports = files
            .filter { $0.pathExtension.lowercased() == "srt" }
            .map { analyzeSRTFile($0, settings: settings) }

        guard !reports.isEmpty else { return nil }
        return SRTQAReport(files: reports)
    }

    private func analyzeSRTFile(_ url: URL, settings: AppSettings) -> SRTQAFileReport {
        var report = SRTQAFileReport(fileName: url.lastPathComponent)
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            report.invalidBlocks = 1
            return report
        }

        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var previousEnd: Double?

        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            guard let timeIndex = lines.firstIndex(where: { $0.contains("-->") }) else {
                if !lines.isEmpty {
                    report.invalidBlocks += 1
                    addSRTIssue(
                        kind: .invalid,
                        timecode: "be laiko",
                        message: "Blokas neturi teisingos laiko eilutės.",
                        textLines: lines,
                        to: &report
                    )
                }
                continue
            }

            let parts = lines[timeIndex].components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = Self.parseSRTTimestamp(parts[0]),
                  let end = Self.parseSRTTimestamp(parts[1]),
                  end > start else {
                report.invalidBlocks += 1
                addSRTIssue(
                    kind: .invalid,
                    timecode: "blogas laikas",
                    message: "Laiko žyma nesuprantama arba pabaiga yra prieš pradžią.",
                    textLines: Array(lines.dropFirst(timeIndex + 1)),
                    to: &report
                )
                continue
            }

            report.blocks += 1
            if let previousEnd, start < previousEnd + settings.minimumSubtitleGap {
                report.overlaps += 1
                addSRTIssue(
                    kind: .overlap,
                    timecode: Self.formatSRTTimestamp(start),
                    message: "Subtitras prasideda per arti ankstesnio bloko.",
                    textLines: Array(lines.dropFirst(timeIndex + 1)),
                    to: &report
                )
            }

            let duration = end - start
            if duration < settings.minimumSubtitleDuration {
                report.tooShort += 1
                addSRTIssue(
                    kind: .duration,
                    timecode: Self.formatSRTTimestamp(start),
                    message: String(format: "Per trumpa trukmė: %.1fs.", duration),
                    textLines: Array(lines.dropFirst(timeIndex + 1)),
                    to: &report
                )
            }
            if duration > settings.maximumSubtitleDuration {
                report.tooLong += 1
                addSRTIssue(
                    kind: .duration,
                    timecode: Self.formatSRTTimestamp(start),
                    message: String(format: "Per ilga trukmė: %.1fs.", duration),
                    textLines: Array(lines.dropFirst(timeIndex + 1)),
                    to: &report
                )
            }

            let textLines = Array(lines.dropFirst(timeIndex + 1))
            if textLines.count > settings.maxSubtitleLines {
                report.tooManyLines += 1
                addSRTIssue(
                    kind: .tooManyLines,
                    timecode: Self.formatSRTTimestamp(start),
                    message: "Bloke yra \(textLines.count) eilutės; riba yra \(settings.maxSubtitleLines).",
                    textLines: textLines,
                    to: &report
                )
            }
            if textLines.contains(where: { $0.count > settings.maxSubtitleLineLength }) {
                report.longLines += 1
                addSRTIssue(
                    kind: .longLine,
                    timecode: Self.formatSRTTimestamp(start),
                    message: "Viena eilutė viršija \(settings.maxSubtitleLineLength) simbolių ribą.",
                    textLines: textLines,
                    to: &report
                )
            }

            let characters = textLines.joined(separator: " ").count
            let cps = Double(characters) / max(0.1, duration)
            if cps > settings.maxCharactersPerSecond {
                report.tooFast += 1
                addSRTIssue(
                    kind: .tooFast,
                    timecode: Self.formatSRTTimestamp(start),
                    message: String(format: "Skaitymo greitis %.0f CPS; riba %.0f.", cps, settings.maxCharactersPerSecond),
                    textLines: textLines,
                    to: &report
                )
            }

            previousEnd = end
        }

        return report
    }

    private func addSRTIssue(
        kind: SRTQAIssue.Kind,
        timecode: String,
        message: String,
        textLines: [String],
        to report: inout SRTQAFileReport
    ) {
        guard report.issues.count < 8 else { return }
        let preview = textLines
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        report.issues.append(
            SRTQAIssue(
                kind: kind,
                timecode: timecode,
                message: message,
                textPreview: preview.isEmpty ? "Teksto nėra." : preview
            )
        )
    }

    private static func formatSRTTimestamp(_ value: Double) -> String {
        let totalMilliseconds = max(0, Int((value * 1000.0).rounded()))
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds % 3_600_000) / 60_000
        let seconds = (totalMilliseconds % 60_000) / 1000
        let milliseconds = totalMilliseconds % 1000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }

    private func analyzeSelectedAudioIfPossible() {
        guard let selectedFile else { return }
        let report = DependencyResolver.report(settings: settings)
        guard case .ready(let ffmpegPath) = report.ffmpeg else { return }
        let ffprobePath = Self.ffprobePath(for: ffmpegPath)
        guard FileManager.default.isExecutableFile(atPath: ffprobePath) else { return }

        isAnalyzingAudio = true
        let file = selectedFile

        Task.detached {
            let diagnostic = AudioDiagnosticAnalyzer.analyze(file: file, ffmpegPath: ffmpegPath, ffprobePath: ffprobePath)

            await MainActor.run {
                self.audioDiagnosticReport = diagnostic
                self.isAnalyzingAudio = false
                if !diagnostic.tracks.isEmpty {
                    self.append(.info, "Audio diagnostika: \(diagnostic.title). \(diagnostic.detail)")
                }
            }
        }
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

    private var currentShortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    private var currentBuildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private static func isUpdate(_ candidate: AppUpdate, newerThanVersion currentVersion: String, currentBuild: String) -> Bool {
        if isVersion(candidate.version, newerThan: currentVersion) {
            return true
        }
        if isVersion(currentVersion, newerThan: candidate.version) {
            return false
        }
        return (Int(candidate.build ?? "") ?? 0) > (Int(currentBuild) ?? 0)
    }

    private static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let left = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let right = current.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(left.count, right.count)

        for index in 0..<count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a > b { return true }
            if a < b { return false }
        }
        return false
    }

    private static func isLikelyVideoFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["mp4", "mov", "m4v", "mkv", "webm", "avi"].contains(ext)
    }

    func prepareEverything() {
        guard !isRunning, !isDownloadingModel, !isPreparingTools else { return }

        isPreparingTools = true
        cancellation = CancellationBox()
        phase = .validating
        progress = 0.05
        statusMessage = "Ruošiama programa: įrankiai ir modelis."
        append(.info, "Pradedamas automatinis įrankių paruošimas.")

        let token = cancellation

        Task {
            do {
                guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/brew")
                    || FileManager.default.isExecutableFile(atPath: "/usr/local/bin/brew")
                else {
                    throw PipelineError.commandFailed("Homebrew nerastas. Friend DMG aplanke atidaryk „Pirmas paruošimas.command“ arba įdiek Homebrew iš https://brew.sh, tada vėl spausk „Internetinis paruošimas“.")
                }

                let brewPath = FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/brew")
                    ? "/opt/homebrew/bin/brew"
                    : "/usr/local/bin/brew"

                progress = 0.15
                statusMessage = "Diegiamas ffmpeg-full, Whisper variklis ir modelio siuntimo įrankis."

                try await runner.run(
                    executable: "/bin/zsh",
                    arguments: [
                        "-lc",
                        """
                        \(brewPath) list ffmpeg-full >/dev/null 2>&1 || \(brewPath) install ffmpeg-full
                        FFMPEG_BIN="/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg"
                        [ -x "$FFMPEG_BIN" ] || FFMPEG_BIN="/usr/local/opt/ffmpeg-full/bin/ffmpeg"
                        "$FFMPEG_BIN" -hide_banner -filters 2>/dev/null | grep -Eq '(^|[[:space:]])subtitles([[:space:]]|$)'
                        \(brewPath) list whisper-cpp >/dev/null 2>&1 || \(brewPath) install whisper-cpp
                        /usr/bin/python3 -m pip install --user --upgrade 'huggingface_hub[hf_xet]'
                        """
                    ],
                    log: { [weak self] level, message in
                        self?.append(level, message)
                    },
                    cancellation: { token.isCancelled }
                )

                progress = 0.45
                refreshDependencies()

                try await downloadModel(token: token)

                progress = 1.0
                phase = .complete
                statusMessage = "Viskas paruošta. Gali kurti SRT."
                append(.success, "Pilnas paruošimas baigtas.")
            } catch PipelineError.cancelled {
                phase = .cancelled
                statusMessage = "Paruošimas nutrauktas."
                append(.warning, "Paruošimas nutrauktas.")
            } catch {
                phase = .failed
                statusMessage = error.localizedDescription
                append(.error, error.localizedDescription)
            }

            isPreparingTools = false
            isDownloadingModel = false
            refreshDependencies()
        }
    }

    func downloadLargeV3Model() {
        guard !isRunning, !isDownloadingModel, !isPreparingTools else { return }

        isDownloadingModel = true
        cancellation = CancellationBox()
        phase = .validating
        progress = 0.35
        statusMessage = "Siunčiamas large-v3 modelis."
        append(.info, "Pradedamas large-v3 modelio siuntimas.")

        let token = cancellation

        Task {
            do {
                try await downloadModel(token: token)
                phase = .complete
                progress = 1.0
                statusMessage = "large-v3 modelis atsisiųstas."
            } catch PipelineError.cancelled {
                phase = .cancelled
                statusMessage = "Modelio siuntimas nutrauktas."
                append(.warning, "Modelio siuntimas nutrauktas.")
            } catch {
                append(.error, "Modelio siuntimas nepavyko: \(error.localizedDescription)")
                phase = .failed
                statusMessage = "Modelio siuntimas nepavyko."
            }

            isDownloadingModel = false
            refreshDependencies()
        }
    }

    private func downloadModel(token: CancellationBox) async throws {
        try FileManager.default.createDirectory(at: AppPaths.modelsDirectory, withIntermediateDirectories: true)

        let target = AppPaths.defaultModelURL
        let temporary = target.appendingPathExtension("tmp")

        if FileManager.default.fileExists(atPath: target.path),
           DependencyResolver.isModelComplete(at: target) {
            settings.modelPath = target.path
            append(.success, "large-v3 modelis jau yra: \(target.path)")
            return
        }

        if FileManager.default.fileExists(atPath: target.path) {
            append(.warning, "Rastas nepilnas large-v3 modelis. Jis bus pakeistas nauju atsisiuntimu.")
            try? FileManager.default.removeItem(at: target)
        }

        append(.info, "large-v3 modelis yra apie 3.1 GB. Siuntimas gali užtrukti.")

        if let hfPath = huggingFaceCLIPath() {
            append(.info, "Naudojamas oficialus Hugging Face siuntimo įrankis su Xet palaikymu.")
            try? FileManager.default.removeItem(at: temporary)
            try? FileManager.default.removeItem(at: temporary.appendingPathExtension("aria2"))

            try await runner.run(
                executable: "/bin/zsh",
                arguments: [
                    "-lc",
                    "HF_XET_HIGH_PERFORMANCE=1 '\(hfPath)' download ggerganov/whisper.cpp ggml-large-v3.bin --local-dir '\(AppPaths.modelsDirectory.path)' --max-workers 8"
                ],
                log: { [weak self] level, message in
                    self?.append(level, message)
                },
                cancellation: { token.isCancelled }
            )
        } else {
            append(.warning, "Hugging Face siuntimo įrankis nerastas, naudojamas lėtesnis curl.")
            try await runner.run(
                executable: "/usr/bin/curl",
                arguments: [
                    "-L",
                    "--fail",
                    "--continue-at",
                    "-",
                    "--progress-bar",
                    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin",
                    "-o",
                    temporary.path
                ],
                log: { [weak self] level, message in
                    self?.append(level, message)
                },
                cancellation: { token.isCancelled }
            )

            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.moveItem(at: temporary, to: target)
        }

        guard FileManager.default.fileExists(atPath: target.path),
              DependencyResolver.isModelComplete(at: target) else {
            throw PipelineError.commandFailed("Modelio failas neatsirado arba yra nepilnas po siuntimo: \(target.path)")
        }

        settings.modelPath = target.path
        append(.success, "large-v3 modelis atsisiųstas: \(target.path)")
    }

    private func huggingFaceCLIPath() -> String? {
        let candidates = [
            "\(NSHomeDirectory())/Library/Python/3.12/bin/hf",
            "\(NSHomeDirectory())/Library/Python/3.11/bin/hf",
            "\(NSHomeDirectory())/Library/Python/3.10/bin/hf",
            "\(NSHomeDirectory())/Library/Python/3.9/bin/hf"
        ]

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func append(_ level: LogEntry.LogLevel, _ message: String) {
        logs.append(LogEntry(level: level, message: message))
        if logs.count > 600 {
            logs.removeFirst(logs.count - 600)
        }
    }
}

final class CancellationBox {
    private let lock = NSLock()
    private var value = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func cancel() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

private enum AudioDiagnosticAnalyzer {
    static func analyze(file: URL, ffmpegPath: String, ffprobePath: String) -> AudioDiagnosticReport {
        var report = readAudioDiagnostics(file: file, ffprobePath: ffprobePath)
        for index in report.tracks.indices {
            report.tracks[index].meanVolumeDB = meanVolumeDB(
                file: file,
                ffmpegPath: ffmpegPath,
                audioTrackIndex: report.tracks[index].audioPosition
            )
        }

        if report.tracks.count == 1, let track = report.tracks.first, track.channels > 1 {
            report.channels = (0..<track.channels).map { channelIndex in
                AudioChannelDiagnostic(
                    streamIndex: track.streamIndex,
                    channelIndex: channelIndex,
                    label: channelLabel(file: file, channelIndex: channelIndex),
                    meanVolumeDB: channelMeanVolumeDB(
                        file: file,
                        ffmpegPath: ffmpegPath,
                        channelIndex: channelIndex
                    )
                )
            }
            report.recommendedChannel = report.channels
                .compactMap { channel -> (Int, Double, Double)? in
                    guard let mean = channel.meanVolumeDB else { return nil }
                    return (
                        channel.channelIndex,
                        mean + channelLabelScoreAdjustment(channel.label),
                        mean
                    )
                }
                .sorted {
                    if $0.1 == $1.1 {
                        return $0.2 > $1.2
                    }
                    return $0.1 > $1.1
                }
                .first?
                .0
        }

        report.recommendedTrack = report.tracks
            .compactMap { track -> (Int, Double)? in
                guard let mean = track.meanVolumeDB else { return nil }
                return (track.audioPosition, mean)
            }
            .sorted { $0.1 > $1.1 }
            .first?
            .0
        return report
    }

    private static func channelLabel(file: URL, channelIndex: Int) -> String {
        guard
            let handle = try? FileHandle(forReadingFrom: file)
        else {
            return ""
        }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 262_144)
        let content = String(data: data, encoding: .isoLatin1) ?? ""
        let exactCandidates = [
            "sTRK\(channelIndex + 1)=",
            "TRK\(channelIndex + 1)="
        ]
        for marker in exactCandidates {
            guard let range = content.range(of: marker) else { continue }
            return metadataValue(after: range, in: content)
        }

        let pattern = #"s?TRK(\d+)="#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }
        let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
        let labels = matches
            .compactMap { match -> (Int, String)? in
                guard
                    let numberRange = Range(match.range(at: 1), in: content),
                    let fullRange = Range(match.range(at: 0), in: content),
                    let number = Int(content[numberRange])
                else {
                    return nil
                }
                let value = metadataValue(after: fullRange, in: content)
                return value.isEmpty ? nil : (number, value)
            }
            .sorted { $0.0 < $1.0 }
            .map(\.1)

        if channelIndex < labels.count {
            return labels[channelIndex]
        }
        return ""
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

    private static func readAudioDiagnostics(file: URL, ffprobePath: String) -> AudioDiagnosticReport {
        var report = AudioDiagnosticReport(fileName: file.lastPathComponent)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobePath)
        process.arguments = [
            "-v", "error",
            "-select_streams", "a",
            "-show_entries", "stream=index,codec_name,channels,sample_rate",
            "-of", "csv=p=0",
            file.path
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return report
        }

        guard process.terminationStatus == 0 else { return report }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        report.tracks = output
            .split(whereSeparator: \.isNewline)
            .enumerated()
            .compactMap { line -> AudioTrackDiagnostic? in
                let parts = line.element.split(separator: ",").map(String.init)
                guard parts.count >= 4, let index = Int(parts[0]) else { return nil }
                return AudioTrackDiagnostic(
                    streamIndex: index,
                    audioPosition: line.offset,
                    codec: parts[1],
                    channels: Int(parts[3]) ?? 0,
                    sampleRate: parts[2],
                    meanVolumeDB: nil
                )
            }
        return report
    }

    private static func meanVolumeDB(file: URL, ffmpegPath: String, audioTrackIndex: Int) -> Double? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-hide_banner",
            "-t", "10",
            "-i", file.path,
            "-map", "0:a:\(audioTrackIndex)",
            "-af", "volumedetect",
            "-f", "null",
            "-"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let pattern = #"mean_volume:\s*(-?\d+(?:\.\d+)?)\s*dB"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output) else {
            return nil
        }
        return Double(output[range])
    }

    private static func channelMeanVolumeDB(file: URL, ffmpegPath: String, channelIndex: Int) -> Double? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-hide_banner",
            "-t", "10",
            "-i", file.path,
            "-af", "pan=mono|c0=c\(channelIndex),volumedetect",
            "-f", "null",
            "-"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let pattern = #"mean_volume:\s*(-?\d+(?:\.\d+)?)\s*dB"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output) else {
            return nil
        }
        return Double(output[range])
    }
}
