import SwiftUI
import Combine

// MARK: - Universal navigation chrome (exactly three components)
//
// PageHeader  → SUB_PAGE / NESTED_SUB_PAGE (back + breadcrumb + fallback)
// ModalHeader → MODAL (top-right X + Esc-gated-to-topmost via OverlayStack)
// WizardHeader → WIZARD_STEP (step back + dots + flow close)
// SHEET (inspector pane) uses the existing toolbar collapse toggle.
// No fourth header component: anything else is a prop on these three.

// MARK: - Overlay stack (Esc closes the topmost overlay ONLY)

final class OverlayStack: ObservableObject, @unchecked Sendable {
    // Main-confined in practice (present/dismiss from UI thread), hence Sendable.
    @Published private(set) var stack: [String] = []

    func present(_ id: String) {
        stack.removeAll { $0 == id }
        stack.append(id)
    }

    func dismiss(_ id: String) {
        stack.removeAll { $0 == id }
    }

    func isTopmost(_ id: String) -> Bool {
        stack.last == id
    }
}

// MARK: - Breadcrumb segment (last = "here", non-interactive)

struct Crumb: Identifiable {
    let id = UUID()
    let label: String
    let action: (() -> Void)?

    static func link(_ label: String, _ action: @escaping () -> Void) -> Crumb {
        Crumb(label: label, action: action)
    }

    static func here(_ label: String) -> Crumb {
        Crumb(label: label, action: nil)
    }
}

// MARK: - PageHeader (SUB_PAGE / NESTED_SUB_PAGE)

struct PageHeader: View {
    let title: String
    let segments: [Crumb]
    let canGoBack: Bool
    let onBack: () -> Void
    let fallback: () -> Void

    private func goBack() {
        if canGoBack {
            onBack()
        } else {
            fallback() // deep link / restored session: jump to a sane parent
        }
    }

    /// Overflow rule (§5.4): >4 segments collapse middles, keep first + last two.
    private var visible: [(crumb: Crumb, isEllipsis: Bool)] {
        guard segments.count > 4 else {
            return segments.map { ($0, false) }
        }
        let first = segments.first!
        let lastTwo = Array(segments.suffix(2))
        return [(first, false), (Crumb(label: "…", action: nil), true)] + lastTwo.map { ($0, false) }
    }

    var body: some View {
        HStack(spacing: DesignTokens.Space.xs) {
            Button(action: goBack) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .help("Back (\(title))")
            .keyboardShortcut("[", modifiers: .command)
            .accessibilityLabel("Back to \(title)")
            ForEach(Array(visible.enumerated()), id: \.element.crumb.id) { index, item in
                if index > 0 {
                    Text("›").foregroundStyle(.tertiary)
                }
                if item.isEllipsis || item.crumb.action == nil {
                    Text(item.crumb.label)
                        .font(.caption)
                        .foregroundStyle(item.isEllipsis ? .tertiary : .primary)
                } else {
                    Button(item.crumb.label, action: item.crumb.action!)
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            Spacer()
        }
        .font(.caption)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

// MARK: - ModalHeader (MODAL: X + Esc iff topmost)

struct ModalHeader: View {
    let title: String
    let overlayID: String
    let onClose: () -> Void

    @EnvironmentObject var overlays: OverlayStack

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(minWidth: 28, minHeight: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close \(title) (Esc)")
            .accessibilityLabel("Close \(title)")
            // NOTE: no .keyboardShortcut(.cancelAction) here on purpose —
            // Esc is handled SOLELY by the gated onExitCommand below so
            // stacked overlays close topmost-only (§5.3).
        }
        .onExitCommand {
            if overlays.isTopmost(overlayID) {
                onClose()
            }
        }
    }
}

// MARK: - WizardHeader (WIZARD_STEP: step back + dots + flow close)

struct WizardHeader: View {
    let step: Int
    let totalSteps: Int
    let onBack: (() -> Void)? // nil on step 1 → back hidden (product decision)
    let onClose: () -> Void // abandons the entire flow (never just a step)

    var body: some View {
        HStack {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .help("Previous step")
                .keyboardShortcut("[", modifiers: .command)
                .accessibilityLabel("Back to previous step")
            } else {
                Color.clear.frame(width: 16, height: 16)
            }
            Spacer()
            Text("Step \(step) of \(totalSteps)")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    Circle()
                        .fill(i < step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(minWidth: 28, minHeight: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Exit setup")
            .accessibilityLabel("Exit setup")
        }
        .onExitCommand { onClose() } // wizard is never stacked: Esc exits flow
    }
}
