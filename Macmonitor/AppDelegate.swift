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
        NSApp.setActivationPolicy(.accessory)

        setupMenuBar()
        model.startMonitoring()

        // Drive the label from published model values — fires immediately on change
        Publishers.CombineLatest3(model.$cpuUsage, model.$memPct, model.$cpuTemp)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cpu, mem, temp in
                self?.updateLabel(cpu: cpu, mem: mem, temp: temp)
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
            btn.title  = "🟢 CPU --%  MEM --%"
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

    private func updateLabel(cpu: Int, mem: Int, temp: Double) {
        guard let btn = statusItem?.button else { return }
        let dot = cpu >= 85 || mem >= 85 ? "🔴"
                : cpu >= 60 || mem >= 60 ? "🟡" : "🟢"
        let tempStr = temp > 0 ? String(format: " %.0f°", temp) : ""
        btn.title = "\(dot) CPU \(cpu)%\(tempStr)  MEM \(mem)%"
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
            popover.contentViewController?.view.window?.makeKey()
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
            contentRect:  NSRect(x: 0, y: 0, width: 320, height: 280),
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
