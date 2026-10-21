# Validation record

## Completed checks

- Baseline Debug build succeeded before implementation.
- Intermediate universal Debug builds succeeded during the redesign.
- Unit run: **167 Swift Testing tests passed**, plus the existing XCTest suites, using the normal `DiskBuddy` scheme. This run included new geometry, route-completeness and local-activity tests.
- Subsequent build/unit run: **168 Swift Testing tests passed**, plus the existing XCTest suites (`design-unit-final.xcresult` in the approved temporary directory). This includes the protected-content-inset test and the macOS 13 table fallback.
- Refined-palette/adaptive-preview build: **168 Swift Testing tests passed**, plus existing XCTest suites (`design-unit-refined.xcresult`).
- Refined palette calculations on the opaque panel color: primary text **14.04:1**, muted text **7.34:1**, orange **6.75:1**, cyan **7.17:1**. These are specific color-pair checks, not whole-app accessibility certification.
- `git diff --check` passed during implementation.
- Source review checked geometry flat-side behavior, notification consent and foreground routing, query/navigation behavior, compact inspector state and Settings opening.
- First-pass native Appearance Settings screenshot captured and visually inspected: `screenshots/appearance-settings.png`. It shows real SwiftUI controls, three-sided frame thickness and planar docking edges; it is not an HTML rendering. It predates the later softened-palette/spacing refinement.
- Softer-palette native Settings screenshot: `screenshots/appearance-settings-refined.png`. Native main-window video was also inspected locally; it contained actual private filenames, so no copy was added to the repository.
- First enabled UI run built and ran both tests but failed main-window/search startup assertions. The Settings screen still opened and produced the screenshot above. A native New Window command and explicit test opening were added for the subsequent run. This was **not** an Accessibility-permission failure.
- The next UI attempt exposed test-harness issues: multiple restored main windows made the unscoped search locator ambiguous, and the toggle query used the wrong accessibility lookup. Tests now scope controls to a main window and use stable identifiers; the next result must still be checked rather than assuming success.

## Commands

```sh
xcodebuild -project DiskBuddy.xcodeproj -scheme DiskBuddy -configuration Debug -destination 'platform=macOS' build
xcodebuild -project DiskBuddy.xcodeproj -scheme DiskBuddy -configuration Debug -destination 'platform=macOS' test -only-testing:DiskBuddyTests
xcodebuild -project DiskBuddy.xcodeproj -scheme DiskBuddy-DesignValidation -configuration Debug -destination 'platform=macOS' test -only-testing:DiskBuddyUITests/IndustrialDesignUITests
```

The normal scheme intentionally skips the UI runner. `DiskBuddy-DesignValidation` enables it separately; macOS may require Accessibility approval for the test runner. Tests attach native screenshots to their `.xcresult` on success.

## Outstanding ship gates

- Run the final source revision through build and unit tests after the last adjustments.
- Record UI test outcome, including any OS Accessibility blocker rather than treating a skipped run as a pass.
- Compare full-size and 820-point-wide screenshots against the supplied design geometry.
- Exercise keyboard-only scan → navigate → select → preview → stage → cancel/review.
- Manually verify VoiceOver, Increase Contrast, Reduce Motion, long Unicode filenames, localized labels and the inspector-sheet focus return.
- Test partial scan, no-permission, stale data, empty/filter-empty, error/retry, and partial removal on controlled fixtures.
- Benchmark large tables/trees and idle CPU on representative Intel and Apple Silicon hardware. No measured speedup is claimed.
- Verify notification opens while already running and while terminated; verify denied OS authorization and foreground/background low-space handling.
- The tracked `DiskDoom.app` remains the pre-redesign checkpoint until an explicit distribution build replaces it. Use the Xcode build product to run the redesign.

These gates are intentionally explicit: source migration is not the same as complete runtime/visual validation.
