import SwiftUI

@main
struct DiskBuddyApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            // §37 menu bar structure (prototype subset).
            CommandGroup(replacing: .newItem) {
                Button("New Scan") { state.startScan() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Save Snapshot") {
                    state.snapshots.insert(
                        Snapshot(date: Date(), label: "Just now", totalBytes: 256_000_000_000, files: 1_892_341, target: state.scanTargetName),
                        at: 0)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(state.scanPhase != .done)
            }
            CommandMenu("Edit") {
                Button("Copy Path") {
                    if let node = state.selectedNode {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(node.path, forType: .string)
                    }
                }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(state.selectedNode == nil)
            }
            CommandMenu("View") {
                Button(state.inspectorVisible ? "Hide Inspector" : "Show Inspector") {
                    state.inspectorVisible.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                Button("Open Cleanup Queue") { state.showCleanup = true }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                Divider()
                // 8 viz modes (§37): ⌥⌘1–8 to avoid clashing with ⌘1–5 tabs.
                ForEach(Array(AppState.ExploreView.allCases.enumerated()), id: \.element) { index, view in
                    Button("Show \(view.title)") {
                        state.sidebarTab = .explore
                        state.exploreView = view
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command, .option])
                }
            }
            CommandMenu("Go") {
                Button("Explore") { state.sidebarTab = .explore }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Duplicates") { state.sidebarTab = .duplicates }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Applications") { state.sidebarTab = .applications }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Monitor") { state.sidebarTab = .monitor }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Snapshots") { state.sidebarTab = .snapshots }
                    .keyboardShortcut("5", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
        }
    }
}
