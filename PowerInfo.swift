import Cocoa
import IOKit.ps

class PowerNotificationApp: NSObject, NSApplicationDelegate {
    var window: NSPanel?
    var timer: Timer?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupWindow()
        setupPowerMonitoring()
        setupLowPowerMonitoring()
        
        // Test popup on launch to verify UI
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.showPopup(state: self.isCurrentlyPluggedIn() ? .plugged : .unplugged)
        }
        
        // Hide from Dock
        NSApp.setActivationPolicy(.accessory)
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
    
    enum PowerState {
        case plugged
        case unplugged
        case lowPowerOn
        case lowPowerOff
        case unpluggedAndLowPower
        case pluggedAndLowPowerOff
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
        }
        
        // Use wider panel for long combined-state text
        let isWide = (state == .unpluggedAndLowPower || state == .pluggedAndLowPowerOff)
        let panelWidth: CGFloat = isWide ? 360 : 250
        let panelHeight: CGFloat = 250
        
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let x = screenRect.origin.x + (screenRect.width - panelWidth) / 2
            let y = screenRect.origin.y + 40
            window.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: false)
        }
        
        // Rebuild visual effect mask to match new size
        if let ve = contentView.subviews.first(where: { $0 is NSVisualEffectView }) as? NSVisualEffectView {
            ve.frame = contentView.bounds
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
        imageView.contentTintColor = .white
        
        let textField = NSTextField(labelWithString: text)
        textField.font = .systemFont(ofSize: 22, weight: .bold)
        textField.textColor = .white
        textField.alignment = .center
        
        // Add status line (Percentage and Low Power Status)
        let status = getBatteryStatus()
        var statusParts: [String] = ["\(status.percentage)%"]
        
        // Add "Low Power" label if active, even if the main message was Plugged/Unplugged
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
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
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
