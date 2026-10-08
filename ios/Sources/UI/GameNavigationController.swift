import UIKit

/// The launcher remains portrait while actual gameplay requests landscape.
/// Child controllers decide their orientation, rather than UIKit guessing it.
final class GameNavigationController: UINavigationController {
    override var shouldAutorotate: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        topViewController?.supportedInterfaceOrientations ?? .allButUpsideDown
    }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        topViewController?.preferredInterfaceOrientationForPresentation ?? .portrait
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
