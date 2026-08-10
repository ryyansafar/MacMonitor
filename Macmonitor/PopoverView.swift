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

    // Section visibility (configurable in Settings). Each section is preceded by a
    // separator, so hiding a section hides its separator too — no stray dividers.
    @AppStorage("showCPU")        private var showCPU        = true
    @AppStorage("showGPU")        private var showGPU        = true
    @AppStorage("showMemory")     private var showMemory     = true
    @AppStorage("showDisk")       private var showDisk       = true
    @AppStorage("showSystem")     private var showSystem     = true
    @AppStorage("showBattery")    private var showBattery    = true
    @AppStorage("showNetwork")    private var showNetwork    = true
    @AppStorage("showPower")      private var showPower      = true
    @AppStorage("showProcesses")  private var showProcesses  = true

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                Header(model: model, showSettings: $showSettings)
                if model.helperMissing {
                    HelperMissingBanner()
                }
                if showCPU { sep; CPUSection(model: model) }
                if showGPU { sep; GPUSection(model: model) }
                if model.fanRPM > 0 { sep; FanSection(model: model) }
                if showMemory { sep; MemorySection(model: model) }
                if showDisk { sep; DiskSection(model: model) }
                if showNetwork { sep; NetworkSection(model: model) }
                if showSystem { sep; SystemSection(model: model) }
                if showBattery { sep; BatterySection(model: model) }
                if showPower { sep; PowerSection(model: model) }
                if showProcesses { sep; ProcessSection(model: model) }
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
                .foregroundColor(Color(hex: "FF9F0A"))
                .font(.system(size: 11))
            VStack(alignment: .leading, spacing: 1) {
                Text("System helper not installed")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "FF9F0A"))
                Text("Run Install.command from the DMG to enable GPU, temps, and power data.")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "888899"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(hex: "FF9F0A").opacity(0.08))
    }
}

// MARK: - Header

private struct Header: View {
    @ObservedObject var model: SystemStatsModel
    @Binding var showSettings: Bool
    @ObservedObject private var updater = UpdateChecker.shared

    var thermalColor: Color {
        switch model.thermalState {
        case "Normal":   return Color(hex: "30D158")
        case "Fair":     return Color(hex: "FFD60A")
        default:         return Color(hex: "FF453A")
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
                        .foregroundColor(Color(hex: "888899"))
                        .padding(.leading, 12)
                    if updater.updateAvailable {
                        Circle()
                            .fill(Color(hex: "FF9F0A"))
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
                Row(label: "E-cluster  \(model.eCoresMHz) MHz") {
                    StatBar(pct: model.eCoresPct, color: Color(hex: "64D2FF"))
                }
                Row(label: "P-cluster  \(model.pCoresMHz) MHz") {
                    StatBar(pct: model.pCoresPct, color: Color(hex: "BF5AF2"))
                }
                // M5+ Super cluster — only shown when present
                if model.sClusterPct > 0 || model.sClusterMHz > 0 {
                    Row(label: "S-cluster  \(model.sClusterMHz) MHz") {
                        StatBar(pct: model.sClusterPct, color: Color(hex: "FF6B6B"))
                    }
                }
            }
            if !model.perCoreCPU.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                    ForEach(Array(model.perCoreCPU.enumerated()), id: \.offset) { i, pct in
                        CoreTile(index: i, pct: pct, isE: i < model.eCoreCount)
                    }
                }
                .padding(.top, 4)
            }
            HStack {
                Pill(icon: "thermometer", val: formatTemp(model.cpuTemp),
                     color: tempColor(model.cpuTemp))
                if model.cpuDieHotspot > 0 {
                    Pill(icon: "thermometer.sun.fill",
                         val: formatTemp(model.cpuDieHotspot),
                         color: tempColor(model.cpuDieHotspot))
                }
                Spacer()
                Pill(icon: "bolt", val: String(format: "%.2f W", model.cpuPower),
                     color: Color(hex: "FFD60A"))
            }
            .padding(.top, 2)
        }
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
                StatBar(pct: model.gpuUsage, color: Color(hex: "FF9F0A"))
            }
            HStack {
                Pill(icon: "thermometer", val: formatTemp(model.gpuTemp),
                     color: tempColor(model.gpuTemp))
                Spacer()
                Pill(icon: "bolt", val: String(format: "%.3f W", model.gpuPower),
                     color: Color(hex: "FFD60A"))
            }
            .padding(.top, 2)
        }
    }
}

// MARK: - Memory

private struct MemorySection: View {
    @ObservedObject var model: SystemStatsModel

    var pressureLabel: String {
        switch model.memPressureLevel {
        case 4:  return "Critical"
        case 2:  return "Warning"
        default: return "Normal"
        }
    }
    var pressureColor: Color {
        switch model.memPressureLevel {
        case 4:  return Color(hex: "FF453A")
        case 2:  return Color(hex: "FFD60A")
        default: return Color(hex: "30D158")
        }
    }

    var body: some View {
        SectionBox(icon: "memorychip", title: "Memory") {
            Row(label: "\(fmtB(model.memUsed)) / \(fmtB(model.memTotal))") {
                StatBar(pct: model.memPct, color: Color(hex: "0A84FF"))
            }
            HStack(spacing: 5) {
                Circle().fill(pressureColor).frame(width: 6, height: 6)
                Text("Pressure: \(pressureLabel)")
                    .font(.system(size: 11)).foregroundColor(pressureColor)
                Spacer()
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    KV("App",        fmtB(model.memApp))
                    KV("Wired",      fmtB(model.memWired))
                }
                GridRow {
                    KV("Compressed", fmtB(model.memCompressed))
                    KV("Cached",     fmtB(model.memCached))
                }
                GridRow {
                    KV("DRAM BW",    String(format: "%.1f GB/s", model.dramBW))
                    KV("Swap", model.swapTotal > 0
                        ? "\(fmtB(model.swapUsed)) / \(fmtB(model.swapTotal))" : "None")
                }
            }
            .padding(.top, 2)
        }
    }
}

// MARK: - System (uptime, load average)

private struct SystemSection: View {
    @ObservedObject var model: SystemStatsModel
    var body: some View {
        SectionBox(icon: "clock", title: "System") {
            HStack(spacing: 16) {
                KV("Uptime", fmtUptime(model.uptime))
                KV("Load (1·5·15m)",
                   model.loadAvg.map { String(format: "%.2f", $0) }.joined(separator: " · "))
            }
        }
    }
}

// MARK: - Disk

private struct DiskSection: View {
    @ObservedObject var model: SystemStatsModel
    var body: some View {
        SectionBox(icon: "internaldrive", title: "Disk") {
            Row(label: "\(fmtB(model.diskSpaceUsed)) / \(fmtB(model.diskSpaceTotal))") {
                StatBar(pct: model.diskSpacePct, color: Color(hex: "BF5AF2"))
            }
            HStack(spacing: 16) {
                IORow(icon: "arrow.down", val: String(format: "%.0f KB/s", model.diskReadKBs),  color: Color(hex:"64D2FF"))
                IORow(icon: "arrow.up",   val: String(format: "%.0f KB/s", model.diskWriteKBs), color: Color(hex:"FF9F0A"))
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
        model.batteryPct < 20 ? Color(hex: "FF453A")
            : (model.batteryCharging || model.batteryCharged)
                ? Color(hex: "30D158") : Color(hex: "FFD60A")
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
                        ? formatTemp(model.batteryTempC, decimals: 1) : "—")
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

// MARK: - Network

private struct NetworkSection: View {
    @ObservedObject var model: SystemStatsModel

    var isWiFi: Bool { model.netLinkType == "Wi-Fi" }

    var signalLabel: String {
        model.wifiRSSI == 0 ? "—" : "\(model.wifiRSSI) dBm"
    }
    var signalColor: Color {
        let r = model.wifiRSSI
        if r == 0   { return Color(hex: "666680") }
        if r >= -60 { return Color(hex: "30D158") }
        if r >= -70 { return Color(hex: "FFD60A") }
        return Color(hex: "FF453A")
    }

    var icon: String {
        model.netLinkType == "Ethernet" ? "cable.connector" : "wifi"
    }

    var body: some View {
        SectionBox(icon: icon, title: "Network") {
            HStack(spacing: 16) {
                IORow(icon: "arrow.down", val: fmtB(model.netInBps)  + "/s", color: Color(hex:"30D158"))
                IORow(icon: "arrow.up",   val: fmtB(model.netOutBps) + "/s", color: Color(hex:"FF9F0A"))
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    KV("Connection", model.netLinkType.isEmpty ? "—" : model.netLinkType)
                    KV("IP", model.ipAddress)
                }
                if isWiFi {
                    GridRow {
                        KV("SSID", model.ssid.isEmpty ? "—" : model.ssid)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Signal").font(.system(size: 9)).foregroundColor(Color(hex: "666680"))
                            Text(signalLabel)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(signalColor)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.top, 2)
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
                .foregroundColor(highlight ? Color(hex:"FFD60A") : Color(hex:"888899"))
            Spacer()
            Text(String(format: val >= 1 ? "%.2f W" : "%.3f W", val))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(highlight ? Color(hex:"FFD60A") : .primary)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Color.primary.opacity(highlight ? 0.07 : 0.03))
        .cornerRadius(6)
    }
}

// MARK: - Processes

private struct ProcessSection: View {
    @ObservedObject var model: SystemStatsModel
    var body: some View {
        SectionBox(icon: "list.bullet", title: "Top Processes") {
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
                        .foregroundColor(Color(hex: "64D2FF"))
                        .frame(width: 64, alignment: .trailing)
                }
            }
        }
    }
    func cpuClr(_ v: Double) -> Color {
        v >= 50 ? Color(hex:"FF453A") : v >= 20 ? Color(hex:"FFD60A") : Color(hex:"30D158")
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
            .buttonStyle(.borderedProminent).tint(Color(hex: "FF9F0A")).disabled(working)

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
    @AppStorage("showDockIcon")  var showDockIcon  = false
    @AppStorage("appTheme") private var appTheme = AppTheme.automatic.rawValue

    // Display
    @AppStorage("tempUnit")        var tempUnit        = "C"
    @AppStorage("cpuOnlyMenuBar")  var cpuOnlyMenuBar  = false
    @AppStorage("refreshInterval") var refreshInterval = 2
    @AppStorage("topProcCount")    var topProcCount    = 8

    // Dashboard section visibility
    @AppStorage("showCPU")       var showCPU       = true
    @AppStorage("showGPU")       var showGPU       = true
    @AppStorage("showMemory")    var showMemory    = true
    @AppStorage("showDisk")      var showDisk      = true
    @AppStorage("showSystem")    var showSystem    = true
    @AppStorage("showBattery")   var showBattery   = true
    @AppStorage("showNetwork")   var showNetwork   = true
    @AppStorage("showPower")     var showPower     = true
    @AppStorage("showProcesses") var showProcesses = true

    @ObservedObject private var updater = UpdateChecker.shared
    @ObservedObject private var location = LocationAuthManager.shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Settings")
                        .font(.system(size: 16, weight: .bold)).foregroundColor(.primary)

                    generalGroup
                    displayGroup
                    sectionsGroup
                }
                .padding(22)
            }

            Divider().background(Color.primary.opacity(0.1))

            aboutBar
                .padding(.horizontal, 22).padding(.vertical, 14)
        }
        .frame(width: 320, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(AppTheme(rawValue: appTheme)?.colorScheme)
    }

    // MARK: General

    private var generalGroup: some View {
        VStack(alignment: .leading, spacing: 14) {
            groupHeader("General")

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Open at Login", isOn: $openAtLogin)
                    .toggleStyle(SwitchToggleStyle(tint: Color(hex: "30D158")))
                    .onChange(of: openAtLogin) { enabled in
                        if enabled {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                    }
                settingCaption("Automatically start MacMonitor when you log in.")
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
                settingCaption("Right-click your desktop → Edit Widgets → find MacMonitor. It refreshes automatically while MacMonitor is running.")
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Show Dock Icon", isOn: $showDockIcon)
                    .toggleStyle(SwitchToggleStyle(tint: Color(hex: "30D158")))
                    .onChange(of: showDockIcon) { on in
                        NSApp.setActivationPolicy(on ? .regular : .accessory)
                        if on { NSApp.activate(ignoringOtherApps: true) }
                    }
                settingCaption("Show MacMonitor in the Dock and app switcher.")
            }
        }
    }

    // MARK: Display

    private var displayGroup: some View {
        VStack(alignment: .leading, spacing: 14) {
            groupHeader("Display")

            VStack(alignment: .leading, spacing: 6) {
                settingRow("Appearance") {
                    Picker("", selection: $appTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.label).tag(theme.rawValue)
                        }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 170)
                }
                settingCaption("Automatic follows your Mac’s current appearance.")
            }

            settingRow("Temperature") {
                Picker("", selection: $tempUnit) {
                    Text("°C").tag("C")
                    Text("°F").tag("F")
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 110)
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("CPU Percentage Only", isOn: $cpuOnlyMenuBar)
                    .toggleStyle(SwitchToggleStyle(tint: Color(hex: "30D158")))
                settingCaption("Show a compact value such as 12% in the menu bar.")
            }

            settingRow("Refresh") {
                Picker("", selection: $refreshInterval) {
                    Text("1s").tag(1)
                    Text("2s").tag(2)
                    Text("5s").tag(5)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 110)
            }

            settingRow("Processes") {
                Picker("", selection: $topProcCount) {
                    Text("5").tag(5)
                    Text("8").tag(8)
                    Text("10").tag(10)
                    Text("15").tag(15)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 140)
            }

            VStack(alignment: .leading, spacing: 6) {
                settingRow("Wi-Fi name & signal") { wifiAccessControl }
                settingCaption("Shows the Wi-Fi network name and signal in the Network section. macOS requires Location access to read the network name.")
            }
        }
    }

    @ViewBuilder
    private var wifiAccessControl: some View {
        if location.isGranted {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                Text("Granted")
            }
            .font(.system(size: 11, weight: .medium)).foregroundColor(Color(hex: "30D158"))
        } else if location.isDenied {
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered).font(.system(size: 11))
        } else {
            Button("Allow") { location.request() }
                .buttonStyle(.borderedProminent).tint(Color(hex: "0A84FF"))
                .font(.system(size: 11, weight: .medium))
        }
    }

    // MARK: Dashboard sections

    private var sectionsGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            groupHeader("Dashboard Sections")
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                GridItem(.flexible(), alignment: .leading)],
                      spacing: 8) {
                compactToggle("CPU", $showCPU)
                compactToggle("GPU", $showGPU)
                compactToggle("Memory", $showMemory)
                compactToggle("Disk", $showDisk)
                compactToggle("System", $showSystem)
                compactToggle("Battery", $showBattery)
                compactToggle("Network", $showNetwork)
                compactToggle("Power Rails", $showPower)
                compactToggle("Processes", $showProcesses)
            }
        }
    }

    // MARK: Building blocks

    private func groupHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundColor(.secondary).tracking(0.6)
    }

    private func settingCaption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11)).foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func settingToggle(_ title: String, _ binding: Binding<Bool>,
                               _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(title, isOn: binding)
                .toggleStyle(SwitchToggleStyle(tint: Color(hex: "30D158")))
            settingCaption(caption)
        }
    }

    private func settingRow<Content: View>(_ title: String,
                                           @ViewBuilder _ control: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12)).foregroundColor(.primary)
            Spacer()
            control()
        }
    }

    private func compactToggle(_ title: String, _ binding: Binding<Bool>) -> some View {
        Toggle(title, isOn: binding)
            .toggleStyle(SwitchToggleStyle(tint: Color(hex: "30D158")))
            .font(.system(size: 12))
            .foregroundColor(.primary)
    }

    // MARK: About / update

    private var aboutBar: some View {
        HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("MacMonitor  v\(updater.currentVersion)")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(.primary)
                    Group {
                        switch updater.updatePhase {
                        case .idle:
                            if updater.updateAvailable {
                                Text("v\(updater.latestVersion) available")
                                    .foregroundColor(Color(hex: "FF9F0A"))
                            } else {
                                Text("Apple Silicon  ·  macOS 13+  ·  MIT")
                                    .foregroundColor(.secondary)
                            }
                        case .downloading:
                            Text("Downloading v\(updater.latestVersion)…")
                                .foregroundColor(Color(hex: "FF9F0A"))
                        case .installing:
                            Text("Installing…")
                                .foregroundColor(Color(hex: "FF9F0A"))
                        case .readyToRelaunch:
                            Text("Ready — relaunch to apply")
                                .foregroundColor(Color(hex: "30D158"))
                        case .failed(let msg):
                            Text(msg)
                                .foregroundColor(Color(hex: "FF453A"))
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
                                    .tint(Color(hex: "FF9F0A"))
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            Button("Done") { isPresented = false }
                                .buttonStyle(.borderedProminent)
                                .tint(Color(hex: "0A84FF"))
                        }
                    case .downloading:
                        VStack(alignment: .trailing, spacing: 3) {
                            ProgressView(value: updater.downloadFraction)
                                .progressViewStyle(.linear)
                                .tint(Color(hex: "FF9F0A"))
                                .frame(width: 80)
                            Text("\(Int(updater.downloadFraction * 100))%")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    case .installing:
                        ProgressView()
                            .scaleEffect(0.75)
                            .tint(Color(hex: "FF9F0A"))
                    case .readyToRelaunch:
                        Button("Relaunch") { updater.relaunch() }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(hex: "30D158"))
                            .font(.system(size: 12, weight: .semibold))
                    case .failed:
                        Button("Dismiss") { updater.dismissUpdateError() }
                            .buttonStyle(.bordered)
                            .font(.system(size: 12))
                    }
                }
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
                    .foregroundColor(Color(hex: "888899"))
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "888899")).tracking(0.6)
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
    let pct: Int; var color: Color = Color(hex: "30D158")
    private var barColor: Color {
        pct >= 85 ? Color(hex:"FF453A") : pct >= 60 ? Color(hex:"FFD60A") : color
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
    let index: Int; let pct: Double; let isE: Bool
    var color: Color {
        pct >= 85 ? Color(hex:"FF453A") : pct >= 60 ? Color(hex:"FFD60A")
            : (isE ? Color(hex:"64D2FF") : Color(hex:"BF5AF2"))
    }
    var body: some View {
        HStack(spacing: 5) {
            Text("C\(index)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(color.opacity(0.7))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 22, alignment: .leading)
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

private func fmtUptime(_ seconds: TimeInterval) -> String {
    let s = Int(seconds)
    let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
    if d > 0 { return "\(d)d \(h)h \(m)m" }
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
}

private func tempColor(_ t: Double) -> Color {
    t >= 80 ? Color(hex:"FF453A") : t >= 65 ? Color(hex:"FFD60A") : Color(hex:"888899")
}

// MARK: - Hex colour helper

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
