import Foundation
import CryptoKit

/// An opaque, local-only revision. No file content or individual hashes leave the device.
enum ProtectedTrainingSnapshotRevision {
    static func capture(athleteID: Int, root: URL? = nil) throws -> String {
        guard athleteID > 0 else { throw AcceptedPrescriptionPlanError.staleReview }
        let base = try root ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("ProtectedTraining", isDirectory: true)
        let directory = base.appendingPathComponent(String(athleteID), isDirectory: true)
        var enumerationFailed = false
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [], errorHandler: { _, _ in
            enumerationFailed = true
            return false
        }) else { throw AcceptedPrescriptionPlanError.staleReview }
        let files = try enumerator.compactMap { $0 as? URL }.filter {
            try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
        }.sorted { $0.path < $1.path }
        guard !enumerationFailed, !files.isEmpty else { throw AcceptedPrescriptionPlanError.staleReview }
        struct Entry: Encodable { let path: String; let digest: String }
        let entries = try files.map { file in
            Entry(path: String(file.path.dropFirst(directory.path.count)), digest: SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined())
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return SHA256.hash(data: try encoder.encode(entries)).map { String(format: "%02x", $0) }.joined()
    }
}
