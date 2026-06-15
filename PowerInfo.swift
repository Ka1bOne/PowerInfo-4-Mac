import Cocoa
import IOKit.ps
import IOKit

class PowerNotificationApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var window: NSPanel?
    var timer: Timer?
    var statusItem: NSStatusItem?
    var settingsWindow: NSWindow?
    var settingsHealthField: NSTextField?
    var settingsCyclesField: NSTextField?
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
        if defaults.object(forKey: "enableLowPowerAlerts") == nil {
            defaults.set(true, forKey: "enableLowPowerAlerts")
        }
        if defaults.object(forKey: "enableHighPowerAlerts") == nil {
            defaults.set(true, forKey: "enableHighPowerAlerts")
        }
        if defaults.object(forKey: "themePref") == nil {
            defaults.set(0, forKey: "themePref") // 0: System HUD, 1: Dark, 2: Light
        }
        if defaults.object(forKey: "notificationStyle") == nil {
            defaults.set(0, forKey: "notificationStyle") // 0: Normal HUD, 1: Compact Toast
        }
        
        // Register fallback defaults
        let appDefaults: [String: Any] = [
            "enableThresholdAlerts": true,
            "enableLowPowerAlerts": true,
            "enableHighPowerAlerts": true,
            "themePref": 0,
            "notificationStyle": 0
        ]
        defaults.register(defaults: appDefaults)
    }
    
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            let image = NSImage(systemSymbolName: "bolt.batteryblock.fill", accessibilityDescription: "PowerInfo")
            image?.isTemplate = true
            button.image = image
        }
        
        let menu = NSMenu()
        menu.delegate = self
        
        let headerItem = NSMenuItem(title: "PowerInfo Status", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        
        let healthItem = NSMenuItem(title: "Battery Health: Checking...", action: nil, keyEquivalent: "")
        healthItem.isEnabled = false
        healthItem.tag = 101
        menu.addItem(healthItem)
        
        let cyclesItem = NSMenuItem(title: "Battery Cycles: Checking...", action: nil, keyEquivalent: "")
        cyclesItem.isEnabled = false
        cyclesItem.tag = 102
        menu.addItem(cyclesItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit PowerInfo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    func menuWillOpen(_ menu: NSMenu) {
        let health = getBatteryMaximumCapacityPercent()
        let cycles = getBatteryCycleCount()
        
        if let healthItem = menu.item(withTag: 101) {
            if let health = health {
                healthItem.title = "Battery Health: \(health)%"
                healthItem.isHidden = false
            } else {
                healthItem.isHidden = true
            }
        }
        
        if let cyclesItem = menu.item(withTag: 102) {
            if let cycles = cycles {
                cyclesItem.title = "Battery Cycles: \(cycles)"
                cyclesItem.isHidden = false
            } else {
                cyclesItem.isHidden = true
            }
        }
    }
    
    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 390),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "PowerInfo Settings"
            window.center()
            window.isReleasedWhenClosed = false
            window.level = .floating
            
            let visualEffect = NSVisualEffectView(frame: window.contentView!.bounds)
            visualEffect.blendingMode = .behindWindow
            visualEffect.material = .windowBackground
            visualEffect.state = .active
            visualEffect.autoresizingMask = [.width, .height]
            window.contentView?.addSubview(visualEffect)
            
            let mainStack = NSStackView()
            mainStack.orientation = .vertical
            mainStack.spacing = 14
            mainStack.alignment = .leading
            mainStack.translatesAutoresizingMaskIntoConstraints = false
            visualEffect.addSubview(mainStack)
            
            NSLayoutConstraint.activate([
                mainStack.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: 20),
                mainStack.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: -20),
                mainStack.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 20),
                mainStack.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -20)
            ])
            
            // Header Section
            let headerStack = NSStackView()
            headerStack.orientation = .horizontal
            headerStack.spacing = 10
            headerStack.alignment = .centerY
            
            let iconConfig = NSImage.SymbolConfiguration(pointSize: 26, weight: .semibold)
            let iconImage = NSImage(systemSymbolName: "bolt.batteryblock.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(iconConfig)
            let iconView = NSImageView(image: iconImage ?? NSImage())
            iconView.contentTintColor = .systemGreen
            
            let titleStack = NSStackView()
            titleStack.orientation = .vertical
            titleStack.spacing = 2
            titleStack.alignment = .leading
            
            let titleField = NSTextField(labelWithString: "PowerInfo")
            titleField.font = .systemFont(ofSize: 18, weight: .bold)
            titleField.textColor = .labelColor
            
            let subtitleField = NSTextField(labelWithString: "Macbook Power Utility")
            subtitleField.font = .systemFont(ofSize: 11)
            subtitleField.textColor = .secondaryLabelColor
            
            titleStack.addArrangedSubview(titleField)
            titleStack.addArrangedSubview(subtitleField)
            
            headerStack.addArrangedSubview(iconView)
            headerStack.addArrangedSubview(titleStack)
            mainStack.addArrangedSubview(headerStack)
            
            // Divider 1
            let divider1 = NSBox()
            divider1.boxType = .separator
            mainStack.addArrangedSubview(divider1)
            divider1.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
            
            // Stats Section (Health & Cycles)
            let statsStack = NSStackView()
            statsStack.orientation = .horizontal
            statsStack.spacing = 0
            statsStack.distribution = .fillEqually
            statsStack.alignment = .centerY
            
            let healthWidget = NSStackView()
            healthWidget.orientation = .vertical
            healthWidget.spacing = 4
            healthWidget.alignment = .centerX
            let healthTitle = NSTextField(labelWithString: "BATTERY HEALTH")
            healthTitle.font = .systemFont(ofSize: 10, weight: .bold)
            healthTitle.textColor = .secondaryLabelColor
            let healthVal = NSTextField(labelWithString: "--")
            healthVal.font = .systemFont(ofSize: 22, weight: .bold)
            healthVal.textColor = .labelColor
            healthWidget.addArrangedSubview(healthTitle)
            healthWidget.addArrangedSubview(healthVal)
            self.settingsHealthField = healthVal
            
            let cyclesWidget = NSStackView()
            cyclesWidget.orientation = .vertical
            cyclesWidget.spacing = 4
            cyclesWidget.alignment = .centerX
            let cyclesTitle = NSTextField(labelWithString: "CYCLE COUNT")
            cyclesTitle.font = .systemFont(ofSize: 10, weight: .bold)
            cyclesTitle.textColor = .secondaryLabelColor
            let cyclesVal = NSTextField(labelWithString: "--")
            cyclesVal.font = .systemFont(ofSize: 22, weight: .bold)
            cyclesVal.textColor = .labelColor
            cyclesWidget.addArrangedSubview(cyclesTitle)
            cyclesWidget.addArrangedSubview(cyclesVal)
            self.settingsCyclesField = cyclesVal
            
            statsStack.addArrangedSubview(healthWidget)
            statsStack.addArrangedSubview(cyclesWidget)
            mainStack.addArrangedSubview(statsStack)
            statsStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
            
            // Divider 2
            let divider2 = NSBox()
            divider2.boxType = .separator
            mainStack.addArrangedSubview(divider2)
            divider2.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
            
            // Controls Section (Checkbox & Theme Popup & Style Popup)
            let controlsStack = NSStackView()
            controlsStack.orientation = .vertical
            controlsStack.spacing = 8
            controlsStack.alignment = .leading
            
            let thresholdBtn = NSButton(checkboxWithTitle: "Enable 20% & 10% Battery Alerts", target: self, action: #selector(toggleThreshold(_:)))
            thresholdBtn.state = UserDefaults.standard.bool(forKey: "enableThresholdAlerts") ? .on : .off
            thresholdBtn.font = .systemFont(ofSize: 13)
            controlsStack.addArrangedSubview(thresholdBtn)
            
            let lowPowerBtn = NSButton(checkboxWithTitle: "Enable Low Power Mode Alerts", target: self, action: #selector(toggleLowPowerAlerts(_:)))
            lowPowerBtn.state = UserDefaults.standard.bool(forKey: "enableLowPowerAlerts") ? .on : .off
            lowPowerBtn.font = .systemFont(ofSize: 13)
            controlsStack.addArrangedSubview(lowPowerBtn)
            
            let highPowerBtn = NSButton(checkboxWithTitle: "Enable High Performance Alerts", target: self, action: #selector(toggleHighPowerAlerts(_:)))
            highPowerBtn.state = UserDefaults.standard.bool(forKey: "enableHighPowerAlerts") ? .on : .off
            highPowerBtn.font = .systemFont(ofSize: 13)
            controlsStack.addArrangedSubview(highPowerBtn)
            
            let themeRow = NSStackView()
            themeRow.orientation = .horizontal
            themeRow.spacing = 8
            themeRow.alignment = .centerY
            
            let themeLabel = NSTextField(labelWithString: "App Theme:")
            themeLabel.font = .systemFont(ofSize: 13)
            themeLabel.textColor = .labelColor
            
            let themePopup = NSPopUpButton(frame: .zero, pullsDown: false)
            themePopup.addItems(withTitles: ["System", "Dark", "Light"])
            themePopup.selectItem(at: UserDefaults.standard.integer(forKey: "themePref"))
            themePopup.target = self
            themePopup.action = #selector(themeChanged(_:))
            
            themeRow.addArrangedSubview(themeLabel)
            themeRow.addArrangedSubview(themePopup)
            controlsStack.addArrangedSubview(themeRow)
            
            let styleRow = NSStackView()
            styleRow.orientation = .horizontal
            styleRow.spacing = 8
            styleRow.alignment = .centerY
            
            let styleLabel = NSTextField(labelWithString: "Notification Style:")
            styleLabel.font = .systemFont(ofSize: 13)
            styleLabel.textColor = .labelColor
            
            let stylePopup = NSPopUpButton(frame: .zero, pullsDown: false)
            stylePopup.addItems(withTitles: ["Normal HUD", "Compact Toast"])
            stylePopup.selectItem(at: UserDefaults.standard.integer(forKey: "notificationStyle"))
            stylePopup.target = self
            stylePopup.action = #selector(styleChanged(_:))
            
            styleRow.addArrangedSubview(styleLabel)
            styleRow.addArrangedSubview(stylePopup)
            controlsStack.addArrangedSubview(styleRow)
            
            // Align label widths
            themeLabel.widthAnchor.constraint(equalToConstant: 120).isActive = true
            styleLabel.widthAnchor.constraint(equalToConstant: 120).isActive = true
            
            mainStack.addArrangedSubview(controlsStack)
            controlsStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
            
            // Divider 3
            let divider3 = NSBox()
            divider3.boxType = .separator
            mainStack.addArrangedSubview(divider3)
            divider3.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
            
            // Bottom Action & Credits
            let bottomStack = NSStackView()
            bottomStack.orientation = .horizontal
            bottomStack.spacing = 10
            bottomStack.alignment = .centerY
            
            let testBtn = NSButton(title: "Test Notification", target: self, action: #selector(testNotification))
            testBtn.bezelStyle = .rounded
            
            let creditField = NSTextField(labelWithString: "v1.3.2 • Ka1bOne")
            creditField.font = .systemFont(ofSize: 10)
            creditField.textColor = .tertiaryLabelColor
            creditField.alignment = .right
            
            bottomStack.addArrangedSubview(testBtn)
            bottomStack.addArrangedSubview(creditField)
            mainStack.addArrangedSubview(bottomStack)
            bottomStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
            
            // Force credit field to stretch and push to the right
            creditField.setContentHuggingPriority(.defaultLow, for: .horizontal)
            testBtn.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            
            settingsWindow = window
        }
        
        let health = getBatteryMaximumCapacityPercent()
        let cycles = getBatteryCycleCount()
        
        if let health = health {
            settingsHealthField?.stringValue = "\(health)%"
        } else {
            settingsHealthField?.stringValue = "--"
        }
        
        if let cycles = cycles {
            settingsCyclesField?.stringValue = "\(cycles)"
        } else {
            settingsCyclesField?.stringValue = "--"
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func toggleThreshold(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "enableThresholdAlerts")
    }
    
    @objc func toggleLowPowerAlerts(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "enableLowPowerAlerts")
    }
    
    @objc func toggleHighPowerAlerts(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "enableHighPowerAlerts")
    }

    @objc func themeChanged(_ sender: NSPopUpButton) {
        UserDefaults.standard.set(sender.indexOfSelectedItem, forKey: "themePref")
        if let window = self.window, let contentView = window.contentView,
           let ve = contentView.subviews.first(where: { $0 is NSVisualEffectView }) as? NSVisualEffectView {
            applyTheme(to: ve)
        }
    }
    
    @objc func styleChanged(_ sender: NSPopUpButton) {
        UserDefaults.standard.set(sender.indexOfSelectedItem, forKey: "notificationStyle")
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
        case highPowerOn
        case highPowerOff
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
        case .highPowerOn:
            iconName = "speedometer"
            text = "High Power Mode On"
        case .highPowerOff:
            iconName = "speedometer"
            text = "High Power Mode Off"
        }
        
        let isCompact = UserDefaults.standard.integer(forKey: "notificationStyle") == 1
        let isWide = (state == .unpluggedAndLowPower || state == .pluggedAndLowPowerOff || isAlert || state == .highPowerOn || state == .highPowerOff)
        
        let panelWidth: CGFloat = isCompact ? 280 : (isWide ? 360 : 250)
        let panelHeight: CGFloat = isCompact ? 64 : 250
        
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let x: CGFloat
            let y: CGFloat
            if isCompact {
                // Top Right corner of the screen
                x = screenRect.origin.x + screenRect.width - panelWidth - 20
                y = screenRect.origin.y + screenRect.height - panelHeight - 20
            } else {
                // Bottom Center (HUD style)
                x = screenRect.origin.x + (screenRect.width - panelWidth) / 2
                y = screenRect.origin.y + 40
            }
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
        
        if isCompact {
            let mainStack = NSStackView()
            mainStack.orientation = .horizontal
            mainStack.spacing = 12
            mainStack.alignment = .centerY
            mainStack.distribution = .fill
            mainStack.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(mainStack)
            
            NSLayoutConstraint.activate([
                mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
                mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
                mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
                mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
            ])
            
            let iconConfig = NSImage.SymbolConfiguration(pointSize: 24, weight: .bold)
            let iconImage = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?.withSymbolConfiguration(iconConfig) ?? NSImage()
            let imageView = NSImageView(image: iconImage)
            imageView.contentTintColor = isAlert ? .systemRed : .labelColor
            mainStack.addArrangedSubview(imageView)
            
            let textStack = NSStackView()
            textStack.orientation = .vertical
            textStack.spacing = 2
            textStack.alignment = .leading
            textStack.distribution = .fill
            
            let textField = NSTextField(labelWithString: text)
            textField.font = .systemFont(ofSize: 14, weight: .bold)
            textField.textColor = .labelColor
            
            let status = getBatteryStatus()
            var statusParts: [String] = ["\(status.percentage)%"]
            if status.isLowPower {
                statusParts.append("Low Power")
            }
            if isHighPowerModeEnabled() {
                statusParts.append("High Power")
            }
            let statusText = statusParts.joined(separator: " • ")
            let statusField = NSTextField(labelWithString: statusText)
            statusField.font = .systemFont(ofSize: 11, weight: .medium)
            statusField.textColor = status.isLowPower ? .systemYellow : (isHighPowerModeEnabled() ? .systemOrange : .secondaryLabelColor)
            
            textStack.addArrangedSubview(textField)
            textStack.addArrangedSubview(statusField)
            mainStack.addArrangedSubview(textStack)
        } else {
            let stack = NSStackView(frame: contentView.bounds.insetBy(dx: 20, dy: 20))
            stack.orientation = .vertical
            stack.spacing = 8
            stack.alignment = .centerX
            stack.distribution = .fill
            
            let config = NSImage.SymbolConfiguration(pointSize: 80, weight: .bold)
            let iconImage = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?.withSymbolConfiguration(config) ?? NSImage()
            
            let imageView = NSImageView(image: iconImage)
            imageView.contentTintColor = isAlert ? .systemRed : .labelColor
            
            let textField = NSTextField(labelWithString: text)
            textField.font = .systemFont(ofSize: 22, weight: .bold)
            textField.textColor = .labelColor
            textField.alignment = .center
            
            // Add status line (Percentage and Low Power Status)
            let status = getBatteryStatus()
            var statusParts: [String] = ["\(status.percentage)%"]
            
            if status.isLowPower {
                statusParts.append("Low Power")
            }
            if isHighPowerModeEnabled() {
                statusParts.append("High Power")
            }
            
            let statusText = statusParts.joined(separator: " • ")
            let statusField = NSTextField(labelWithString: statusText)
            statusField.font = .systemFont(ofSize: 16, weight: .medium)
            statusField.textColor = status.isLowPower ? .systemYellow : (isHighPowerModeEnabled() ? .systemOrange : .secondaryLabelColor)
            statusField.alignment = .center
            
            stack.addArrangedSubview(imageView)
            stack.addArrangedSubview(textField)
            stack.addArrangedSubview(statusField)
            
            contentView.addSubview(stack)
            stack.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                stack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 16),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16)
            ])
        }
        
        let isAlreadyVisible = window.isVisible && window.alphaValue > 0
        
        if !isAlreadyVisible {
            window.alphaValue = 0
            window.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                window.animator().alphaValue = 1.0
            }
        } else {
            window.makeKeyAndOrderFront(nil)
            window.alphaValue = 1.0
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
        // Notification-based monitoring for Low Power Mode
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { _ in
            self.updatePowerModeStatus()
        }
        
        // Polling-based fallback for High Power Mode & Low Power Mode (every 3 seconds)
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            self.updatePowerModeStatus()
        }
        
        lastLowPowerState = ProcessInfo.processInfo.isLowPowerModeEnabled
        lastHighPowerState = isHighPowerModeEnabled()
    }
    
    func setupBatteryThresholdMonitoring() {
        // Check battery level every 60 seconds as a fallback
        Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { _ in
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
    
    func updatePowerModeStatus() {
        // 1. Low Power Mode Check
        let currentLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        if lastLowPowerState != currentLowPower {
            lastLowPowerState = currentLowPower
            if UserDefaults.standard.bool(forKey: "enableLowPowerAlerts") {
                DispatchQueue.main.async {
                    self.showPopup(state: currentLowPower ? .lowPowerOn : .lowPowerOff)
                }
            }
        }
        
        // 2. High Power / High Performance Mode Check
        let currentHighPower = isHighPowerModeEnabled()
        if lastHighPowerState != currentHighPower {
            lastHighPowerState = currentHighPower
            if UserDefaults.standard.bool(forKey: "enableHighPowerAlerts") {
                DispatchQueue.main.async {
                    self.showPopup(state: currentHighPower ? .highPowerOn : .highPowerOff)
                }
            }
        }
    }
    
    func checkPowerStatus() {
        let currentState = isCurrentlyPluggedIn()
        checkBatteryThresholds()
        updatePowerModeStatus()
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
                        if UserDefaults.standard.bool(forKey: "enableLowPowerAlerts") {
                            self.showPopup(state: .pluggedAndLowPowerOff)
                        } else {
                            self.showPopup(state: .plugged)
                        }
                    } else {
                        self.showPopup(state: .plugged)
                    }
                } else {
                    // Unplugged — check if low power auto-enabled
                    if isLowPower {
                        self.lastLowPowerState = true
                        if UserDefaults.standard.bool(forKey: "enableLowPowerAlerts") {
                            self.showPopup(state: .unpluggedAndLowPower)
                        } else {
                            self.showPopup(state: .unplugged)
                        }
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
    
    func getBatteryCycleCount() -> Int? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        var cycleCount: Int? = nil
        if service != 0 {
            if let prop = IORegistryEntryCreateCFProperty(service, "CycleCount" as CFString, kCFAllocatorDefault, 0) {
                cycleCount = prop.takeRetainedValue() as? Int
            }
            IOObjectRelease(service)
        }
        return cycleCount
    }
    
    func getBatteryMaximumCapacityPercent() -> Int? {
        let process = Process()
        process.launchPath = "/usr/bin/pmset"
        process.arguments = ["-g", "ps", "-xml"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            
            if let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                return plist["Maximum Capacity Percent"] as? Int
            } else if let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [[String: Any]],
                      let dict = plist.first {
                return dict["Maximum Capacity Percent"] as? Int
            }
        } catch {
            // Fallback: calculate using DesignCapacity and AppleRawMaxCapacity if pmset fails
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
            if service != 0 {
                defer { IOObjectRelease(service) }
                if let rawMaxProp = IORegistryEntryCreateCFProperty(service, "AppleRawMaxCapacity" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Double,
                   let designProp = IORegistryEntryCreateCFProperty(service, "DesignCapacity" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Double,
                   designProp > 0 {
                    return Int(round((rawMaxProp / designProp) * 100))
                }
            }
        }
        return nil
    }
    
    func isHighPowerModeEnabled() -> Bool {
        let process = Process()
        process.launchPath = "/usr/bin/pmset"
        process.arguments = ["-g"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if let output = String(data: data, encoding: .utf8) {
                let lines = output.components(separatedBy: .newlines)
                for line in lines {
                    let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if cleaned.contains("powermode") && (cleaned.contains("2") || cleaned.contains("high")) {
                        return true
                    }
                    if cleaned.contains("highpowermode") && !cleaned.contains("0") {
                        return true
                    }
                }
            }
        } catch {
            print("Error checking high power mode: \(error)")
        }
        return false
    }
    
    private var lastPowerState: Bool?
    private var lastLowPowerState: Bool?
    private var lastHighPowerState: Bool?
}

let app = NSApplication.shared
let delegate = PowerNotificationApp()
app.delegate = delegate
app.run()

