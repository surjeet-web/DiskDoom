import Foundation
import SwiftUI

// MARK: - 3D & creative application cache registry (real on-disk locations)
//
// These apps generate enormous caches: render caches, simulation caches,
// texture caches, undo history. Cleaning routes through the cleanup queue
// (Trash) for .trash entries; .manual entries are information-only.

enum ProCacheRisk {
    case safe, safeSlow, caution, dangerous

    var badge: String {
        switch self {
        case .safe: return "Safe"
        case .safeSlow: return "Safe (rebuild)"
        case .caution: return "Inspect"
        case .dangerous: return "Don't Delete"
        }
    }

    var color: Color {
        switch self {
        case .safe: return .green
        case .safeSlow: return .yellow
        case .caution: return .orange
        case .dangerous: return .red
        }
    }
}

enum ProCacheCleanMethod {
    case trash   // staged into the cleanup queue
    case manual  // manage inside the app (info + tip only)
}

struct CachePath {
    let path: String
    let description: String
}

struct Pro3DCacheDefinition: Identifiable, Hashable {
    let id: String
    let name: String
    let appName: String
    let icon: String
    let color: Color
    let cachePaths: [CachePath]
    let description: String
    let riskLevel: ProCacheRisk
    let cleanMethod: ProCacheCleanMethod

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (l: Pro3DCacheDefinition, r: Pro3DCacheDefinition) -> Bool { l.id == r.id }
}

enum Pro3DCacheRegistry {
    static let all: [Pro3DCacheDefinition] = [
        // ── Blender ──
        .init(id: "blender-renders", name: "Blender Render Cache", appName: "Blender",
              icon: "cube.fill", color: .orange,
              cachePaths: [
                CachePath(path: "~/Library/Caches/org.blenderfoundation.blender", description: "Blender application cache"),
                CachePath(path: "~/Library/Application Support/Blender/cache", description: "Blender persistent cache"),
              ],
              description: "Rendered frames, shader compilation cache, preview thumbnails.",
              riskLevel: .safe, cleanMethod: .trash),
        .init(id: "blender-autosave", name: "Blender Autosave", appName: "Blender",
              icon: "clock.arrow.circlepath", color: .orange,
              cachePaths: [
                CachePath(path: "~/Library/Application Support/Blender/autosave", description: "Auto-saved .blend files"),
              ],
              description: "Automatic recovery files — usually the 3 most recent, but they accumulate after crashes.",
              riskLevel: .caution, cleanMethod: .manual),
        .init(id: "blender-tmp", name: "Blender Temp Renders", appName: "Blender",
              icon: "photo.fill", color: .orange,
              cachePaths: [
                CachePath(path: "/tmp/blender*", description: "Default render output location"),
              ],
              description: "Rendered frames and sequences Blender wrote to /tmp. Check project settings — output may live elsewhere.",
              riskLevel: .caution, cleanMethod: .manual),
        // ── Cinema 4D ──
        .init(id: "c4d-texture-cache", name: "Cinema 4D Texture Cache", appName: "Cinema 4D",
              icon: "paintpalette.fill", color: .purple,
              cachePaths: [
                CachePath(path: "~/Library/MAXON/cache", description: "MAXON texture and preview cache"),
                CachePath(path: "~/Library/Caches/net.maxon.cinema4d", description: "C4D application cache"),
              ],
              description: "Texture previews, material thumbnails, viewport cache. Rebuilt automatically.",
              riskLevel: .safe, cleanMethod: .trash),
        // ── Maya ──
        .init(id: "maya-cache", name: "Maya Cache", appName: "Maya",
              icon: "cube.transparent.fill", color: .blue,
              cachePaths: [
                CachePath(path: "~/Library/Preferences/Autodesk/Maya/cache", description: "Maya scene cache"),
                CachePath(path: "~/Library/Caches/com.autodesk.Maya", description: "Maya application cache"),
                CachePath(path: "~/Documents/maya/projects/default/cache", description: "Default project cache"),
              ],
              description: "Geometry caches, simulation caches, viewport caches. Project caches can be 50 GB+.",
              riskLevel: .caution, cleanMethod: .trash),
        .init(id: "maya-simulation", name: "Maya Simulation Cache", appName: "Maya",
              icon: "wind", color: .blue,
              cachePaths: [
                CachePath(path: "~/Documents/maya/projects/default/particles", description: "Particle cache"),
                CachePath(path: "~/Documents/maya/projects/default/nCache", description: "nCache simulation data"),
                CachePath(path: "~/Documents/maya/projects/default/fluidCache", description: "Fluid simulation cache"),
              ],
              description: "Particle, cloth, fluid and nDynamics simulation caches — enormous for VFX work.",
              riskLevel: .caution, cleanMethod: .trash),
        // ── Houdini ──
        .init(id: "houdini-cache", name: "Houdini Cache", appName: "Houdini",
              icon: "sparkles", color: .red,
              cachePaths: [
                CachePath(path: "~/Library/Caches/houdini", description: "Houdini application cache"),
                CachePath(path: "/tmp/houdini*", description: "Houdini temporary cache"),
              ],
              description: "VDB volumes, simulation caches, flipbooks. Houdini caches can reach 100 GB+.",
              riskLevel: .caution, cleanMethod: .trash),
        .init(id: "houdini-simulation", name: "Houdini Simulation Cache", appName: "Houdini",
              icon: "waveform.path.ecg", color: .red,
              cachePaths: [
                CachePath(path: "~/houdini/cache", description: "Default Houdini cache directory"),
              ],
              description: "FLIP, pyro, cloth and grain simulation caches. Re-cache by re-running the simulation.",
              riskLevel: .caution, cleanMethod: .trash),
        // ── Substance ──
        .init(id: "substance-cache", name: "Substance Cache", appName: "Substance 3D",
              icon: "paintbrush.fill", color: .green,
              cachePaths: [
                CachePath(path: "~/Library/Application Support/Adobe/Substance 3D Designer/cache", description: "Substance Designer cache"),
                CachePath(path: "~/Library/Caches/com.adobe.Substance3D*", description: "Substance application caches"),
                CachePath(path: "~/Library/Application Support/Allegorithmic/Substance Designer/cache", description: "Legacy Substance cache"),
              ],
              description: "Graph evaluation cache, baked texture cache, preview thumbnails.",
              riskLevel: .safe, cleanMethod: .trash),
        // ── ZBrush ──
        .init(id: "zbrush-cache", name: "ZBrush Cache", appName: "ZBrush",
              icon: "paintbrush.pointed.fill", color: .pink,
              cachePaths: [
                CachePath(path: "~/Library/Application Support/ZBrush/cache", description: "Undo history and cache"),
              ],
              description: "ZBrush undo history lives on disk — each step can be 1 GB+ at high subdivision levels.",
              riskLevel: .caution, cleanMethod: .trash),
        // ── Unreal ──
        .init(id: "unreal-ddc", name: "Unreal DDC (Derived Data Cache)", appName: "Unreal Engine",
              icon: "cube.fill", color: .gray,
              cachePaths: [
                CachePath(path: "~/Library/Application Support/Unreal Engine/DerivedDataCache", description: "Global Unreal DDC"),
                CachePath(path: "/Users/Shared/Unreal Engine/DerivedDataCache", description: "Shared Unreal DDC"),
              ],
              description: "Compiled shaders, cooked textures, build artifacts. Legendary for its size — commonly 50–200 GB.",
              riskLevel: .safeSlow, cleanMethod: .trash),
        // ── Unity ──
        .init(id: "unity-cache", name: "Unity Editor Cache", appName: "Unity",
              icon: "gamecontroller.fill", color: .blue,
              cachePaths: [
                CachePath(path: "~/Library/Caches/com.unity3d.UnityEditor", description: "Unity editor cache"),
                CachePath(path: "~/Library/Unity/Asset Store-5.x", description: "Unity Asset Store cache"),
                CachePath(path: "~/Library/Unity/cache", description: "Unity package cache"),
              ],
              description: "Editor cache, downloaded Asset Store packages, shader cache.",
              riskLevel: .safe, cleanMethod: .trash),
        .init(id: "unity-library", name: "Unity Project Libraries", appName: "Unity",
              icon: "books.vertical.fill", color: .blue,
              cachePaths: [
                CachePath(path: "~/Documents/*/Library", description: "Per-project Library folders"),
              ],
              description: "Each Unity project has a Library/ folder with imported assets — often 10–50 GB per project. Verify each is a Unity project before cleaning.",
              riskLevel: .caution, cleanMethod: .manual),
        // ── Color management ──
        .init(id: "ocio-cache", name: "Color Management Cache", appName: "Shared",
              icon: "circle.lefthalf.filled", color: .mint,
              cachePaths: [
                CachePath(path: "~/Library/Application Support/OpenColorIO", description: "OCIO LUT cache"),
              ],
              description: "Cached color transform LUTs. Small but accumulates across projects.",
              riskLevel: .safe, cleanMethod: .trash),
        // ── HDRI libraries ──
        .init(id: "hdri-haven", name: "HDRI Environment Cache", appName: "Shared",
              icon: "sun.max.fill", color: .yellow,
              cachePaths: [
                CachePath(path: "~/Library/Application Support/HDRI Haven", description: "Downloaded HDRIs"),
                CachePath(path: "~/Documents/HDRIs", description: "User HDRI library"),
              ],
              description: "Downloaded HDRI environment maps, 50–500 MB each. Keep what you use, archive the rest.",
              riskLevel: .caution, cleanMethod: .manual),
    ]
}

// MARK: - Shared scanner for professional cache registries (3D + video)
//
// Expands glob paths ("~/Movies/*.fcpbundle/Render Files", "/tmp/houdini*")
// and measures directories in one enumerator pass.

enum ProCacheScanner {
    struct Measurement: Sendable {
        let bytes: Int64
        let files: Int
    }

    /// Expand a path with glob components into existing directories.
    /// Supports "*" (any entry), "prefix*", and "*suffix" per component.
    static func expandGlob(_ raw: String) -> [String] {
        let fm = FileManager.default
        let expanded = (raw as NSString).expandingTildeInPath
        let components = expanded.split(separator: "/").map(String.init)
        var frontier = ["/"]
        for component in components {
            var next: [String] = []
            for base in frontier {
                if component == "*" {
                    if let children = try? fm.contentsOfDirectory(atPath: base) {
                        for child in children where !child.hasPrefix(".") {
                            let candidate = base == "/" ? "/\(child)" : "\(base)/\(child)"
                            var isDir: ObjCBool = false
                            if fm.fileExists(atPath: candidate, isDirectory: &isDir), isDir.boolValue {
                                next.append(candidate)
                            }
                        }
                    }
                } else if component.hasSuffix("*") {
                    let prefix = String(component.dropLast())
                    if let children = try? fm.contentsOfDirectory(atPath: base) {
                        for child in children where child.hasPrefix(prefix) {
                            let candidate = base == "/" ? "/\(child)" : "\(base)/\(child)"
                            var isDir: ObjCBool = false
                            if fm.fileExists(atPath: candidate, isDirectory: &isDir), isDir.boolValue {
                                next.append(candidate)
                            }
                        }
                    }
                } else if component.hasPrefix("*") {
                    let suffix = String(component.dropFirst())
                    if let children = try? fm.contentsOfDirectory(atPath: base) {
                        for child in children where child.hasSuffix(suffix) {
                            let candidate = base == "/" ? "/\(child)" : "\(base)/\(child)"
                            var isDir: ObjCBool = false
                            if fm.fileExists(atPath: candidate, isDirectory: &isDir), isDir.boolValue {
                                next.append(candidate)
                            }
                        }
                    }
                } else {
                    let candidate = base == "/" ? "/\(component)" : "\(base)/\(component)"
                    if fm.fileExists(atPath: candidate) {
                        next.append(candidate)
                    }
                }
            }
            frontier = next
            if frontier.isEmpty { break }
        }
        // Only directories at the final level.
        return frontier.filter { (try? URL(fileURLWithPath: $0).resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
    }

    /// Measure bytes + file count in one pass (hidden files included).
    static func measure(path: String) -> Measurement {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return Measurement(bytes: 0, files: 0) }
        if !isDir.boolValue {
            let size = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return Measurement(bytes: Int64(size), files: 1)
        }
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) else {
            return Measurement(bytes: 0, files: 0)
        }
        var bytes: Int64 = 0
        var files = 0
        while let url = enumerator.nextObject() as? URL {
            if let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
               values.isDirectory != true {
                bytes += Int64(values.fileSize ?? 0)
                files += 1
            }
        }
        return Measurement(bytes: bytes, files: files)
    }
}
