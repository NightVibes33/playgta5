import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let controller = LauncherViewController()
        let navigation = GameNavigationController(rootViewController: controller)
        navigation.navigationBar.tintColor = .white
        navigation.navigationBar.barStyle = .black
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        self.window = window
        LogStore.shared.write("boot", "Launched GTAiOS on \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
        return true
    }
}
