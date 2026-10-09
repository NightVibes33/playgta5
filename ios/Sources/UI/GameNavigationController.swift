import UIKit

/// The launcher remains portrait while actual gameplay requests landscape.
/// Child controllers decide their orientation, rather than UIKit guessing it.
final class GameNavigationController: UINavigationController {
    override var shouldAutorotate: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if visibleViewController is GameViewController { return .landscape }
        // During push/pop animations UIKit can still report the previous
        // portrait-only controller as visible. Keep both orientations allowed
        // until the gameplay controller is fully onscreen.
        if viewControllers.contains(where: { $0 is GameViewController }) {
            return .allButUpsideDown
        }
        return topViewController?.supportedInterfaceOrientations ?? .allButUpsideDown
    }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        if viewControllers.contains(where: { $0 is GameViewController }) {
            return .landscapeRight
        }
        return topViewController?.preferredInterfaceOrientationForPresentation ?? .portrait
    }
}

enum GameOrientation {
    static func request(_ orientations: UIInterfaceOrientationMask, from view: UIView) {
        guard let scene = view.window?.windowScene else {
            LogStore.shared.write("boot", "Orientation update deferred: no window scene")
            return
        }
        if #available(iOS 16.0, *) {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { error in
                LogStore.shared.write("boot", "Orientation update: " + error.localizedDescription)
            }
        } else {
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
}
