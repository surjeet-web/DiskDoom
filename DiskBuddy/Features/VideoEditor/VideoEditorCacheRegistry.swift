import Foundation
import SwiftUI

// MARK: - Video editor cache registry (real on-disk locations)
//
// Video editors generate the largest caches of any category: a single 4K
// project can produce 100 GB+ of proxy, render, peak and cache files.
// .trash entries clean via the queue; .manual entries explain the safe
// in-app route (e.g. FCP's Delete Generated Library Files).

struct VideoEditorCacheDefinition: Identifiable, Hashable {
    let id: String
    let name: String
    let appName: String
    let icon: String
    let color: Color
    let paths: [CachePath]
    let description: String
    let riskLevel: ProCacheRisk
    let cleanMethod: ProCacheCleanMethod
    let managementTip: String
    let safeToDelete: [String]
    let notSafeToDelete: [String]

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (l: VideoEditorCacheDefinition, r: VideoEditorCacheDefinition) -> Bool { l.id == r.id }
}

enum VideoEditorCacheRegistry {
    static let all: [VideoEditorCacheDefinition] = [
        // ── Final Cut Pro ──
        .init(id: "fcpx-libraries", name: "Final Cut Pro Libraries", appName: "Final Cut Pro",
              icon: "film.fill", color: .purple,
              paths: [
                CachePath(path: "~/Movies/*.fcpbundle", description: "FCP libraries (default location)"),
              ],
              description: "FCP libraries hold project data, media, render and proxy files — easily 200–500 GB each. Manage generated files from inside FCP.",
              riskLevel: .caution, cleanMethod: .manual,
              managementTip: "Final Cut Pro → File → Delete Generated Library Files → pick what to remove.",
              safeToDelete: ["Proxy Media", "Render Files", "Analysis Files"],
              notSafeToDelete: ["Original Media", "Project Files"]),
        .init(id: "fcpx-render", name: "Final Cut Pro Render Files", appName: "Final Cut Pro",
              icon: "cpu.fill", color: .purple,
              paths: [
                CachePath(path: "~/Movies/*.fcpbundle/Render Files", description: "Render files inside library bundles"),
                CachePath(path: "~/Movies/*.fcpbundle/Render Files/1", description: "Per-library render tiers"),
              ],
              description: "Background render files. FCP regenerates them automatically when you open the project.",
              riskLevel: .safeSlow, cleanMethod: .trash,
              managementTip: "Safe to move to Trash — FCP re-renders on next open. Or use File → Delete Generated Library Files.",
              safeToDelete: ["All render files"],
              notSafeToDelete: []),
        .init(id: "fcpx-proxy", name: "Final Cut Pro Proxy Media", appName: "Final Cut Pro",
              icon: "rectangle.compress.vertical", color: .purple,
              paths: [
                CachePath(path: "~/Movies/*.fcpbundle/Proxy Media", description: "Proxy media inside library bundles"),
              ],
              description: "Low-resolution proxy copies for editing performance. Regenerable from original media.",
              riskLevel: .safeSlow, cleanMethod: .trash,
              managementTip: "Safe if you don't need proxy editing. FCP: File → Delete Generated Library Files → Proxy Media.",
              safeToDelete: ["All proxy media"],
              notSafeToDelete: ["Original Media"]),
        .init(id: "fcpx-analysis", name: "Final Cut Pro Thumbnails & Analysis", appName: "Final Cut Pro",
              icon: "photo.stack.fill", color: .purple,
              paths: [
                CachePath(path: "~/Movies/*.fcpbundle/Analysis Files", description: "Analysis files inside library bundles"),
              ],
              description: "Waveform thumbnails, stabilization analysis, face detection results.",
              riskLevel: .safe, cleanMethod: .trash,
              managementTip: "Regenerated on next import. Safe to remove.",
              safeToDelete: ["All analysis files", "Thumbnails"],
              notSafeToDelete: []),
        // ── Premiere Pro ──
        .init(id: "premiere-media-cache", name: "Premiere Pro Media Cache", appName: "Premiere Pro",
              icon: "film.stack.fill", color: .blue,
              paths: [
                CachePath(path: "~/Library/Application Support/Adobe/Common/Media Cache", description: "Peak files, waveform cache"),
                CachePath(path: "~/Library/Application Support/Adobe/Common/Media Cache Files", description: "Rendered preview files"),
                CachePath(path: "~/Library/Caches/com.adobe.PremierePro", description: "Premiere application cache"),
              ],
              description: "Peak files (audio waveforms), video thumbnails, preview renders. Auto-generated on import — can reach 50–200 GB.",
              riskLevel: .safe, cleanMethod: .trash,
              managementTip: "Clean via Premiere: Preferences → Media Cache → Delete. Or remove the folders directly — Premiere rebuilds.",
              safeToDelete: ["Peak files", "Media Cache Files", "Thumbnails"],
              notSafeToDelete: []),
        .init(id: "premiere-projects", name: "Premiere Pro Project Backups", appName: "Premiere Pro",
              icon: "arrow.clockwise.circle.fill", color: .blue,
              paths: [
                CachePath(path: "~/Documents/Adobe/Premiere Pro", description: "Auto-save and project backups"),
              ],
              description: "Auto-save project files and backup copies. Keep recent ones — inspect dates before removing anything.",
              riskLevel: .caution, cleanMethod: .manual,
              managementTip: "Open the folder and remove auto-saves older than 30 days; keep the current project.",
              safeToDelete: ["Old auto-saves (> 30 days)"],
              notSafeToDelete: ["Recent auto-saves", "Current project"]),
        // ── After Effects ──
        .init(id: "aftereffects-disk-cache", name: "After Effects Disk Cache", appName: "After Effects",
              icon: "sparkles.rectangle.stack.fill", color: .indigo,
              paths: [
                CachePath(path: "~/Library/Caches/Adobe/After Effects", description: "AE disk cache"),
              ],
              description: "AE renders every frame to disk cache for RAM preview — a 10-second 4K comp is ~2 GB. Reaches 100 GB+ quickly. Auto-saved projects in ~/Documents/Adobe are deliberately NOT listed here: trashing them loses unsaved work.",
              riskLevel: .safe, cleanMethod: .trash,
              managementTip: "AE: Edit → Purge → All Memory & Disk Cache. Or set a cache limit in Preferences → Media & Disk Cache.",
              safeToDelete: ["All disk cache"],
              notSafeToDelete: ["Auto-save projects"]),
        // ── DaVinci Resolve ──
        .init(id: "resolve-cache", name: "DaVinci Resolve Cache", appName: "DaVinci Resolve",
              icon: "circle.grid.cross.fill", color: .red,
              paths: [
                CachePath(path: "~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Cache", description: "Resolve render cache"),
                CachePath(path: "~/Movies/Resolve Cache", description: "Default Resolve cache location"),
                CachePath(path: "/Volumes/*/Resolve Cache", description: "Resolve cache on external drives"),
              ],
              description: "Render cache, optimized media, proxy media. Resolve can use cache locations across multiple drives.",
              riskLevel: .safeSlow, cleanMethod: .trash,
              managementTip: "Resolve: Playback → Delete Render Cache → All. Preferences → Media Storage shows all cache locations.",
              safeToDelete: ["Render cache", "Optimized media", "Proxy media"],
              notSafeToDelete: ["Project database"]),
        .init(id: "resolve-optimized", name: "DaVinci Resolve Optimized Media", appName: "DaVinci Resolve",
              icon: "rectangle.compress.vertical", color: .red,
              paths: [
                CachePath(path: "~/Movies/Resolve Cache/Clip", description: "Optimized media files"),
              ],
              description: "DNxHR/ProRes optimized copies for smooth playback. Regenerated from source media.",
              riskLevel: .safeSlow, cleanMethod: .trash,
              managementTip: "Resolve: right-click clips → Delete Optimized Media.",
              safeToDelete: ["All optimized media"],
              notSafeToDelete: []),
        // ── Apple Motion / Compressor ──
        .init(id: "motion-cache", name: "Apple Motion Cache", appName: "Motion",
              icon: "wand.and.stars", color: .green,
              paths: [
                CachePath(path: "~/Library/Caches/com.apple.motion", description: "Motion application cache"),
              ],
              description: "Motion preview cache and temporary render files.",
              riskLevel: .safe, cleanMethod: .trash,
              managementTip: "Safe to remove — Motion rebuilds on next use.",
              safeToDelete: ["All cache"],
              notSafeToDelete: []),
        .init(id: "compressor-jobs", name: "Compressor Job History", appName: "Compressor",
              icon: "arrow.triangle.2.circlepath", color: .green,
              paths: [
                CachePath(path: "~/Library/Application Support/Compressor", description: "Compressor settings and job cache"),
              ],
              description: "Completed batch job history and temporary transcoding files.",
              riskLevel: .safe, cleanMethod: .trash,
              managementTip: "Clear job history from within Compressor; temp files are safe to remove.",
              safeToDelete: ["Job history", "Temp files"],
              notSafeToDelete: []),
        // ── Shotcut / HandBrake ──
        .init(id: "shotcut-cache", name: "Shotcut Cache", appName: "Shotcut",
              icon: "scissors", color: .teal,
              paths: [
                CachePath(path: "~/Library/Caches/org.shotcut.Shotcut", description: "Shotcut proxy and preview cache"),
              ],
              description: "Shotcut proxy and preview renders.",
              riskLevel: .safe, cleanMethod: .trash,
              managementTip: "Safe to remove — regenerates on next project open.",
              safeToDelete: ["All cache"],
              notSafeToDelete: []),
        .init(id: "handbrake-queue", name: "HandBrake Queue", appName: "HandBrake",
              icon: "arrow.triangle.branch", color: .orange,
              paths: [
                CachePath(path: "~/Library/Application Support/HandBrake", description: "Queue history and temp files"),
              ],
              description: "Completed encode queue and temporary transcoding files.",
              riskLevel: .safe, cleanMethod: .trash,
              managementTip: "Clear queue history from the HandBrake UI.",
              safeToDelete: ["Queue history"],
              notSafeToDelete: []),
    ]
}
