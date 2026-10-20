import Foundation
import ImageIO
import CoreGraphics

// MARK: - Image metadata (EXIF/TIFF/GPS) and dimensions

struct ImageFileMetadata: Sendable, Equatable {
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0
    var dpiWidth: Double = 0
    var dpiHeight: Double = 0
    var bitDepth: Int = 0
    var colorModel: String = ""
    var dateTaken: Date?
    var cameraMake: String = ""
    var cameraModel: String = ""
    var lensModel: String = ""
    var iso: String = ""
    var exposureTime: String = ""
    var focalLength: String = ""
    var fStop: String = ""
    var orientation: Int = 1
    var latitude: Double?
    var longitude: Double?
    var software: String = ""
    var artist: String = ""

    var dimensionsLabel: String {
        guard pixelWidth > 0, pixelHeight > 0 else { return "Unknown" }
        return "\(pixelWidth) × \(pixelHeight)"
    }

    var dpiLabel: String {
        guard dpiWidth > 0 else { return "Unknown" }
        return dpiHeight > 0 && dpiHeight != dpiWidth
            ? "\(Int(dpiWidth)) × \(Int(dpiHeight))"
            : "\(Int(dpiWidth))"
    }

    var megapixels: Double {
        Double(pixelWidth * pixelHeight) / 1_000_000
    }

    var hasCameraMetadata: Bool {
        !cameraMake.isEmpty || !cameraModel.isEmpty || !lensModel.isEmpty
            || !iso.isEmpty || !exposureTime.isEmpty
    }
}

enum FileMetadataReader {
    static let imageExtensions: Set<String> = [
        "heic", "heif", "jpg", "jpeg", "png", "tiff", "tif", "gif", "bmp",
        "webp", "raw", "dng", "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2",
    ]

    static func isImage(_ path: String) -> Bool {
        imageExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    static func read(path: String) -> ImageFileMetadata? {
        guard isImage(path) else { return nil }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }

        var meta = ImageFileMetadata()
        meta.pixelWidth = intValue(properties[kCGImagePropertyPixelWidth])
        meta.pixelHeight = intValue(properties[kCGImagePropertyPixelHeight])
        meta.dpiWidth = doubleValue(properties[kCGImagePropertyDPIWidth])
        meta.dpiHeight = doubleValue(properties[kCGImagePropertyDPIHeight])
        meta.bitDepth = intValue(properties[kCGImagePropertyDepth])
        meta.colorModel = stringValue(properties[kCGImagePropertyColorModel])
        meta.orientation = intValue(properties[kCGImagePropertyOrientation])

        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            meta.dateTaken = dateValue(exif[kCGImagePropertyExifDateTimeOriginal])
                ?? dateValue(exif[kCGImagePropertyExifDateTimeDigitized])
            meta.iso = stringValue(exif[kCGImagePropertyExifISOSpeedRatings])
            meta.exposureTime = rationalValue(exif[kCGImagePropertyExifExposureTime])
            meta.focalLength = rationalValue(exif[kCGImagePropertyExifFocalLength])
            meta.fStop = rationalValue(exif[kCGImagePropertyExifFNumber])
            meta.lensModel = stringValue(exif[kCGImagePropertyExifLensModel])
        }
        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            meta.cameraMake = stringValue(tiff[kCGImagePropertyTIFFMake])
            meta.cameraModel = stringValue(tiff[kCGImagePropertyTIFFModel])
            if meta.software.isEmpty { meta.software = stringValue(tiff[kCGImagePropertyTIFFSoftware]) }
            if meta.artist.isEmpty { meta.artist = stringValue(tiff[kCGImagePropertyTIFFArtist]) }
            if meta.dateTaken == nil { meta.dateTaken = dateValue(tiff[kCGImagePropertyTIFFDateTime]) }
        }
        if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
            meta.latitude = coordinate(gps[kCGImagePropertyGPSLatitude], ref: gps[kCGImagePropertyGPSLatitudeRef])
            meta.longitude = coordinate(gps[kCGImagePropertyGPSLongitude], ref: gps[kCGImagePropertyGPSLongitudeRef])
        }
        return meta
    }

    /// Date/size metadata used by "mark images without metadata".
    static func hasMeaningfulMetadata(_ meta: ImageFileMetadata?) -> Bool {
        guard let meta else { return false }
        return meta.hasCameraMetadata || meta.latitude != nil || meta.longitude != nil
    }

    // MARK: Property coercion

    private static func intValue(_ value: Any?) -> Int {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) ?? 0 }
        return 0
    }

    private static func doubleValue(_ value: Any?) -> Double {
        if let double = value as? Double { return double }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) ?? 0 }
        return 0
    }

    private static func stringValue(_ value: Any?) -> String {
        if let string = value as? String { return string }
        if let array = value as? [Any], let first = array.first { return stringValue(first) }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    private static func dateValue(_ value: Any?) -> Date? {
        let string = stringValue(value)
        guard !string.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["yyyy:MM:dd HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy:MM:dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }

    private static func rationalValue(_ value: Any?) -> String {
        if let number = value as? NSNumber {
            let double = number.doubleValue
            if double <= 0 { return "" }
            if double < 1 { return "1/\(Int((1 / double).rounded()))" }
            return String(format: "%.1f", double)
        }
        if let string = value as? String, !string.isEmpty { return string }
        if let array = value as? [Any], array.count >= 2,
           let numerator = array[0] as? NSNumber, let denominator = array[1] as? NSNumber,
           denominator.doubleValue != 0 {
            let value = numerator.doubleValue / denominator.doubleValue
            if value > 0, value < 1 { return "1/\(Int((1 / value).rounded()))" }
            return String(format: "%.1f", value)
        }
        return ""
    }

    private static func coordinate(_ value: Any?, ref: Any?) -> Double? {
        guard let double = value as? Double ?? (value as? NSNumber)?.doubleValue else { return nil }
        let reference = stringValue(ref).uppercased()
        return reference == "S" || reference == "W" ? -double : double
    }
}
