import Foundation

// MARK: - Explorer row model (path identity: refreshes never look like new rows)

struct FolderNode: Identifiable, Hashable, Sendable {
    var id: String { path }

    let path: String
    let name: String
    let size: Int64

    let isDirectory: Bool
    let isPackage: Bool
    let isSymlink: Bool

    let childCount: Int?
    let fileCount: Int?
    let modified: Date?
    let fileExtension: String?
    let percentageOfParent: Double

    /// WHY: permission-denied children must not render a measured-looking
    /// "0 B" / "0.0%" — the row shows a lock + "Permission denied" instead.
    var isUnreadable: Bool = false
    var isPartial: Bool = false
    var parentIsPartial: Bool = false
    var measuredAt: Date? = nil
    var measurementSource: String = "Filesystem traversal (logical bytes)"

    func evidence<Value>(_ value: Value?, now: Date = Date()) -> Measurement<Value> {
        guard !isUnreadable else { return .unavailable(reason: "Permission denied or metadata unreadable") }
        guard let value, let measuredAt else { return .notMeasured }
        return Measurement.available(value: value, measuredAt: measuredAt, source: measurementSource + (isPartial ? " · partial lower bound" : ""))
            .applyingFreshness(maxAge: FolderMeasurementEngine.measurementTTL, now: now)
    }

    var shareDisplay: String {
        guard !isUnreadable else { return "Unavailable" }
        guard !parentIsPartial else { return "Unknown (parent total incomplete)" }
        return display(evidence(percentageOfParent)) { String(format: "%.1f%%", $0) }
    }

    func display<Value>(_ measurement: Measurement<Value>, format: (Value) -> String) -> String {
        switch measurement {
        case .available(let value, _, _): return format(value)
        case .stale(let value, _, _): return "Stale cached · " + format(value)
        default: return measurement.statusLabel
        }
    }

    var provenanceDisplay: String {
        guard let measuredAt else { return "Not measured" }
        let status = evidence(size).statusLabel
        return "\(status) · \(measurementSource)\(isPartial ? " · partial lower bounds" : "") · \(measuredAt.formatted(date: .abbreviated, time: .standard))"
    }

    var fileCountDisplay: String {
        display(evidence(fileCount)) { "\($0)" + (isPartial ? " (lower bound)" : "") }
    }
    var childCountDisplay: String { display(evidence(childCount)) { "\($0)" } }
    var modifiedDisplay: String { display(evidence(modified)) { $0.formatted(date: .long, time: .shortened) } }

    var sizeFormatted: String {
        ByteFormatting.format(size)
    }

    /// WHY: an unreadable node's `size` is 0 only because nothing could be
    /// read — the inspector must say so instead of claiming a measured 0.
    var sizeDisplay: String {
        if isUnreadable { return "Unknown (permission denied)" }
        return display(evidence(size)) { ByteFormatting.format($0) + (isPartial ? " (lower bound)" : "") }
    }
}
