import SwiftUI

// MARK: - §27 Settings: General + §28 Settings: Scanning (+ minimal About)

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }
            ScanningSettingsTab()
                .tabItem { Label("Scanning", systemImage: "magnifyingglass") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 560)
    }
}

private struct GeneralSettingsTab: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("confirmBeforeTrash") private var confirmBeforeTrash = true
    @AppStorage("moveToTrash") private var moveToTrash = true
    @AppStorage("notifyScanComplete") private var notifyScanComplete = true
    @AppStorage("notifyLeftovers") private var notifyLeftovers = false
    @AppStorage("autoCheckUpdates") private var autoCheckUpdates = true

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch DiskBuddy at login", isOn: $launchAtLogin)
            }
            Section("Cleanup") {
                Toggle("Show confirmation before trashing", isOn: $confirmBeforeTrash)
                Picker("Deletion mode", selection: $moveToTrash) {
                    Text("Move to Trash (recommended)").tag(true)
                    Text("Delete immediately").tag(false)
                }
            }
            Section("Notifications") {
                Toggle("Notify when scan completes", isOn: $notifyScanComplete)
                Toggle("Notify when background monitor finds large leftovers (> 100 MB)", isOn: $notifyLeftovers)
            }
            Section("Updates") {
                HStack {
                    Text("Current version: 1.0.0")
                    Spacer()
                    Button("Check for Updates") { }
                }
                Toggle("Automatically check for updates", isOn: $autoCheckUpdates)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct ScanningSettingsTab: View {
    @AppStorage("defaultTarget") private var defaultTarget = "home"
    @AppStorage("followSymlinks") private var followSymlinks = false
    @AppStorage("includeHidden") private var includeHidden = true
    @AppStorage("includeSnapshots") private var includeSnapshots = false
    @AppStorage("autoSaveSnapshots") private var autoSaveSnapshots = true
    @AppStorage("excludeSystemDuplicates") private var excludeSystemDuplicates = true
    @State private var excludedPaths = ["~/Library/Developer/Xcode/DerivedData", "~/Downloads", "/Volumes/TimeMachine Backups"]
    @State private var newPath = ""

    var body: some View {
        Form {
            Section("Default Scan Target") {
                Picker("Target", selection: $defaultTarget) {
                    Text("Full Mac").tag("full")
                    Text("Home Folder").tag("home")
                    Text("Last used target").tag("last")
                }
            }
            Section("Scan Behavior") {
                Toggle("Follow symlinks", isOn: $followSymlinks)
                Toggle("Include hidden files (.DS_Store, etc.)", isOn: $includeHidden)
                Toggle("Include system snapshots (APFS)", isOn: $includeSnapshots)
            }
            Section("Excluded Paths") {
                ForEach(excludedPaths, id: \.self) { path in
                    HStack {
                        Text(path).font(.callout.monospaced())
                        Spacer()
                        Button {
                            excludedPaths.removeAll { $0 == path }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("Add path…", text: $newPath)
                    Button("Add") {
                        let trimmed = newPath.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            excludedPaths.append(trimmed)
                            newPath = ""
                        }
                    }
                }
            }
            Section("Snapshots") {
                Toggle("Auto-save snapshot after each scan", isOn: $autoSaveSnapshots)
                Button("Clear All Snapshots") { }
                    .foregroundStyle(.red)
            }
            Section("Duplicate Detection") {
                Toggle("Exclude system files from duplicates", isOn: $excludeSystemDuplicates)
                Text("Hash algorithm: SHA-256 (recommended)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: DesignTokens.Space.m) {
            Image(systemName: "circle.grid.3x3.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("DiskBuddy 1.0.0").font(.title2.weight(.semibold))
            Text("Prototype build — mock data, no real scanning or deletion.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    SettingsView()
}
