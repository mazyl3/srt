import Foundation
import SwiftUI

enum WorkMode: String, CaseIterable, Identifiable {
    case minimal = "Minimal"
    case simple = "Paprasta"
    case power = "Patyrusiems"
    case advanced = "Advanced"

    var id: String { rawValue }
}

enum PerformanceMode: String, CaseIterable, Identifiable {
    case safe = "Saugiai"
    case recommended = "Rekomenduojama"
    case maximum = "Iki galo"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .safe:
            return "mažiau kaitimo"
        case .recommended:
            return "geras balansas"
        case .maximum:
            return "maksimali apkrova"
        }
    }

    var explanation: String {
        switch self {
        case .safe:
            return "Naudoja mažiau CPU thread'ų ir apdoroja atsargiau. Tinka, kai nori dirbti su kompiuteriu tuo pačiu metu."
        case .recommended:
            return "Naudoja šio Mac specifikacijoms parinktą balansą tarp greičio, RAM ir stabilumo."
        case .maximum:
            return "Spaudžia hardware stipriau: daugiau thread'ų ir agresyvesnis paralelumas. Mac gali kaisti, ventiliatoriai gali kilti, baterija seks greičiau."
        }
    }
}

enum SubtitleOutputMode: String, CaseIterable, Identifiable {
    case lithuanianOnly = "LT"
    case englishOnly = "EN"
    case lithuanianAndEnglish = "LT + EN"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .lithuanianOnly:
            return "tik lietuviškai"
        case .englishOnly:
            return "tik angliškai"
        case .lithuanianAndEnglish:
            return "abu failai"
        }
    }

    var explanation: String {
        switch self {
        case .lithuanianOnly:
            return "Sukuria vieną lietuvišką SRT failą."
        case .englishOnly:
            return "Sukuria tik anglišką SRT vertimą. Patogu, kai lietuviško failo nereikia."
        case .lithuanianAndEnglish:
            return "Pirmiausia sukuria lietuvišką SRT, tada papildomai sukuria anglišką SRT vertimą."
        }
    }
}

enum VideoExportMode: String, CaseIterable, Identifiable {
    case srtOnly = "SRT"
    case videoOnly = "Track MP4"
    case srtAndVideo = "SRT + Track"
    case burnedVideoOnly = "Burned MP4"
    case srtAndBurnedVideo = "SRT + Burned"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .srtOnly:
            return "tik failas"
        case .videoOnly:
            return "įjungiamas"
        case .srtAndVideo:
            return "track + srt"
        case .burnedVideoOnly:
            return "įkeptas"
        case .srtAndBurnedVideo:
            return "burn + srt"
        }
    }

    var explanation: String {
        switch self {
        case .srtOnly:
            return "Sukuria redagavimo programoms tinkamą SRT failą. Originalus video neliečiamas."
        case .videoOnly:
            return "Sukuria naują MP4 kopiją su vidiniu subtitle track. Subtitrus grotuve galima įjungti arba išjungti."
        case .srtAndVideo:
            return "Sukuria ir SRT failą, ir naują MP4 video kopiją su vidiniu subtitle track."
        case .burnedVideoOnly:
            return "Sukuria naują MP4, kuriame subtitrai įkepti tiesiai į video vaizdą. Tam ffmpeg turi palaikyti subtitles/libass filtrą."
        case .srtAndBurnedVideo:
            return "Sukuria SRT failą ir naują MP4, kuriame subtitrai įkepti tiesiai į video vaizdą."
        }
    }

    var createsVideo: Bool {
        self != .srtOnly
    }

    var keepsSRTOutput: Bool {
        switch self {
        case .srtOnly, .srtAndVideo, .srtAndBurnedVideo:
            return true
        case .videoOnly, .burnedVideoOnly:
            return false
        }
    }

    var burnsSubtitlesIntoVideo: Bool {
        switch self {
        case .burnedVideoOnly, .srtAndBurnedVideo:
            return true
        case .srtOnly, .videoOnly, .srtAndVideo:
            return false
        }
    }
}

enum AudioInputMode: String, CaseIterable, Identifiable {
    case autoBestTrack = "Auto best"
    case firstTrack = "1 track"
    case manualTrack = "Manual"
    case mixAllTracks = "Mix all"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .autoBestTrack:
            return "parenka"
        case .firstTrack:
            return "pirmas"
        case .manualTrack:
            return "rankinis"
        case .mixAllTracks:
            return "visi"
        }
    }

    var explanation: String {
        switch self {
        case .autoBestTrack:
            return "Greitai patikrina audio trackus ir parenka stipriausią kalbos signalą Whisper atpažinimui. Geriausias numatytas režimas kamerų failams."
        case .firstTrack:
            return "Naudoja tik pirmą audio tracką. Tinka paprastiems video arba kai pirmas trackas tikrai yra pagrindinis mikrofonas."
        case .manualTrack:
            return "Naudoja konkretų tracką, kurį pasirenki audio diagnostikos lentelėje. Naudok, kai žinai, kuriame mikrofone kalba švariausia."
        case .mixAllTracks:
            return "Sumaišo visus audio trackus į vieną kalbos takelį. Tai geriau kamerų failams su keliais mono mikrofonais, kai neaišku, kuriame tracke yra geriausia kalba."
        }
    }
}

enum BurnedSubtitleStyle: String, CaseIterable, Identifiable {
    case clean = "Clean"
    case bold = "Bold"
    case highContrast = "High Contrast"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .clean:
            return "tvarkingas"
        case .bold:
            return "social"
        case .highContrast:
            return "ryškus"
        }
    }

    var ffmpegForceStyle: String {
        switch self {
        case .clean:
            return "FontName=Helvetica,FontSize=24,PrimaryColour=&H00FFFFFF,OutlineColour=&HAA000000,BorderStyle=1,Outline=2,Shadow=0,Alignment=2,MarginV=54"
        case .bold:
            return "FontName=Helvetica Bold,FontSize=30,PrimaryColour=&H00FFFFFF,OutlineColour=&HDD111111,BackColour=&H70000000,BorderStyle=3,Outline=1,Shadow=0,Alignment=2,MarginV=70"
        case .highContrast:
            return "FontName=Helvetica Bold,FontSize=28,PrimaryColour=&H0000FFFF,OutlineColour=&HFF000000,BorderStyle=1,Outline=3,Shadow=1,Alignment=2,MarginV=64"
        }
    }
}

enum JobPhase: String {
    case idle = "Pasirink failą"
    case validating = "Tikrinama, ar viskas paruošta"
    case copying = "Kuriama saugi kopija"
    case converting = "Ruošiamas garsas"
    case transcribing = "Atpažįstama kalba"
    case finishing = "Kuriamas SRT failas"
    case renderingVideo = "Kuriamas video su subtitrais"
    case complete = "Baigta"
    case failed = "Klaida"
    case cancelled = "Nutraukta"

    var stepIndex: Int {
        switch self {
        case .idle, .validating:
            return 0
        case .copying:
            return 1
        case .converting:
            return 2
        case .transcribing:
            return 3
        case .finishing, .renderingVideo, .complete:
            return 4
        case .failed, .cancelled:
            return 0
        }
    }
}

enum DependencyState: Equatable {
    case checking
    case ready(String)
    case missing(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .checking:
            return "Tikrinama"
        case .ready(let path):
            return path
        case .missing(let message):
            return message
        }
    }
}

struct DependencyReport: Equatable {
    var ffmpeg: DependencyState = .checking
    var whisper: DependencyState = .checking
    var model: DependencyState = .checking
}

struct AppSettings {
    var languageCode = "lt"
    var autoDetectLanguage = false
    var subtitleOutputMode: SubtitleOutputMode = .lithuanianOnly
    var videoExportMode: VideoExportMode = .srtOnly
    var burnedSubtitleStyle: BurnedSubtitleStyle = .clean
    var keepWorkingFiles = false
    var audioInputMode: AudioInputMode = .autoBestTrack
    var manualAudioTrackPosition: Int?
    var manualAudioChannelIndex: Int?
    var enhanceSpeechAudio = true
    var useWhisperLanguagePrompt = true
    var splitOnWord = true
    var normalizePunctuation = true
    var formatDialogueLines = true
    var splitOnSentenceBoundaries = true
    var removeASRArtifacts = true
    var suppressNonSpeechTokens = true
    var useGPU = true
    var maxSegmentLength = 42
    var maxSubtitleLineLength = 42
    var maxSubtitleLines = 2
    var maxCharactersPerSecond = 20.0
    var minimumSubtitleDuration = 1.0
    var maximumSubtitleDuration = 7.0
    var minimumSubtitleGap = 0.10
    var beamSize = 5
    var bestOf = 5
    var noSpeechThreshold = 0.60
    var threadCount = max(2, ProcessInfo.processInfo.processorCount - 2)
    var outputFolder: URL?
    var modelPath: String = AppPaths.defaultModelURL.path
    var ffmpegPath: String = "auto"
    var whisperPath: String = "auto"
}

struct PipelineResult: Equatable {
    let primaryFile: URL
    let srtFiles: [URL]
    let transcriptFiles: [URL]
    let vttFiles: [URL]
    let videoFile: URL?

    var allFiles: [URL] {
        srtFiles + transcriptFiles + vttFiles + [videoFile].compactMap { $0 }
    }
}

struct AppUpdate: Codable, Equatable {
    let version: String
    let build: String?
    let downloadURL: URL
    let releaseNotes: String?
    let minimumSystemVersion: String?
}

struct GitHubContentsManifest: Codable {
    let content: String
    let encoding: String?
}

struct ASRQualityReport: Equatable {
    var files: [ASRQualityFileReport] = []

    var totalBlocks: Int {
        files.map(\.blocks).reduce(0, +)
    }

    var issueCount: Int {
        files.map(\.issueCount).reduce(0, +)
    }

    var statusTitle: String {
        issueCount == 0 ? "ASR tekstas atrodo patikimas" : "ASR tekstą reikia peržiūrėti"
    }

    var statusDetail: String {
        if files.isEmpty {
            return "ASR teksto patikrai nėra SRT failų."
        }
        if issueCount == 0 {
            return "\(totalBlocks) blokai patikrinti. Hallucination ar kartojimosi signalų nerasta."
        }
        return "\(totalBlocks) blokai patikrinti. Rasta \(issueCount) transkripcijos kokybės signalų."
    }
}

struct ASRQualityFileReport: Identifiable, Equatable {
    let id = UUID()
    let fileName: String
    var blocks = 0
    var textCharacters = 0
    var duration = 0.0
    var repeatedText = 0
    var repeatedPhrases = 0
    var promptLeakage = 0
    var lowTextDensity = 0
    var highTextDensity = 0
    var issues: [ASRQualityIssue] = []

    var issueCount: Int {
        repeatedText + repeatedPhrases + promptLeakage + lowTextDensity + highTextDensity
    }

    var textDensityLabel: String {
        guard duration > 0 else { return "n/a" }
        return String(format: "%.1f chars/s", Double(textCharacters) / duration)
    }
}

struct ASRQualityIssue: Identifiable, Equatable {
    let id = UUID()
    let kind: Kind
    let timecode: String
    let message: String
    let textPreview: String

    enum Kind: String, Equatable {
        case repeatText = "Kartojasi"
        case repeatPhrase = "Frazė"
        case promptLeak = "Prompt"
        case lowDensity = "Mažai teksto"
        case highDensity = "Tankis"
    }
}

struct SRTQAReport: Equatable {
    var files: [SRTQAFileReport] = []

    var totalBlocks: Int {
        files.map(\.blocks).reduce(0, +)
    }

    var issueCount: Int {
        files.map(\.issueCount).reduce(0, +)
    }

    var statusTitle: String {
        issueCount == 0 ? "SRT kokybė gera" : "SRT reikia peržiūros"
    }

    var statusDetail: String {
        if files.isEmpty {
            return "SRT failų patikrai nėra."
        }
        if issueCount == 0 {
            return "\(totalBlocks) blokai patikrinti. Kritinių kokybės problemų nerasta."
        }
        return "\(totalBlocks) blokai patikrinti. Rasta \(issueCount) kokybės signalų."
    }
}

struct SRTQAFileReport: Identifiable, Equatable {
    let id = UUID()
    let fileName: String
    var blocks = 0
    var invalidBlocks = 0
    var overlaps = 0
    var longLines = 0
    var tooManyLines = 0
    var tooFast = 0
    var tooShort = 0
    var tooLong = 0
    var issues: [SRTQAIssue] = []

    var issueCount: Int {
        invalidBlocks + overlaps + longLines + tooManyLines + tooFast + tooShort + tooLong
    }
}

struct SRTQAIssue: Identifiable, Equatable {
    let id = UUID()
    let kind: Kind
    let timecode: String
    let message: String
    let textPreview: String

    enum Kind: String, Equatable {
        case overlap = "Overlap"
        case tooFast = "CPS"
        case longLine = "Ilga eilutė"
        case tooManyLines = "Per daug eilučių"
        case duration = "Trukmė"
        case invalid = "Blogas blokas"
    }
}

struct AudioDiagnosticReport: Equatable {
    let fileName: String
    var tracks: [AudioTrackDiagnostic] = []
    var recommendedTrack: Int?
    var channels: [AudioChannelDiagnostic] = []
    var recommendedChannel: Int?

    var title: String {
        if tracks.count == 1, channels.count > 1 {
            return "\(channels.count) WAV kanalai"
        }
        if tracks.isEmpty {
            return "Audio trackų nerasta"
        }
        if tracks.count == 1 {
            return "1 audio trackas"
        }
        return "\(tracks.count) audio trackai"
    }

    var detail: String {
        if let recommendedChannel {
            return "Auto best rekomenduoja Ch \(recommendedChannel + 1)."
        }
        if let recommendedTrack {
            return "Auto best rekomenduoja Track \(recommendedTrack + 1)."
        }
        return "Naudok Mix all arba pasirink pirmą tracką."
    }
}

struct AudioChannelDiagnostic: Identifiable, Equatable {
    let id = UUID()
    let streamIndex: Int
    let channelIndex: Int
    var label: String = ""
    var meanVolumeDB: Double?

    var displayName: String {
        label.isEmpty ? "Ch \(channelIndex + 1)" : "Ch \(channelIndex + 1) \(label)"
    }

    var meanVolumeLabel: String {
        guard let meanVolumeDB else { return "n/a" }
        return String(format: "%.1f dB", meanVolumeDB)
    }
}

struct AudioTrackDiagnostic: Identifiable, Equatable {
    let id = UUID()
    let streamIndex: Int
    let audioPosition: Int
    var codec: String = "audio"
    var channels: Int = 0
    var sampleRate: String = ""
    var meanVolumeDB: Double?

    var meanVolumeLabel: String {
        guard let meanVolumeDB else { return "n/a" }
        return String(format: "%.1f dB", meanVolumeDB)
    }
}

enum JobState: String {
    case waiting = "Laukia"
    case running = "Vyksta"
    case complete = "Baigta"
    case failed = "Klaida"
    case cancelled = "Nutraukta"
}

struct TranscriptionJob: Identifiable, Equatable {
    let id = UUID()
    let inputFile: URL
    var resultFile: URL?
    var srtFiles: [URL] = []
    var transcriptFiles: [URL] = []
    var vttFiles: [URL] = []
    var phase: JobPhase = .idle
    var state: JobState = .waiting
    var progress: Double = 0
    var statusMessage = "Laukia eilėje."
    var logs: [LogEntry] = []

    var displayName: String {
        inputFile.lastPathComponent
    }
}

struct DeviceProfile: Equatable {
    let processorName: String
    let cpuCores: Int
    let activeCores: Int
    let memoryGB: Int
    let osVersion: String
    let tier: String
    let recommendedParallelJobs: Int
    let recommendedThreadsPerJob: Int
    let recommendation: String
}

struct WorkflowStep: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let systemImage: String
}

let defaultWorkflowSteps = [
    WorkflowStep(title: "Failas", detail: "Video/audio", systemImage: "doc.badge.plus"),
    WorkflowStep(title: "Kopija", detail: "Originalas saugus", systemImage: "doc.on.doc"),
    WorkflowStep(title: "Garsas", detail: "Tinkamas formatas", systemImage: "waveform"),
    WorkflowStep(title: "Atpažinimas", detail: "Whisper", systemImage: "brain.head.profile"),
    WorkflowStep(title: "SRT", detail: "Subtitrai", systemImage: "captions.bubble")
]

struct LogEntry: Identifiable, Equatable {
    let id = UUID()
    let date = Date()
    let level: LogLevel
    let message: String

    enum LogLevel: String {
        case info = "INFO"
        case command = "CMD"
        case warning = "WARN"
        case error = "ERROR"
        case success = "OK"

        var color: Color {
            switch self {
            case .info:
                return .secondary
            case .command:
                return .blue
            case .warning:
                return .orange
            case .error:
                return .red
            case .success:
                return .green
            }
        }
    }
}

enum PipelineError: LocalizedError {
    case noInputFile
    case missingDependency(String)
    case commandFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noInputFile:
            return "Pasirink audio arba video failą."
        case .missingDependency(let name):
            return "Trūksta būtino įrankio: \(name)."
        case .commandFailed(let message):
            return message
        case .cancelled:
            return "Darbas nutrauktas."
        }
    }
}

enum AppPaths {
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("SRT Forge", isDirectory: true)
    }

    static var jobsDirectory: URL {
        supportDirectory.appendingPathComponent("Jobs", isDirectory: true)
    }

    static var modelsDirectory: URL {
        supportDirectory.appendingPathComponent("Models", isDirectory: true)
    }

    static var defaultModelURL: URL {
        modelsDirectory.appendingPathComponent("ggml-large-v3.bin")
    }
}
