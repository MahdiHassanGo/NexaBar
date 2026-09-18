import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @AppStorage("menuBarMode") private var menuBarMode = "balanced"

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    gauges
                    quickStats
                    audioCard
                    actionRow
                    ClipboardPanel()
                    settingsCard
                    footer
                }
                .padding(13)
            }

            if let toast = state.toastMessage {
                Text(toast)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 6, y: 2)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .frame(width: 404, height: 610)
        .background(.ultraThinMaterial)
        .animation(.easeOut(duration: 0.2), value: state.toastMessage)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let logoURL = getAppLogoURL(), let nsImage = NSImage(contentsOf: logoURL) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.primary.opacity(0.08))
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .font(.system(size: 20, weight: .semibold))
                }
                .frame(width: 36, height: 36)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("NexaBar")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text("Your Mac. One glance away.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            } label: {
                Image(systemName: "waveform.path.ecg")
            }
            .buttonStyle(.borderless)
            .help("Open Activity Monitor")
        }
    }

    private func getAppLogoURL() -> URL? {
        if let bundleURL = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           FileManager.default.fileExists(atPath: bundleURL.path) {
            return bundleURL
        }
        if let packageURL = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           FileManager.default.fileExists(atPath: packageURL.path) {
            return packageURL
        }
        return nil
    }

    private var gauges: some View {
        HStack(spacing: 6) {
            RingGauge(
                title: "CPU",
                systemImage: "cpu",
                value: state.cpuPercent,
                detail: "Live usage"
            )
            RingGauge(
                title: "MEM",
                systemImage: "memorychip",
                value: state.memoryPercent,
                detail: "\(ByteFormatter.gigabytes(state.memoryUsedGB)) / \(ByteFormatter.gigabytes(state.memoryTotalGB))"
            )
            RingGauge(
                title: "DISK",
                systemImage: "internaldrive",
                value: state.diskPercent,
                detail: "\(ByteFormatter.gigabytes(state.diskUsedGB)) / \(ByteFormatter.gigabytes(state.diskTotalGB))"
            )
        }
        .padding(11)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var quickStats: some View {
        HStack(spacing: 10) {
            miniStat(
                icon: "thermometer.medium",
                title: "CPU Temp",
                value: state.cpuTemperature.map { "\(Int($0.rounded())) °C" } ?? "Unavailable"
            )

            miniStat(
                icon: "arrow.down.circle",
                title: "Download",
                value: ByteFormatter.rate(state.downloadBytesPerSecond)
            )

            miniStat(
                icon: "arrow.up.circle",
                title: "Upload",
                value: ByteFormatter.rate(state.uploadBytesPerSecond)
            )
        }
    }

    private func miniStat(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var audioCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            // Audio Output Devices Sub-section
            HStack {
                Label("Audio Output Devices", systemImage: "speaker.wave.2.fill")
                    .font(.headline)
                Spacer()
                if let active = state.audioDevices.first(where: { $0.isDefaultOutput }) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                        Text(active.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            if state.audioDevices.isEmpty {
                Text("Scanning audio devices...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(state.audioDevices) { device in
                        HStack(spacing: 10) {
                            Button {
                                state.setDefaultAudioOutput(device: device)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: device.iconName)
                                        .font(.system(size: 14))
                                        .foregroundStyle(device.isDefaultOutput ? .blue : .primary)
                                        .frame(width: 20)

                                    Text(device.name)
                                        .font(.system(size: 12.5, weight: device.isDefaultOutput ? .bold : .regular))
                                        .lineLimit(1)
                                        .foregroundStyle(device.isDefaultOutput ? .primary : .secondary)
                                }
                                .frame(width: 134, alignment: .leading)
                            }
                            .buttonStyle(.plain)

                            Button {
                                state.toggleDeviceMute(device: device)
                            } label: {
                                Image(systemName: device.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .foregroundStyle(device.isMuted ? .red : .secondary)
                                    .frame(width: 18)
                            }
                            .buttonStyle(.plain)

                            Slider(
                                value: Binding(
                                    get: { device.volume },
                                    set: { state.setDeviceVolume(device: device, volume: $0) }
                                ),
                                in: 0...1
                            )

                            Text("\(Int((device.volume * 100).rounded()))%")
                                .font(.caption)
                                .monospacedDigit()
                                .frame(width: 36, alignment: .trailing)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)

                        if device.id != state.audioDevices.last?.id {
                            Divider().opacity(0.3)
                        }
                    }
                }
            }

            Divider().opacity(0.4)

            // APPS Section (SoundSource Style)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("APPS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(state.appAudioItems.count) playing")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if state.appAudioItems.isEmpty {
                    Text("No active applications detected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(state.appAudioItems) { app in
                            HStack(spacing: 10) {
                                // App Icon & Name
                                HStack(spacing: 8) {
                                    Image(nsImage: app.icon)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 20, height: 20)
                                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                                    Text(app.name)
                                        .font(.system(size: 12.5, weight: .medium))
                                        .lineLimit(1)
                                        .foregroundStyle(.primary)
                                }
                                .frame(width: 134, alignment: .leading)

                                // Mute button
                                Button {
                                    state.toggleAppMute(app: app)
                                } label: {
                                    Image(systemName: app.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                        .foregroundStyle(app.isMuted ? .red : .secondary)
                                        .frame(width: 18)
                                }
                                .buttonStyle(.plain)

                                // Volume Slider
                                Slider(
                                    value: Binding(
                                        get: { app.volume },
                                        set: { state.setAppVolume(app: app, volume: $0) }
                                    ),
                                    in: 0...1
                                )

                                // Percentage
                                Text("\(Int((app.volume * 100).rounded()))%")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .frame(width: 36, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)

                            if app.id != state.appAudioItems.last?.id {
                                Divider().opacity(0.2)
                            }
                        }
                    }
                }
            }
        }
        .padding(11)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                state.captureSelection()
            } label: {
                Label("Capture Selection", systemImage: "viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                if let item = state.clipboardItems.first {
                    state.copyClipboardItem(item)
                } else {
                    state.showToast("Clipboard is empty")
                }
            } label: {
                Label("Copy Latest", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Settings & Options", systemImage: "gearshape")
                    .font(.headline)
                Spacer()
                Text("⌘⇧V")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.1)))
            }

            Toggle(isOn: Binding(
                get: { state.launchAtLogin },
                set: { state.toggleLaunchAtLogin(enabled: $0) }
            )) {
                HStack(spacing: 8) {
                    Image(systemName: "power")
                        .foregroundStyle(.blue)
                        .font(.system(size: 13, weight: .semibold))
                    Text("Start NexaBar at startup")
                        .font(.system(size: 12.5, weight: .medium))
                }
            }
            .toggleStyle(.switch)

            Divider().opacity(0.3)

            VStack(alignment: .leading, spacing: 6) {
                Text("Menu Bar Layout")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Menu Bar Layout", selection: $menuBarMode) {
                    Text("Compact").tag("compact")
                    Text("Balanced").tag("balanced")
                    Text("Full").tag("full")
                }
                .pickerStyle(.segmented)

                Text(menuBarPreview)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var menuBarPreview: String {
        switch menuBarMode {
        case "compact": return "CPU 24%  52°"
        case "full": return "CPU 24%  MEM 61%  SSD 72%  52°C  ↓1.2M/s ↑90K/s"
        default: return " 4%  61%  72%  52°  ↓1.2M/s"
        }
    }

    private var footer: some View {
        HStack {
            Text("Shortcut: ⌘⇧V (Cmd+Shift+V) to toggle")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
