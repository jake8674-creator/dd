import UIKit
import AVFoundation
import CoreMotion
import ImageIO

struct CapturedFrame {
    var image: UIImage
    var fired: Bool
    var gravity: PixelVector?
}

final class PhotoDriver: NSObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    let front: Bool
    private let queue = DispatchQueue(label: "framefitpad.photo")
    private let output = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    private var stopped = false
    var onReady: (() -> Void)?
    var onError: ((String) -> Void)?
    var onPhoto: ((Data,Bool) -> Void)?
    init(front: Bool) { self.front = front; super.init() }
    func start() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
            guard let self = self else { return }
            guard allowed else { self.fail("설정에서 카메라 접근을 허용해주세요."); return }
            self.queue.async { self.configure() }
        }
    }
    private func configure() {
        guard !stopped, device == nil else { return }
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: front ? .front : .back) else { fail("카메라가 없습니다. 촬영은 실제 아이패드에서 확인하세요."); return }
        if !front && !camera.hasFlash { fail("후면 LED 플래시 지원이 필요합니다."); return }
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            session.beginConfiguration(); session.sessionPreset = .photo
            guard session.canAddInput(input), session.canAddOutput(output) else { session.commitConfiguration(); fail("카메라 출력을 구성하지 못했습니다."); return }
            session.addInput(input); session.addOutput(output)
            output.maxPhotoQualityPrioritization = .quality
            session.commitConfiguration()
            device = camera
            session.startRunning()
            DispatchQueue.main.async { self.onReady?() }
        } catch { fail(error.localizedDescription) }
    }
    func shoot(orientation: AVCaptureVideoOrientation) {
        queue.async {
            guard !self.stopped, self.session.isRunning else { self.fail("카메라가 중지되었습니다."); return }
            if let connection = self.output.connection(with: .video) {
                if connection.isVideoOrientationSupported { connection.videoOrientation = orientation }
                if connection.isVideoMirroringSupported { connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = false }
            }
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            settings.photoQualityPrioritization = .quality
            if !self.front {
                guard self.device?.isFlashAvailable == true else { self.fail("플래시 준비가 안 됐습니다. 잠시 뒤 다시 시도하세요."); return }
                settings.flashMode = .on
            } else { settings.flashMode = .off }
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error { fail(error.localizedDescription); return }
        let exif = photo.metadata[kCGImagePropertyExifDictionary as String] as? [String:Any]
        let flash = (exif?[kCGImagePropertyExifFlash as String] as? NSNumber)?.intValue
        let fired = flash.map { $0 & 1 == 1 } ?? false
        guard front || fired else { fail("LED 발광을 사진 정보에서 확인하지 못했습니다. 다시 촬영하세요."); return }
        guard let data = photo.fileDataRepresentation() else { fail("사진 데이터가 없습니다."); return }
        DispatchQueue.main.async { self.onPhoto?(data,fired) }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) { if let error = error { fail(error.localizedDescription) } }
    private func fail(_ message: String) { DispatchQueue.main.async { self.onError?(message) } }
    func stop() { queue.async { self.stopped = true; if self.session.isRunning { self.session.stopRunning() } } }
}

@MainActor
final class CaptureController: UIViewController {
    private let position: PhotoPosition
    private let nearCM: String
    private let completion: (CapturedFrame) -> Void
    private let driver: PhotoDriver
    private let motion = CMMotionManager()
    private let preview = UIView()
    private let caption = UILabel()
    private let status = UILabel()
    private let shootButton = UIButton(type: .system)
    private let countLabel = UILabel()
    private let whiteScreen = UIView()
    private let fixation = UILabel()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var countdown: Task<Void,Never>?
    private var screen: UIScreen?
    private var brightness: CGFloat?
    private var savedGravity: PixelVector?
    private var finished = false
    init(position: PhotoPosition, nearCM: String, completion: @escaping (CapturedFrame) -> Void) {
        self.position = position; self.nearCM = nearCM; self.completion = completion
        driver = PhotoDriver(front: position == .reading)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Programmatic UI") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = position.title
        view.backgroundColor = .black
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "닫기", style: .plain, target: self, action: #selector(close))
        caption.text = position.instruction; caption.textColor = .white; caption.numberOfLines = 0
        status.text = "카메라 준비 중"; status.textColor = .systemOrange; status.numberOfLines = 0
        shootButton.setTitle("3초 후 촬영", for: .normal); shootButton.configuration = .filled(); shootButton.isEnabled = false
        shootButton.addTarget(self, action: #selector(beginCountdown), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [caption,preview,status,shootButton]); stack.axis = .vertical; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16), stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20), stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            shootButton.heightAnchor.constraint(equalToConstant: 56)
        ])
        previewLayer = AVCaptureVideoPreviewLayer(session: driver.session); previewLayer.videoGravity = .resizeAspect; preview.layer.addSublayer(previewLayer)
        countLabel.textColor = .white; countLabel.font = .boldSystemFont(ofSize: 84); countLabel.textAlignment = .center
        countLabel.translatesAutoresizingMaskIntoConstraints = false; preview.addSubview(countLabel)
        NSLayoutConstraint.activate([countLabel.centerXAnchor.constraint(equalTo: preview.centerXAnchor), countLabel.centerYAnchor.constraint(equalTo: preview.centerYAnchor)])
        fixation.numberOfLines = 0; fixation.textAlignment = .center; fixation.textColor = .white; fixation.font = .preferredFont(forTextStyle: .title2)
        fixation.text = position == .reading ? "이 글자를 편하게 봅니다\n눈–화면 거리 \(nearCM) cm" : ""
        fixation.translatesAutoresizingMaskIntoConstraints = false; preview.addSubview(fixation)
        NSLayoutConstraint.activate([fixation.centerXAnchor.constraint(equalTo: preview.centerXAnchor), fixation.centerYAnchor.constraint(equalTo: preview.centerYAnchor), fixation.widthAnchor.constraint(lessThanOrEqualTo: preview.widthAnchor, multiplier: 0.9)])
        whiteScreen.backgroundColor = .white; whiteScreen.isHidden = true; whiteScreen.isUserInteractionEnabled = false
        driver.onReady = { [weak self] in guard let self = self, !self.finished else { return }; self.shootButton.isEnabled = true; self.status.text = self.driver.front ? "전면 · 화면 플래시" : "후면 · LED 플래시" }
        driver.onError = { [weak self] message in self?.restoreBrightness(); self?.status.text = message; self?.shootButton.isEnabled = true }
        driver.onPhoto = { [weak self] data,fired in self?.received(data,fired:fired) }
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted), name: UIApplication.willResignActiveNotification, object: nil)
        motion.deviceMotionUpdateInterval = 0.05
        if motion.isDeviceMotionAvailable { motion.startDeviceMotionUpdates() }
        driver.start()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews(); previewLayer.frame = preview.bounds
        if let orientation = view.window?.windowScene?.interfaceOrientation, let video = AVCaptureVideoOrientation(rawValue: orientation.rawValue), let c = previewLayer.connection {
            if c.isVideoOrientationSupported { c.videoOrientation = video }
            if c.isVideoMirroringSupported { c.automaticallyAdjustsVideoMirroring = false; c.isVideoMirrored = false }
        }
        whiteScreen.frame = view.window?.bounds ?? .zero
    }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); cleanup() }
    @objc private func close() { cleanup(); dismiss(animated: true) }
    @objc private func interrupted() { cleanup(); dismiss(animated: false) }
    private func cleanup() {
        finished = true; countdown?.cancel(); restoreBrightness(); motion.stopDeviceMotionUpdates(); driver.stop()
        driver.onReady = nil; driver.onPhoto = nil; driver.onError = nil
        NotificationCenter.default.removeObserver(self)
    }
    private func restoreBrightness() {
        whiteScreen.removeFromSuperview(); whiteScreen.isHidden = true
        if let original = brightness { screen?.brightness = original }; brightness = nil; screen = nil
    }
    @objc private func beginCountdown() {
        guard countdown == nil, let window = view.window else { return }
        shootButton.isEnabled = false
        countdown = Task { @MainActor [weak self] in
            guard let self = self else { return }
            defer { self.countdown = nil; self.countLabel.text = nil }
            do {
                for n in [3,2,1] { self.countLabel.text = "\(n)"; try await Task.sleep(nanoseconds: 1_000_000_000) }
                guard !self.finished else { return }
                let orientation = window.windowScene?.interfaceOrientation ?? .portrait
                self.savedGravity = self.gravity(orientation)
                if self.driver.front {
                    self.screen = window.screen; self.brightness = window.screen.brightness; window.screen.brightness = 1
                    self.whiteScreen.frame = window.bounds; self.whiteScreen.isHidden = false; window.addSubview(self.whiteScreen)
                    let target = UILabel(); target.text = "여기를 보세요"; target.textColor = .black; target.font = .preferredFont(forTextStyle: .title2); target.sizeToFit()
                    for v in self.whiteScreen.subviews { v.removeFromSuperview() }
                    target.center = CGPoint(x: self.whiteScreen.bounds.midX, y: self.whiteScreen.bounds.midY); self.whiteScreen.addSubview(target)
                    try await Task.sleep(nanoseconds: 600_000_000)
                }
                try Task.checkCancellation()
                self.driver.shoot(orientation: AVCaptureVideoOrientation(rawValue: orientation.rawValue) ?? .portrait)
            } catch { self.restoreBrightness() }
        }
    }
    private func gravity(_ orientation: UIInterfaceOrientation) -> PixelVector? {
        guard let g = motion.deviceMotion?.gravity else { return nil }
        let v: PixelVector
        switch orientation {
        case .landscapeLeft: v = .init(x:g.y,y:g.x)
        case .landscapeRight: v = .init(x:-g.y,y:-g.x)
        case .portraitUpsideDown: v = .init(x:-g.x,y:g.y)
        default: v = .init(x:g.x,y:-g.y)
        }
        return v.length > 0.3 && v.y > 0 ? v.unit : nil
    }
    private func received(_ data: Data, fired: Bool) {
        guard !finished else { return }; restoreBrightness()
        guard let source = UIImage(data: data) else { status.text = "사진을 읽지 못했습니다"; shootButton.isEnabled = true; return }
        let ratio = min(1,3000/max(source.size.width,source.size.height))
        let size = CGSize(width:source.size.width*ratio,height:source.size.height*ratio)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let upright = UIGraphicsImageRenderer(size:size,format:format).image { _ in source.draw(in:CGRect(origin:.zero,size:size)) }
        completion(CapturedFrame(image:upright,fired:fired,gravity:savedGravity))
    }
}
