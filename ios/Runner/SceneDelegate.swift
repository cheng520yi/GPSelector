import UIKit
import Flutter

@available(iOS 13.0, *)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    guard let windowScene = (scene as? UIWindowScene) else { return }
    
    // 获取 AppDelegate
    let appDelegate = UIApplication.shared.delegate as! FlutterAppDelegate
    
    // 如果 AppDelegate 已经有窗口，使用它并更新 windowScene
    if let existingWindow = appDelegate.window {
      existingWindow.windowScene = windowScene
      self.window = existingWindow
      return
    }
    
    // 创建新窗口
    let window = UIWindow(windowScene: windowScene)
    
    // 从 storyboard 加载 FlutterViewController（如果存在）
    let storyboard = UIStoryboard(name: "Main", bundle: nil)
    if let controller = storyboard.instantiateInitialViewController() as? FlutterViewController {
      window.rootViewController = controller
    } else {
      // 如果 storyboard 中没有，创建一个新的 FlutterViewController
      // Flutter 会自动处理引擎初始化
      let controller = FlutterViewController()
      window.rootViewController = controller
    }
    
    window.makeKeyAndVisible()
    self.window = window
    appDelegate.window = window
  }

  func sceneDidDisconnect(_ scene: UIScene) {
  }

  func sceneDidBecomeActive(_ scene: UIScene) {
  }

  func sceneWillResignActive(_ scene: UIScene) {
  }

  func sceneWillEnterForeground(_ scene: UIScene) {
  }

  func sceneDidEnterBackground(_ scene: UIScene) {
  }
}

