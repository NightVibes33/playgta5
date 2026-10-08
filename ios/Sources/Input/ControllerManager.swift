import Foundation
import GameController
import UIKit

/// Reads real, continuous analog values. The WebAssembly bridge currently falls back to
/// the browser's keyboard/mouse input ABI until a native gamepad ABI is identified.
final class ControllerManager {
    static let shared = ControllerManager()
    var onState: (([String: Double]) -> Void)?
    var onConnection: ((String) -> Void)?
    private var timer: Timer?
    private var controller: GCController?

    private init() {
        NotificationCenter.default.addObserver(self, selector: #selector(refresh),
            name: .GCControllerDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh),
            name: .GCControllerDidDisconnect, object: nil)
    }

    func begin() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.sample()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        onState = nil
        onConnection = nil
    }

    @objc private func refresh() {
        controller = GCController.controllers().first(where: { $0.extendedGamepad != nil })
        let label = controller?.vendorName ?? "No controller"
        onConnection?(label)
        LogStore.shared.write("controller", "Active gamepad: \(label)")
    }

    private func sample() {
        guard let g = controller?.extendedGamepad else {
            onState?([:]); return
        }
        func value(_ b: GCControllerButtonInput) -> Double { Double(b.value) }
        onState?([
            "lx": Double(g.leftThumbstick.xAxis.value),
            "ly": Double(g.leftThumbstick.yAxis.value),
            "rx": Double(g.rightThumbstick.xAxis.value),
            "ry": Double(g.rightThumbstick.yAxis.value),
            "lt": value(g.leftTrigger), "rt": value(g.rightTrigger),
            "lb": value(g.leftShoulder), "rb": value(g.rightShoulder),
            "a": value(g.buttonA), "b": value(g.buttonB),
            "x": value(g.buttonX), "y": value(g.buttonY),
            "up": value(g.dpad.up), "down": value(g.dpad.down),
            "left": value(g.dpad.left), "right": value(g.dpad.right)
        ])
    }
}
