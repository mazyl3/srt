import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            VisualBackdrop()

            VStack(spacing: 0) {
                TitleBar()
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                    .padding(.bottom, 10)

                CommandBar()
                    .padding(.horizontal, 22)
                    .padding(.bottom, 16)

                HStack(alignment: .top, spacing: 18) {
                    LeftPanel()
                        .frame(width: 370)

                    MainPanel()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
            }
        }
        .foregroundStyle(.white)
    }
}

private struct VisualBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.028, green: 0.035, blue: 0.055),
                    Color(red: 0.050, green: 0.045, blue: 0.090),
                    Color(red: 0.026, green: 0.080, blue: 0.088)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LiquidBlob(color: .pink, width: 420, height: 310, x: -130, y: -120, opacity: 0.26)
            LiquidBlob(color: .cyan, width: 520, height: 360, x: 820, y: -80, opacity: 0.22)
            LiquidBlob(color: .orange, width: 420, height: 340, x: 980, y: 560, opacity: 0.18)
            LiquidBlob(color: .green, width: 390, height: 300, x: 130, y: 660, opacity: 0.16)

            Canvas { context, size in
                var path = Path()
                let spacing: CGFloat = 38
                var x: CGFloat = 0
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += spacing
                }

                var y: CGFloat = 0
                while y < size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += spacing
                }

                context.stroke(path, with: .color(.white.opacity(0.030)), lineWidth: 1)
            }

            LinearGradient(
                colors: [
                    Color.pink.opacity(0.09),
                    Color.clear,
                    Color.cyan.opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

private struct LiquidBlob: View {
    let color: Color
    let width: CGFloat
    let height: CGFloat
    let x: CGFloat
    let y: CGFloat
    let opacity: Double

    var body: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [color.opacity(opacity), color.opacity(opacity * 0.26), .clear],
                    center: .center,
                    startRadius: 20,
                    endRadius: max(width, height) / 2
                )
            )
            .frame(width: width, height: height)
            .blur(radius: 34)
            .offset(x: x, y: y)
    }
}

private struct TitleBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(colors: [.cyan, .green], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "captions.bubble.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.black.opacity(0.82))
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 5) {
                    Text("SRT Forge")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Lokali video ir audio transkripcija į SRT su Whisper large-v3")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                }
            }

            Spacer()

            ReadinessBadge()

            Button {
                model.refreshDependencies()
            } label: {
                Label("Patikrinti", systemImage: "arrow.clockwise")
            }
            .buttonStyle(SecondaryButtonStyle())
            .help("Patikrina, ar kompiuteryje yra ffmpeg, Whisper variklis ir modelio failas.")
        }
    }
}

private struct CommandBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Darbo režimas")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.50))

                WorkModeSelector()
                .frame(width: 400)
            }

            Divider()
                .frame(height: 36)
                .overlay(Color.white.opacity(0.18))

            CommandPill(
                title: model.selectedFile?.lastPathComponent ?? "Failas nepasirinktas",
                subtitle: model.mode == .advanced ? "Advanced režime gali rinktis kelis failus" : "Originalas nebus keičiamas",
                icon: "doc.badge.plus",
                tint: model.selectedFile == nil ? .orange : .green
            )

            CommandPill(
                title: model.dependencies.model.isReady ? "large-v3 paruoštas" : "Trūksta large-v3",
                subtitle: "Pagrindinis kokybės modelis",
                icon: "brain.head.profile",
                tint: model.dependencies.model.isReady ? .green : .orange
            )

            Spacer(minLength: 8)

            Button {
                model.selectInputFile()
            } label: {
                Label(model.mode == .advanced ? "Pasirinkti failus" : "Pasirinkti failą", systemImage: "plus")
            }
            .buttonStyle(SecondaryButtonStyle())

            Button {
                model.start()
            } label: {
                Label(model.isRunning ? "Kuriama" : model.primaryActionTitle, systemImage: model.primaryActionSystemImage)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!model.canStart)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.09, green: 0.10, blue: 0.15).opacity(0.82))
                .overlay(
                    LinearGradient(
                        colors: [Color.white.opacity(0.16), Color.cyan.opacity(0.08), Color.pink.opacity(0.07)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                )
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                .shadow(color: Color.cyan.opacity(0.14), radius: 18, x: 0, y: 10)
        )
    }
}

private struct WorkModeSelector: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(WorkMode.allCases) { mode in
                Button {
                    model.applyWorkMode(mode)
                } label: {
                    VStack(spacing: 2) {
                        Text(mode.rawValue)
                            .font(.system(size: 12, weight: .bold))
                        Text(modeHint(mode))
                            .font(.system(size: 9, weight: .semibold))
                            .opacity(0.72)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                }
                .buttonStyle(ModeButtonStyle(isSelected: model.mode == mode, tint: tint(mode)))
            }
        }
    }

    private func modeHint(_ mode: WorkMode) -> String {
        switch mode {
        case .minimal:
            return "bare"
        case .simple:
            return "greita"
        case .power:
            return "kontrolė"
        case .advanced:
            return "batch"
        }
    }

    private func tint(_ mode: WorkMode) -> Color {
        switch mode {
        case .minimal:
            return .pink
        case .simple:
            return .cyan
        case .power:
            return .green
        case .advanced:
            return .orange
        }
    }
}

private struct CommandPill: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 150, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.20))
                .overlay(RoundedRectangle(cornerRadius: 14).fill(tint.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(tint.opacity(0.24), lineWidth: 1))
        )
    }
}

private struct LeftPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                DropZone()

                ReadinessCard()

                if model.mode != .minimal {
                    OfflineCard()
                    UpdateCard()
                }

                Button {
                    model.prepareEverything()
                } label: {
                    Label(model.isPreparingTools ? "Ruošiama programa" : "Internetinis paruošimas", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.isRunning || model.isDownloadingModel || model.isPreparingTools)
                .help("Pirmo setupo veiksmas: įdiegia įrankius ir atsisiunčia modelį. Po to transkripcija veikia lokaliai be interneto.")

                if model.mode != .minimal {
                    DependencyCard(
                        title: "Konvertavimo įrankis",
                        subtitle: "ffmpeg paruošia garsą Whisper modeliui",
                        state: model.dependencies.ffmpeg,
                        actionTitle: "Parinkti",
                        action: model.selectFFmpegBinary
                    )

                    DependencyCard(
                        title: "Kalbos atpažinimo variklis",
                        subtitle: "whisper.cpp transkribuoja lokaliai Mac kompiuteryje",
                        state: model.dependencies.whisper,
                        actionTitle: "Parinkti",
                        action: model.selectWhisperBinary
                    )

                    DependencyCard(
                        title: "Whisper large-v3 modelis",
                        subtitle: "Stipriausias pilnas modelis geriausiai kokybei",
                        state: model.dependencies.model,
                        actionTitle: "Parinkti",
                        action: model.selectModelFile
                    )

                    Button {
                        model.downloadLargeV3Model()
                    } label: {
                        Label(model.isDownloadingModel ? "Siunčiamas modelis" : "Atsisiųsti large-v3 modelį", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.isRunning || model.isDownloadingModel || model.isPreparingTools)
                    .help("Reikia tik vieną kartą arba kai modelio failo nėra šiame Mac. Pats SRT kūrimas interneto nenaudoja.")

                    Button {
                        model.openModelsFolder()
                    } label: {
                        Label("Atidaryti modelių aplanką", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .scrollIndicators(.visible)
    }
}

private struct MainPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            if model.mode == .minimal {
                VStack(spacing: 14) {
                    MinimalModePanel()
                }
            } else {
                VStack(spacing: 14) {
                    OverviewPanel()

                    StatusPanel()

                    if model.qualityReport != nil {
                        SRTQualityPanel()
                    }

                    WorkflowProgressPanel()

                    if model.mode == .advanced {
                        AdvancedModePanel()
                    } else if model.mode == .power {
                        PowerSettingsPanel()
                    } else {
                        SimpleSettingsPanel()
                    }

                    LogPanel()
                }
            }
        }
        .scrollIndicators(.visible)
    }
}

private struct MinimalModePanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                MinimalTile(title: "Išvestis", value: "LT SRT", detail: "vienas failas", icon: "captions.bubble", tint: .pink)
                MinimalTile(title: "Kalba", value: "Lietuvių", detail: "be papildomų pasirinkimų", icon: "text.bubble", tint: .cyan)
                MinimalTile(title: "Tvarkymas", value: "Auto", detail: "skyryba + dialogai", icon: "sparkles", tint: .green)
            }

            StatusPanel()

            VStack(alignment: .leading, spacing: 9) {
                Label("Minimal režimas", systemImage: "bolt.circle")
                    .font(.system(size: 17, weight: .bold))
                Text("Bare power tool: pasirink vieną failą ir spausk „Kurti SRT“. Jokių batch, gilių nustatymų ar techninių panelių.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(panelBackground)
        }
    }
}

private struct MinimalTile: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(tint.opacity(0.16))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.48))
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(detail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .background(panelBackground)
    }
}

private struct OverviewPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            OverviewTile(
                title: "Failas",
                value: model.selectedFile == nil ? "Trūksta" : "Parinktas",
                detail: model.selectedFile?.lastPathComponent ?? "Pasirink video arba audio",
                icon: "film.stack",
                tint: model.selectedFile == nil ? .orange : .green
            )
            OverviewTile(
                title: "Įrankiai",
                value: "\(model.readinessScore)/4",
                detail: model.canStart ? "Viskas paruošta" : "Reikia paruošimo",
                icon: "checklist.checked",
                tint: model.canStart ? .green : .orange
            )
            OverviewTile(
                title: "Našumas",
                value: model.mode == .advanced ? "\(model.maxParallelJobs)x" : "\(model.settings.threadCount)t",
                detail: model.mode == .advanced ? "Paralelūs darbai" : "Whisper thread'ai",
                icon: "speedometer",
                tint: .cyan
            )
            OverviewTile(
                title: "Rezultatas",
                value: model.resultFile == nil ? model.settings.videoExportMode.rawValue : "Gautas",
                detail: model.resultFile?.lastPathComponent ?? "Bus sukurtas atskiras failas",
                icon: "captions.bubble",
                tint: model.resultFile == nil ? .white.opacity(0.72) : .green
            )
        }
    }
}

private struct OverviewTile: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(0.16))
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .background(panelBackground)
    }
}

private struct ReadinessBadge: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.canStart ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(model.canStart ? "Paruošta darbui" : "Reikia paruošimo")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.84))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.08))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.11), lineWidth: 1))
        )
    }
}

private struct ReadinessCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Paruošimas")
                        .font(.system(size: 15, weight: .bold))
                    Text("\(model.readinessScore) iš \(model.readinessTotal) būtinų dalių paruošta")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                }
                Spacer()
                Text("\(model.readinessScore)/\(model.readinessTotal)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(model.canStart ? .green : .orange)
            }

            SegmentedReadinessBar(score: model.readinessScore, total: model.readinessTotal)

            VStack(spacing: 7) {
                ReadinessRow(title: "Pasirinktas failas", ready: model.selectedFile != nil)
                ReadinessRow(title: "Garsui paruošti", ready: model.dependencies.ffmpeg.isReady)
                ReadinessRow(title: "Kalbai atpažinti", ready: model.dependencies.whisper.isReady)
                ReadinessRow(title: "large-v3 modelis", ready: model.dependencies.model.isReady)
                if model.settings.videoExportMode != .srtOnly {
                    ReadinessRow(title: "MP4 eksportui video failas", ready: model.videoExportInputIsValid)
                }
            }

            if let blocker = model.primaryBlocker {
                Text(blocker)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(panelBackground)
    }
}

private struct OfflineCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill((model.offlineReady ? Color.green : Color.orange).opacity(0.18))
                    Image(systemName: model.offlineReady ? "wifi.slash" : "icloud.and.arrow.down")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(model.offlineReady ? .green : .orange)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(model.offlineReady ? "Offline režimas paruoštas" : "Offline režimui dar trūksta dalių")
                            .font(.system(size: 14, weight: .bold))
                        HelpTip(
                            title: "Darbas be interneto",
                            message: "Internetas reikalingas tik pirmam įrankių ar modelio atsisiuntimui. Kai ffmpeg, whisper.cpp ir large-v3 modelis yra šiame Mac, SRT kūrimas ir LT/EN vertimas vyksta lokaliai."
                        )
                    }
                    Text(model.offlineStatusMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 7) {
                OfflinePart(title: "ffmpeg", ready: model.dependencies.ffmpeg.isReady)
                OfflinePart(title: "Whisper", ready: model.dependencies.whisper.isReady)
                OfflinePart(title: "large-v3", ready: model.dependencies.model.isReady)
            }
        }
        .padding(14)
        .background(panelBackground)
    }
}

private struct OfflinePart: View {
    let title: String
    let ready: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: ready ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(ready ? .green : .orange)
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill((ready ? Color.green : Color.orange).opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder((ready ? Color.green : Color.orange).opacity(0.20), lineWidth: 1))
        )
    }
}

private struct UpdateCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.cyan.opacity(0.16))
                    Image(systemName: "arrow.down.app.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.cyan)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text("Atnaujinimai")
                            .font(.system(size: 14, weight: .bold))
                        HelpTip(
                            title: "OTA atnaujinimai",
                            message: "Saugus pirmas variantas: programa patikrina mažą version.json manifestą ir atidaro naujo DMG atsisiuntimo nuorodą. Ji pati neperrašo veikiančio appo."
                        )
                    }
                    Text("Versija \(model.appVersion)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.72))
                    Text(model.updateStatusMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.56))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Button {
                    model.checkForUpdates()
                } label: {
                    Label(model.isCheckingForUpdates ? "Tikrinama" : "Tikrinti", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(model.isCheckingForUpdates)

                Button {
                    model.openAvailableUpdate()
                } label: {
                    Label("Atsisiųsti", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.availableUpdate == nil)
            }
        }
        .padding(14)
        .background(panelBackground)
    }
}

private struct SegmentedReadinessBar: View {
    let score: Int
    let total: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index < score ? Color.green.opacity(0.95) : Color.white.opacity(0.12))
                    .frame(height: 7)
            }
        }
        .accessibilityLabel("\(score) iš \(total) dalių paruošta")
    }
}

private struct ReadinessRow: View {
    let title: String
    let ready: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: ready ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ready ? .green : .white.opacity(0.35))
                .frame(width: 16)
            Text(title)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Text(ready ? "OK" : "Trūksta")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(ready ? .green : .white.opacity(0.42))
        }
    }
}

private struct WorkflowProgressPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(defaultWorkflowSteps.enumerated()), id: \.element.id) { index, step in
                WorkflowStepView(
                    step: step,
                    index: index,
                    activeIndex: model.phase.stepIndex,
                    isComplete: model.phase == .complete || index < model.phase.stepIndex
                )

                if index < defaultWorkflowSteps.count - 1 {
                    Rectangle()
                        .fill(index < model.phase.stepIndex ? Color.green.opacity(0.75) : Color.white.opacity(0.12))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .background(panelBackground)
    }
}

private struct WorkflowStepView: View {
    let step: WorkflowStep
    let index: Int
    let activeIndex: Int
    let isComplete: Bool

    private var isActive: Bool {
        index == activeIndex && !isComplete
    }

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(circleColor)
                    .frame(width: 34, height: 34)
                Image(systemName: isComplete ? "checkmark" : step.systemImage)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isComplete ? .black : .white)
            }
            Text(step.title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(isActive || isComplete ? 0.9 : 0.46))
            Text(step.detail)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(1)
        }
        .frame(width: 72)
    }

    private var circleColor: Color {
        if isComplete { return .green }
        if isActive { return .cyan.opacity(0.85) }
        return .white.opacity(0.10)
    }
}

private struct DropZone: View {
    @EnvironmentObject private var model: AppModel
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 74, height: 74)

                Image(systemName: "waveform.and.arrow.down")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.cyan)
            }

            VStack(spacing: 7) {
                Text(model.selectedFile?.lastPathComponent ?? "Įmesk video arba audio failą")
                    .font(.system(size: 18, weight: .bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text("Originalas nebus keičiamas. Programa sukurs darbo kopiją ir atskirą SRT failą.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                model.selectInputFile()
            } label: {
                Label(model.mode == .advanced ? "Pasirinkti failus" : "Pasirinkti failą", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .help(model.mode == .advanced ? "Pasirink kelis video arba audio failus SRT eilei." : "Pasirink video arba audio failą, iš kurio nori gauti subtitrus.")
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(isTargeted ? 0.22 : 0.16))
                .overlay(RoundedRectangle(cornerRadius: 8).fill(Color.cyan.opacity(isTargeted ? 0.12 : 0.04)))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isTargeted ? Color.cyan : Color.white.opacity(0.13), lineWidth: 1)
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            provider.loadDataRepresentation(forTypeIdentifier: "public.file-url") { data, _ in
                guard
                    let data,
                    let text = String(data: data, encoding: .utf8),
                    let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines))
                else { return }

                DispatchQueue.main.async {
                    model.setInputFile(url)
                }
            }
            return true
        }
    }
}

private struct DependencyCard: View {
    let title: String
    let subtitle: String
    let state: DependencyState
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: state.isReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(state.isReady ? .green : .orange)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                Text(state.label)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Button(actionTitle, action: action)
                .buttonStyle(TinyButtonStyle())
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.18))
                .overlay(RoundedRectangle(cornerRadius: 8).fill(state.isReady ? Color.green.opacity(0.08) : Color.orange.opacity(0.07)))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
                )
        )
    }
}

private struct StatusPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(model.phase.rawValue)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text(model.statusMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                    Text(model.canStart ? "Kitas žingsnis: spausk „Kurti SRT“." : "Kitas žingsnis: sutvarkyk trūkstamą dalį kairėje.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(model.canStart ? .green.opacity(0.9) : .orange.opacity(0.9))
                }

                Spacer()

                ProgressRing(value: model.progress, tint: model.phase == .failed ? .red : .cyan)

                if model.resultFile != nil {
                    Button {
                        model.openResult()
                    } label: {
                        Label("Atidaryti", systemImage: "doc.text")
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button {
                        model.revealAllResults()
                    } label: {
                        Label(model.resultFiles.count > 1 ? "Rodyti visus" : "Rodyti aplanke", systemImage: "folder")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }

            ProgressView(value: model.progress)
                .progressViewStyle(.linear)
                .tint(.cyan)
                .scaleEffect(x: 1, y: 1.4, anchor: .center)

            HStack(spacing: 10) {
                Button {
                    model.start()
                } label: {
                    Label(model.isRunning ? "Kuriama" : model.primaryActionTitle, systemImage: model.primaryActionSystemImage)
                        .frame(width: 178)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!model.canStart)

                Button {
                    model.cancel()
                } label: {
                    Label("Nutraukti", systemImage: "stop.fill")
                        .frame(width: 128)
                }
                .buttonStyle(DangerButtonStyle())
                .disabled(!model.isRunning && !model.isDownloadingModel && !model.isPreparingTools)

                Spacer()

                if !model.canStart, let blocker = model.primaryBlocker {
                    Label(blocker, systemImage: "info.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .frame(maxWidth: 300, alignment: .trailing)
                }

                Text("\(Int(model.progress * 100))%")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.cyan)
            }
        }
        .padding(18)
        .background(panelBackground)
    }
}

private struct ProgressRing: View {
    let value: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: 8)
            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int(value * 100))")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("%")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: 64, height: 64)
        .accessibilityLabel("Progresas \(Int(value * 100)) procentų")
    }
}

private struct SRTQualityPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let report = model.qualityReport {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill((report.issueCount == 0 ? Color.green : Color.orange).opacity(0.16))
                        Image(systemName: report.issueCount == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(report.issueCount == 0 ? .green : .orange)
                    }
                    .frame(width: 42, height: 42)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Text(report.statusTitle)
                                .font(.system(size: 17, weight: .bold))
                            HelpTip(
                                title: "SRT kokybės patikra",
                                message: "Patikrina sugeneruotus SRT failus pagal montavimui svarbias taisykles: laiko persidengimus, skaitymo greitį, eilučių ilgį, eilučių skaičių ir trukmes."
                            )
                        }
                        Text(report.statusDetail)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.58))
                    }

                    Spacer()

                    QualityMetric(title: "Blokai", value: "\(report.totalBlocks)", tint: .cyan)
                    QualityMetric(title: "Signalai", value: "\(report.issueCount)", tint: report.issueCount == 0 ? .green : .orange)
                }

                ForEach(report.files) { file in
                    SRTQualityFileRow(file: file)
                }
            }
            .padding(16)
            .background(panelBackground)
        }
    }
}

private struct SRTQualityFileRow: View {
    let file: SRTQAFileReport

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: file.issueCount == 0 ? "checkmark.circle.fill" : "waveform.badge.exclamationmark")
                    .foregroundStyle(file.issueCount == 0 ? .green : .orange)
                    .frame(width: 22)
                Text(file.fileName)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(file.issueCount == 0 ? "Editor-ready" : "\(file.issueCount) signalai")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(file.issueCount == 0 ? .green : .orange)
            }

            HStack(spacing: 7) {
                QualityChip(title: "Blokai", value: file.blocks, tint: .cyan)
                QualityChip(title: "Overlap", value: file.overlaps, tint: .red)
                QualityChip(title: "CPS", value: file.tooFast, tint: .orange)
                QualityChip(title: "Ilgos eil.", value: file.longLines, tint: .pink)
                QualityChip(title: "Eilutės", value: file.tooManyLines, tint: .purple)
                QualityChip(title: "Trukmės", value: file.tooShort + file.tooLong, tint: .yellow)
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.18))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        )
    }
}

private struct QualityMetric: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.48))
        }
        .frame(width: 70, alignment: .trailing)
    }
}

private struct QualityChip: View {
    let title: String
    let value: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(value == 0 ? Color.green.opacity(0.75) : tint.opacity(0.9))
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.50))
                .lineLimit(1)
            Text("\(value)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(value == 0 ? .white.opacity(0.78) : tint)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.055))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        )
    }
}

private struct SimpleSettingsPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Paprastas režimas")
                        .font(.system(size: 16, weight: .bold))
                    Text("Bazinis valdymas: kalba, išvestis ir vienas failas. Techniniai nustatymai paslėpti.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.56))
                }

                Spacer()

                Toggle("Atpažinti kalbą automatiškai", isOn: $model.settings.autoDetectLanguage)
                    .toggleStyle(.switch)
                    .frame(width: 230)

                LanguagePicker()
                    .disabled(model.settings.autoDetectLanguage)
                    .frame(width: 140)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text("Subtitrų išvestis")
                        .font(.system(size: 12, weight: .bold))
                    HelpTip(title: "Subtitrų išvestis", message: "Pasirink, ar reikia tik lietuviško SRT, tik angliško SRT, ar abiejų failų.")
                }
                SubtitleOutputSelector()
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text("Eksportas")
                        .font(.system(size: 12, weight: .bold))
                    HelpTip(title: "Eksportas", message: "Pasirink, ar reikia tik SRT, video su įdegintais subtitrais, ar abiejų rezultatų.")
                }
                VideoExportSelector()
            }
        }
        .padding(16)
        .background(panelBackground)
    }
}

private struct PowerSettingsPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Nustatymai patyrusiems", systemImage: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Button {
                    model.selectOutputFolder()
                } label: {
                    Label("Kur išsaugoti SRT", systemImage: "folder.badge.plus")
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                SettingBlock(title: "Kalba", help: "Jei žinai kalbą, pasirink ją rankiniu būdu. „Auto“ naudok, kai nesi tikras.") {
                    HStack {
                        Toggle("Auto", isOn: $model.settings.autoDetectLanguage)
                            .toggleStyle(.switch)
                        LanguagePicker()
                            .disabled(model.settings.autoDetectLanguage)
                    }
                }

                SettingBlock(title: "Našumas", help: "Daugiau thread'ų gali būti greičiau. Jei GPU/Metal krenta, programa automatiškai bandys CPU režimą.") {
                    VStack(alignment: .leading) {
                        Stepper("Threads: \(model.settings.threadCount)", value: $model.settings.threadCount, in: 1...max(1, ProcessInfo.processInfo.processorCount))
                        Toggle("Naudoti GPU / Metal", isOn: $model.settings.useGPU)
                    }
                }

                SettingBlock(title: "Garso atpažinimo kokybė", help: "Jei kamera turi kelis audio trackus, pirmas trackas gali būti netinkamas. „Mix all“ sumaišo visus mikrofonus, o kalbos filtrai normalizuoja garsumą ir mažina triukšmą prieš Whisper.") {
                    VStack(alignment: .leading, spacing: 9) {
                        AudioInputSelector()
                        Toggle("Kalbos garso filtrai", isOn: $model.settings.enhanceSpeechAudio)
                        Toggle("Whisper kalbos promptas", isOn: $model.settings.useWhisperLanguagePrompt)
                    }
                }

                SettingBlock(title: "Subtitrų išvestis", help: "Pasirink, kokius SRT failus reikia sukurti: tik lietuvišką, tik anglišką arba abu.") {
                    VStack(alignment: .leading) {
                        SubtitleOutputSelector()
                        Toggle("Palikti darbinius failus", isOn: $model.settings.keepWorkingFiles)
                    }
                }

                SettingBlock(title: "Video eksportas", help: "SRT režimas skirtas montavimo programoms. MP4 režimas sukuria naują video kopiją su vidiniu subtitle track; originalas neperrašomas.") {
                    VideoExportSelector()
                }

                SettingBlock(title: "Subtitrų skaitomumas", help: "Trumpesni segmentai lengviau skaitomi. Programa taip pat gali sutvarkyti dialogo brūkšnius ir sakinių pabaigas.") {
                    VStack(alignment: .leading) {
                        Stepper("Maks. simbolių: \(model.settings.maxSegmentLength)", value: $model.settings.maxSegmentLength, in: 24...96)
                        Toggle("Skaidyti per žodžius", isOn: $model.settings.splitOnWord)
                        Toggle("Skaidyti per sakinius", isOn: $model.settings.splitOnSentenceBoundaries)
                        Toggle("Baigti sakinius skyryba", isOn: $model.settings.normalizePunctuation)
                        Toggle("Tvarkyti dialogo brūkšnius", isOn: $model.settings.formatDialogueLines)
                    }
                }

                SettingBlock(title: "SRT kokybės taisyklės", help: "Profesionaliam SRT: programa taiso persidengiančius laikus, per trumpus/per ilgus blokus, riboja eilutes ir pažymi per greitai skaitomus subtitrus.") {
                    VStack(alignment: .leading, spacing: 7) {
                        Stepper("Eilutės ilgis: \(model.settings.maxSubtitleLineLength)", value: $model.settings.maxSubtitleLineLength, in: 24...56)
                        Stepper("Eilučių bloke: \(model.settings.maxSubtitleLines)", value: $model.settings.maxSubtitleLines, in: 1...3)
                        HStack {
                            Text("CPS")
                            Slider(value: $model.settings.maxCharactersPerSecond, in: 12...28, step: 1)
                            Text("\(Int(model.settings.maxCharactersPerSecond))")
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .frame(width: 28, alignment: .trailing)
                        }
                        HStack {
                            Text("Min")
                            Slider(value: $model.settings.minimumSubtitleDuration, in: 0.6...2.0, step: 0.1)
                            Text(String(format: "%.1fs", model.settings.minimumSubtitleDuration))
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .frame(width: 42, alignment: .trailing)
                        }
                        HStack {
                            Text("Max")
                            Slider(value: $model.settings.maximumSubtitleDuration, in: 3.0...10.0, step: 0.5)
                            Text(String(format: "%.1fs", model.settings.maximumSubtitleDuration))
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .frame(width: 42, alignment: .trailing)
                        }
                        HStack {
                            Text("Tarpas")
                            Slider(value: $model.settings.minimumSubtitleGap, in: 0.02...0.30, step: 0.01)
                            Text("\(Int(model.settings.minimumSubtitleGap * 1000))ms")
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                }

                SettingBlock(title: "Atpažinimo tikslumas", help: "Beam ir best-of didina paiešką. Aukštesnis no-speech slenkstis agresyviau ignoruoja tylą.") {
                    VStack(alignment: .leading) {
                        Stepper("Beam: \(model.settings.beamSize)", value: $model.settings.beamSize, in: 1...10)
                        Stepper("Best-of: \(model.settings.bestOf)", value: $model.settings.bestOf, in: 1...10)
                        HStack {
                            Text("No-speech")
                            Slider(value: $model.settings.noSpeechThreshold, in: 0.1...0.95, step: 0.05)
                            Text(String(format: "%.2f", model.settings.noSpeechThreshold))
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .frame(width: 34, alignment: .trailing)
                        }
                    }
                }

                SettingBlock(title: "Triukšmo valymas", help: "Padeda sumažinti muzikos, triukšmo ir specialių tokenų šiukšles subtitruose.") {
                    Toggle("Slopinti ne kalbos tokenus", isOn: $model.settings.suppressNonSpeechTokens)
                }

                SettingBlock(title: "Išsaugojimas", help: "Jei vieta nepasirinkta, SRT bus sukurtas šalia originalaus failo.") {
                    Text(model.settings.outputFolder?.path ?? "Šalia originalaus failo")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(16)
        .background(panelBackground)
    }
}

private struct AdvancedModePanel: View {
    var body: some View {
        VStack(spacing: 14) {
            DeviceProfilePanel()
            BatchQueuePanel()
            PowerSettingsPanel()
        }
    }
}

private struct DeviceProfilePanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Label("Kompiuterio galios patikra", systemImage: "cpu")
                            .font(.system(size: 17, weight: .bold))
                        HelpTip(
                            title: "Kas yra galios patikra?",
                            message: "Programa pažiūri CPU branduolius, RAM ir macOS versiją. Pagal tai pasiūlo, kiek failų ir kiek thread'ų paleisti, kad Whisper large-v3 dirbtų greitai, bet stabiliai."
                        )
                    }
                    Text(model.performanceWarning)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    model.applyRecommendedPerformance()
                    model.refreshDependencies()
                } label: {
                    Label("Pritaikyti rekomendacijas", systemImage: "speedometer")
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            HStack(spacing: 10) {
                SpecPill(title: "Lygis", value: model.deviceProfile.tier, color: .green)
                SpecPill(title: "CPU", value: "\(model.deviceProfile.activeCores) branduoliai", color: .cyan)
                SpecPill(title: "RAM", value: "\(model.deviceProfile.memoryGB) GB", color: .orange)
                SpecPill(title: "Vienu metu", value: "\(model.deviceProfile.recommendedParallelJobs)", color: .purple)
            }

            PerformanceModeSelector()

            PerformanceBars(profile: model.deviceProfile)

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.deviceProfile.processorName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(model.deviceProfile.osVersion)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                }

                Spacer()

                Stepper(
                    "Paraleliai: \(model.maxParallelJobs)",
                    value: $model.maxParallelJobs,
                    in: 1...max(1, model.maxHardwareParallelJobs)
                )
                .font(.system(size: 12, weight: .medium))
                .frame(width: 190)
            }
        }
        .padding(16)
        .background(panelBackground)
    }
}

private struct PerformanceModeSelector: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PerformanceMode.allCases) { mode in
                Button {
                    model.applyPerformanceMode(mode)
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: icon(mode))
                            .font(.system(size: 14, weight: .bold))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.rawValue)
                                .font(.system(size: 12, weight: .bold))
                            Text(mode.subtitle)
                                .font(.system(size: 9, weight: .semibold))
                                .opacity(0.70)
                        }
                        Spacer(minLength: 0)
                        HelpTip(title: mode.rawValue, message: mode.explanation)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(ModeButtonStyle(isSelected: model.performanceMode == mode, tint: tint(mode)))
            }
        }
    }

    private func icon(_ mode: PerformanceMode) -> String {
        switch mode {
        case .safe:
            return "leaf.fill"
        case .recommended:
            return "sparkles"
        case .maximum:
            return "flame.fill"
        }
    }

    private func tint(_ mode: PerformanceMode) -> Color {
        switch mode {
        case .safe:
            return .green
        case .recommended:
            return .cyan
        case .maximum:
            return .pink
        }
    }
}

private struct SubtitleOutputSelector: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 7) {
            ForEach(SubtitleOutputMode.allCases) { mode in
                Button {
                    model.settings.subtitleOutputMode = mode
                } label: {
                    VStack(spacing: 2) {
                        HStack(spacing: 5) {
                            Text(mode.rawValue)
                                .font(.system(size: 12, weight: .bold))
                            HelpTip(title: mode.rawValue, message: mode.explanation)
                        }
                        Text(mode.subtitle)
                            .font(.system(size: 9, weight: .semibold))
                            .opacity(0.72)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                }
                .buttonStyle(ModeButtonStyle(isSelected: model.settings.subtitleOutputMode == mode, tint: tint(mode)))
            }
        }
    }

    private func tint(_ mode: SubtitleOutputMode) -> Color {
        switch mode {
        case .lithuanianOnly:
            return .green
        case .englishOnly:
            return .cyan
        case .lithuanianAndEnglish:
            return .pink
        }
    }
}

private struct VideoExportSelector: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 7) {
            ForEach(VideoExportMode.allCases) { mode in
                Button {
                    model.settings.videoExportMode = mode
                } label: {
                    VStack(spacing: 2) {
                        HStack(spacing: 5) {
                            Text(mode.rawValue)
                                .font(.system(size: 12, weight: .bold))
                            HelpTip(title: mode.rawValue, message: mode.explanation)
                        }
                        Text(mode.subtitle)
                            .font(.system(size: 9, weight: .semibold))
                            .opacity(0.72)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                }
                .buttonStyle(ModeButtonStyle(isSelected: model.settings.videoExportMode == mode, tint: tint(mode)))
            }
        }
    }

    private func tint(_ mode: VideoExportMode) -> Color {
        switch mode {
        case .srtOnly:
            return .cyan
        case .videoOnly:
            return .orange
        case .srtAndVideo:
            return .green
        }
    }
}

private struct AudioInputSelector: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 7) {
            ForEach(AudioInputMode.allCases) { mode in
                Button {
                    model.settings.audioInputMode = mode
                } label: {
                    VStack(spacing: 2) {
                        HStack(spacing: 5) {
                            Text(mode.rawValue)
                                .font(.system(size: 12, weight: .bold))
                            HelpTip(title: mode.rawValue, message: mode.explanation)
                        }
                        Text(mode.subtitle)
                            .font(.system(size: 9, weight: .semibold))
                            .opacity(0.72)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                }
                .buttonStyle(ModeButtonStyle(isSelected: model.settings.audioInputMode == mode, tint: tint(mode)))
            }
        }
    }

    private func tint(_ mode: AudioInputMode) -> Color {
        switch mode {
        case .autoBestTrack:
            return .cyan
        case .firstTrack:
            return .orange
        case .mixAllTracks:
            return .green
        }
    }
}

private struct PerformanceBars: View {
    let profile: DeviceProfile

    var body: some View {
        VStack(spacing: 8) {
            MetricBar(title: "CPU pajėgumas", value: min(Double(profile.activeCores) / 12.0, 1), tint: .cyan)
            MetricBar(title: "RAM large-v3 modeliui", value: min(Double(profile.memoryGB) / 32.0, 1), tint: .green)
            MetricBar(title: "Maks. spaudimo atsarga", value: min(Double(max(profile.memoryGB / 8, profile.recommendedParallelJobs)) / 4.0, 1), tint: .pink)
        }
    }
}

private struct MetricBar: View {
    let title: String
    let value: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))
                .frame(width: 170, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(tint.opacity(0.78))
                        .frame(width: max(8, proxy.size.width * min(max(value, 0), 1)))
                }
            }
            .frame(height: 8)
        }
    }
}

private struct SpecPill: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.48))
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(color.opacity(0.15))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(color.opacity(0.28), lineWidth: 1))
        )
    }
}

private struct BatchQueuePanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Failų eilė", systemImage: "square.stack.3d.up")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Text(model.jobs.isEmpty ? "Nėra failų" : "\(model.jobs.count) failų")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.56))
            }

            if model.jobs.isEmpty {
                Text("Pasirink kelis failus kairėje. Programa pati parinks, kiek jų apdoroti vienu metu pagal šio Mac pajėgumą.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.56))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                BatchSummaryStrip(jobs: model.jobs)

                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(model.jobs) { job in
                            BatchJobRow(job: job)
                        }
                    }
                    .padding(.vertical, 1)
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(16)
        .background(panelBackground)
    }
}

private struct BatchSummaryStrip: View {
    let jobs: [TranscriptionJob]

    var body: some View {
        HStack(spacing: 8) {
            SummaryChip(title: "Laukia", count: count(.waiting), color: .white.opacity(0.55))
            SummaryChip(title: "Vyksta", count: count(.running), color: .cyan)
            SummaryChip(title: "Baigta", count: count(.complete), color: .green)
            SummaryChip(title: "Klaidos", count: count(.failed), color: .red)
        }
    }

    private func count(_ state: JobState) -> Int {
        jobs.filter { $0.state == state }.count
    }
}

private struct SummaryChip: View {
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
            Text("\(count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        )
    }
}

private struct BatchJobRow: View {
    @EnvironmentObject private var model: AppModel
    let job: TranscriptionJob

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.displayName)
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(job.statusMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.52))
                        .lineLimit(1)
                }
                Spacer()
                Text(job.state.rawValue)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(iconColor)

                if job.resultFile != nil {
                    Button {
                        model.revealJobResult(job)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(TinyButtonStyle())
                    .help("Rodyti SRT failą aplanke.")
                }
            }

            ProgressView(value: job.progress)
                .progressViewStyle(.linear)
                .tint(iconColor)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.black.opacity(0.18))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        )
    }

    private var iconName: String {
        switch job.state {
        case .waiting:
            return "clock"
        case .running:
            return "waveform"
        case .complete:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .cancelled:
            return "stop.circle.fill"
        }
    }

    private var iconColor: Color {
        switch job.state {
        case .waiting:
            return .white.opacity(0.45)
        case .running:
            return .cyan
        case .complete:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .orange
        }
    }
}

private struct SettingBlock<Content: View>: View {
    let title: String
    let help: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                HelpTip(title: title, message: help)
                Spacer(minLength: 0)
            }
            content
                .font(.system(size: 12, weight: .medium))
            Text(help)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.46))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.12, green: 0.13, blue: 0.18).opacity(0.82))
                .overlay(
                    LinearGradient(
                        colors: [Color.white.opacity(0.12), Color.pink.opacity(0.06), Color.cyan.opacity(0.07)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.16), radius: 10, x: 0, y: 7)
        )
    }
}

private struct HelpTip: View {
    let title: String
    let message: String
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.68))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .help(message)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(red: 0.08, green: 0.09, blue: 0.12))
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(red: 0.20, green: 0.22, blue: 0.28))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 280, alignment: .leading)
            .background(Color.white.opacity(0.96))
        }
    }
}

private struct LanguagePicker: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Menu {
            Button("Lietuvių") { model.settings.languageCode = "lt" }
            Button("Anglų") { model.settings.languageCode = "en" }
            Button("Rusų") { model.settings.languageCode = "ru" }
            Button("Lenkų") { model.settings.languageCode = "pl" }
            Button("Vokiečių") { model.settings.languageCode = "de" }
            Button("Ispanų") { model.settings.languageCode = "es" }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                Text(languageName)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryButtonStyle())
    }

    private var languageName: String {
        switch model.settings.languageCode {
        case "lt":
            return "Lietuvių"
        case "en":
            return "Anglų"
        case "ru":
            return "Rusų"
        case "pl":
            return "Lenkų"
        case "de":
            return "Vokiečių"
        case "es":
            return "Ispanų"
        default:
            return model.settings.languageCode.uppercased()
        }
    }
}

private struct LogPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Kas vyksta dabar", systemImage: "terminal")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Text("\(model.logs.count) įrašų")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 7) {
                        ForEach(model.logs) { entry in
                            HStack(alignment: .top, spacing: 9) {
                                Text(entry.level.rawValue)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(entry.level.color)
                                    .frame(width: 46, alignment: .leading)
                                Text(entry.message)
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.68))
                                    .textSelection(.enabled)
                            }
                            .id(entry.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
                .background(Color.black.opacity(0.26))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onChange(of: model.logs.count) { _ in
                    guard let last = model.logs.last else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .padding(16)
        .background(panelBackground)
    }
}

private var panelBackground: some View {
    RoundedRectangle(cornerRadius: 16)
        .fill(Color(red: 0.09, green: 0.10, blue: 0.14).opacity(0.78))
        .overlay(
            LinearGradient(
                colors: [Color.white.opacity(0.10), Color.cyan.opacity(0.045), Color.pink.opacity(0.045)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 10)
        .shadow(color: Color.white.opacity(0.035), radius: 1, x: 0, y: 1)
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(configuration.isPressed ? Color.cyan.opacity(0.72) : Color.cyan)
            .foregroundStyle(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct ModeButtonStyle: ButtonStyle {
    let isSelected: Bool
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.74))
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(background(configuration: configuration))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(isSelected ? tint.opacity(0.65) : Color.white.opacity(0.10), lineWidth: 1)
            )
    }

    private func background(configuration: Configuration) -> Color {
        if isSelected {
            return configuration.isPressed ? tint.opacity(0.75) : tint
        }
        return configuration.isPressed ? Color.white.opacity(0.13) : Color.white.opacity(0.07)
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(configuration.isPressed ? Color.white.opacity(0.18) : Color.white.opacity(0.1))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct DangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(configuration.isPressed ? Color.red.opacity(0.68) : Color.red.opacity(0.82))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct TinyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(configuration.isPressed ? Color.white.opacity(0.18) : Color.white.opacity(0.1))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
