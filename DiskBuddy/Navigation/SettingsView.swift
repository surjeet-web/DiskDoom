import SwiftUI
import ServiceManagement
import UserNotifications

// MARK: - §27 General + §28 Scanning settings (real: login item, accent, notifications, schedule, paths)

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var permissions: PermissionsService
    @EnvironmentObject var license: LicenseStore

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }
            ScanningSettingsTab()
                .tabItem { Label("Scanning", systemImage: "magnifyingglass") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 600)
    }
}

private struct GeneralSettingsTab: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var permissions: PermissionsService
    @EnvironmentObject var license: LicenseStore
    @State private var loginEnabled = false
    @State private var notifyStatus: UNAuthorizationStatus = .notDetermined

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
        .onAppear {
            loginEnabled = SMAppService.mainApp.status == .enabled
            UNUserNotificationCenter.current().getNotificationSettings {
                notifyStatus = $0.authorizationStatus
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
    @State private var newPath = ""

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
                Toggle("Auto-save snapshot after each scan", isOn: .constant(true))
                    .disabled(true)
                Stepper("Retain: \(state.snapshotRetention) snapshots", value: saved(\.snapshotRetention), in: 1...100)
                Text("Storage: \(state.snapshots.count) snapshots (~/Library/Application Support/DiskBuddy/snapshots/)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
    SettingsView()
        .environmentObject(AppState())
        .environmentObject(PermissionsService())
        .environmentObject(LicenseStore())
}
