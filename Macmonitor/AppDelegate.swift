import AppKit
import SwiftUI
import Combine
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {

    var statusItem: NSStatusItem?
    var popover    = NSPopover()
    var welcomeWin: NSWindow?
    let model      = SystemStatsModel()

    // Subscribe to model changes so the label updates in sync with each tick,
    // not on a separate independent timer that may fire before data is ready.
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only by default; show in Dock when the user opts in.
        NSApp.setActivationPolicy(
            UserDefaults.standard.bool(forKey: "showDockIcon") ? .regular : .accessory)

        setupMenuBar()
        model.startMonitoring()

        // Drive the label from published model values — fires immediately on change.
        // Dot color uses memory *pressure* (the real health signal), not used %,
        // because macOS keeps used % high by design — it would pin the dot yellow.
        Publishers.CombineLatest4(model.$cpuUsage, model.$memPressureLevel, model.$cpuTemp, model.$totalPower)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cpu, pressure, temp, power in
                self?.updateLabel(cpu: cpu, pressure: pressure, temp: temp, power: power)
            }
            .store(in: &cancellables)

        // Restore Open at Login state on launch
        if UserDefaults.standard.bool(forKey: "openAtLogin") {
            try? SMAppService.mainApp.register()
        }

        // Show welcome window on very first launch
        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.showWelcomeWindow()
            }
        }

        // Check for updates in the background — non-blocking
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 5.0) {
            UpdateChecker.shared.check()
        }
    }

    // MARK: - Menu bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem?.button {
            btn.image = createCircleImage(color: .systemGreen)
            btn.title = ""
            btn.target = self
            btn.action = #selector(handleClick)
            btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.contentSize = NSSize(width: 340, height: 640)
        popover.behavior    = .transient
        popover.animates    = true
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(model: model).preferredColorScheme(.dark)
        )
    }

    private func createCircleImage(color: NSColor, size: CGFloat = 10.0) -> NSImage {
        let imageSize = CGFloat(22)
        let image = NSImage(size: NSSize(width: imageSize, height: imageSize))
        image.lockFocus()
        color.set()
        let rect = NSRect(x: (imageSize - size) / 2, y: (imageSize - size) / 2, width: size, height: size)
        let path = NSBezierPath(ovalIn: rect)
        path.fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func updateLabel(cpu: Int, pressure: Int, temp: Double, power: Double) {
        guard let btn = statusItem?.button else { return }

        // pressure: 1 = Normal, 2 = Warning, 4 = Critical
        let color: NSColor
        if cpu >= 85 || pressure >= 4 {
            color = .systemRed
        } else if cpu >= 60 || pressure >= 2 {
            color = .systemYellow
        } else {
            color = .systemGreen
        }

        // Menu bar content depends on the chosen style.
        switch UserDefaults.standard.string(forKey: "menuBarStyle") ?? "dot" {
        case "cpu":
            btn.image = nil
            setColoredTitle("\(cpu)%", color: color, on: btn)
        case "temp":
            btn.image = nil
            setColoredTitle(temp > 0 ? formatTemp(temp) : "—", color: color, on: btn)
        case "power":
            btn.image = nil
            setColoredTitle(String(format: "%.1fW", power), color: color, on: btn)
        default: // "dot"
            btn.image = createCircleImage(color: color)
            btn.title = ""
            btn.attributedTitle = NSAttributedString(string: "")
        }

        let pressureWord = pressure >= 4 ? "Critical" : pressure >= 2 ? "Warning" : "Normal"
        let tempStr = temp > 0 ? String(format: " %@", formatTemp(temp)) : ""
        btn.toolTip = "CPU: \(cpu)% \(tempStr)\nMEM: \(model.memPct)%  ·  Pressure: \(pressureWord)"
    }

    private func setColoredTitle(_ text: String, color: NSColor, on btn: NSStatusBarButton) {
        btn.attributedTitle = NSAttributedString(string: text, attributes: [
            .foregroundColor: color,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
        ])
    }

    // MARK: - Click handling

    @objc func handleClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover(sender)
        }
    }

    func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            if let win = popover.contentViewController?.view.window {
                // Let the popover float into another app's fullscreen Space.
                // Without this it only appears over fullscreen apps when we run as
                // an accessory app; with the Dock icon on (.regular) it would
                // otherwise be confined to the app's own Space.
                win.collectionBehavior.insert(.canJoinAllSpaces)
                win.collectionBehavior.insert(.fullScreenAuxiliary)
                win.makeKey()
            }
        }
    }

    func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Dashboard",
                                action: #selector(openPopover), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…",
                                action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit MacMonitor",
                                action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc func openPopover() {
        if let btn = statusItem?.button { togglePopover(btn) }
    }

    // MARK: - Welcome window

    func showWelcomeWindow() {
        let win = NSWindow(
            contentRect:  NSRect(x: 0, y: 0, width: 480, height: 420),
            styleMask:    [.titled, .closable, .fullSizeContentView],
            backing:      .buffered,
            defer:        false
        )
        win.titlebarAppearsTransparent  = true
        win.titleVisibility             = .hidden
        win.isMovableByWindowBackground = true
        win.backgroundColor             = NSColor(Color(hex: "0E0E12"))
        win.contentViewController       = NSHostingController(rootView: WelcomeView())
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        welcomeWin = win
    }

    // MARK: - Settings window

    @objc func openSettings() {
        let win = NSWindow(
            contentRect:  NSRect(x: 0, y: 0, width: 320, height: 560),
            styleMask:    [.titled, .closable, .fullSizeContentView],
            backing:      .buffered,
            defer:        false
        )
        win.title                      = "MacMonitor Settings"
        win.titlebarAppearsTransparent = true
        win.backgroundColor            = NSColor(Color(hex: "1C1C1E"))
        win.contentViewController      = NSHostingController(
            rootView: SettingsSheet(isPresented: .constant(true))
                .preferredColorScheme(.dark)
        )
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
