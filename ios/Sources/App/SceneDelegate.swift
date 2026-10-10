import UIKit

/// Modern scene lifecycle. UIWindow(windowScene:) uses the iPhone 16's actual
/// fullscreen bounds; UIScreen.main.bounds was creating a compatibility-sized window.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let launcher = GTAFiveTabController()
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = launcher
        window.backgroundColor = .black
        window.makeKeyAndVisible()
        self.window = window
        LogStore.shared.write("boot", "Scene window frame: \(window.bounds), screen: \(windowScene.screen.bounds), scale: \(windowScene.screen.scale)")
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        LogStore.shared.write("boot", "Scene active")
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        LogStore.shared.write("boot", "Scene disconnected")
    }
}
