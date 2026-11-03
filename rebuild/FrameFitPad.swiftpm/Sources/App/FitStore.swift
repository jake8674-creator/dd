import Foundation
import UIKit

@MainActor
final class FitStore {
    private let directory: URL
    private(set) var sessions: [FitSession]
    init() throws {
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        directory = documents.appendingPathComponent("FrameFitPadRecords", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var flags = URLResourceValues(); flags.isExcludedFromBackup = true
        var folder = directory; try folder.setResourceValues(flags)
        let index = directory.appendingPathComponent("sessions.json")
        if FileManager.default.fileExists(atPath: index.path) {
            // Failure is propagated; existing records are never silently replaced with an empty list.
            sessions = try JSONDecoder().decode([FitSession].self, from: Data(contentsOf: index))
        } else { sessions = [] }
    }
    func save(_ record: FitSession) throws {
        var next = sessions
        if let i = next.firstIndex(where: { $0.id == record.id }) { next[i] = record }
        else { next.insert(record, at: 0) }
        try persist(next)
        sessions = next
    }
    func delete(_ record: FitSession) throws {
        let next = sessions.filter { $0.id != record.id }
        try persist(next); sessions = next
        let folder = directory.appendingPathComponent(record.id.uuidString)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }
    private func persist(_ next: [FitSession]) throws {
        try JSONEncoder().encode(next).write(to: directory.appendingPathComponent("sessions.json"), options: [.atomic, .completeFileProtection])
    }
    func attach(_ image: UIImage, metadata: FitPhoto, to record: FitSession) throws -> FitSession {
        let folder = directory.appendingPathComponent(record.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let filename = record.id.uuidString + "/" + UUID().uuidString + ".jpg"
        guard let data = image.jpegData(compressionQuality: 0.97) else { throw CocoaError(.fileWriteUnknown) }
        let destination = directory.appendingPathComponent(filename)
        try data.write(to: destination, options: [.atomic, .completeFileProtection])
        var photo = metadata; photo.file = filename
        var next = record; next.photos[photo.position.rawValue] = photo
        do { try save(next) } catch { try? FileManager.default.removeItem(at: destination); throw error }
        return next
    }
    func image(for photo: FitPhoto) -> UIImage? { UIImage(contentsOfFile: directory.appendingPathComponent(photo.file).path) }
    func csv(_ record: FitSession) throws -> URL {
        func cell(_ text: String) -> String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let protected = ["=", "+", "-", "@"].contains(where: { trimmed.hasPrefix($0) }) ? "'" + text : text
            return "\"" + protected.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        var rows = [["FrameFit Pad · 사진 투영 추정 / 실측 정확도 미검증"], ["기록",record.name], ["A",record.lensWidth,"DBL",record.bridgeWidth], ["근거리 cm",record.readingDistance], ["항목","값","단위","설명"]]
        for result in FittingCalculator.results(record) { rows.append([result.name,result.number == nil ? "" : result.text,result.unit,result.note]) }
        rows.append(["메모",record.memo])
        let text = "\u{FEFF}" + rows.map { $0.map(cell).joined(separator: ",") }.joined(separator: "\r\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FrameFit-\(UUID().uuidString).csv")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

@MainActor
extension UIViewController {
    func showMessage(_ text: String, title: String = "확인") {
        let alert = UIAlertController(title: title, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default))
        present(alert, animated: true)
    }
}
