import AppKit
import SwiftUI
import ServiceManagement
import WidgetKit

enum AppTheme: String, CaseIterable, Identifiable {
    case automatic
    case light
    case dark

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .automatic: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Root

struct PopoverView: View {
    @ObservedObject var model: SystemStatsModel
    @State private var showSettings = false
    @AppStorage("appTheme") private var appTheme = AppTheme.automatic.rawValue

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                Header(model: model, showSettings: $showSettings)
                if model.helperMissing {
                    HelperMissingBanner()
                }
                sep
                CPUSection(model: model)
                sep
                GPUSection(model: model)
                if model.fanRPM > 0 {
                    sep
                    FanSection(model: model)
                }
                sep
                MemorySection(model: model)
                if model.hasBattery {
                    sep
                    BatterySection(model: model)
                }
                sep
                NetworkDiskSection(model: model)
                sep
                PowerSection(model: model)
                sep
                ProcessSection(model: model)
                sep
                FooterBar(model: model)
            }
        }
        .frame(width: 340)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(AppTheme(rawValue: appTheme)?.colorScheme)
        .sheet(isPresented: $showSettings) {
            SettingsSheet(isPresented: $showSettings)
        }
    }

    private var sep: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.horizontal, 14)
    }
}

// MARK: - Helper missing banner

private struct HelperMissingBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Palette.orange)
                .font(.system(size: 11))
            VStack(alignment: .leading, spacing: 1) {
                Text("System helper not installed")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Palette.orange)
                Text("Run Install.command from the DMG to enable GPU, temps, and power data.")
                    .font(.system(size: 10))
                    .foregroundColor(Palette.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Palette.orange.opacity(0.08))
    }
}

// MARK: - Header

private struct Header: View {
    @ObservedObject var model: SystemStatsModel
    @Binding var showSettings: Bool
    @ObservedObject private var updater = UpdateChecker.shared

    var thermalColor: Color {
        switch model.thermalState {
        case "Normal":   return Palette.green
        case "Fair":     return Palette.yellow
        default:         return Palette.red
        }
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.chipName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                HStack(spacing: 5) {
                    Circle().fill(thermalColor).frame(width: 6, height: 6)
                    Text(model.thermalState)
                        .font(.system(size: 11))
                        .foregroundColor(thermalColor)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f W", model.totalPower))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
                Text("total power")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Button { showSettings = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundColor(Palette.dim)
                        .padding(.leading, 12)
                    if updater.updateAvailable {
                        Circle()
                            .fill(Palette.orange)
                            .frame(width: 7, height: 7)
                            .offset(x: -2, y: 1)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - CPU

private struct CPUSection: View {
    @ObservedObject var model: SystemStatsModel
    var body: some View {
        SectionBox(icon: "cpu", title: "CPU") {
            Row(label: "Overall") { StatBar(pct: model.cpuUsage) }
            if model.eCoreCount > 0 {
                Row(label: "E-core  \(model.eCoresMHz) MHz") {
                    StatBar(pct: model.eCoresPct, color: Palette.cyan)
                }
            }
            if model.pCoreCount > 0 {
                Row(label: "P-core  \(model.pCoresMHz) MHz") {
                    StatBar(pct: model.pCoresPct, color: Palette.purple)
                }
            }
            if model.sCoreCount > 0 {
                Row(label: "S-core  \(model.sClusterMHz) MHz") {
                    StatBar(pct: model.sClusterPct, color: Palette.coral)
                }
            }
            if !model.perCoreCPU.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                    ForEach(Array(model.perCoreCPU.enumerated()), id: \.offset) { i, pct in
                        CoreTile(label: coreLabel(at: i), pct: pct, kind: coreKind(at: i))
                    }
                }
                .padding(.top, 4)
            }
            HStack {
                Pill(icon: "thermometer", val: String(format: "%.0f°C", model.cpuTemp),
                     color: tempColor(model.cpuTemp))
                if model.cpuDieHotspot > 0 {
                    Pill(icon: "thermometer.sun.fill",
                         val: String(format: "%.0f°C", model.cpuDieHotspot),
                         color: tempColor(model.cpuDieHotspot))
                }
                Spacer()
                Pill(icon: "bolt", val: String(format: "%.2f W", model.cpuPower),
                     color: Palette.yellow)
            }
            .padding(.top, 2)
        }
    }

    private func coreKind(at index: Int) -> CPUCoreKind {
        guard model.cpuCoreKinds.indices.contains(index) else { return .performance }
        return model.cpuCoreKinds[index]
    }

    private func coreLabel(at index: Int) -> String {
        let kind = coreKind(at: index)
        let ordinal = coreOrdinal(at: index, kind: kind)
        switch kind {
        case .efficiency:
            return String(format: "E%02d", ordinal)
        case .performance:
            return String(format: "P%02d", ordinal)
        case .superPerformance:
            return String(format: "S%02d", ordinal)
        }
    }

    private func coreOrdinal(at index: Int, kind: CPUCoreKind) -> Int {
        guard !model.cpuCoreKinds.isEmpty else { return index + 1 }

        var ordinal = 0
        for currentKind in model.cpuCoreKinds.prefix(index + 1) {
            switch (currentKind, kind) {
            case (.efficiency, .efficiency),
                 (.performance, .performance),
                 (.superPerformance, .superPerformance):
                ordinal += 1
            default:
                break
            }
        }
        return max(ordinal, 1)
    }
}

// MARK: - Fan (hidden on fanless models)

private struct FanSection: View {
    @ObservedObject var model: SystemStatsModel
    var body: some View {
        SectionBox(icon: "fan", title: "Fan") {
            Row(label: "Speed") {
                HStack {
                    Text("\(model.fanRPM) RPM")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.primary)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - GPU

private struct GPUSection: View {
    @ObservedObject var model: SystemStatsModel
    var body: some View {
        SectionBox(icon: "rectangle.3.group", title: "GPU  ·  \(model.gpuCoreCount) cores") {
            Row(label: "\(model.gpuMHz) MHz") {
                StatBar(pct: model.gpuUsage, color: Palette.orange)
            }
            HStack {
                Pill(icon: "thermometer", val: String(format: "%.0f°C", model.gpuTemp),
                     color: tempColor(model.gpuTemp))
                Spacer()
                Pill(icon: "bolt", val: String(format: "%.3f W", model.gpuPower),
                     color: Palette.yellow)
            }
            .padding(.top, 2)
        }
    }
}

// MARK: - Memory

private struct MemorySection: View {
    @ObservedObject var model: SystemStatsModel
    var body: some View {
        SectionBox(icon: "memorychip", title: "Memory") {
            Row(label: "\(fmtB(model.memUsed)) / \(fmtB(model.memTotal))") {
                StatBar(pct: model.memPct, color: Palette.blue)
            }
            HStack(spacing: 16) {
                KV("DRAM BW",  String(format: "%.1f GB/s", model.dramBW))
                KV("Swap", model.swapTotal > 0
                    ? "\(fmtB(model.swapUsed)) / \(fmtB(model.swapTotal))" : "None")
            }
            .padding(.top, 2)
        }
    }
}

// MARK: - Battery

private struct BatterySection: View {
    @ObservedObject var model: SystemStatsModel

    var statusLabel: String {
        if model.batteryCharged  { return "Fully Charged" }
        if model.batteryCharging { return "Charging" }
        return "On Battery"
    }

    var batteryColor: Color {
        model.batteryPct < 20 ? Palette.red
            : (model.batteryCharging || model.batteryCharged)
                ? Palette.green : Palette.yellow
    }

    var body: some View {
        SectionBox(icon: "battery.75percent", title: "Battery") {
            Row(label: statusLabel) {
                StatBar(pct: model.batteryPct, color: batteryColor)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    KV("Source",     model.batteryOnAC ? "AC Power" : "Battery")
                    KV("Remaining",  model.batteryTimeLeft)
                }
                GridRow {
                    KV("Adapter",    model.adapterWatts > 0
                        ? String(format: "%.0f W", model.adapterWatts) : "—")
                    KV("Charge rate",model.chargingWatts > 0
                        ? String(format: "%.1f W", model.chargingWatts) : "—")
                }
                GridRow {
                    KV("Temp",       model.batteryTempC > 0
                        ? String(format: "%.1f °C", model.batteryTempC) : "—")
                    KV("Cycles",     model.batteryCycles > 0
                        ? "\(model.batteryCycles)" : "—")
                }
                GridRow {
                    KV("Health",     "\(model.batteryHealthPct)%")
                    KV("Capacity",   model.batteryMaxMAh > 0
                        ? "\(model.batteryMaxMAh) / \(model.batteryDesignMAh) mAh" : "—")
                }
            }
            .padding(.top, 2)
        }
    }
}

// MARK: - Network + Disk

private struct NetworkDiskSection: View {
    @ObservedObject var model: SystemStatsModel
    var body: some View {
        HStack(spacing: 0) {
            SectionBox(icon: "wifi", title: "Network") {
                IORow(icon: "arrow.down", val: fmtB(model.netInBps)  + "/s", color: Palette.green)
                IORow(icon: "arrow.up",   val: fmtB(model.netOutBps) + "/s", color: Palette.orange)
            }
            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1)
            SectionBox(icon: "internaldrive", title: "Disk I/O") {
                IORow(icon: "arrow.down", val: String(format: "%.0f KB/s", model.diskReadKBs),  color: Palette.cyan)
                IORow(icon: "arrow.up",   val: String(format: "%.0f KB/s", model.diskWriteKBs), color: Palette.orange)
            }
        }
    }
}

private struct IORow: View {
    let icon: String; let val: String; let color: Color
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9)).foregroundColor(color)
            Text(val)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary)
            Spacer()
        }
    }
}

// MARK: - Power rails

private struct PowerSection: View {
    @ObservedObject var model: SystemStatsModel
    var body: some View {
        SectionBox(icon: "bolt.fill", title: "Power Rails") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 5) {
                PowerTile(label: "CPU",   val: model.cpuPower)
                PowerTile(label: "GPU",   val: model.gpuPower)
                PowerTile(label: "ANE",   val: model.anePower)
                PowerTile(label: "DRAM",  val: model.dramPower)
                PowerTile(label: "SYS",   val: model.sysPower)
                PowerTile(label: "TOTAL", val: model.totalPower, highlight: true)
            }
        }
    }
}

private struct PowerTile: View {
    let label: String; let val: Double; var highlight: Bool = false
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(highlight ? Palette.yellow : Palette.dim)
            Spacer()
            Text(String(format: val >= 1 ? "%.2f W" : "%.3f W", val))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(highlight ? Palette.yellow : .primary)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Color.primary.opacity(highlight ? 0.07 : 0.03))
        .cornerRadius(6)
    }
}

// MARK: - Processes

private struct ProcessSection: View {
    @ObservedObject var model: SystemStatsModel
    @State private var mode: ProcessMode = .cpu

    private enum ProcessMode: String, CaseIterable, Identifiable {
        case cpu = "CPU"
        case disk = "Disk"
        case network = "Network"
        var id: Self { self }
    }

    var body: some View {
        SectionBox(icon: "list.bullet", title: "Top Processes") {
            Picker("Process metric", selection: $mode) {
                ForEach(ProcessMode.allCases) { metric in
                    Text(metric.rawValue).tag(metric)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch mode {
            case .cpu:
                cpuRows
            case .disk:
                ioRows(
                    header: ("Read", "Write"),
                    rows: model.topDiskProcs.map { ($0.id, $0.name, fmtB($0.readBps) + "/s", fmtB($0.writeBps) + "/s") },
                    colors: (Color(hex: "64D2FF"), Color(hex: "FF9F0A"))
                )
            case .network:
                ioRows(
                    header: ("Down", "Up"),
                    rows: model.topNetworkProcs.map { ($0.id, $0.name, fmtB($0.downBps) + "/s", fmtB($0.upBps) + "/s") },
                    colors: (Color(hex: "30D158"), Color(hex: "BF5AF2"))
                )
            }
        }
    }

    private var cpuRows: some View {
        Group {
            HStack {
                Text("Process").frame(maxWidth: .infinity, alignment: .leading)
                Text("CPU").frame(width: 40, alignment: .trailing)
                Text("Memory").frame(width: 64, alignment: .trailing)
            }
            .font(.system(size: 9)).foregroundColor(.secondary)

            ForEach(model.topProcs) { p in
                HStack(spacing: 0) {
                    Text(p.name)
                        .font(.system(size: 11)).foregroundColor(.primary)
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(String(format: "%.1f%%", p.cpu))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(cpuClr(p.cpu))
                        .frame(width: 40, alignment: .trailing)
                    Text(fmtB(p.mem))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Palette.cyan)
                        .frame(width: 64, alignment: .trailing)
                }
            }
        }
    }

    @ViewBuilder
    private func ioRows(
        header: (String, String),
        rows: [(Int, String, String, String)],
        colors: (Color, Color)
    ) -> some View {
        HStack {
            Text("Process").frame(maxWidth: .infinity, alignment: .leading)
            Text(header.0).frame(width: 70, alignment: .trailing)
            Text(header.1).frame(width: 70, alignment: .trailing)
        }
        .font(.system(size: 9)).foregroundColor(.secondary)

        if rows.isEmpty {
            Text("Collecting activity…")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ForEach(rows, id: \.0) { row in
                HStack(spacing: 0) {
                    Text(row.1)
                        .font(.system(size: 11)).foregroundColor(.primary)
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.2)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(colors.0)
                        .frame(width: 70, alignment: .trailing)
                    Text(row.3)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(colors.1)
                        .frame(width: 70, alignment: .trailing)
                }
            }
        }
    }

    func cpuClr(_ v: Double) -> Color {
        v >= 50 ? Palette.red : v >= 20 ? Palette.yellow : Palette.green
    }
}

// MARK: - Footer

private struct FooterBar: View {
    @ObservedObject var model: SystemStatsModel
    @State private var working = false
    var body: some View {
        HStack(spacing: 10) {
            Button {
                working = true
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                    model.optimize()
                    DispatchQueue.main.async { working = false }
                }
            } label: {
                Label(working ? "Working…" : "Optimize", systemImage: "bolt.fill")
                    .frame(maxWidth: .infinity)
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent).tint(Palette.orange).disabled(working)

            Button { NSApp.terminate(nil) } label: {
                Text("Quit").frame(maxWidth: .infinity)
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.regular).padding(.horizontal, 14).padding(.vertical, 10)
    }
}

// MARK: - Settings sheet

struct SettingsSheet: View {
    @Binding var isPresented: Bool
    @AppStorage("openAtLogin")   var openAtLogin   = false
    @AppStorage("cpuOnlyMenuBar") var cpuOnlyMenuBar = false
    @AppStorage("appTheme") private var appTheme = AppTheme.automatic.rawValue
    @ObservedObject private var updater = UpdateChecker.shared
    @State private var menuMetrics = MenuBarLayoutStore.orderedMetrics()

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.system(size: 16, weight: .bold)).foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 6) {
                Toggle("CPU Percentage Only", isOn: $cpuOnlyMenuBar)
                    .toggleStyle(SwitchToggleStyle(tint: Palette.green))
                Text("Show a compact value such as 12% in the menu bar.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }

            DisclosureGroup("Menu Bar Metrics") {
                VStack(spacing: 8) {
                    ForEach(menuMetrics) { metric in
                        MenuBarMetricRow(metric: metric, metrics: $menuMetrics)
                    }
                    HStack {
                        Text("At least one metric remains enabled.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Reset") {
                            MenuBarLayoutStore.reset()
                            menuMetrics = MenuBarLayoutStore.orderedMetrics()
                        }
                        .font(.system(size: 10))
                    }
                }
                .padding(.top, 8)
            }
            .font(.system(size: 12, weight: .medium))
            .disabled(cpuOnlyMenuBar)
            .opacity(cpuOnlyMenuBar ? 0.55 : 1)

            VStack(alignment: .leading, spacing: 6) {
                Text("Appearance")
                    .font(.system(size: 12, weight: .medium))
                Picker("Appearance", selection: $appTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.label).tag(theme.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                Text("Automatic follows your Mac’s current appearance.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Open at Login", isOn: $openAtLogin)
                    .toggleStyle(SwitchToggleStyle(tint: Palette.green))
                    .onChange(of: openAtLogin) { enabled in
                        if enabled {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                    }
                Text("Automatically start MacMonitor when you log in.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Desktop Widget")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button("Refresh Now") {
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                    .font(.system(size: 11))
                }
                Text("Right-click your desktop → Edit Widgets → find MacMonitor. "
                     + "It refreshes on its own while MacMonitor is running.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("MacMonitor  v\(updater.currentVersion)")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(.primary)
                    Group {
                        switch updater.updatePhase {
                        case .idle:
                            if updater.updateAvailable {
                                Text("v\(updater.latestVersion) available")
                                    .foregroundColor(Palette.orange)
                            } else {
                                Text("Apple Silicon  ·  macOS 13+  ·  MIT")
                                    .foregroundColor(.secondary)
                            }
                        case .downloading:
                            Text("Downloading v\(updater.latestVersion)…")
                                .foregroundColor(Palette.orange)
                        case .installing:
                            Text("Installing…")
                                .foregroundColor(Palette.orange)
                        case .readyToRelaunch:
                            Text("Ready — relaunch to apply")
                                .foregroundColor(Palette.green)
                        case .failed(let msg):
                            Text(msg)
                                .foregroundColor(Palette.red)
                        }
                    }
                    .font(.system(size: 10))
                }
                Spacer()
                Group {
                    switch updater.updatePhase {
                    case .idle:
                        HStack(spacing: 6) {
                            if updater.updateAvailable {
                                Button("Update") { updater.startUpdate() }
                                    .buttonStyle(.borderedProminent)
                                    .tint(Palette.orange)
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            Button("Done") { isPresented = false }
                                .buttonStyle(.borderedProminent)
                                .tint(Palette.blue)
                        }
                    case .downloading:
                        VStack(alignment: .trailing, spacing: 3) {
                            ProgressView(value: updater.downloadFraction)
                                .progressViewStyle(.linear)
                                .tint(Palette.orange)
                                .frame(width: 80)
                            Text("\(Int(updater.downloadFraction * 100))%")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    case .installing:
                        ProgressView()
                            .scaleEffect(0.75)
                            .tint(Palette.orange)
                    case .readyToRelaunch:
                        Button("Relaunch") { updater.relaunch() }
                            .buttonStyle(.borderedProminent)
                            .tint(Palette.green)
                            .font(.system(size: 12, weight: .semibold))
                    case .failed:
                        Button("Dismiss") { updater.dismissUpdateError() }
                            .buttonStyle(.bordered)
                            .font(.system(size: 12))
                    }
                }
            }
        }
        .padding(22)
        }
        .frame(width: 400, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(AppTheme(rawValue: appTheme)?.colorScheme)
    }
}

private struct MenuBarMetricRow: View {
    let metric: MenuBarMetric
    @Binding var metrics: [MenuBarMetric]
    @State private var isVisible = false

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { isVisible },
                set: { requested in
                    _ = MenuBarLayoutStore.setVisible(metric, requested)
                    isVisible = MenuBarLayoutStore.isVisible(metric)
                    metrics = MenuBarLayoutStore.orderedMetrics()
                }
            )) {
                Label(metric.title, systemImage: metric.systemImage)
                    .font(.system(size: 11))
            }
            .toggleStyle(.checkbox)

            Spacer()

            Button {
                MenuBarLayoutStore.move(metric, direction: -1)
                metrics = MenuBarLayoutStore.orderedMetrics()
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(metrics.first == metric)

            Button {
                MenuBarLayoutStore.move(metric, direction: 1)
                metrics = MenuBarLayoutStore.orderedMetrics()
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(metrics.last == metric)
        }
        .onAppear { isVisible = MenuBarLayoutStore.isVisible(metric) }
        .onReceive(NotificationCenter.default.publisher(for: .menuBarLayoutChanged)) { _ in
            isVisible = MenuBarLayoutStore.isVisible(metric)
        }
    }
}

// MARK: - Reusable atoms

private struct SectionBox<Content: View>: View {
    let icon: String; let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Palette.dim)
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(Palette.dim).tracking(0.6)
            }
            content
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }
}

private struct Row<R: View>: View {
    let label: String; @ViewBuilder let right: R
    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11)).foregroundColor(.secondary)
                .frame(width: 130, alignment: .leading).lineLimit(1)
            right
        }
    }
}

private struct StatBar: View {
    let pct: Int; var color: Color = Palette.green
    private var barColor: Color {
        pct >= 85 ? Palette.red : pct >= 60 ? Palette.yellow : color
    }
    var body: some View {
        HStack(spacing: 6) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 3).fill(barColor)
                        .frame(width: g.size.width * CGFloat(min(pct,100)) / 100)
                        .animation(.easeInOut(duration: 0.4), value: pct)
                }
            }
            .frame(height: 7)
            Text("\(pct)%")
                .font(.system(size: 11, design: .monospaced)).foregroundColor(.primary)
                .frame(width: 32, alignment: .trailing)
        }
    }
}

private struct CoreTile: View {
    let label: String; let pct: Double; let kind: CPUCoreKind
    @Environment(\.colorScheme) var colorScheme
    var color: Color {
        pct >= 85 ? Palette.red : pct >= 60 ? Palette.yellow : baseColor
    }
    var baseColor: Color {
        switch kind {
        case .efficiency: return Palette.cyan
        case .performance: return Palette.purple
        case .superPerformance: return Palette.coral
        }
    }
    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                // Dimmed in Dark mode only: at 70% the Light values fall to about 3:1
                // against the window background, under the 4.5:1 text minimum.
                .foregroundColor(color.opacity(colorScheme == .dark ? 0.7 : 1))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 24, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 2).fill(color)
                        .frame(width: g.size.width * CGFloat(min(pct,100)) / 100)
                        .animation(.easeInOut(duration: 0.4), value: pct)
                }
            }
            .frame(height: 5)
            Text("\(Int(pct))%")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 26, alignment: .trailing)
        }
    }
}

private struct Pill: View {
    let icon: String; let val: String; let color: Color
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9))
            Text(val).font(.system(size: 10, design: .monospaced))
        }
        .foregroundColor(color)
    }
}

private struct KV: View {
    let k: String; let v: String
    init(_ k: String, _ v: String) { self.k = k; self.v = v }
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k).font(.system(size: 9)).foregroundColor(.secondary)
            Text(v).font(.system(size: 11, design: .monospaced)).foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Helpers

private func fmtB(_ b: Int64) -> String {
    let d = Double(b)
    if d >= 1_073_741_824 { return String(format: "%.1f GB", d/1_073_741_824) }
    if d >= 1_048_576     { return String(format: "%.1f MB", d/1_048_576) }
    if d >= 1_024         { return String(format: "%.0f KB", d/1_024) }
    return "\(b) B"
}

private func tempColor(_ t: Double) -> Color {
    t >= 80 ? Palette.red : t >= 65 ? Palette.yellow : Palette.dim
}

// MARK: - Palette

/// Accent colours for the dashboard, settings and welcome window.
///
/// Each colour resolves per appearance, the same way the `windowBackgroundColor`
/// background does, so it follows both Automatic and the Light/Dark override.
///
/// The dark values are the colours the app has always used, so Dark mode is unchanged.
/// They are Apple's dark-mode system colours, which are far too light on a light
/// background (yellow measured 1.2:1 on the window, 1.0:1 on the TOTAL tile). Each
/// light value is a darker shade that clears WCAG AA (4.5:1) as text on every light
/// surface it is drawn on, including the TOTAL power tile and the helper banner.
/// Check any new pair the same way before using it for text.
enum Palette {
    static let green  = Color(light: 0x1B7932, dark: 0x30D158)
    static let yellow = Color(light: 0x825600, dark: 0xFFD60A)
    static let orange = Color(light: 0xA64300, dark: 0xFF9F0A)
    static let red    = Color(light: 0xD40C00, dark: 0xFF453A)
    static let cyan   = Color(light: 0x00719F, dark: 0x64D2FF)
    static let purple = Color(light: 0x8944AB, dark: 0xBF5AF2)
    static let blue   = Color(light: 0x0067D0, dark: 0x0A84FF)
    static let coral  = Color(light: 0xCC1D49, dark: 0xFF6B6B)
    /// Section titles, tile labels and idle readings.
    static let dim    = Color(light: 0x606070, dark: 0x888899)
}

extension Color {
    /// A colour with separate light and dark values, resolved by AppKit at draw time.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(rgb: dark) : NSColor(rgb: light)
        })
    }
}

private extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green:   CGFloat((rgb >>  8) & 0xFF) / 255,
                  blue:    CGFloat( rgb        & 0xFF) / 255,
                  alpha:   1)
    }
}

// MARK: - Hex colour helper

// Fixed colours: they look the same in Light and Dark. Use Palette for anything that
// sits on the window background.
extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >>  8) & 0xFF) / 255
        let b = Double((int)       & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
