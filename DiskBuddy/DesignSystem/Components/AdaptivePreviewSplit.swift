import SwiftUI

/// Keep the records readable instead of squeezing two fixed-width panes into
/// a compact workspace. Selection belongs to the caller and survives resizing.
struct AdaptivePreviewSplit<Content: View, Preview: View>: View {
    let showsPreview: Bool
    let content: Content
    let preview: Preview
    @State private var previewExpanded = false

    init(showsPreview: Bool, @ViewBuilder content: () -> Content, @ViewBuilder preview: () -> Preview) {
        self.showsPreview = showsPreview
        self.content = content()
        self.preview = preview()
    }

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 800 {
                HSplitView {
                    content.frame(minWidth: 420)
                    if showsPreview {
                        preview.frame(minWidth: 280, idealWidth: 320, maxWidth: 420)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    content.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if showsPreview {
                        Divider()
                        DisclosureGroup("File preview", isExpanded: $previewExpanded) {
                            preview.frame(height: min(220, geometry.size.height * 0.45))
                        }
                        .padding(12)
                        .background(DesignTokens.Palette.panel)
                    }
                }
            }
        }
    }
}
