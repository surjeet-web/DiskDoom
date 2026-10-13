import Foundation

// MARK: - D6 File Provenance Tracker (ObservableObject; async; ";" quarantine parse)
//
// Review fixes applied:
// - Analysis is async (mdls/Process + xattr off the main thread, cancellable).
// - com.apple.quarantine fields are SEMICOLON-delimited, not "|".
// - Confidence reflects which signals actually fired.

struct FileProvenance: Sendable {
    let filePath: String
    let createdBy: String?
    let method: CreationMethod?
    let createdDate: Date?
    let downloadSource: String?
    let isQuarantined: Bool
    let matchedApp: String?
    let confidence: Confidence
    let xattrNames: [String]

    enum CreationMethod: String, Sendable {
        // ONLY produced when real origin metadata was read (kMDItemWhereFroms,
        // the com.apple.quarantine xattr, or kMDItemCreator) — see analyzeSync.
        case downloaded, appCreated
        var label: String {
            switch self {
            case .downloaded: return "Downloaded"
            case .appCreated: return "Created by app"
            }
        }

        var symbol: String {
            switch self {
            case .downloaded: return "arrow.down.circle.fill"
            case .appCreated: return "app.fill"
            }
        }
    }

    enum Confidence: String, Sendable {
        case high, medium, low
    }
}

@MainActor
final class FileProvenanceEngine: ObservableObject, @unchecked Sendable {
    @Published private(set) var current: FileProvenance?
    @Published private(set) var isAnalyzing = false
    private var task: Task<Void, Never>?

    func analyze(path: String) {
        task?.cancel()
        isAnalyzing = true
        task = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.isAnalyzing = true
            }
            let result = await Task.detached { Self.analyzeSync(path: path) }.value
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.current = result
                self.isAnalyzing = false
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isAnalyzing = false
    }

    // MARK: Synchronous analysis (runs off-main)

    nonisolated private static func analyzeSync(path: String) -> FileProvenance {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: path)
        let created = (try? fm.attributesOfItem(atPath: path))?[.creationDate] as? Date
        let xattrs = (try? url.listExtendedAttributes()) ?? []

        // Quarantine: "flag;timestamp;agent;eventID" (SEMICOLON-delimited).
        var quarantined = false
        if let raw = try? url.extendedAttribute(forName: "com.apple.quarantine"),
           let str = String(data: raw, encoding: .utf8) {
            let parts = str.split(separator: ";")
            quarantined = parts.count >= 3
        }

        let downloadSource = queryMDItem(path: path, attribute: "kMDItemWhereFroms")
        let creator = queryMDItem(path: path, attribute: "kMDItemCreator")

        let method: FileProvenance.CreationMethod?
        if downloadSource != nil || quarantined {
            // Evidence read: kMDItemWhereFroms URL(s) and/or the
            // com.apple.quarantine xattr written by the downloader.
            method = .downloaded
        } else if creator != nil {
            // Evidence read: kMDItemCreator metadata.
            method = .appCreated
        } else {
            // WHY: the old chain guessed `.userCreated` ("Created by user" —
            // any file that merely exists) and classified caches/receipts as
            // system/installer-made purely from the path. Without origin
            // metadata every one of those was a fabrication, so report no
            // method and let the view say "Unknown — no origin metadata".
            method = nil
        }

        let matched = matchApp(from: path)
        let confidence: FileProvenance.Confidence
        if creator != nil && matched != nil { confidence = .high }
        else if matched != nil || downloadSource != nil { confidence = .medium }
        else { confidence = .low }

        return FileProvenance(
            filePath: path, createdBy: creator, method: method, createdDate: created,
            downloadSource: downloadSource, isQuarantined: quarantined,
            matchedApp: matched, confidence: confidence, xattrNames: xattrs)
    }

    nonisolated private static func queryMDItem(path: String, attribute: String) -> String? {
        do {
            let data = try FeatureProcessRunner.run(executable: "/usr/bin/mdls",
                arguments: ["-name", attribute, "-raw", path], timeout: 5)
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let output, output != "(null)", !output.isEmpty else { return nil }
            return output
        } catch {
            return nil
        }
    }

    nonisolated static func matchApp(from path: String) -> String? {
        let components = path.split(separator: "/").map(String.init)
        for marker in ["Caches", "Application Support", "HTTPStorages", "Logs", "Preferences"] {
            if let i = components.lastIndex(of: marker), i + 1 < components.count {
                return components[i + 1]
            }
        }
        // Reverse-DNS bundle-ID-ish component.
        return components.first {
            $0.contains(".") && $0.split(separator: ".").count >= 3 && !$0.hasPrefix(".")
        }
    }
}

// MARK: - Extended attribute helpers

extension URL {
    func listExtendedAttributes() throws -> [String] {
        let path = self.path
        let length = listxattr(path, nil, 0, 0)
        guard length > 0 else { return [] }
        var buffer = [CChar](repeating: 0, count: length)
        let result = listxattr(path, &buffer, length, 0)
        guard result > 0 else { return [] }
        return Data(bytes: buffer, count: result)
            .split(separator: 0)
            .compactMap { String(data: Data($0), encoding: .utf8) }
    }

    func extendedAttribute(forName name: String) throws -> Data? {
        let path = self.path
        let length = getxattr(path, name, nil, 0, 0, 0)
        guard length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        let result = getxattr(path, name, &buffer, length, 0, 0)
        guard result > 0 else { return nil }
        return Data(buffer)
    }
}
