import SwiftUI
import UIKit

final class AgarAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return .landscape
    }
}

@main
struct MyApp: App {
    @UIApplicationDelegateAdaptor(AgarAppDelegate.self) var appDelegate

    init() {
        MyFont.registerFonts()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .statusBar(hidden: true)
                .persistentSystemOverlays(.hidden)
                .ignoresSafeArea()
                .onAppear {
                    if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
                        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { _ in }
                    }
                }
        }
    }
    // Custom App Delegate to configure the window
    
}
