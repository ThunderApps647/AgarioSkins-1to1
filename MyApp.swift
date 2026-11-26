import SwiftUI

@main
struct MyApp: App {
    init() {
        MyFont.registerFonts()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .statusBar(hidden: true)
                .persistentSystemOverlays(.hidden)
                .ignoresSafeArea()
        }
    }
    // Custom App Delegate to configure the window
    
}
