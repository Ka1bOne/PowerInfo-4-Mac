import Cocoa
import IOKit.ps

class PowerNotificationApp: NSObject, NSApplicationDelegate {
    var window: NSPanel?
    var timer: Timer?
    var statusItem: NSStatusItem?
    var settingsWindow: NSWindow?
    var lastNotifiedThreshold: Int = 100
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupDefaults()
        setupMenuBar()
        setupWindow()
        setupPowerMonitoring()
        setupLowPowerMonitoring()
        setupBatteryThresholdMonitoring()
        
        // Test popup on launch to verify UI
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.showPopup(state: self.isCurrentlyPluggedIn() ? .plugged : .unplugged)
        }
        
        // Hide from Dock
        NSApp.setActivationPolicy(.accessory)
    }
    
    func setupDefaults() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "enableThresholdAlerts") == nil {
            defaults.set(true, forKey: "enableThresholdAlerts")
        }
        if defaults.object(forKey: "themePref") == nil {
            defaults.set(0, forKey: "themePref") // 0: System HUD, 1: Dark, 2: Light
        }
    }
    
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
    
    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "PowerInfo Settings"
            window.center()
            window.isReleasedWhenClosed = false
            window.level = .floating
            
            let contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))
            
            // Threshold toggle
            let thresholdBtn = NSButton(checkboxWithTitle: "Enable 20% & 10% Battery Alerts", target: self, action: #selector(toggleThreshold(_:)))
            thresholdBtn.frame = NSRect(x: 20, y: 140, width: 260, height: 20)
            thresholdBtn.state = UserDefaults.standard.bool(forKey: "enableThresholdAlerts") ? .on : .off
            contentView.addSubview(thresholdBtn)
            
            // Theme selector
            let themeLabel = NSTextField(labelWithString: "Theme:")
            themeLabel.isEditable = false
            themeLabel.isBordered = false
            themeLabel.backgroundColor = .clear
            themeLabel.frame = NSRect(x: 20, y: 70, width: 50, height: 20)
            contentView.addSubview(themeLabel)
            
            let themePopup = NSPopUpButton(frame: NSRect(x: 70, y: 65, width: 120, height: 25), pullsDown: false)
            themePopup.addItems(withTitles: ["System", "Dark", "Light"])
            themePopup.selectItem(at: UserDefaults.standard.integer(forKey: "themePref"))
            themePopup.target = self
            themePopup.action = #selector(themeChanged(_:))
            contentView.addSubview(themePopup)
            
            // Test Notification Button
            let testBtn = NSButton(title: "Test Notification", target: self, action: #selector(testNotification))
            testBtn.frame = NSRect(x: 20, y: 20, width: 150, height: 25)
            contentView.addSubview(testBtn)
            
            window.contentView = contentView
            settingsWindow = window
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func toggleThreshold(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "enableThresholdAlerts")
    }

    @objc func themeChanged(_ sender: NSPopUpButton) {
        UserDefaults.standard.set(sender.indexOfSelectedItem, forKey: "themePref")
    }
    
    @objc func testNotification() {
        showPopup(state: isCurrentlyPluggedIn() ? .plugged : .unplugged)
    }
    
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
        
        // Position at bottom center (like volume HUD)
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let x = screenRect.origin.x + (screenRect.width - 250) / 2
            let y = screenRect.origin.y + 40 // Lower positioning
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        let visualEffect = NSVisualEffectView(frame: panel.contentView!.bounds)
        visualEffect.blendingMode = .behindWindow
        applyTheme(to: visualEffect)
        visualEffect.state = .active
        visualEffect.maskImage = NSImage(size: visualEffect.bounds.size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: 20, yRadius: 20)
            path.fill()
            return true
        }
        
        panel.contentView?.addSubview(visualEffect)
        
        self.window = panel
    }
    
    func applyTheme(to visualEffect: NSVisualEffectView) {
        let themePref = UserDefaults.standard.integer(forKey: "themePref")
        visualEffect.material = .hudWindow
        if themePref == 1 {
            visualEffect.appearance = NSAppearance(named: .darkAqua)
        } else if themePref == 2 {
            visualEffect.appearance = NSAppearance(named: .aqua)
        } else {
            visualEffect.appearance = nil // System Default
        }
    }
    
    enum PowerState {
        case plugged
        case unplugged
        case lowPowerOn
        case lowPowerOff
        case unpluggedAndLowPower
        case pluggedAndLowPowerOff
        case battery20
        case battery10
    }
    
    func getBatteryStatus() -> (percentage: Int, isLowPower: Bool, isPlugged: Bool) {
        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let isPlugged = isCurrentlyPluggedIn()
        var percentage = 0
        
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return (0, isLowPower, isPlugged)
        }
        
        for source in sources {
            let description = IOPSGetPowerSourceDescription(blob, source).takeUnretainedValue() as! [String: Any]
            if let current = description[kIOPSCurrentCapacityKey] as? Int,
               let max = description[kIOPSMaxCapacityKey] as? Int {
                percentage = Int((Double(current) / Double(max)) * 100)
                break
            }
        }
        return (percentage, isLowPower, isPlugged)
    }

    func showPopup(state: PowerState) {
        guard let window = self.window, let contentView = window.contentView else { return }
        
        let iconName: String
        let text: String
        var isAlert = false
        
        switch state {
        case .plugged:
            iconName = "powerplug.fill"
            text = "Plugged In"
        case .unplugged:
            iconName = "battery.100"
            text = "Unplugged"
        case .lowPowerOn:
            iconName = "leaf.fill"
            text = "Low Power Mode On"
        case .lowPowerOff:
            iconName = "leaf"
            text = "Low Power Mode Off"
        case .unpluggedAndLowPower:
            iconName = "leaf.fill"
            text = "Unplugged • Low Power Mode"
        case .pluggedAndLowPowerOff:
            iconName = "powerplug.fill"
            text = "Plugged In • Low Power Off"
        case .battery20:
            iconName = "battery.25"
            text = "20% Battery Remaining"
            isAlert = true
        case .battery10:
            iconName = "battery.0"
            text = "10% Battery Remaining"
            isAlert = true
        }
        
        let isWide = (state == .unpluggedAndLowPower || state == .pluggedAndLowPowerOff || isAlert)
        let panelWidth: CGFloat = isWide ? 360 : 250
        let panelHeight: CGFloat = 250
        
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let x = screenRect.origin.x + (screenRect.width - panelWidth) / 2
            let y = screenRect.origin.y + 40
            window.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: false)
        }
        
        // Rebuild visual effect mask to match new size and apply theme
        if let ve = contentView.subviews.first(where: { $0 is NSVisualEffectView }) as? NSVisualEffectView {
            ve.frame = contentView.bounds
            applyTheme(to: ve)
            ve.maskImage = NSImage(size: ve.bounds.size, flipped: false) { rect in
                let path = NSBezierPath(roundedRect: rect, xRadius: 20, yRadius: 20)
                path.fill()
                return true
            }
        }
        
        // Clear previous content views
        contentView.subviews.forEach { if !($0 is NSVisualEffectView) { $0.removeFromSuperview() } }
        
        let stack = NSStackView(frame: contentView.bounds.insetBy(dx: 20, dy: 20))
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .centerX
        stack.distribution = .fill
        
        let config = NSImage.SymbolConfiguration(pointSize: 80, weight: .bold)
        let iconImage = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        
        let imageView = NSImageView(image: iconImage!)
        imageView.contentTintColor = isAlert ? .systemRed : .white
        
        let textField = NSTextField(labelWithString: text)
        textField.font = .systemFont(ofSize: 22, weight: .bold)
        textField.textColor = .white
        textField.alignment = .center
        
        // Add status line (Percentage and Low Power Status)
        let status = getBatteryStatus()
        var statusParts: [String] = ["\(status.percentage)%"]
        
        if status.isLowPower {
            statusParts.append("Low Power")
        }
        
        let statusText = statusParts.joined(separator: " • ")
        let statusField = NSTextField(labelWithString: statusText)
        statusField.font = .systemFont(ofSize: 16, weight: .medium)
        statusField.textColor = status.isLowPower ? .systemYellow : .white.withAlphaComponent(0.8)
        statusField.alignment = .center
        
        stack.addArrangedSubview(imageView)
        stack.addArrangedSubview(textField)
        stack.addArrangedSubview(statusField)
        
        contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
        
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            window.animator().alphaValue = 1.0
        }
        
        timer?.invalidate()
        let displayDuration = isAlert ? 3.0 : 1.5
        timer = Timer.scheduledTimer(withTimeInterval: displayDuration, repeats: false) { _ in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.5
                window.animator().alphaValue = 0
            }, completionHandler: {
                window.orderOut(nil)
            })
        }
    }
    
    func setupPowerMonitoring() {
        let callback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { context in
            guard let context = context else { return }
            let app = Unmanaged<PowerNotificationApp>.fromOpaque(context).takeUnretainedValue()
            app.checkPowerStatus()
        }
        
        let runLoopSource = IOPSNotificationCreateRunLoopSource(callback, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())).takeRetainedValue()
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)
        
        // Initial check to store current state
        lastPowerState = isCurrentlyPluggedIn()
    }
    
    func setupLowPowerMonitoring() {
        // Notification-based monitoring
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("NSProcessInfoLowPowerModeDidChangeNotification"),
            object: nil,
            queue: .main
        ) { _ in
            self.updateLowPowerStatus()
        }
        
        // Polling-based fallback (every 2 seconds)
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            self.updateLowPowerStatus()
        }
        
        lastLowPowerState = ProcessInfo.processInfo.isLowPowerModeEnabled
    }
    
    func setupBatteryThresholdMonitoring() {
        // Check battery level every 30 seconds
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            self.checkBatteryThresholds()
        }
    }
    
    func checkBatteryThresholds() {
        guard UserDefaults.standard.bool(forKey: "enableThresholdAlerts") else { return }
        
        let status = getBatteryStatus()
        if status.isPlugged {
            lastNotifiedThreshold = 100 // Reset when plugged in
            return
        }
        
        let level = status.percentage
        if level <= 10 && lastNotifiedThreshold > 10 {
            lastNotifiedThreshold = 10
            showPopup(state: .battery10)
        } else if level <= 20 && level > 10 && lastNotifiedThreshold > 20 {
            lastNotifiedThreshold = 20
            showPopup(state: .battery20)
        }
    }
    
    func updateLowPowerStatus() {
        let currentState = ProcessInfo.processInfo.isLowPowerModeEnabled
        if lastLowPowerState != currentState {
            lastLowPowerState = currentState
            DispatchQueue.main.async {
                self.showPopup(state: currentState ? .lowPowerOn : .lowPowerOff)
            }
        }
    }
    
    func checkPowerStatus() {
        let currentState = isCurrentlyPluggedIn()
        if lastPowerState != currentState {
            lastPowerState = currentState
            // Wait 0.3s so macOS has time to update low power state after cable change
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
                if currentState {
                    self.lastNotifiedThreshold = 100 // Reset threshold notification state
                    // Plugged in — check if low power auto-disabled
                    if !isLowPower && self.lastLowPowerState == true {
                        self.lastLowPowerState = false
                        self.showPopup(state: .pluggedAndLowPowerOff)
                    } else {
                        self.showPopup(state: .plugged)
                    }
                } else {
                    // Unplugged — check if low power auto-enabled
                    if isLowPower {
                        self.lastLowPowerState = true
                        self.showPopup(state: .unpluggedAndLowPower)
                    } else {
                        self.showPopup(state: .unplugged)
                    }
                }
            }
        }
    }
    
    func isCurrentlyPluggedIn() -> Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }
        
        for source in sources {
            let description = IOPSGetPowerSourceDescription(blob, source).takeUnretainedValue() as! [String: Any]
            if let powerSourceState = description[kIOPSPowerSourceStateKey] as? String {
                if powerSourceState == kIOPSACPowerValue {
                    return true
                }
            }
        }
        return false
    }
    
    private var lastPowerState: Bool?
    private var lastLowPowerState: Bool?
}

let app = NSApplication.shared
let delegate = PowerNotificationApp()
app.delegate = delegate
app.run()

