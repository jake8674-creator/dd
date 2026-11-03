import SwiftUI
import UIKit

@main
@MainActor
struct FrameFitPadApp: App {
    var body: some Scene {
        WindowGroup { NativeRoot().ignoresSafeArea() }
    }
}

@MainActor
struct NativeRoot: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        UINavigationController(rootViewController: HomeController())
    }
    func updateUIViewController(_ controller: UINavigationController, context: Context) {}
}

