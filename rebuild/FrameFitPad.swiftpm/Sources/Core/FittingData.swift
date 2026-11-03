import Foundation

struct FitPoint: Codable, Equatable {
    var x: Double
    var y: Double
    var finite: Bool { x.isFinite && y.isFinite }
    static func -(a: Self, b: Self) -> PixelVector { PixelVector(x:a.x-b.x,y:a.y-b.y) }
    var valid: Bool { x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y) }
}
struct PixelVector {
    var x: Double
    var y: Double
    var length: Double { hypot(x, y) }
    var unit: Self { length > 0 ? self * (1 / length) : .init(x: 0, y: 0) }
    static func + (a: Self, b: Self) -> Self { .init(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: Self, b: Self) -> Self { .init(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: Self, b: Double) -> Self { .init(x: a.x * b, y: a.y * b) }
    func dot(_ b: Self) -> Double { x * b.x + y * b.y }
}

enum PhotoPosition: String, Codable, CaseIterable {
    case distance, right, left, above, reading
    var title: String {
        switch self {
        case .distance: return "원거리 정면"
        case .right: return "고객 오른쪽 측면"
        case .left: return "고객 왼쪽 측면"
        case .above: return "위쪽"
        case .reading: return "근거리 정면"
        }
    }
    var frontal: Bool { self == .distance || self == .reading }
    var side: Bool { self == .right || self == .left }
    var instruction: String {
        switch self {
        case .distance: return "고객은 카메라가 아닌 먼 표적을 봅니다. 촬영자는 눈높이에서 정면을 맞추세요."
        case .reading: return "평소 읽는 자세로 화면 중앙의 글자를 봅니다. 실제 눈–화면 거리를 확인하세요. 흰 화면 플래시와 함께 촬영합니다."
        case .right, .left: return "고객 머리는 정면으로 유지하고 촬영자가 옆으로 이동하세요. 눈높이에서 렌즈 후면과 각막 꼭짓점이 보이는 정확한 측면을 찍습니다."
        case .above: return "고객 자세를 유지하고 카메라를 위로 이동하세요. 두 렌즈 후면의 수평 단면을 내려다봅니다. 사진 아래쪽은 코, 왼쪽은 고객 오른쪽입니다."
        }
    }
    var required: [FitLandmark] {
        if frontal { return [.rightPupil,.leftPupil,.rightOuter,.rightInner,.rightTop,.rightBottom,.leftInner,.leftOuter,.leftTop,.leftBottom] }
        if side { return [.lensBackTop,.lensBackBottom,.cornea] }
        return [.rightOuter,.rightInner,.leftInner,.leftOuter]
    }
    var editable: [FitLandmark] { required + (frontal ? [.rightReflection,.leftReflection] : []) }
}
enum FitLandmark: String, Codable, CaseIterable {
    case rightPupil, leftPupil, rightOuter, rightInner, rightTop, rightBottom
    case leftInner, leftOuter, leftTop, leftBottom
    case lensBackTop, lensBackBottom, cornea, rightReflection, leftReflection
    var title: String {
        switch self {
        case .rightPupil: return "R 동공 중심"
        case .leftPupil: return "L 동공 중심"
        case .rightOuter: return "R 렌즈 귀쪽 경계"
        case .rightInner: return "R 렌즈 코쪽 경계"
        case .rightTop: return "R 렌즈 최상단"
        case .rightBottom: return "R 렌즈 최하단"
        case .leftInner: return "L 렌즈 코쪽 경계"
        case .leftOuter: return "L 렌즈 귀쪽 경계"
        case .leftTop: return "L 렌즈 최상단"
        case .leftBottom: return "L 렌즈 최하단"
        case .lensBackTop: return "렌즈 후면 위쪽"
        case .lensBackBottom: return "렌즈 후면 아래쪽"
        case .cornea: return "각막 꼭짓점"
        case .rightReflection: return "R 각막 반사 후보（참고）"
        case .leftReflection: return "L 각막 반사 후보（참고）"
        }
    }
}
struct FitPhoto: Codable {
    var file: String
    var position: PhotoPosition
    var width: Double
    var height: Double
    var points: [String:FitPoint] = [:]
    var automatic: [String] = []
    var reviewed: [String] = []
    var postureAccepted = false
    var rearFlashFired = false
    var gravityX: Double?
    var gravityY: Double?
    var detectionMessage = ""
    var allReviewed: Bool {
        postureAccepted && position.required.allSatisfy { reviewed.contains($0.rawValue) && points[$0.rawValue]?.valid == true }
    }
    func pixel(_ key: FitLandmark) -> PixelVector? {
        guard let p = points[key.rawValue], p.valid else { return nil }
        return PixelVector(x: p.x * width, y: p.y * height)
    }
    mutating func move(_ key: FitLandmark, to p: FitPoint) {
        guard p.valid else { return }
        points[key.rawValue] = p
        reviewed.removeAll { $0 == key.rawValue }
        automatic.removeAll { $0 == key.rawValue }
    }
}
struct FitSession: Codable, Identifiable {
    var id = UUID()
    var created = Date()
    var name = ""
    var lensWidth = ""
    var bridgeWidth = ""
    var readingDistance = "40"
    var memo = ""
    var leftSide = false
    var photos: [String:FitPhoto] = [:]
    var title: String { name.isEmpty ? "새 피팅" : name }
    var positions: [PhotoPosition] { [.distance, leftSide ? .left : .right, .above, .reading] }
    static func number(_ text: String) -> Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")), value.isFinite else { return nil }
        return value
    }
}
struct FitResult {
    var name: String
    var number: Double?
    var unit: String
    var note: String
    var text: String { number.map { String(format: "%.1f", $0) } ?? "—" }
}
