// swift-tools-version: 5.9
import PackageDescription
import AppleProductTypes
let package = Package(
    name: "FrameFitPad",
    platforms: [.iOS("17.0")],
    products: [.iOSApplication(
        name: "프레임핏 패드",
        targets: ["FrameFitPad"],
        bundleIdentifier: "local.framefit.pad",
        displayVersion: "1.0.0",
        bundleVersion: "1",
        appIcon: .placeholder(icon: .star),
        accentColor: .presetColor(.teal),
        supportedDeviceFamilies: [.pad],
        supportedInterfaceOrientations: [.portrait, .landscapeLeft, .landscapeRight],
        capabilities: [.camera(purposeString: "눈과 안경테를 촬영해 피팅 기준점을 확인합니다.")],
        additionalInfoPlistContentFilePath: "AppInfo.plist"
    )],
    targets: [.executableTarget(name: "FrameFitPad", path: "Sources")]
)
