import AppKit
import SwiftUI
import Combine
import ServiceManagement
import WidgetKit

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {

    var statusItem: NSStatusItem?
    var popover    = NSPopover()
    var welcomeWin: NSWindow?
    var settingsWin: NSWindow?
    let model      = SystemStatsModel()

    // Anchor tracking for the popover — see beginTrackingAnchor(_:).
    private var anchorObservers: [NSObjectProtocol] = []
    private var anchorOrigin: NSPoint?
    private var outsideClickMonitor: Any?
    private var lastWidgetReload = Date.distantPast

    // Subscribe to model changes so the label updates in sync with each tick,
    // not on a separate independent timer that may fire before data is ready.
    private var cancellables = Set<AnyCancellable>()
    private var lastCPU = 0
    private var lastMem = 0
    private var lastTemp = 0.0
    private var isCPUOnlyMenuBar = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UserDefaults.standard.register(defaults: [
            "cpuOnlyMenuBar": false,
            "appTheme": AppTheme.automatic.rawValue
        ])
        isCPUOnlyMenuBar = UserDefaults.standard.bool(forKey: "cpuOnlyMenuBar")

        setupMenuBar()
        model.startMonitoring()

        // Drive the label from published model values — fires immediately on change
        Publishers.CombineLatest3(model.$cpuUsage, model.$memPct, model.$cpuTemp)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cpu, mem, temp in
                self?.lastCPU = cpu
                self?.lastMem = mem
                self?.lastTemp = temp
                self?.updateLabel(cpu: cpu, mem: mem, temp: temp)
                self?.refreshWidgetsIfDue()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let isCPUOnly = UserDefaults.standard.bool(forKey: "cpuOnlyMenuBar")
                guard isCPUOnly != self.isCPUOnlyMenuBar else { return }
                self.isCPUOnlyMenuBar = isCPUOnly
                self.updateLabel(cpu: self.lastCPU, mem: self.lastMem, temp: self.lastTemp)
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
            btn.toolTip = "MacMonitor"
            btn.target = self
            btn.action = #selector(handleClick)
            btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.contentSize = NSSize(width: 340, height: 640)
        popover.behavior    = .transient
        popover.animates    = true
        popover.delegate    = self
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(model: model)
        )
    }

    private func createCircleImage(color: NSColor, size: CGFloat = 10.0) -> NSImage {
        let imageSize = CGFloat(22)
        let image = NSImage(size: NSSize(width: imageSize, height: imageSize))
        image.lockFocus()
        color.set()
        let rect = NSRect(
            x: (imageSize - size) / 2,
            y: (imageSize - size) / 2,
            width: size,
            height: size
        )
        NSBezierPath(ovalIn: rect).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func updateLabel(cpu: Int, mem: Int, temp: Double) {
        guard let btn = statusItem?.button else { return }
        if isCPUOnlyMenuBar {
            btn.image = nil
            btn.title = "\(cpu)%"
            btn.toolTip = "CPU usage: \(cpu)%"
            return
        }

        let color: NSColor
        if cpu >= 85 || mem >= 85 {
            color = .systemRed
        } else if cpu >= 60 || mem >= 60 {
            color = .systemYellow
        } else {
            color = .systemGreen
        }

        btn.image = createCircleImage(color: color)
        btn.title = ""
        btn.attributedTitle = NSAttributedString(string: "")

        let tempStr = temp > 0 ? String(format: " %.0f°C", temp) : ""
        btn.toolTip = "CPU: \(cpu)%\(tempStr)\nMEM: \(mem)%"
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
            beginTrackingAnchor(sender)
        }
    }

    // MARK: - Anchor tracking

    /// The popover is positioned relative to the status item button. In native
    /// full-screen mode the menu bar auto-hides, which slides the button's window
    /// off the top of the screen. AppKit keeps the popover attached to that anchor,
    /// so it flashes and lands in the top-right corner with its top edge clipped.
    ///
    /// Rather than fight AppKit's positioning, dismiss the popover as soon as the
    /// anchor stops being a valid thing to point at.
    private func beginTrackingAnchor(_ button: NSStatusBarButton) {
        endTrackingAnchor()

        guard let anchorWindow = button.window else { return }
        anchorOrigin = anchorWindow.frame.origin

        let center = NotificationCenter.default

        // The menu bar retracting moves the status item's window.
        anchorObservers.append(
            center.addObserver(forName: NSWindow.didMoveNotification,
                               object: anchorWindow,
                               queue: .main) { [weak self] _ in
                self?.closeIfAnchorInvalid(anchorWindow)
            }
        )

        // Display or Space changes can also relocate the anchor.
        anchorObservers.append(
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                               object: nil,
                               queue: .main) { [weak self] _ in
                self?.closeIfAnchorInvalid(anchorWindow)
            }
        )

        // Collapse when the user clicks anything outside the dashboard, the same way
        // clicking the menu bar icon again collapses it.
        //
        // NSPopover.behavior = .transient is supposed to do this, but the app runs as
        // .accessory: a click in another application is delivered to that application
        // and never reaches us, so the popover just sits there. A global monitor sees
        // those events. It deliberately does not fire for clicks inside our own
        // windows — global monitors only observe events routed to other apps — so
        // interacting with the dashboard itself won't dismiss it, and clicking the menu
        // bar icon still goes through togglePopover.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.dismissPopoverSoon()
        }
    }

    private func closeIfAnchorInvalid(_ anchorWindow: NSWindow) {
        guard popover.isShown else { return }

        // Only a *vertical* move means the menu bar itself retracted.
        //
        // The status item uses NSStatusItem.variableLength and its title is rewritten
        // on every metrics tick, so the label's width changes whenever a value gains or
        // loses a digit. Menu bar items are laid out from the right, so a width change
        // shifts the anchor window's origin.x — which is not a reason to dismiss.
        // Comparing the full origin here closed the popover roughly once a second and
        // made the dashboard impossible to interact with.
        if let origin = anchorOrigin, abs(anchorWindow.frame.origin.y - origin.y) > 1 {
            dismissPopoverSoon()
            return
        }

        // Anchor left its screen entirely — nothing valid to point at. Deliberately
        // checks for *no* intersection rather than full containment, so a status item
        // that is merely clipped by a crowded menu bar doesn't dismiss the popover.
        if let screen = anchorWindow.screen, !screen.frame.intersects(anchorWindow.frame) {
            dismissPopoverSoon()
        }
    }

    /// Closes the popover on a later runloop pass rather than inline.
    ///
    /// Both triggers here are window-geometry notifications, which AppKit posts from
    /// inside a CoreAnimation transaction. Tearing the popover down synchronously at
    /// that point re-enters window animation teardown and can over-release
    /// `_NSWindowTransformAnimation`, which showed up as an EXC_BAD_ACCESS in
    /// `objc_release` under `CA::Context::commit_transaction`. Deferring lets the
    /// current transaction finish before the popover goes away.
    private func dismissPopoverSoon() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.popover.isShown else { return }
            self.popover.performClose(nil)
        }
    }

    private func endTrackingAnchor() {
        for observer in anchorObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        anchorObservers.removeAll()
        anchorOrigin = nil

        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    // MARK: - Widget refresh

    // Measured, not guessed. chronod honoured app-driven reloads at a strict 30s with
    // no drops, then at 5s (renders every 5.4-6.4s, zero rejections), so the throttle
    // was always the bottleneck rather than the system budget. Now 2s.
    //
    // This is the floor worth using. Each reload wakes the widget extension, which then
    // samples CPU over a 0.4s window before rendering, so a shorter interval would keep
    // that process almost continuously awake for a glanceable snapshot. The dashboard is
    // the live view; widgets are snapshot-based by design and cannot stream.
    private static let widgetReloadInterval: TimeInterval = 2

    /// Pushes a timeline reload to the desktop widget so it tracks the dashboard.
    ///
    /// The widget samples its own data, but left alone it only refreshes on the cadence
    /// WidgetKit grants it — far slower than the app's sampling, and its timeline policy
    /// is only a request, not a guarantee. While the app is running we can drive reloads
    /// so the widget stays close to live.
    ///
    /// Throttled deliberately: WidgetKit budgets reloads per extension and starts
    /// dropping them when one is too chatty, so reloading on every metrics tick would
    /// make the widget update *less* often, not more.
    private func refreshWidgetsIfDue() {
        let now = Date()
        guard now.timeIntervalSince(lastWidgetReload) >= Self.widgetReloadInterval else { return }
        lastWidgetReload = now
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        endTrackingAnchor()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Drop the reference so the next "Settings…" builds a fresh window rather
        // than trying to reuse a closed one. Covers both Done and the close button.
        if (notification.object as? NSWindow) === settingsWin {
            settingsWin = nil
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
        win.backgroundColor             = .windowBackgroundColor
        win.contentViewController       = NSHostingController(rootView: WelcomeView())
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        welcomeWin = win
    }

    // MARK: - Settings window

    @objc func openSettings() {
        // Reuse the existing window instead of stacking a new one on every invocation.
        if let existing = settingsWin {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let win = NSWindow(
            contentRect:  NSRect(x: 0, y: 0, width: 360, height: 460),
            styleMask:    [.titled, .closable, .fullSizeContentView],
            backing:      .buffered,
            defer:        false
        )
        win.title                      = "MacMonitor Settings"
        win.titlebarAppearsTransparent = true
        // Adaptive so the window tracks the chosen appearance (#14) rather than
        // being pinned to a dark hex value.
        win.backgroundColor            = .windowBackgroundColor
        win.isReleasedWhenClosed       = false

        // SettingsSheet drives dismissal through its isPresented binding. As a
        // standalone window this used to be passed .constant(true), which is
        // read-only — so tapping Done wrote to nothing and the window never closed.
        // Back the binding with an actual close, weakly so the window and its
        // content view don't retain each other.
        let dismiss = Binding<Bool>(
            get: { true },
            set: { [weak win] shouldPresent in
                if !shouldPresent { win?.performClose(nil) }
            }
        )

        // No preferredColorScheme override — SettingsSheet applies the user's
        // Automatic/Light/Dark choice itself.
        win.contentViewController = NSHostingController(
            rootView: SettingsSheet(isPresented: dismiss)
        )
        win.delegate = self
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWin = win
    }
}
