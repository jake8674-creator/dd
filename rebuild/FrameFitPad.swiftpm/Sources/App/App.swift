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

@MainActor
final class HomeController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "프레임핏 패드"
        view.backgroundColor = .systemBackground
        let label = UILabel()
        label.text = "실행 준비 완료"
        label.font = .preferredFont(forTextStyle: .largeTitle)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}
