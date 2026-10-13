import Foundation

/// A value is evidence only when its availability, age and origin are known.
/// This file is compiled into the app, widget and QuickLook targets.
enum Measurement<Value> {
    case available(value: Value, measuredAt: Date, source: String)
    case stale(value: Value, measuredAt: Date, source: String)
    case unavailable(reason: String)
    case notMeasured
    case error(reason: String)

    var availableValue: Value? {
        guard case .available(let value, _, _) = self else { return nil }
        return value
    }

    /// Only use together with an explicit cached/stale label.
    var recordedValue: Value? {
        switch self {
        case .available(let value, _, _), .stale(let value, _, _): return value
        default: return nil
        }
    }

    var measuredAt: Date? {
        switch self {
        case .available(_, let date, _), .stale(_, let date, _): return date
        default: return nil
        }
    }

    var source: String? {
        switch self {
        case .available(_, _, let source), .stale(_, _, let source): return source
        default: return nil
        }
    }

    var statusLabel: String {
        switch self {
        case .available: return "Measured"
        case .stale: return "Stale"
        case .unavailable: return "Unavailable"
        case .notMeasured: return "Not measured"
        case .error: return "Measurement failed"
        }
    }

    var reason: String? {
        switch self {
        case .unavailable(let reason), .error(let reason): return reason
        default: return nil
        }
    }

    func applyingFreshness(maxAge: TimeInterval, now: Date = Date()) -> Self {
        guard case .available(let value, let date, let source) = self else { return self }
        let age = now.timeIntervalSince(date)
        guard maxAge.isFinite, maxAge >= 0, age >= 0, age <= maxAge else {
            return .stale(value: value, measuredAt: date, source: source)
        }
        return self
    }

    func map<NewValue>(_ transform: (Value) -> NewValue) -> Measurement<NewValue> {
        switch self {
        case .available(let value, let date, let source):
            return .available(value: transform(value), measuredAt: date, source: source)
        case .stale(let value, let date, let source):
            return .stale(value: transform(value), measuredAt: date, source: source)
        case .unavailable(let reason): return .unavailable(reason: reason)
        case .notMeasured: return .notMeasured
        case .error(let reason): return .error(reason: reason)
        }
    }
}

extension Measurement: Equatable where Value: Equatable {}
extension Measurement: Sendable where Value: Sendable {}
extension Measurement: Codable where Value: Codable {}

struct StorageCapacity: Equatable, Codable, Sendable {
    let totalBytes: Int64
    let freeBytes: Int64

    init?(totalBytes: Int64, freeBytes: Int64) {
        guard totalBytes > 0, freeBytes >= 0, freeBytes <= totalBytes else { return nil }
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
    }

    private enum CodingKeys: String, CodingKey { case totalBytes, freeBytes }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let total = try container.decode(Int64.self, forKey: .totalBytes)
        let free = try container.decode(Int64.self, forKey: .freeBytes)
        guard let capacity = Self(totalBytes: total, freeBytes: free) else {
            throw DecodingError.dataCorruptedError(forKey: .freeBytes, in: container,
                debugDescription: "Invalid stored capacity; zero free is valid, missing/inconsistent capacity is not.")
        }
        self = capacity
    }

    var usedBytes: Int64 { totalBytes - freeBytes }
    var usedPercent: Double { Double(usedBytes) / Double(totalBytes) * 100 }
}

enum StorageCapacityReader {
    static let source = "Filesystem volume capacity (URL resource values)"

    static func fromReadings(totalBytes: Int64?, freeBytes: Int64?,
                             measuredAt: Date = Date()) -> Measurement<StorageCapacity> {
        guard let totalBytes, let freeBytes else {
            return .unavailable(reason: "The filesystem did not return both total and available capacity.")
        }
        guard let capacity = StorageCapacity(totalBytes: totalBytes, freeBytes: freeBytes) else {
            return .error(reason: "The filesystem returned inconsistent capacity values.")
        }
        return .available(value: capacity, measuredAt: measuredAt, source: source)
    }

    static func read(at url: URL = URL(fileURLWithPath: "/"),
                     measuredAt: Date = Date()) -> Measurement<StorageCapacity> {
        do {
            let values = try url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
            return fromReadings(totalBytes: values.volumeTotalCapacity.map(Int64.init),
                                freeBytes: values.volumeAvailableCapacity.map(Int64.init),
                                measuredAt: measuredAt)
        } catch {
            return fromFailure(error)
        }
    }

    static func fromFailure(_ error: Error) -> Measurement<StorageCapacity> {
        let error = error as NSError
        if (error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError) ||
           (error.domain == NSPOSIXErrorDomain &&
            (error.code == Int(POSIXError.Code.EACCES.rawValue) || error.code == Int(POSIXError.Code.EPERM.rawValue))) {
            return .unavailable(reason: "Permission denied while reading volume capacity.")
        }
        return .error(reason: error.localizedDescription)
    }
}
