import Foundation
import GameController
import CoreHaptics
import UIKit

/// Hardware controller input. Values remain analog up to the JavaScript bridge.
/// The closed WebAssembly build still exposes only keyboard/mouse input for gameplay.
final class ControllerManager {
    static let shared = ControllerManager()

    var onState: (([String: Double]) -> Void)?
    var onConnection: ((String) -> Void)?
    private(set) var currentName = "No controller"
    private var controller: GCController?
    private var timer: Timer?
    private var hapticEngine: CHHapticEngine?
    private var lastConnected = false

    static let deadzoneKey = "gtaios.controller.deadzone"
    static let sensitivityKey = "gtaios.controller.sensitivity"
    static let invertYKey = "gtaios.controller.invertY"

    private init() {
        NotificationCenter.default.addObserver(self, selector: #selector(refresh),
            name: .GCControllerDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh),
            name: .GCControllerDidDisconnect, object: nil)
    }

    func begin() {
        refresh()
        onConnection?(currentName)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.sample()
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        onState?(["connected": 0])
        onState = nil
        onConnection = nil
        hapticEngine?.stop(completionHandler: nil)
        hapticEngine = nil
    }

    @objc private func refresh() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.refresh() }
            return
        }
        let next = GCController.controllers().first(where: { $0.extendedGamepad != nil })
        if controller !== next {
            controller = next
            hapticEngine?.stop(completionHandler: nil)
            hapticEngine = nil
            lastConnected = false
            currentName = next?.vendorName ?? "No controller"
            onConnection?(currentName)
            LogStore.shared.write("controller", "Controller changed: \(currentName), haptics=\(next?.haptics != nil)")
        }
    }

    private func deadzone(_ x: Double, _ y: Double, threshold: Double) -> (Double, Double) {
        let magnitude = (x * x + y * y).squareRoot()
        if magnitude <= threshold { return (0, 0) }
        let corrected = min(1, (magnitude - threshold) / (1 - threshold))
        let k = corrected / max(0.0001, magnitude)
        return (x * k, y * k)
    }

    private func sample() {
        guard let g = controller?.extendedGamepad else {
            if lastConnected {
                lastConnected = false
                LogStore.shared.write("controller", "Disconnected, releasing all game input")
            }
            onState?(["connected": 0])
            return
        }
        lastConnected = true
        func value(_ b: GCControllerButtonInput?) -> Double { Double(b?.value ?? 0) }
        let saved = UserDefaults.standard
        let threshold = saved.object(forKey: Self.deadzoneKey) == nil ? 0.15 : saved.double(forKey: Self.deadzoneKey)
        let dead = min(0.45, max(0.02, threshold))
        let (lx, ly) = deadzone(Double(g.leftThumbstick.xAxis.value),
                               Double(g.leftThumbstick.yAxis.value), threshold: dead)
        let (rawRX, rawRY) = deadzone(Double(g.rightThumbstick.xAxis.value),
                                     Double(g.rightThumbstick.yAxis.value), threshold: dead)
        let gain = saved.object(forKey: Self.sensitivityKey) == nil ? 1.0 :
            min(3.0, max(0.25, saved.double(forKey: Self.sensitivityKey)))
        let rx = max(-1.0, min(1.0, rawRX * gain))
        let ry = max(-1.0, min(1.0, rawRY * gain))
        if GTALaunchPreferences.text("controlScheme", fallback: "Automatic") == "Touch" {
            onState?(["connected": 0])
            return
        }
        let invert = saved.bool(forKey: Self.invertYKey)
        onState?([
            "connected": 1,
            "lx": lx, "ly": ly, "rx": rx, "ry": invert ? -ry : ry,
            "lt": value(g.leftTrigger), "rt": value(g.rightTrigger),
            "lb": value(g.leftShoulder), "rb": value(g.rightShoulder),
            "a": value(g.buttonA), "b": value(g.buttonB),
            "x": value(g.buttonX), "y": value(g.buttonY),
            "up": value(g.dpad.up), "down": value(g.dpad.down),
            "left": value(g.dpad.left), "right": value(g.dpad.right),
            "l3": value(g.leftThumbstickButton),
            "r3": value(g.rightThumbstickButton),
            "menu": value(g.buttonMenu), "options": value(g.buttonOptions)
        ])
    }

    @discardableResult
    func testRumble() -> Bool {
        // Haptics can be tested directly from Graphics without first opening Controls.
        refresh()
        guard GTALaunchPreferences.enabled("controllerVibration", fallback: true) else {
            LogStore.shared.write("controller", "Haptics disabled by user")
            return false
        }
        guard let info = controller?.haptics,
              let engine = info.createEngine(withLocality: .default) else {
            LogStore.shared.write("controller", "Controller vibration unavailable")
            return false
        }
        do {
            hapticEngine = engine
            try engine.start()
            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)
            ], relativeTime: 0)
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            LogStore.shared.write("controller", "Controller vibration test sent")
            return true
        } catch {
            LogStore.shared.write("controller", "Vibration error: \(error)")
            return false
        }
    }
}
