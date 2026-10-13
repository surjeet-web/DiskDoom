"""Standalone policy regression tests; no extension test-target imports required.

Run: python3 DiskBuddyTests/ExtensionMeasurementContractTests.py
Compiles the actual pure policies from the extension sources and the shared
measurement contract. Does not build, sign, or launch either extension.
"""
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def section(path, start, end):
    text = (ROOT / path).read_text()
    return text.split(start, 1)[1].split(end, 1)[0]


SWIFT_TESTS = r'''
struct DuplicateFile { let path: String }
struct DuplicateSet { let files: [DuplicateFile] }

let now = Date(timeIntervalSince1970: 10_000_000)
let zero = StorageCapacityReader.fromReadings(totalBytes: 100, freeBytes: 0, measuredAt: now)
let old = Measurement.available(value: StorageCapacity(totalBytes: 100, freeBytes: 80)!, measuredAt: now, source: "Test scan")
assert(WidgetMeasurementPolicy.capacity(live: zero, cached: old, now: now).availableValue?.freeBytes == 0)
assert(zero.availableValue?.usedBytes == 100)
let missing: Measurement<StorageCapacity> = .unavailable(reason: "Missing metadata")
let failed: Measurement<StorageCapacity> = .error(reason: "Permission denied")
assert(WidgetMeasurementPolicy.capacity(live: missing, cached: nil, now: now).availableValue == nil)
assert(WidgetMeasurementPolicy.capacity(live: failed, cached: nil, now: now).reason == "Permission denied")
let fallback = WidgetMeasurementPolicy.capacity(live: failed, cached: old, now: now)
assert(fallback.availableValue?.freeBytes == 80)
assert(fallback.source?.hasPrefix("Cached") == true)
let expired = WidgetMeasurementPolicy.capacity(live: missing, cached: old, now: now.addingTimeInterval(301))
assert(expired.availableValue == nil && expired.recordedValue?.freeBytes == 80)
assert(expired.statusLabel == "Stale")
assert(zero.applyingFreshness(maxAge: 300, now: now.addingTimeInterval(301)).availableValue == nil)

let scan = WidgetSnapshot(schemaVersion: 2, scanSource: "Test scan", healthGrade: "A", lastScanDate: now)
assert(WidgetMeasurementPolicy.scan(scan, now: now).availableValue?.healthGrade == "A")
assert(WidgetMeasurementPolicy.scan(scan, now: now.addingTimeInterval(86_401)).availableValue == nil)
assert(WidgetMeasurementPolicy.scan(nil, now: now).availableValue == nil)
let legacy = WidgetSnapshot(freeBytes: 80, totalBytes: 100, lastScanDate: now, updatedAt: now)
assert(WidgetMeasurementPolicy.scan(legacy, now: now).availableValue == nil)

let sparse = QLMeasurementPolicy.size(0, measuredAt: now, source: "Allocated metadata")
assert(sparse.availableValue == 0 && sparse.source == "Allocated metadata" && sparse.measuredAt == now)
assert(QLMeasurementPolicy.size(nil, measuredAt: now, source: "Metadata").availableValue == nil)
assert(QLMeasurementPolicy.size(-1, measuredAt: now, source: "Metadata").availableValue == nil)
assert(QLMeasurementPolicy.size(nil, measuredAt: now, source: "Metadata", failure: "Read failed").statusLabel == "Measurement failed")

let dated = QLMeasurementPolicy.DuplicateSnapshot(schemaVersion: 2, scannedAt: now, source: "Hash scan", counts: ["/file": 2])
let data = try JSONEncoder().encode(dated)
let duplicates = QLMeasurementPolicy.duplicate(data: data, path: "/file", now: now)
assert(duplicates.availableValue == nil && duplicates.recordedValue == 2)
assert(duplicates.measuredAt == now && duplicates.source == "Hash scan")
assert(QLMeasurementPolicy.duplicate(data: data, path: "/replaced", now: now).recordedValue == nil)
assert(QLMeasurementPolicy.duplicate(data: nil, path: "/file", now: now).recordedValue == nil)
assert(QLMeasurementPolicy.duplicate(data: Data("corrupt".utf8), path: "/file", now: now).recordedValue == nil)
let legacyData = try JSONEncoder().encode(["/file": 2])
assert(QLMeasurementPolicy.duplicate(data: legacyData, path: "/file", now: now).recordedValue == nil)
let future = QLMeasurementPolicy.DuplicateSnapshot(schemaVersion: 2, scannedAt: now.addingTimeInterval(1), source: "Hash scan", counts: ["/file": 2])
let futureData = try JSONEncoder().encode(future)
assert(QLMeasurementPolicy.duplicate(data: futureData, path: "/file", now: now).recordedValue == nil)
let invalid = QLMeasurementPolicy.DuplicateSnapshot(schemaVersion: 2, scannedAt: now, source: "Hash scan", counts: ["/file": 0])
let invalidData = try JSONEncoder().encode(invalid)
assert(QLMeasurementPolicy.duplicate(data: invalidData, path: "/file", now: now).recordedValue == nil)

let appSnapshot = WidgetDataBridge.Snapshot(capacity: zero, scanSource: "Test scan", healthGrade: "A", lastScanDate: now)
let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(appSnapshot))
assert(decoded.schemaVersion == 2 && decoded.capacity?.availableValue?.freeBytes == 0)
assert(WidgetMeasurementPolicy.scan(decoded, now: now).availableValue?.healthGrade == "A")
print("Extension measurement contract tests passed")
'''


def main():
    source = "import Foundation\n"
    source += (ROOT / "DiskBuddy/Core/Measurement/Measurement.swift").read_text()
    source += "\nstruct WidgetSnapshot" + section(
        "DiskBuddyWidget/DiskBuddyWidget.swift", "struct WidgetSnapshot", "enum SharedWidgetStore"
    ) + "\n"
    source += section("DiskBuddyWidget/DiskBuddyWidget.swift", "// MARK: - Pure widget measurement policy", "// MARK: - End pure widget measurement policy")
    source += section("DiskBuddyQuickLook/PreviewViewController.swift", "// MARK: - Pure Quick Look measurement policy", "// MARK: - End pure Quick Look measurement policy")
    source += (ROOT / "DiskBuddy/Core/Persistence/WidgetDataBridge.swift").read_text()
    source += SWIFT_TESTS
    base = Path("/private/var/folders/qq/8pdnjdzj0w77lfjrlwq9kvb00000gn/T/opencode")
    with tempfile.TemporaryDirectory(prefix="extension-measurement-tests-", dir=base) as directory:
        main_file = Path(directory) / "main.swift"
        executable = Path(directory) / "tests"
        main_file.write_text(source)
        subprocess.run(["swiftc", str(main_file), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    main()
