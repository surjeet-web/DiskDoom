import Foundation

// MARK: - D6 File Provenance Tracker (ObservableObject; async; ";" quarantine parse)
//
// Review fixes applied:
// - Analysis is async (mdls/Process + xattr off the main thread, cancellable).
// - com.apple.quarantine fields are SEMICOLON-delimited, not "|".
// - Confidence reflects which signals actually fired.

struct FileProvenance {
    let filePath: String
    let createdBy: String?
    let method: CreationMethod?
    let createdDate: Date?
    let downloadSource: String?
    let isQuarantined: Bool
    let matchedApp: String?
    let confidence: Confidence
    let xattrNames: [String]

    enum CreationMethod: String {
        case downloaded, appCreated, userCreated, systemGenerated, installerPlaced
        var label: String {
            switch self {
            case .downloaded: return "Downloaded"
            case .appCreated: return "Created by app"
            case .userCreated: return "Created by user"
            case .systemGenerated: return "System generated"
            case .installerPlaced: return "Placed by installer"
            }
        }

        var symbol: String {
            switch self {
            case .downloaded: return "arrow.down.circle.fill"
            case .appCreated: return "app.fill"
            case .userCreated: return "person.fill"
            case .systemGenerated: return "gear.circle.fill"
            case .installerPlaced: return "shippingbox.fill"
            }
        }
    }

    enum Confidence: String {
        case high, medium, low
    }
}

final class FileProvenanceEngine: ObservableObject, @unchecked Sendable {
    @Published private(set) var current: FileProvenance?
    @Published private(set) var isAnalyzing = false
    private var task: Task<Void, Never>?

    func analyze(path: String) {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            await MainActor.run { self.isAnalyzing = true }
            let result = await Task.detached { Self.analyzeSync(path: path) }.value
            guard !Task.isCancelled else {
                await MainActor.run { self.isAnalyzing = false }
                return
            }
            await MainActor.run {
                self.current = result
                self.isAnalyzing = false
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    // MARK: Synchronous analysis (runs off-main)

    private static func analyzeSync(path: String) -> FileProvenance {
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
            method = .downloaded
        } else if creator != nil {
            method = .appCreated
        } else if path.contains("/Library/Caches/") || path.contains("/Library/Logs/") {
            method = .systemGenerated
        } else if path.contains("/var/db/receipts/") {
            method = .installerPlaced
        } else if fm.fileExists(atPath: path) {
            method = .userCreated
        } else {
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

    private static func queryMDItem(path: String, attribute: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdls")
        process.arguments = ["-name", attribute, "-raw", path]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let output, output != "(null)", !output.isEmpty else { return nil }
            return output
        } catch {
            return nil
        }
    }

    static func matchApp(from path: String) -> String? {
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
