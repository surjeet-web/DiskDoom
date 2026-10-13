import SwiftUI

struct GlobalSearchResultsView: View {
    let query: String
    let result: GlobalSearchResult
    let isSearching: Bool
    let scanLabel: String?
    let appsLoading: Bool
    let incompleteIndex: Bool
    let onSelect: (GlobalSearchHit) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Search everywhere")
                        .font(.title2.weight(.semibold))
                    Text("Sections, visualizations, installed apps, and indexed scan files")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close Search", action: onClear)
                    .buttonStyle(.bordered)
            }
            .padding(DesignTokens.Space.m)
            Divider()
            if let scanLabel {
                Label("Indexed files and folders from \(scanLabel) only\(incompleteIndex ? " · index loading, capped, or scan incomplete" : "")",
                      systemImage: incompleteIndex ? "exclamationmark.circle" : "internaldrive")
                    .font(.caption)
                    .foregroundStyle(incompleteIndex ? .orange : .secondary)
                    .padding(.horizontal, DesignTokens.Space.m)
                    .padding(.vertical, DesignTokens.Space.s)
            } else {
                Label("Scan a location to search its files. Sections and installed apps remain searchable.",
                      systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(DesignTokens.Space.m)
            }
            Divider()
            if appsLoading {
                Label("Loading installed apps…", systemImage: "app.badge")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, DesignTokens.Space.m)
                    .padding(.vertical, DesignTokens.Space.xs)
            }
            if scanLabel != nil {
                Text("Collapsed packages, excluded folders, and unreadable locations may not appear. A result may have moved since the scan.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, DesignTokens.Space.m)
                    .padding(.vertical, DesignTokens.Space.xs)
            }
            if isSearching && result.hits.isEmpty {
                VStack(spacing: DesignTokens.Space.s) {
                    ProgressView()
                    Text("Searching indexed items…")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if result.hits.isEmpty && appsLoading {
                ProgressView("Loading installed apps…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if result.hits.isEmpty {
                EmptyState(symbol: "magnifyingglass", title: "No indexed matches",
                           message: query.count == 1
                             ? "Type one more character to search files and folders."
                             : "Try a filename, folder, app, or section name. Files outside this scan are not indexed.")
            } else {
                HStack(spacing: DesignTokens.Space.s) {
                    if isSearching { ProgressView().controlSize(.small) }
                    Text(isSearching
                         ? "Searching indexed files… showing sections and apps now"
                         : "\(result.matches) indexed matches · showing \(result.hits.count) best results")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, DesignTokens.Space.m)
                .padding(.top, DesignTokens.Space.s)
                List(result.hits) { hit in
                    Button { onSelect(hit) } label: {
                        HStack(spacing: DesignTokens.Space.m) {
                            Image(systemName: symbol(for: hit.kind))
                                .foregroundStyle(tint(for: hit.kind))
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: DesignTokens.Space.s) {
                                    Text(hit.title).font(.callout.weight(.medium))
                                        .lineLimit(1)
                                    Text(hit.kind.rawValue.capitalized)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text(hit.detail)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: DesignTokens.Space.s)
                            if let bytes = hit.bytes {
                                Text(ByteFormatting.format(bytes))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: "arrow.up.left")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(hit.kind.rawValue.capitalized): \(hit.title), \(hit.detail)")
                    .contextMenu {
                        if hit.kind == .file || hit.kind == .folder ||
                           (hit.kind == .application && hit.target.hasPrefix("/")) {
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.selectFile(hit.target, inFileViewerRootedAtPath: "")
                            }
                            Button("Copy Path") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(hit.target, forType: .string)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func symbol(for kind: GlobalSearchHit.Kind) -> String {
        switch kind {
        case .section: return "square.grid.2x2"
        case .visualization: return "chart.bar.xaxis"
        case .application: return "app.badge"
        case .folder: return "folder.fill"
        case .file: return "doc.fill"
        }
    }

    private func tint(for kind: GlobalSearchHit.Kind) -> Color {
        switch kind {
        case .section, .visualization: return .accentColor
        case .application: return .purple
        case .folder: return .blue
        case .file: return .secondary
        }
    }
}
