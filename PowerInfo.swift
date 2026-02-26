import Cocoa
import IOKit.ps

class PowerNotificationApp: NSObject, NSApplicationDelegate {
    var window: NSPanel?
    var timer: Timer?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupWindow()
        setupPowerMonitoring()
        
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
    
    func showPopup(plugged: Bool) {
        guard let window = self.window, let contentView = window.contentView else { return }
        
        // Clear previous views
        contentView.subviews.forEach { if !($0 is NSVisualEffectView) { $0.removeFromSuperview() } }
        
        let stack = NSStackView(frame: contentView.bounds.insetBy(dx: 20, dy: 20))
        stack.orientation = .vertical
        stack.spacing = 15
        stack.alignment = .centerX
        stack.distribution = .fill
        
        let iconName = plugged ? "powerplug.fill" : "battery.100"
        let config = NSImage.SymbolConfiguration(pointSize: 80, weight: .bold)
        let iconImage = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        
        let imageView = NSImageView(image: iconImage!)
        imageView.contentTintColor = .black // Black icon
        
        let textField = NSTextField(labelWithString: plugged ? "Plugged In" : "Unplugged")
        textField.font = .systemFont(ofSize: 24, weight: .bold)
        textField.textColor = .black // Black text
        textField.alignment = .center
        
        stack.addArrangedSubview(imageView)
        stack.addArrangedSubview(textField)
        
        contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
        
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        window.center()
        
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
    
    private var lastPowerState: Bool?
    
    func checkPowerStatus() {
        let currentState = isCurrentlyPluggedIn()
        if lastPowerState != currentState {
            lastPowerState = currentState
            // Delay slightly to allow the OS to update power source info
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.showPopup(plugged: currentState)
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
}

let app = NSApplication.shared
let delegate = PowerNotificationApp()
app.delegate = delegate
app.run()
