import Cocoa
import IOKit.ps
import ServiceManagement

class PowerNotificationApp: NSObject, NSApplicationDelegate {
    var window: NSPanel?
    var timer: Timer?
    var statusItem: NSStatusItem?
    var settingsWindow: NSWindow?
    var lastNotifiedThreshold: Int = 100
    private var lastPowerState: Bool?
    private var lastLowPowerState: Bool?
    private var lastHighPowerState: Bool = false
    private var lastThermalState: ProcessInfo.ThermalState = .nominal

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupDefaults()
        setupMenuBar()
        setupWindow()
        setupPowerMonitoring()
        setupLowPowerMonitoring()
        setupBatteryThresholdMonitoring()
        setupHighPowerMonitoring()
        setupThermalMonitoring()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.showPopup(state: self.isCurrentlyPluggedIn() ? .plugged : .unplugged)
        }
        NSApp.setActivationPolicy(.accessory)
    }

    func setupDefaults() {
        let d = UserDefaults.standard
        if d.object(forKey: "enableThresholdAlerts") == nil { d.set(true, forKey: "enableThresholdAlerts") }
        if d.object(forKey: "themePref") == nil { d.set(0, forKey: "themePref") }
        if d.object(forKey: "hudStyle") == nil { d.set(0, forKey: "hudStyle") }
        if d.object(forKey: "enableThermalAlerts") == nil { d.set(true, forKey: "enableThermalAlerts") }
        if d.object(forKey: "enableHighPowerAlerts") == nil { d.set(true, forKey: "enableHighPowerAlerts") }
    }

    // MARK: - Menu Bar

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "bolt.batteryblock.fill", accessibilityDescription: "PowerInfo")
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit PowerInfo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    // MARK: - Settings Window

    @objc func openSettings() {
        if settingsWindow == nil {
            let w: CGFloat = 320
            let h: CGFloat = 360
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            win.title = "PowerInfo Settings"
            win.center()
            win.isReleasedWhenClosed = false
            win.level = .floating

            let cv = NSView(frame: win.contentRect(forFrameRect: win.frame))
            let lm: CGFloat = 20
            var y: CGFloat = h

            func sectionHeader(_ title: String) {
                y -= 30
                let lbl = NSTextField(labelWithString: title.uppercased())
                lbl.font = .systemFont(ofSize: 11, weight: .semibold)
                lbl.textColor = .secondaryLabelColor
                lbl.frame = NSRect(x: lm, y: y, width: 280, height: 16)
                cv.addSubview(lbl)
                y -= 4
            }

            func separator() {
                y -= 8
                let box = NSBox()
                box.boxType = .separator
                box.frame = NSRect(x: lm, y: y, width: w - lm * 2, height: 1)
                cv.addSubview(box)
                y -= 4
            }

            func checkbox(_ title: String, key: String, action: Selector) -> NSButton {
                y -= 26
                let btn = NSButton(checkboxWithTitle: title, target: self, action: action)
                btn.frame = NSRect(x: lm, y: y, width: 280, height: 20)
                btn.state = UserDefaults.standard.bool(forKey: key) ? .on : .off
                cv.addSubview(btn)
                return btn
            }

            func popupRow(_ label: String, items: [String], key: String, action: Selector, labelW: CGFloat = 75) {
                y -= 32
                let lbl = NSTextField(labelWithString: label)
                lbl.frame = NSRect(x: lm, y: y + 3, width: labelW, height: 20)
                cv.addSubview(lbl)
                let popup = NSPopUpButton(frame: NSRect(x: lm + labelW + 4, y: y, width: 160, height: 26), pullsDown: false)
                popup.addItems(withTitles: items)
                popup.selectItem(at: UserDefaults.standard.integer(forKey: key))
                popup.target = self
                popup.action = action
                cv.addSubview(popup)
            }

            // Notifications
            sectionHeader("Notifications")
            _ = checkbox("Enable 20% & 10% Battery Alerts", key: "enableThresholdAlerts", action: #selector(toggleThreshold(_:)))
            _ = checkbox("Enable Thermal Alerts", key: "enableThermalAlerts", action: #selector(toggleThermalAlerts(_:)))
            _ = checkbox("Enable High Power Mode Alerts", key: "enableHighPowerAlerts", action: #selector(toggleHighPowerAlerts(_:)))

            separator()

            // Appearance
            sectionHeader("Appearance")
            popupRow("Theme:", items: ["System", "Dark", "Light"], key: "themePref", action: #selector(themeChanged(_:)))
            popupRow("HUD Style:", items: ["Large HUD", "Compact Toast"], key: "hudStyle", action: #selector(hudStyleChanged(_:)), labelW: 80)

            separator()

            // System
            sectionHeader("System")
            y -= 26
            let loginBtn = NSButton(checkboxWithTitle: "Launch at Login", target: self, action: #selector(toggleLaunchAtLogin(_:)))
            loginBtn.frame = NSRect(x: lm, y: y, width: 280, height: 20)
            loginBtn.state = isLaunchAtLoginEnabled() ? .on : .off
            cv.addSubview(loginBtn)

            // Test button
            y -= 40
            let testBtn = NSButton(title: "Test Notification", target: self, action: #selector(testNotification))
            testBtn.frame = NSRect(x: lm, y: y, width: 150, height: 26)
            cv.addSubview(testBtn)

            win.contentView = cv
            settingsWindow = win
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func toggleThreshold(_ s: NSButton)    { UserDefaults.standard.set(s.state == .on, forKey: "enableThresholdAlerts") }
    @objc func toggleThermalAlerts(_ s: NSButton) { UserDefaults.standard.set(s.state == .on, forKey: "enableThermalAlerts") }
    @objc func toggleHighPowerAlerts(_ s: NSButton) { UserDefaults.standard.set(s.state == .on, forKey: "enableHighPowerAlerts") }
    @objc func themeChanged(_ s: NSPopUpButton)   { UserDefaults.standard.set(s.indexOfSelectedItem, forKey: "themePref") }
    @objc func hudStyleChanged(_ s: NSPopUpButton) { UserDefaults.standard.set(s.indexOfSelectedItem, forKey: "hudStyle") }
    @objc func testNotification()                 { showPopup(state: isCurrentlyPluggedIn() ? .plugged : .unplugged) }

    // MARK: - Launch at Login

    func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            return FileManager.default.fileExists(atPath: launchAgentPath())
        }
    }

    @objc func toggleLaunchAtLogin(_ s: NSButton) {
        setLaunchAtLogin(s.state == .on)
    }

    func setLaunchAtLogin(_ enable: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enable { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                let alert = NSAlert()
                alert.messageText = "Launch at Login Error"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        } else {
            if enable { writeLaunchAgent() } else { removeLaunchAgent() }
        }
    }

    func launchAgentPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/LaunchAgents/com.user.PowerInfo.plist"
    }

    func writeLaunchAgent() {
        let exec = Bundle.main.bundlePath + "/Contents/MacOS/PowerInfo"
        let plist = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>Label</key><string>com.user.PowerInfo</string>
    <key>ProgramArguments</key><array><string>\(exec)</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><false/>
</dict></plist>
"""
        let path = launchAgentPath()
        try? plist.write(toFile: path, atomically: true, encoding: .utf8)
        let p = Process(); p.launchPath = "/bin/launchctl"; p.arguments = ["load", path]; try? p.run()
    }

    func removeLaunchAgent() {
        let path = launchAgentPath()
        let p = Process(); p.launchPath = "/bin/launchctl"; p.arguments = ["unload", path]; try? p.run()
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Window Setup

    func setupWindow() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 250, height: 250),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .mainMenu + 1
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true

        if let screen = NSScreen.main {
            let r = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: r.origin.x + (r.width - 250) / 2, y: r.origin.y + 40))
        }

        let ve = NSVisualEffectView(frame: panel.contentView!.bounds)
        ve.blendingMode = .behindWindow
        applyTheme(to: ve)
        ve.state = .active
        ve.maskImage = roundedMask(size: ve.bounds.size, radius: 20)
        panel.contentView?.addSubview(ve)
        self.window = panel
    }

    func applyTheme(to ve: NSVisualEffectView) {
        ve.material = .hudWindow
        switch UserDefaults.standard.integer(forKey: "themePref") {
        case 1: ve.appearance = NSAppearance(named: .darkAqua)
        case 2: ve.appearance = NSAppearance(named: .aqua)
        default: ve.appearance = nil
        }
    }

    func roundedMask(size: CGSize, radius: CGFloat) -> NSImage {
        return NSImage(size: size, flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
    }

    // MARK: - Power States

    enum PowerState {
        case plugged, unplugged
        case lowPowerOn, lowPowerOff
        case unpluggedAndLowPower, pluggedAndLowPowerOff
        case battery20, battery10
        case highPowerOn, highPowerOff
        case thermalSerious, thermalCritical
    }

    func popupContent(for state: PowerState) -> (icon: String, text: String, isAlert: Bool, isWide: Bool) {
        switch state {
        case .plugged:               return ("powerplug.fill",       "Plugged In",                   false, false)
        case .unplugged:             return ("battery.100",           "Unplugged",                    false, false)
        case .lowPowerOn:            return ("leaf.fill",             "Low Power Mode On",             false, false)
        case .lowPowerOff:           return ("leaf",                  "Low Power Mode Off",            false, false)
        case .unpluggedAndLowPower:  return ("leaf.fill",             "Unplugged • Low Power Mode",   false, true)
        case .pluggedAndLowPowerOff: return ("powerplug.fill",       "Plugged In • Low Power Off",   false, true)
        case .battery20:             return ("battery.25",            "20% Battery Remaining",         true,  true)
        case .battery10:             return ("battery.0",             "10% Battery Remaining",         true,  true)
        case .highPowerOn:           return ("bolt.fill",             "High Power Mode On",            false, true)
        case .highPowerOff:          return ("bolt",                  "High Power Mode Off",           false, true)
        case .thermalSerious:        return ("thermometer.medium",    "High System Temperature",       true,  true)
        case .thermalCritical:       return ("thermometer.high",      "Critical Temperature!",         true,  true)
        }
    }

    // MARK: - Show Popup (dispatcher)

    func showPopup(state: PowerState) {
        DispatchQueue.main.async {
            if UserDefaults.standard.integer(forKey: "hudStyle") == 1 {
                self.showCompactToast(state: state)
            } else {
                self.showLargeHUD(state: state)
            }
        }
    }

    // MARK: - Large HUD

    func showLargeHUD(state: PowerState) {
        guard let window = self.window, let cv = window.contentView else { return }
        let c = popupContent(for: state)
        let isAlert = c.isAlert
        let panelW: CGFloat = (c.isWide || isAlert) ? 360 : 250
        let panelH: CGFloat = 250

        if let screen = NSScreen.main {
            let r = screen.visibleFrame
            window.setFrame(NSRect(x: r.origin.x + (r.width - panelW) / 2, y: r.origin.y + 40, width: panelW, height: panelH), display: false)
        }

        if let ve = cv.subviews.first(where: { $0 is NSVisualEffectView }) as? NSVisualEffectView {
            ve.frame = cv.bounds; applyTheme(to: ve)
            ve.maskImage = roundedMask(size: ve.bounds.size, radius: 20)
        }
        cv.subviews.forEach { if !($0 is NSVisualEffectView) { $0.removeFromSuperview() } }

        let stack = NSStackView(frame: cv.bounds.insetBy(dx: 20, dy: 20))
        stack.orientation = .vertical; stack.spacing = 8
        stack.alignment = .centerX; stack.distribution = .fill

        let cfg = NSImage.SymbolConfiguration(pointSize: 80, weight: .bold)
        let img = NSImage(systemSymbolName: c.icon, accessibilityDescription: nil)?.withSymbolConfiguration(cfg)
        let iv = NSImageView(image: img!)
        iv.contentTintColor = isAlert ? (state == .thermalCritical ? .systemOrange : .systemRed) : .white

        let tf = NSTextField(labelWithString: c.text)
        tf.font = .systemFont(ofSize: 22, weight: .bold); tf.textColor = .white; tf.alignment = .center

        let status = getBatteryStatus()
        var parts = ["\(status.percentage)%"]
        if status.isLowPower { parts.append("Low Power") }
        if lastHighPowerState { parts.append("High Power") }
        let sf = NSTextField(labelWithString: parts.joined(separator: " • "))
        sf.font = .systemFont(ofSize: 16, weight: .medium)
        sf.textColor = lastHighPowerState ? .systemBlue : (status.isLowPower ? .systemYellow : NSColor.white.withAlphaComponent(0.8))
        sf.alignment = .center

        [iv, tf, sf].forEach { stack.addArrangedSubview($0) }
        cv.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: cv.centerYAnchor)
        ])
        animateIn(window: window, displayDuration: isAlert ? 3.0 : 1.5)
    }

    // MARK: - Compact Toast

    func showCompactToast(state: PowerState) {
        guard let window = self.window, let cv = window.contentView else { return }
        let c = popupContent(for: state)
        let isAlert = c.isAlert
        let toastW: CGFloat = 280, toastH: CGFloat = 56

        if let screen = NSScreen.main {
            let r = screen.visibleFrame
            window.setFrame(NSRect(x: r.origin.x + (r.width - toastW) / 2,
                                   y: r.origin.y + r.height - toastH - 20,
                                   width: toastW, height: toastH), display: false)
        }

        if let ve = cv.subviews.first(where: { $0 is NSVisualEffectView }) as? NSVisualEffectView {
            ve.frame = cv.bounds; applyTheme(to: ve)
            ve.maskImage = roundedMask(size: ve.bounds.size, radius: toastH / 2)
        }
        cv.subviews.forEach { if !($0 is NSVisualEffectView) { $0.removeFromSuperview() } }

        let stack = NSStackView()
        stack.orientation = .horizontal; stack.spacing = 10; stack.alignment = .centerY

        let cfg = NSImage.SymbolConfiguration(pointSize: 22, weight: .bold)
        let img = NSImage(systemSymbolName: c.icon, accessibilityDescription: nil)?.withSymbolConfiguration(cfg)
        let iv = NSImageView(image: img!)
        iv.contentTintColor = isAlert ? (state == .thermalCritical ? .systemOrange : .systemRed) : .white
        iv.setContentHuggingPriority(.required, for: .horizontal)

        let tf = NSTextField(labelWithString: c.text)
        tf.font = .systemFont(ofSize: 14, weight: .semibold)
        tf.textColor = .white; tf.alignment = .left

        stack.addArrangedSubview(iv); stack.addArrangedSubview(tf)
        cv.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: cv.centerYAnchor)
        ])
        animateIn(window: window, displayDuration: isAlert ? 3.0 : 1.5)
    }

    func animateIn(window: NSPanel, displayDuration: TimeInterval) {
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            window.animator().alphaValue = 1.0
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: displayDuration, repeats: false) { _ in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.5
                window.animator().alphaValue = 0
            }, completionHandler: { window.orderOut(nil) })
        }
    }

    // MARK: - Battery Status

    func getBatteryStatus() -> (percentage: Int, isLowPower: Bool, isPlugged: Bool) {
        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let isPlugged = isCurrentlyPluggedIn()
        var pct = 0
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
            for src in sources {
                let d = IOPSGetPowerSourceDescription(blob, src).takeUnretainedValue() as! [String: Any]
                if let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int {
                    pct = Int((Double(cur) / Double(max)) * 100); break
                }
            }
        }
        return (pct, isLowPower, isPlugged)
    }

    func isCurrentlyPluggedIn() -> Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        for src in sources {
            let d = IOPSGetPowerSourceDescription(blob, src).takeUnretainedValue() as! [String: Any]
            if (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue { return true }
        }
        return false
    }

    // MARK: - Power Monitoring

    func setupPowerMonitoring() {
        let cb: @convention(c) (UnsafeMutableRawPointer?) -> Void = { ctx in
            guard let ctx = ctx else { return }
            Unmanaged<PowerNotificationApp>.fromOpaque(ctx).takeUnretainedValue().checkPowerStatus()
        }
        let src = IOPSNotificationCreateRunLoopSource(cb, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())).takeRetainedValue()
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .defaultMode)
        lastPowerState = isCurrentlyPluggedIn()
    }

    func checkPowerStatus() {
        let current = isCurrentlyPluggedIn()
        guard lastPowerState != current else { return }
        lastPowerState = current
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let lp = ProcessInfo.processInfo.isLowPowerModeEnabled
            if current {
                self.lastNotifiedThreshold = 100
                if !lp && self.lastLowPowerState == true { self.lastLowPowerState = false; self.showPopup(state: .pluggedAndLowPowerOff) }
                else { self.showPopup(state: .plugged) }
            } else {
                if lp { self.lastLowPowerState = true; self.showPopup(state: .unpluggedAndLowPower) }
                else { self.showPopup(state: .unplugged) }
            }
        }
    }

    // MARK: - Low Power Monitoring

    func setupLowPowerMonitoring() {
        NotificationCenter.default.addObserver(forName: NSNotification.Name("NSProcessInfoLowPowerModeDidChangeNotification"),
                                               object: nil, queue: .main) { _ in self.updateLowPowerStatus() }
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in self.updateLowPowerStatus() }
        lastLowPowerState = ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    func updateLowPowerStatus() {
        let cur = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard lastLowPowerState != cur else { return }
        lastLowPowerState = cur
        DispatchQueue.main.async { self.showPopup(state: cur ? .lowPowerOn : .lowPowerOff) }
    }

    // MARK: - Battery Threshold Monitoring

    func setupBatteryThresholdMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in self.checkBatteryThresholds() }
    }

    func checkBatteryThresholds() {
        guard UserDefaults.standard.bool(forKey: "enableThresholdAlerts") else { return }
        let s = getBatteryStatus()
        if s.isPlugged { lastNotifiedThreshold = 100; return }
        if s.percentage <= 10 && lastNotifiedThreshold > 10 {
            lastNotifiedThreshold = 10; showPopup(state: .battery10)
        } else if s.percentage <= 20 && s.percentage > 10 && lastNotifiedThreshold > 20 {
            lastNotifiedThreshold = 20; showPopup(state: .battery20)
        }
    }

    // MARK: - High Power Mode Monitoring

    func setupHighPowerMonitoring() {
        lastHighPowerState = getHighPowerModeState()
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in self.checkHighPowerMode() }
    }

    func getHighPowerModeState() -> Bool {
        let proc = Process()
        proc.launchPath = "/usr/bin/env"
        proc.arguments = ["pmset", "-g"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run(); proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            // Look for "highpowermode 1"
            if let range = output.range(of: "highpowermode") {
                let sub = output[range.upperBound...]
                return sub.contains("1")
            }
        } catch {}
        return false
    }

    func checkHighPowerMode() {
        guard UserDefaults.standard.bool(forKey: "enableHighPowerAlerts") else { return }
        let cur = getHighPowerModeState()
        guard lastHighPowerState != cur else { return }
        lastHighPowerState = cur
        DispatchQueue.main.async { self.showPopup(state: cur ? .highPowerOn : .highPowerOff) }
    }

    // MARK: - Thermal Monitoring

    func setupThermalMonitoring() {
        lastThermalState = ProcessInfo.processInfo.thermalState
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil, queue: .main
        ) { _ in self.checkThermalState() }
        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in self.checkThermalState() }
    }

    func checkThermalState() {
        guard UserDefaults.standard.bool(forKey: "enableThermalAlerts") else { return }
        let cur = ProcessInfo.processInfo.thermalState
        guard cur != lastThermalState else { return }
        let prev = lastThermalState
        lastThermalState = cur

        DispatchQueue.main.async {
            // Only alert when moving INTO serious/critical (not when recovering)
            if cur == .critical && prev != .critical {
                self.showPopup(state: .thermalCritical)
            } else if cur == .serious && prev == .nominal || cur == .serious && prev == .fair {
                self.showPopup(state: .thermalSerious)
            }
        }
    }
}

let app = NSApplication.shared
let delegate = PowerNotificationApp()
app.delegate = delegate
app.run()
