import SwiftUI
import AppKit

private enum NexaTab: String, CaseIterable, Identifiable {
    case overview = "Overview", sound = "Sound", clipboard = "Clipboard", settings = "Settings"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .sound: return "speaker.wave.2"
        case .clipboard: return "doc.on.clipboard"
        case .settings: return "slider.horizontal.3"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("menuBarMode") private var menuBarMode = "compact"
    @AppStorage("nexaAppearance") private var appearance = "system"
    @State private var selectedTab: NexaTab = .overview

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                header.padding(.horizontal, 20).padding(.top, 19).padding(.bottom, 17)
                navigation.padding(.horizontal, 18).padding(.bottom, 15)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        NexaUpdateBanner(updateManager: state.updateManager)
                        tabContent
                    }.padding(.horizontal, 18).padding(.bottom, 18)
                }.scrollIndicators(.hidden)
                footer
            }
            if let toast = state.toastMessage {
                Text(toast).font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7))
                    .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
                    .padding(.horizontal, 16).padding(.top, 10)
                    .transition(.opacity).allowsHitTesting(false).zIndex(10)
            }
        }
        .frame(width: NexaTheme.panelWidth, height: NexaTheme.panelHeight)
        .background(NexaBackground()).tint(NexaTheme.accent)
        .preferredColorScheme(NexaTheme.colorScheme(for: appearance))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: state.toastMessage)
        .sheet(isPresented: $state.updateManager.showUpdateSheet) {
            UpdateView(updateManager: state.updateManager)
                .preferredColorScheme(NexaTheme.colorScheme(for: appearance))
        }
        .onAppear { if menuBarMode == "full" { menuBarMode = "balanced" } }
    }

    private var header: some View {
        HStack(spacing: 11) {
            NexaAppMark()
            VStack(alignment: .leading, spacing: 3) {
                Text("NexaBar").font(.system(size: 18, weight: .semibold, design: .rounded))
                Text("A little space. A clearer day.").font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(NexaTheme.mint).frame(width: 5, height: 5)
                Text("Live").font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(NexaTheme.mint.opacity(0.09), in: Capsule())
            .accessibilityLabel("Live system statistics")
        }
    }

    private var navigation: some View {
        HStack(spacing: 3) {
            ForEach(NexaTab.allCases) { tab in
                Button { selectedTab = tab } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.symbol).font(.system(size: 10.5))
                        Text(tab.rawValue).font(.system(size: 10.5, weight: .medium))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .foregroundStyle(selectedTab == tab ? NexaTheme.accent : Color.secondary)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(selectedTab == tab ? Color(nsColor: .controlBackgroundColor) : .clear))
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(4).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder private var tabContent: some View {
        switch selectedTab {
        case .overview: overview
        case .sound: sound
        case .clipboard: ClipboardPanel()
        case .settings: settings
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
            NexaSectionHeading(title: "Your Mac, at a glance", detail: "Updates every 2s")
            HStack(spacing: 8) {
                RingGauge(title: "CPU", systemImage: "cpu", value: state.cpuPercent, detail: "Live usage")
                RingGauge(title: "Memory", systemImage: "memorychip", value: state.memoryPercent,
                          detail: "\(ByteFormatter.gigabytes(state.memoryUsedGB)) / \(ByteFormatter.gigabytes(state.memoryTotalGB))", accent: NexaTheme.mint)
                RingGauge(title: "Storage", systemImage: "internaldrive", value: state.diskPercent,
                          detail: "\(ByteFormatter.gigabytes(state.diskUsedGB)) / \(ByteFormatter.gigabytes(state.diskTotalGB))", accent: NexaTheme.amber)
            }.padding(.vertical, 19).padding(.horizontal, 10).nexaCard()
            HStack(spacing: 8) {
                metric("Temperature", symbol: "thermometer.medium", value: state.cpuTemperature.map { "\(Int($0.rounded())) °C" } ?? "Unavailable", tint: NexaTheme.amber)
                metric("Download", symbol: "arrow.down", value: ByteFormatter.rate(state.downloadBytesPerSecond), tint: NexaTheme.mint)
                metric("Upload", symbol: "arrow.up", value: ByteFormatter.rate(state.uploadBytesPerSecond), tint: NexaTheme.accent)
            }
            NexaSectionHeading(title: "Make room for your next idea")
            HStack(spacing: 10) {
                quickAction("Capture", detail: "Select & copy", symbol: "viewfinder") { state.captureSelection() }
                quickAction("Clipboard", detail: "\(state.clipboardItems.count) saved items", symbol: "doc.on.clipboard") { selectedTab = .clipboard }
            }
            HStack(spacing: 10) {
                Image(systemName: "speaker.wave.2").foregroundStyle(NexaTheme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sound, in your control").font(.system(size: 12, weight: .medium))
                    Text(state.audioDevices.first(where: { $0.isDefaultOutput })?.name ?? "Choose an output in Sound")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Button { selectedTab = .sound } label: { Image(systemName: "arrow.up.right") }
                    .buttonStyle(NexaIconButtonStyle()).help("Open sound controls")
                    .accessibilityLabel("Open sound controls")
            }.padding(14).nexaCard()
        }
    }

    private func metric(_ title: String, symbol: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(tint)
            Text(value).font(.system(size: 13, weight: .medium, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
            Text(title).font(.system(size: 9.5)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12).nexaCard()
        .accessibilityElement(children: .combine)
    }

    private func quickAction(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 17, weight: .light)).foregroundStyle(NexaTheme.accent)
                    .frame(width: 33, height: 33)
                    .background(NexaTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 12, weight: .medium))
                    Text(detail).font(.system(size: 9.5)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.padding(13).frame(maxWidth: .infinity).nexaCard()
        }
        .buttonStyle(.plain)
        .help(title == "Capture" ? "Select a screen area and copy it to the clipboard" : "Browse and search clipboard history")
    }

    private var sound: some View {
        VStack(alignment: .leading, spacing: 16) {
            NexaSectionHeading(title: "Output devices", detail: "Select to switch")
            VStack(spacing: 14) {
                if state.audioDevices.isEmpty {
                    NexaEmptyState(symbol: "speaker.wave.2", title: "Finding your audio devices", detail: "Connected outputs will appear here.")
                } else {
                    ForEach(state.audioDevices) { device in deviceRow(device) }
                }
            }.padding(14).nexaCard()
            NexaSectionHeading(title: "App volume", detail: "\(state.appAudioItems.count) active")
            VStack(spacing: 14) {
                if state.appAudioItems.isEmpty {
                    NexaEmptyState(symbol: "waveform", title: "A quiet moment", detail: "Play audio in an app to adjust its volume here.")
                } else {
                    ForEach(state.appAudioItems) { app in appRow(app) }
                }
            }.padding(14).nexaCard()
        }
    }

    private func deviceRow(_ device: AudioDeviceItem) -> some View {
        VStack(spacing: 9) {
            Button { state.setDefaultAudioOutput(device: device) } label: {
                HStack(spacing: 10) {
                    Image(systemName: device.iconName).foregroundStyle(device.isDefaultOutput ? NexaTheme.accent : Color.secondary)
                        .frame(width: 27, height: 27)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                    Text(device.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 4)
                    if device.isDefaultOutput {
                        Text("Selected").font(.system(size: 9, weight: .medium)).foregroundStyle(NexaTheme.accent)
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(NexaTheme.accent.opacity(0.1), in: Capsule())
                    }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).help("Use \(device.name) for audio output")
            volumeControl(volume: Binding(get: { device.volume }, set: { state.setDeviceVolume(device: device, volume: $0) }),
                          muted: device.isMuted, name: device.name) { state.toggleDeviceMute(device: device) }
        }
    }

    private func appRow(_ app: AppAudioItem) -> some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                Image(nsImage: app.icon).resizable().scaledToFit().frame(width: 25, height: 25)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                Text(app.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer()
                if app.isMuted { Text("Muted").font(.system(size: 9)).foregroundStyle(.secondary) }
            }
            volumeControl(volume: Binding(get: { app.volume }, set: { state.setAppVolume(app: app, volume: $0) }),
                          muted: app.isMuted, name: app.name) { state.toggleAppMute(app: app) }
        }
    }

    private func volumeControl(volume: Binding<Double>, muted: Bool, name: String, onMute: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button(action: onMute) {
                Image(systemName: muted ? "speaker.slash" : "speaker.wave.2")
                    .foregroundStyle(muted ? NexaTheme.accent : Color.secondary)
            }
            .buttonStyle(NexaIconButtonStyle()).help(muted ? "Unmute \(name)" : "Mute \(name)")
            .accessibilityLabel(muted ? "Unmute \(name)" : "Mute \(name)")
            Slider(value: volume, in: 0...1).controlSize(.small).accessibilityLabel("\(name) volume")
            Text("\(Int((volume.wrappedValue * 100).rounded()))%")
                .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 16) {
            NexaSectionHeading(title: "Make it yours")
            VStack(alignment: .leading, spacing: 15) {
                Text("Appearance").font(.system(size: 12, weight: .medium))
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }.pickerStyle(.segmented)
                Divider().opacity(0.5)
                Text("Menu bar").font(.system(size: 12, weight: .medium))
                Picker("Menu bar layout", selection: $menuBarMode) {
                    Text("Compact").tag("compact")
                    Text("Balanced").tag("balanced")
                }.pickerStyle(.segmented)
                Text(menuBarMode == "compact" ? "CPU and memory. More room in your menu bar." : "CPU, memory, storage and download speed.")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Label("\(Int(state.cpuPercent.rounded()))%", systemImage: "cpu")
                    Label("\(Int(state.memoryPercent.rounded()))%", systemImage: "memorychip")
                    if menuBarMode == "balanced" {
                        Label("\(Int(state.diskPercent.rounded()))%", systemImage: "internaldrive")
                        Label(ByteFormatter.rate(state.downloadBytesPerSecond), systemImage: "network")
                    }
                }
                .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
            }.padding(16).nexaCard()
            NexaSectionHeading(title: "Ready when you are")
            Toggle(isOn: Binding(get: { state.launchAtLogin }, set: { state.toggleLaunchAtLogin(enabled: $0) })) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Launch at login").font(.system(size: 12, weight: .medium))
                    Text("Keep your tools one click away.").font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }.toggleStyle(.switch).controlSize(.small).padding(16).nexaCard()
            NexaUpdateSettings(updateManager: state.updateManager)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Button { state.onRequestToggleClipboard?() } label: {
                HStack(spacing: 6) {
                    Text("⌘⇧V").font(.system(size: 10, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 6).padding(.vertical, 4)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 5))
                    Text("Clipboard").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.buttonStyle(.plain).help("Open clipboard history")
            Spacer()
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            } label: { Image(systemName: "waveform.path.ecg") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Open Activity Monitor")
                .accessibilityLabel("Open Activity Monitor")
            Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1, height: 11).padding(.horizontal, 7)
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20).padding(.vertical, 11).background(Color.primary.opacity(0.018))
        .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.055)).frame(height: 0.7) }
    }
}

struct NexaAppMark: View {
    private var image: NSImage? {
        let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png")
            ?? Bundle.module.url(forResource: "AppIcon", withExtension: "png")
        return url.flatMap { NSImage(contentsOf: $0) }
    }
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "square.stack.3d.up.fill").font(.system(size: 23)).foregroundStyle(NexaTheme.accent) }
        }
        .frame(width: 39, height: 39).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
    }
}

// Observe UpdateManager directly: AppState doesn't publish the manager's nested changes.
private struct NexaUpdateBanner: View {
    @ObservedObject var updateManager: UpdateManager
    var body: some View {
        if let release = updateManager.availableRelease {
            Button { updateManager.showUpdateSheet = true } label: {
                HStack(spacing: 9) {
                    Image(systemName: "sparkles").foregroundStyle(NexaTheme.accent)
                    Text("NexaBar \(release.version) is ready").font(.system(size: 11, weight: .medium))
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .padding(12).background(NexaTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain)
        }
    }
}

private struct NexaUpdateSettings: View {
    @ObservedObject var updateManager: UpdateManager
    @AppStorage("autoCheckUpdates") private var autoCheck = true
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Software updates").font(.system(size: 12, weight: .medium))
                Spacer()
                Text("v\(updateManager.currentVersion)").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Text(statusText).font(.system(size: 10.5)).foregroundStyle(.secondary)
            if let error = updateManager.errorMessage {
                Text(error).font(.system(size: 10.5)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Toggle("Automatic checks", isOn: $autoCheck).toggleStyle(.checkbox).font(.system(size: 11))
                Spacer()
                if updateManager.availableRelease != nil {
                    Button("View update") { updateManager.showUpdateSheet = true }.buttonStyle(NexaButtonStyle(prominent: true))
                } else {
                    Button { updateManager.checkForUpdates(isUserInitiated: true) } label: {
                        if updateManager.isChecking { ProgressView().controlSize(.mini) }
                        else { Text("Check now") }
                    }.buttonStyle(NexaButtonStyle()).disabled(updateManager.isChecking)
                }
            }
        }.padding(16).nexaCard()
    }
    private var statusText: String {
        if updateManager.isChecking { return "Checking for a fresh version…" }
        if let release = updateManager.availableRelease { return "Version \(release.version) is available." }
        if case .upToDate = updateManager.status { return "You're up to date." }
        return "Small improvements, delivered when they're ready."
    }
}
