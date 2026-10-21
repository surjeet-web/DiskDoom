import SwiftUI

// MARK: - D13 Photo Library view (explicit access states, demo measurement)

struct PhotoLibraryView: View {
    @EnvironmentObject var analyzer: PhotoLibraryAnalyzer
    @State private var showDuplicates = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Photo Library").font(.title2.weight(.semibold))
                    Text("Structure, duplicates, and reclaimable space")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Photo view", selection: $showDuplicates) {
                    Text("Library").tag(false)
                    Text("Duplicates & Similar").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                if !showDuplicates {
                    Button("Check Access") { analyzer.checkAccess() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(DesignTokens.Space.m)
            if !showDuplicates {
                HStack(spacing: DesignTokens.Space.s) {
                    TextField("Custom library path (optional)…", text: $analyzer.customPath)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal, DesignTokens.Space.m)
                .padding(.bottom, DesignTokens.Space.s)
            }
            Divider()
            if showDuplicates {
                PhotoDuplicatesView()
            } else {
            switch analyzer.access {
            case .unchecked:
                EmptyState(symbol: "photo.on.rectangle.angled", title: "Analyze your Photos library", message: "DiskDoom checks access first — nothing is fabricated when the library can't be read.", actionTitle: "Check Access", action: { analyzer.checkAccess() })
            case .checking:
                ProgressView("Checking library access…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .missing(let path):
                VStack(spacing: DesignTokens.Space.m) {
                    Spacer()
                    Image(systemName: "lock.fill").font(.system(size: 48)).foregroundStyle(.orange)
                    Text("Can't read the Photos library")
                        .font(.title3.weight(.semibold))
                    Text("\(path)\n\nThis usually means the library is elsewhere, or macOS denied access (Photos libraries need your consent under TCC). Grant Full Disk Access or enter the correct path above — DiskDoom won't guess numbers.")
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                    Button("Try Again") { analyzer.checkAccess() }.buttonStyle(.bordered)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            case .granted:
                if analyzer.isAnalyzing {
                    ProgressView("Measuring library…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let stats = analyzer.stats {
                    ScrollView {
                        VStack(spacing: DesignTokens.Space.l) {
                            HStack(spacing: DesignTokens.Space.xl) {
                                PhotoStatCard(label: "Total Size", value: ByteFormatting.format(stats.totalBytes), color: .blue)
                                PhotoStatCard(label: "Photos", value: "\(stats.photoCount.formatted())", color: .green)
                                PhotoStatCard(label: "Videos", value: "\(stats.videoCount.formatted())", color: .purple)
                            }
                            VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
                                Text("Library Structure").font(.headline)
                                LibrarySizeRow(label: "Originals", bytes: stats.originalsBytes, total: stats.totalBytes, color: .blue)
                                LibrarySizeRow(label: "Resources (renders, thumbnails)", bytes: stats.resourcesBytes, total: stats.totalBytes, color: .purple)
                                LibrarySizeRow(label: "Database", bytes: stats.databaseBytes, total: stats.totalBytes, color: .gray)
                            }
                            VStack(alignment: .leading, spacing: DesignTokens.Space.s) {
                                Text("Reclaimable").font(.headline)
                                if stats.duplicateSets > 0 {
                                    HStack {
                                        Image(systemName: "doc.on.doc.fill").foregroundStyle(.orange)
                                        Text("\(stats.duplicateSets) duplicate sets · \(ByteFormatting.format(stats.duplicateWasteBytes)) waste")
                                            .font(.callout)
                                    }
                                    .padding(DesignTokens.Space.s)
                                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.s))
                                } else {
                                    Text("Duplicate detection inside the Photos library isn't available — DiskBuddy won't guess. Use the Duplicates tab for byte-identical files found by scanning, or manage duplicates in the Photos app.")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: 520, alignment: .leading)
                                }
                                Text("Recently Deleted can only be emptied inside the Photos app — DiskDoom never deletes it silently.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                    }
                }
            }
            }
        }
        .onAppear { analyzer.checkAccess() }
        .onDisappear { analyzer.cancel() }
    }
}

private struct PhotoStatCard: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.weight(.bold)).foregroundStyle(color).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignTokens.Space.m)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.m))
    }
}

private struct LibrarySizeRow: View {
    let label: String
    let bytes: Int64
    let total: Int64
    let color: Color

    var body: some View {
        HStack(spacing: DesignTokens.Space.m) {
            Text(label).font(.callout).frame(width: 220, alignment: .leading)
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.2))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color.opacity(0.6))
                            .frame(width: geo.size.width * CGFloat(bytes) / CGFloat(max(total, 1)))
                    }
            }
            .frame(height: 14)
            Text(ByteFormatting.format(bytes)).font(.caption.monospacedDigit()).frame(width: 80, alignment: .trailing)
        }
    }
}

#Preview {
    PhotoLibraryView()
        .environmentObject(PhotoLibraryAnalyzer())
        .environmentObject(AppState())
        .frame(width: 800, height: 600)
}
