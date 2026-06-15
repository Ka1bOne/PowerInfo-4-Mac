import Cocoa
import IOKit.ps

class PowerNotificationApp: NSObject, NSApplicationDelegate {
    var window: NSPanel?
    var timer: Timer?
    var statusItem: NSStatusItem?
    
    // Settings Keys
    let keyPosition = "Position"       // 0: Bottom Center, 1: Top Right, 2: Center
    let keyStyle = "Style"             // 0: Regular HUD, 1: Compact Pill
    let keyDuration = "Duration"       // Double (seconds)
    let keyNotifyPlugged = "NotifyPlugged"
    let keyNotifyUnplugged = "NotifyUnplugged"
    let keyNotifyLowPower = "NotifyLowPower"
    let keyNotifyBatteryLow = "NotifyBatteryLow"
    
    var durationValueField: NSTextField?
    var settingsWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register default user settings
        UserDefaults.standard.register(defaults: [
            keyPosition: 0,
            keyStyle: 0,
            keyDuration: 1.5,
            keyNotifyPlugged: true,
            keyNotifyUnplugged: true,
            keyNotifyLowPower: true,
            keyNotifyBatteryLow: true
        ])
        
        setupWindow()
        setupPowerMonitoring()
        setupLowPowerMonitoring()
        setupStatusItem()
        
        // Test popup on launch to verify UI
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.showPopup(state: self.isCurrentlyPluggedIn() ? .plugged : .unplugged)
        }
        
        // Hide from Dock
        NSApp.setActivationPolicy(.accessory)
    }
    
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            if let image = NSImage(systemSymbolName: "powerplug", accessibilityDescription: "PowerInfo")?.withSymbolConfiguration(config) {
                button.image = image
            } else {
                button.title = "⚡️"
            }
        }
        
        setupMenu()
    }
    
    func setupMenu() {
        let menu = NSMenu()
        
        let titleItem = NSMenuItem(title: "PowerInfo v1.0", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettingsWindow), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        let testItem = NSMenuItem(title: "Test HUD Notification", action: #selector(triggerTestHUD), keyEquivalent: "t")
        testItem.target = self
        menu.addItem(testItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit PowerInfo", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    @objc func showSettingsWindow() {
        if settingsWindow == nil {
            createSettingsWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    
    func createSettingsWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 350),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "PowerInfo Settings"
        window.center()
        
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 16
        container.alignment = .leading
        container.distribution = .fill
        
        // 1. Style Choice
        let styleLabel = NSTextField(labelWithString: "Notification Style:")
        styleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        
        let stylePopUp = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 25), pullsDown: false)
        stylePopUp.addItems(withTitles: ["Regular HUD (Vertical)", "Compact Pill (Horizontal)"])
        stylePopUp.selectItem(at: UserDefaults.standard.integer(forKey: keyStyle))
        stylePopUp.target = self
        stylePopUp.action = #selector(styleChanged(_:))
        
        let styleStack = NSStackView()
        styleStack.orientation = .horizontal
        styleStack.spacing = 10
        styleStack.addArrangedSubview(styleLabel)
        styleStack.addArrangedSubview(stylePopUp)
        
        // 2. Position Choice
        let positionLabel = NSTextField(labelWithString: "Screen Position:")
        positionLabel.font = .systemFont(ofSize: 13, weight: .bold)
        
        let positionPopUp = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 25), pullsDown: false)
        positionPopUp.addItems(withTitles: ["Bottom Center", "Top Right", "Center of Screen"])
        positionPopUp.selectItem(at: UserDefaults.standard.integer(forKey: keyPosition))
        positionPopUp.target = self
        positionPopUp.action = #selector(positionChanged(_:))
        
        let positionStack = NSStackView()
        positionStack.orientation = .horizontal
        positionStack.spacing = 10
        positionStack.addArrangedSubview(positionLabel)
        positionStack.addArrangedSubview(positionPopUp)
        
        // 3. Duration Slider
        let durationLabel = NSTextField(labelWithString: "HUD Display Duration:")
        durationLabel.font = .systemFont(ofSize: 13, weight: .bold)
        
        let durationVal = UserDefaults.standard.double(forKey: keyDuration)
        let durationSlider = NSSlider(value: durationVal, minValue: 0.5, maxValue: 5.0, target: self, action: #selector(durationChanged(_:)))
        durationSlider.widthAnchor.constraint(equalToConstant: 160).isActive = true
        
        let durationText = NSTextField(labelWithString: String(format: "%.1fs", durationVal))
        durationText.font = .systemFont(ofSize: 13, weight: .medium)
        durationText.widthAnchor.constraint(equalToConstant: 40).isActive = true
        self.durationValueField = durationText
        
        let durationStack = NSStackView()
        durationStack.orientation = .horizontal
        durationStack.spacing = 10
        durationStack.alignment = .centerY
        durationStack.addArrangedSubview(durationLabel)
        durationStack.addArrangedSubview(durationSlider)
        durationStack.addArrangedSubview(durationText)
        
        // 4. Enabled Notification Events (Checkboxes)
        let eventsLabel = NSTextField(labelWithString: "Enable Notifications For:")
        eventsLabel.font = .systemFont(ofSize: 13, weight: .bold)
        
        let pluggedCheckbox = NSButton(checkboxWithTitle: "Charger Connected", target: self, action: #selector(eventToggled(_:)))
        pluggedCheckbox.state = UserDefaults.standard.bool(forKey: keyNotifyPlugged) ? .on : .off
        pluggedCheckbox.tag = 1
        
        let unpluggedCheckbox = NSButton(checkboxWithTitle: "Charger Disconnected", target: self, action: #selector(eventToggled(_:)))
        unpluggedCheckbox.state = UserDefaults.standard.bool(forKey: keyNotifyUnplugged) ? .on : .off
        unpluggedCheckbox.tag = 2
        
        let lowPowerCheckbox = NSButton(checkboxWithTitle: "Low Power Mode Changes", target: self, action: #selector(eventToggled(_:)))
        lowPowerCheckbox.state = UserDefaults.standard.bool(forKey: keyNotifyLowPower) ? .on : .off
        lowPowerCheckbox.tag = 3
        
        let batteryLowCheckbox = NSButton(checkboxWithTitle: "Battery Low (≤ 15%)", target: self, action: #selector(eventToggled(_:)))
        batteryLowCheckbox.state = UserDefaults.standard.bool(forKey: keyNotifyBatteryLow) ? .on : .off
        batteryLowCheckbox.tag = 4
        
        let checkboxesStack = NSStackView()
        checkboxesStack.orientation = .vertical
        checkboxesStack.spacing = 6
        checkboxesStack.alignment = .leading
        checkboxesStack.addArrangedSubview(pluggedCheckbox)
        checkboxesStack.addArrangedSubview(unpluggedCheckbox)
        checkboxesStack.addArrangedSubview(lowPowerCheckbox)
        checkboxesStack.addArrangedSubview(batteryLowCheckbox)
        
        // Add layouts to central container
        container.addArrangedSubview(styleStack)
        container.addArrangedSubview(positionStack)
        container.addArrangedSubview(durationStack)
        container.addArrangedSubview(eventsLabel)
        container.addArrangedSubview(checkboxesStack)
        
        // Bottom Actions Stack
        let testBtn = NSButton(title: "Test Active Notification Style", target: self, action: #selector(triggerTestHUD))
        testBtn.bezelStyle = .rounded
        
        let closeBtn = NSButton(title: "Close", target: self, action: #selector(closeSettings))
        closeBtn.bezelStyle = .rounded
        
        let bottomStack = NSStackView()
        bottomStack.orientation = .horizontal
        bottomStack.spacing = 10
        bottomStack.addArrangedSubview(testBtn)
        bottomStack.addArrangedSubview(closeBtn)
        
        container.addArrangedSubview(bottomStack)
        
        let view = NSView(frame: window.contentRect(forFrameRect: window.frame))
        view.addSubview(container)
        container.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
        ])
        
        window.contentView = view
        self.settingsWindow = window
    }
    
    @objc func styleChanged(_ sender: NSPopUpButton) {
        UserDefaults.standard.set(sender.indexOfSelectedItem, forKey: keyStyle)
    }
    
    @objc func positionChanged(_ sender: NSPopUpButton) {
        UserDefaults.standard.set(sender.indexOfSelectedItem, forKey: keyPosition)
    }
    
    @objc func durationChanged(_ sender: NSSlider) {
        let val = sender.doubleValue
        UserDefaults.standard.set(val, forKey: keyDuration)
        durationValueField?.stringValue = String(format: "%.1fs", val)
    }
    
    @objc func eventToggled(_ sender: NSButton) {
        let isEnabled = (sender.state == .on)
        switch sender.tag {
        case 1: UserDefaults.standard.set(isEnabled, forKey: keyNotifyPlugged)
        case 2: UserDefaults.standard.set(isEnabled, forKey: keyNotifyUnplugged)
        case 3: UserDefaults.standard.set(isEnabled, forKey: keyNotifyLowPower)
        case 4: UserDefaults.standard.set(isEnabled, forKey: keyNotifyBatteryLow)
        default: break
        }
    }
    
    @objc func closeSettings() {
        settingsWindow?.close()
    }
    
    @objc func triggerTestHUD() {
        self.showPopup(state: self.isCurrentlyPluggedIn() ? .plugged : .unplugged)
    }
    
    @objc func quitApp() {
        NSApp.terminate(nil)
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
        visualEffect.material = .hudWindow // Light HUD look
        visualEffect.state = .active
        visualEffect.maskImage = NSImage(size: visualEffect.bounds.size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: 20, yRadius: 20)
            path.fill()
            return true
        }
        
        panel.contentView?.addSubview(visualEffect)
        
        self.window = panel
    }
    
    enum PowerState: Equatable {
        case plugged
        case unplugged
        case lowPowerOn
        case lowPowerOff
        case unpluggedAndLowPower
        case pluggedAndLowPowerOff
        case batteryLow
    }
    
    func getBatteryStatus() -> (percentage: Int, isLowPower: Bool, isPlugged: Bool, timeRemaining: Int) {
        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let isPlugged = isCurrentlyPluggedIn()
        var percentage = 0
        var timeRemaining = -1
        
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return (0, isLowPower, isPlugged, timeRemaining)
        }
        
        for source in sources {
            let description = IOPSGetPowerSourceDescription(blob, source).takeUnretainedValue() as! [String: Any]
            if let current = description[kIOPSCurrentCapacityKey] as? Int,
               let max = description[kIOPSMaxCapacityKey] as? Int {
                percentage = Int((Double(current) / Double(max)) * 100)
                
                if !isPlugged {
                    timeRemaining = description[kIOPSTimeToEmptyKey] as? Int ?? -1
                } else {
                    timeRemaining = description[kIOPSTimeToFullChargeKey] as? Int ?? -1
                }
                
                break
            }
        }
        return (percentage, isLowPower, isPlugged, timeRemaining)
    }

    func formatTimeRemaining(_ minutes: Int, isPlugged: Bool) -> String? {
        // <= 0 catches 0m which happens when the SMC is calculating right after plug-in
        if minutes <= 0 || minutes > 6000 { return nil }
        let hrs = minutes / 60
        let mins = minutes % 60
        let timeString = hrs > 0 ? "\(hrs)h \(mins)m" : "\(mins)m"
        return isPlugged ? "\(timeString) to full" : "\(timeString) left"
    }

    func showPopup(state: PowerState) {
        guard let window = self.window, let contentView = window.contentView else { return }
        
        // 1. Check if the notification event is enabled in user preferences
        let notifyPlugged = UserDefaults.standard.bool(forKey: keyNotifyPlugged)
        let notifyUnplugged = UserDefaults.standard.bool(forKey: keyNotifyUnplugged)
        let notifyLowPower = UserDefaults.standard.bool(forKey: keyNotifyLowPower)
        let notifyBatteryLow = UserDefaults.standard.bool(forKey: keyNotifyBatteryLow)
        
        switch state {
        case .plugged:
            if !notifyPlugged { return }
        case .unplugged:
            if !notifyUnplugged { return }
        case .lowPowerOn, .lowPowerOff:
            if !notifyLowPower { return }
        case .unpluggedAndLowPower:
            if !notifyUnplugged { return }
        case .pluggedAndLowPowerOff:
            if !notifyPlugged { return }
        case .batteryLow:
            if !notifyBatteryLow { return }
        }
        
        let iconName: String
        let text: String
        let iconColor: NSColor
        
        switch state {
        case .plugged:
            iconName = "powerplug.fill"
            text = "Plugged In"
            iconColor = .systemGreen
        case .unplugged:
            iconName = "powerplug"
            text = "Unplugged"
            iconColor = .white
        case .lowPowerOn:
            iconName = "battery.100.bolt"
            text = "Low Power Mode On"
            iconColor = .systemYellow
        case .lowPowerOff:
            iconName = "battery.100"
            text = "Low Power Mode Off"
            iconColor = .white
        case .unpluggedAndLowPower:
            iconName = "battery.100.bolt"
            text = "Unplugged • Low Power"
            iconColor = .systemYellow
        case .pluggedAndLowPowerOff:
            iconName = "powerplug.fill"
            text = "Plugged In • Low Power Off"
            iconColor = .systemGreen
        case .batteryLow:
            iconName = "battery.25"
            text = "Low Battery"
            iconColor = .systemRed
        }
        
        // 2. Determine layout style (HUD vs Compact Pill) and isWide
        let isWide = (state == .unpluggedAndLowPower || state == .pluggedAndLowPowerOff)
        let style = UserDefaults.standard.integer(forKey: keyStyle) // 0: Regular HUD, 1: Compact Pill
        
        let panelWidth: CGFloat
        let panelHeight: CGFloat
        
        if style == 0 { // Regular HUD
            panelWidth = isWide ? 360 : 250
            panelHeight = 250
        } else { // Compact Pill
            panelWidth = isWide ? 320 : 220
            panelHeight = 68
        }
        
        // 3. Determine positioning on active display screen
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let x: CGFloat
            let y: CGFloat
            
            let position = UserDefaults.standard.integer(forKey: keyPosition) // 0: Bottom Center, 1: Top Right, 2: Center
            
            switch position {
            case 1: // Top Right
                x = screenRect.maxX - panelWidth - 40
                y = screenRect.maxY - panelHeight - 40
            case 2: // Center
                x = screenRect.origin.x + (screenRect.width - panelWidth) / 2
                y = screenRect.origin.y + (screenRect.height - panelHeight) / 2
            default: // 0: Bottom Center
                x = screenRect.origin.x + (screenRect.width - panelWidth) / 2
                y = screenRect.origin.y + 40
            }
            
            window.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: false)
        }
        
        // 4. Rebuild visual effect mask to match style corner radius
        let cornerRadius: CGFloat = (style == 1) ? 34 : 20
        if let ve = contentView.subviews.first(where: { $0 is NSVisualEffectView }) as? NSVisualEffectView {
            ve.frame = contentView.bounds
            ve.maskImage = NSImage(size: ve.bounds.size, flipped: false) { rect in
                let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
                path.fill()
                return true
            }
        }
        
        // 5. Clear previous views and construct the view hierarchy
        contentView.subviews.forEach { if !($0 is NSVisualEffectView) { $0.removeFromSuperview() } }
        
        let status = getBatteryStatus()
        var statusParts: [String] = ["\(status.percentage)%"]
        
        if let timeStr = formatTimeRemaining(status.timeRemaining, isPlugged: status.isPlugged) {
            statusParts.append(timeStr)
        }
        
        if status.isLowPower && state != .lowPowerOn && state != .unpluggedAndLowPower {
            statusParts.append("Low Power")
        }
        let statusText = statusParts.joined(separator: " • ")
        
        let stack = NSStackView()
        
        if style == 0 { // Regular HUD - Vertical Stack
            stack.orientation = .vertical
            stack.spacing = 8
            stack.alignment = .centerX
            stack.distribution = .fill
            
            let config = NSImage.SymbolConfiguration(pointSize: 80, weight: .bold)
            let iconImage = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?.withSymbolConfiguration(config)
            let imageView = NSImageView(image: iconImage!)
            imageView.contentTintColor = iconColor
            
            let textField = NSTextField(labelWithString: text)
            textField.font = .systemFont(ofSize: 22, weight: .bold)
            textField.textColor = .white
            textField.alignment = .center
            
            let statusField = NSTextField(labelWithString: statusText)
            statusField.font = .systemFont(ofSize: 16, weight: .medium)
            statusField.textColor = (state == .batteryLow) ? .systemRed.withAlphaComponent(0.9) : (status.isLowPower ? .systemYellow : .white.withAlphaComponent(0.8))
            statusField.alignment = .center
            
            stack.addArrangedSubview(imageView)
            stack.addArrangedSubview(textField)
            stack.addArrangedSubview(statusField)
        } else { // Compact Pill - Horizontal Stack
            stack.orientation = .horizontal
            stack.spacing = 14
            stack.alignment = .centerY
            stack.distribution = .fill
            
            let config = NSImage.SymbolConfiguration(pointSize: 30, weight: .bold)
            let iconImage = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?.withSymbolConfiguration(config)
            let imageView = NSImageView(image: iconImage!)
            imageView.contentTintColor = iconColor
            
            let textStack = NSStackView()
            textStack.orientation = .vertical
            textStack.spacing = 2
            textStack.alignment = .leading
            textStack.distribution = .fill
            
            let textField = NSTextField(labelWithString: text)
            textField.font = .systemFont(ofSize: 15, weight: .bold)
            textField.textColor = .white
            textField.alignment = .left
            
            let statusField = NSTextField(labelWithString: statusText)
            statusField.font = .systemFont(ofSize: 12, weight: .medium)
            statusField.textColor = (state == .batteryLow) ? .systemRed.withAlphaComponent(0.9) : (status.isLowPower ? .systemYellow : .white.withAlphaComponent(0.8))
            statusField.alignment = .left
            
            textStack.addArrangedSubview(textField)
            textStack.addArrangedSubview(statusField)
            
            stack.addArrangedSubview(imageView)
            stack.addArrangedSubview(textStack)
        }
        
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
        
        // 6. Schedule timer based on the display duration setting
        let displayDuration = UserDefaults.standard.double(forKey: keyDuration)
        timer?.invalidate()
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
        let status = getBatteryStatus()
        lastPowerState = status.isPlugged
        lastBatteryPercentage = status.percentage
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
        let status = getBatteryStatus()
        let currentState = status.isPlugged
        let currentPercentage = status.percentage
        
        let batteryCrossed15 = (lastBatteryPercentage ?? 100) > 15 && currentPercentage <= 15
        
        if lastPowerState != currentState {
            lastPowerState = currentState
            // Wait 0.3s so macOS has time to update low power state after cable change
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
                if currentState {
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
        } else if batteryCrossed15 && !currentState {
            self.showPopup(state: .batteryLow)
        }
        
        lastBatteryPercentage = currentPercentage
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
    private var lastBatteryPercentage: Int?
}

let app = NSApplication.shared
let delegate = PowerNotificationApp()
app.delegate = delegate
app.run()
