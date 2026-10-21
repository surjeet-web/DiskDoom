import SwiftUI
import ServiceManagement
import UserNotifications

// MARK: - §27 General + §28 Scanning settings (real: login item, accent, notifications, schedule, paths)

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var permissions: PermissionsService
    @EnvironmentObject var license: LicenseStore
    @State private var category: Category = .general

    private enum Category: String, CaseIterable {
        case general = "General", scanning = "Scanning", appearance = "Appearance", menuBar = "Menu Bar", about = "About"
        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .scanning: return "magnifyingglass"
            case .appearance: return "paintpalette"
            case .menuBar: return "menubar.rectangle"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("SETTINGS").font(.caption.weight(.bold)).tracking(2).padding(.vertical, 14)
                ForEach(Category.allCases, id: \.self) { item in
                    Button { category = item } label: {
                        Label(item.rawValue, systemImage: item.symbol).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(PlateButtonStyle(selected: category == item))
                    .accessibilityAddTraits(category == item ? [.isSelected] : [])
                }
                Spacer()
                Text("Changes save immediately").font(.caption).foregroundStyle(.secondary)
            }
            .padding(20).frame(width: 180)
            .background { MetalSurface(family: .boot, flatSide: .right) }
            VStack(alignment: .leading, spacing: 0) {
                Text(category.rawValue).font(.title2.weight(.bold)).padding(24)
                Divider()
                Group {
                    switch category {
                    case .general: GeneralSettingsTab()
                    case .scanning: ScanningSettingsTab()
                    case .appearance: AppearanceSettingsTab()
                    case .menuBar: MenuBarSettingsTab()
                    case .about: AboutTab()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background { MetalSurface(family: .tiered, flatSide: .left) }
        }
        .padding(20)
        .frame(minWidth: 720, idealWidth: 840, maxWidth: 1000,
               minHeight: 600, idealHeight: 680, maxHeight: 900)
        .background(DesignTokens.Palette.void)
        .preferredColorScheme(.dark)
    }
}

private struct AppearanceSettingsTab: View {
    @AppStorage("industrialEffects") private var effects = true
    @AppStorage("listRowHeight") private var rowHeight = 40.0
    var body: some View {
        Form {
            Section("Cinematic reference") {
                Text("Uses the supplied DiskDoom HTML colors, connected chassis, and saturated metallic visualization materials.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Ambient lighting and decorative details", isOn: $effects)
                    .accessibilityIdentifier("appearance.effects")
                Text("Effects are decorative and never carry data. No continuous particle animation runs in the background.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Reading density") {
                Picker("List row height", selection: $rowHeight) {
                    Text("Comfortable · 48 pt").tag(48.0)
                    Text("Standard · 40 pt").tag(40.0)
                    Text("Dense · 34 pt").tag(34.0)
                }
                Text("Applies to native lists; specialized charts and file previews retain their safe content sizes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Live specimen") {
                HStack {
                    Label("Selected module", systemImage: "internaldrive")
                    Spacer()
                    Text("PLANAR TEXT").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                .industrialPanel(.plate, accent: DesignTokens.Palette.orange)
            }
            Section("Accessibility") {
                Text("System Reduce Motion and Increase Contrast are respected. Content and keyboard focus stay above decorative frames; reading surfaces remain opaque.")
                    .font(.callout)
            }
        }.formStyle(.grouped)
    }
}

private struct GeneralSettingsTab: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var permissions: PermissionsService
    @EnvironmentObject var license: LicenseStore
    @EnvironmentObject var gamification: GamificationEngine
    @AppStorage("showXPRewards") private var showXPRewards = true
    @AppStorage("gamificationNotifications") private var gamificationNotifications = true
    @State private var loginEnabled = false
    @State private var notifyStatus: UNAuthorizationStatus = .notDetermined
    @State private var confirmGameReset = false

    private func saved<T>(_ keyPath: ReferenceWritableKeyPath<AppState, T>) -> Binding<T> {
        Binding(
            get: { state[keyPath: keyPath] },
            set: { state[keyPath: keyPath] = $0; state.saveSettings() })
    }

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch DiskDoom at login", isOn: Binding(
                    get: { loginEnabled },
                    set: { loginEnabled = $0; applyLoginItem() }))
            }
            Section("Appearance") {
                Picker("Accent color", selection: saved(\.accentName)) {
                    Text("System").tag("system")
                    Text("Blue").tag("blue")
                    Text("Purple").tag("purple")
                    Text("Green").tag("green")
                    Text("Orange").tag("orange")
                    Text("Pink").tag("pink")
                    Text("Red").tag("red")
                }
            }
            Section("Cleanup") {
                Text(license.isLicensed ? "Licensed — full cleanup enabled" : license.trialDaysLeft > 0 ? "Trial: \(license.trialDaysLeft) days left" : "Read-only — trial expired")
                    .font(.caption)
                    .foregroundStyle(license.canClean ? .green : .orange)
                Button(license.isLicensed ? "Manage License" : "Activate License") {
                    state.showLicense = true
                }
            }
            Section("Removal") {
                Picker("Default method", selection: saved(\.removalMethod)) {
                    ForEach(RemovalMethod.allCases) { method in
                        Text(method.title).tag(method.rawValue)
                    }
                }
                if state.removalMethod == RemovalMethod.move.rawValue {
                    HStack {
                        TextField("Destination folder", text: saved(\.removalDestination))
                        Button("Choose…") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.allowsMultipleSelection = false
                            panel.prompt = "Choose Destination"
                            if panel.runModal() == .OK, let url = panel.url {
                                state.removalDestination = url.path
                                state.saveSettings()
                            }
                        }
                    }
                    Toggle("Overwrite files with the same name", isOn: saved(\.removalOverwrite))
                }
                Text((RemovalMethod(rawValue: state.removalMethod) ?? .trash).detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Gamification") {
                HStack {
                    Label("Level \(gamification.level) · \(gamification.title)", systemImage: "trophy.fill")
                    Spacer()
                    Text("\(gamification.xp.formatted()) XP")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Toggle("Show XP reward toasts", isOn: $showXPRewards)
                Toggle("Notify for achievements and level-ups", isOn: $gamificationNotifications)
                Text("Progress comes from real scans and confirmed cleanup. Quests reset daily and weekly; achievements award bonus XP.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Open Progress") { state.sidebarTab = .progress }
                    Spacer()
                    Button("Reset Progress…", role: .destructive) { confirmGameReset = true }
                        .font(.caption)
                }
            }
            Section("Permissions") {
                HStack {
                    Text("Full Disk Access")
                    Spacer()
                    StatusBadge(text: permissions.fdaGranted ? "Granted" : "Required", kind: permissions.fdaGranted ? .granted : .required)
                }
                .font(.caption)
                if !permissions.fdaGranted {
                    Button("Open System Settings") { permissions.openPrivacySettings() }
                        .font(.caption)
                }
                HStack {
                    Text("Notifications")
                    Spacer()
                    Text(notifyStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Enable") { permissions.requestNotifications() }
                        .font(.caption)
                        .disabled(notifyStatus == .authorized)
                }
                Toggle("Notify when scan completes", isOn: saved(\.notifyOnScan))
            }
            Section("Scheduled Scans") {
                Picker("Frequency", selection: saved(\.scheduleFrequency)) {
                    Text("Never").tag("never")
                    Text("Daily").tag("daily")
                    Text("Weekly").tag("weekly")
                    Text("Monthly").tag("monthly")
                }
                Text("Scheduled scans run when DiskDoom is open (requires Launch at Login for background runs).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .confirmationDialog("Reset gamification progress?", isPresented: $confirmGameReset,
                            titleVisibility: .visible) {
            Button("Reset XP, quests and achievements", role: .destructive) {
                gamification.resetProgress()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This only clears the local progress profile. Files, scans and cleanup history are untouched.")
        }
        .onAppear {
            loginEnabled = SMAppService.mainApp.status == .enabled
            UNUserNotificationCenter.current().getNotificationSettings {
                let status = $0.authorizationStatus
                Task { @MainActor in notifyStatus = status }
            }
        }
    }

    private var notifyStatusText: String {
        switch notifyStatus {
        case .authorized: return "Authorized"
        case .denied: return "Denied (enable in System Settings)"
        case .provisional: return "Provisional"
        default: return "Not requested"
        }
    }

    private func applyLoginItem() {
        do {
            if loginEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginEnabled = SMAppService.mainApp.status == .enabled
        }
    }
}

private struct ScanningSettingsTab: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var ignoreRules: IgnoreRules
    @EnvironmentObject var priorities: ScanPriorityStore
    @State private var newPath = ""
    @State private var newExtension = ""
    @State private var newFolderPriority = ""
    @State private var newTypePriority = ""

    private func saved<T>(_ keyPath: ReferenceWritableKeyPath<AppState, T>) -> Binding<T> {
        Binding(
            get: { state[keyPath: keyPath] },
            set: { state[keyPath: keyPath] = $0; state.saveSettings() })
    }

    var body: some View {
        Form {
            Section("Scan Behavior") {
                Toggle("Follow symlinks", isOn: saved(\.followSymlinks))
                Toggle("Include hidden files (.DS_Store, etc.)", isOn: saved(\.includeHidden))
                Picker("Maximum depth", selection: saved(\.maxDepth)) {
                    Text("Unlimited").tag(0)
                    Text("5 levels").tag(5)
                    Text("10 levels").tag(10)
                }
            }
            Section("Excluded Paths") {
                ForEach(state.excludedPaths, id: \.self) { path in
                    HStack {
                        Text(path).font(.callout.monospaced())
                        Spacer()
                        Button {
                            state.excludedPaths.removeAll { $0 == path }
                            state.saveSettings()
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
                            state.excludedPaths.append(trimmed)
                            newPath = ""
                            state.saveSettings()
                        }
                    }
                }
            }
            Section("Snapshots") {
                Toggle("Auto-save snapshot after each scan", isOn: saved(\.autoSaveSnapshots))
                Stepper("Retain: \(state.snapshotRetention) snapshots", value: saved(\.snapshotRetention), in: 1...100)
                Text("Storage: \(state.snapshots.count) snapshots (~/Library/Application Support/DiskBuddy/snapshots/)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Scan Index") {
                Text("SQLite index of scan results and file hashes (~/Library/Application Support/DiskBuddy/Cache.sqlite). Snapshots, settings, and license are stored separately and are never touched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Clear Scan Cache") {
                    Task {
                        try? await ScanDatabase.shared.deleteDatabaseFile()
                    }
                }
                .foregroundStyle(.red)
            }
            Section("Duplicate Detection") {
                Picker("Minimum file size", selection: saved(\.dupMinBytes)) {
                    Text("1 MB").tag(Int64(1_000_000))
                    Text("10 MB").tag(Int64(10_000_000))
                    Text("100 MB").tag(Int64(100_000_000))
                    Text("1 GB").tag(Int64(1_000_000_000))
                }
                Text("Hash algorithm: SHA-256 (size → 8KB sample → full hash)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Ignore List") {
                ForEach(ignoreRules.ignoredPaths, id: \.self) { path in
                    HStack {
                        Text(path).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button {
                            ignoreRules.removePath(path)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("Ignore folder or file…", text: $newPath)
                    Button("Add") {
                        let trimmed = newPath.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            ignoreRules.addPath(trimmed)
                            newPath = ""
                        }
                    }
                }
                ForEach(ignoreRules.ignoredExtensions, id: \.self) { ext in
                    HStack {
                        Text(".\(ext)").font(.caption.monospaced())
                        Spacer()
                        Button {
                            ignoreRules.removeExtension(ext)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("Ignore extension (e.g. dmg)…", text: $newExtension)
                    Button("Add") {
                        let trimmed = newExtension.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            ignoreRules.addExtension(trimmed)
                            newExtension = ""
                        }
                    }
                }
                Text("Ignored folders are excluded from scans. Ignored extensions are skipped by duplicate and similar searches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Folder Priority") {
                ForEach(Array(priorities.folderPaths.enumerated()), id: \.element) { index, folder in
                    HStack {
                        Text("\(index + 1). \(folder)")
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            priorities.moveFolder(from: index, to: index - 1)
                        } label: {
                            Image(systemName: "arrow.up")
                        }
                        .buttonStyle(.plain)
                        .disabled(index == 0)
                        Button {
                            priorities.moveFolder(from: index, to: index + 1)
                        } label: {
                            Image(systemName: "arrow.down")
                        }
                        .buttonStyle(.plain)
                        .disabled(index == priorities.folderPaths.count - 1)
                        Button {
                            priorities.removeFolder(folder)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    Button("Add Folder…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false
                        panel.prompt = "Prioritize"
                        if panel.runModal() == .OK, let url = panel.url {
                            priorities.addFolder(url.path)
                        }
                    }
                    Spacer()
                    Text("Higher folders are preferred when choosing a copy to keep.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("File Type Priority") {
                ForEach(Array(priorities.fileExtensions.enumerated()), id: \.element) { index, ext in
                    HStack {
                        Text("\(index + 1). .\(ext)").font(.caption.monospaced())
                        Spacer()
                        Button {
                            priorities.moveExtension(from: index, to: index - 1)
                        } label: {
                            Image(systemName: "arrow.up")
                        }
                        .buttonStyle(.plain)
                        .disabled(index == 0)
                        Button {
                            priorities.moveExtension(from: index, to: index + 1)
                        } label: {
                            Image(systemName: "arrow.down")
                        }
                        .buttonStyle(.plain)
                        .disabled(index == priorities.fileExtensions.count - 1)
                        Button {
                            priorities.removeExtension(ext)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("Preferred extension…", text: $newTypePriority)
                    Button("Add") {
                        let trimmed = newTypePriority.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            priorities.addExtension(trimmed)
                            newTypePriority = ""
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct AboutTab: View {
    @EnvironmentObject var license: LicenseStore

    var body: some View {
        VStack(spacing: DesignTokens.Space.m) {
            Image(systemName: "circle.grid.3x3.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("DiskBuddy 1.0.0").font(.title2.weight(.semibold))
            if license.isLicensed {
                Text("Licensed").font(.callout).foregroundStyle(.green)
            } else if license.trialDaysLeft > 0 {
                Text("Trial: \(license.trialDaysLeft) days remaining").font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Trial expired — read-only mode").font(.callout).foregroundStyle(.orange)
            }
        }
        .padding()
        .onAppear { license.refresh() }
    }
}

#Preview {
    let state = AppState()
    return SettingsView()
        .environmentObject(state)
        .environmentObject(state.permissions)
        .environmentObject(state.license)
        .environmentObject(state.ignoreRules)
        .environmentObject(state.priorities)
        .environmentObject(state.gamification)
}
