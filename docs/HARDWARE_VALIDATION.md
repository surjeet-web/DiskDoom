# Hardware validation

## Local target

The current validation machine runs macOS 14.8.7 on an 8-core Intel Core i9
MacBook Pro with 32 GB RAM and a PCIe APFS SSD. Local results do not establish behavior on
Apple Silicon, rotational disks, network volumes, or removable media.

## Resource safeguards

- Filesystem scans stream directory entries, drain per-entry autorelease
  pools, and retain a bounded heap of the largest visible children while
  continuing to account for omitted entries in a non-actionable aggregate.
  Exclusion matching accounts for macOS path aliases such as `/var` and
  `/private/var` without resolving every individual file path.
- Scan database writes are atomic and cancellation-aware: failed or cancelled
  inserts cannot leave a partially committed scan after a chunk boundary.
- Hardware monitoring uses wrapping per-core counters with 64-bit aggregate
  deltas, actual elapsed process sample times, one process-info query per app,
  icon-cache eviction, and timer tolerance. Process CPU can exceed 100% when
  more than one core is occupied.
- QuickLook keeps existing input byte budgets and caps decoded thumbnails
  and video posters at 1,200 pixels. Codec-internal memory is not guaranteed
  by an output pixel cap.
- QuickLook cancels media loading when its view task is cancelled and rejects
  stale task results after the preview URL changes.
- Menu-bar folder walks run at utility priority only when the panel appears,
  behind a TTL, entry limit, and time budget. Incomplete walks display a
  lower bound or “Not measured”, not a definite empty folder.
- Menu-bar top-file selection retains five candidates rather than allocating
  and sorting every matching file in a scan.
- Explorer inspector sizes remain unknown for access-denied folders, and
  Live Feed activity counts decay using a 60-second rolling window even when
  no further file events arrive.
- Cleanup notifications distinguish bytes moved to Trash from disk space
  actually reclaimed. Moving a file to Trash does not free its storage.
- What-If execution is scoped to its accepted selections; unrelated staged
  queue entries are retained. Protected-path checks are shared between staging
  and the final Trash backstop, including traversal and system-alias handling.
  Directory sizing runs off-main; selected measurements are awaited before
  execution, and removed/replaced queue identities cannot be silently executed.
- Feature subprocess waits have deadlines and captured-output read limits.
  Cancelled feature scans and duplicate searches cannot publish results into
  a newer run.

These are code-level safeguards, not measured speedup or peak-memory claims.

## Verified on October 12, 2026

- Debug test action succeeded: 83 Swift Testing tests and five XCTest cases
  passed. One additional end-to-end cleanup XCTest was skipped because the
  local trial/license does not authorize cleanup; the test does not bypass
  that restriction. Measurement/identity regressions ran without deletion.
- Release build succeeded. Final Debug/Release logs contain no compiler warnings.
- `git diff --check` passed.
- UI smoke tests remain skipped pending Accessibility authorization.

Filesystem time budgets and cancellation are cooperative: a single stalled
filesystem call cannot be forcibly interrupted. Finder integration, signed
App Group sharing, and comparative Instruments benchmarks remain unverified.

## Reproducible checks

```sh
xcodebuild -scheme DiskBuddy -configuration Debug -destination 'platform=macOS' test
xcodebuild -scheme DiskBuddy -configuration Release -destination 'platform=macOS' build
```

Before release, exercise a large scan, cancel and immediately restart it,
switch features repeatedly, preview malformed and very large media, and
observe CPU/memory in Instruments or Activity Monitor. Test access-denied
folders both with and without Full Disk Access. Keep destructive tests inside
disposable fixtures, never personal files.

## External prerequisites

- App Group sharing for the widget and QuickLook requires valid signing and
  the matching provisioning/entitlements. Ad-hoc builds cannot validate this.
- UI smoke tests are skipped in the shared scheme until the UI test runner
  receives Accessibility permission. Enable the test target after granting
  permission; passing unit tests does not cover those UI scenarios.

Neither prerequisite should be bypassed by weakening permissions or sharing
private user data through an unprotected substitute path.
