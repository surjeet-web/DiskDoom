# DiskDoom industrial UI implementation

## Evidence and scope

- **Confirmed:** native SwiftUI/AppKit host, macOS 13 deployment, 27 destinations, 12 explorer representations, existing local scanner and feature engines.
- **Confirmed:** checkpoint `f17eabc` was pushed to `origin/main` before redesign work.
- **Confirmed:** supplied design files are preserved in `references/`. Their example capacity, folder sizes, percentages, and history are not production data.
- **Confirmed:** licensing remains an existing network integration. File analysis stays local; this redesign does not claim the entire app is network-free.
- **Unknown until tested:** full VoiceOver workflow, visual parity at every window size, older Intel GPU performance, all destructive-operation edge cases.

This is a native implementation, not an embedded HTML page or screenshot. The universal specification includes web/mobile patterns and component recipes that are not all applicable to this macOS product. No fictional chat/AI service, geographic chart, email channel, or cloud scanner has been added.

## Geometry and controls

`DiskBuddy/DesignSystem/IndustrialGeometry.swift` provides the shared 0°/45°/90° plate, canopy, tiered, well and boot families. A declared docking edge has zero extrusion and no cut at its adjoining corners. Three other edges have separately rendered structural faces with upper-left lighting. Side faces are contained in the Canvas bounds, not painted outside a potentially clipped layer.

Content remains native and planar, above decoration. `MetalSurface` never captures input or exposes decorative accessibility elements. `industrialPanel` reserves a 24-point safe content inset. Smaller navigation/button plates have bounded cuts and 36-point hit areas. Native text fields, tables, sheets, alerts, menus and focus behavior remain in use. Table rows, chart marks and thumbnails are not turned into isometric slabs.

`Tokens.swift` owns graphite, steel, orange, cyan, violet, teal and red colors. The refinement pass uses blue-graphite surfaces, warm apricot primary accents, dusty cyan/teal/violet category colors, quieter steel edges and a four-point default structural depth. `IndustrialBackdrop` adds one low-intensity static orange emitter and a subdued cyan echo. Edge particles are deterministic and have no continuously running animation timer. Increased Contrast strengthens structural rims; Reduce Motion is respected by navigation and treemap transitions.

### Layout

- Default window: 1440 × 900; supported minimum: 820 × 640 points.
- Expanded navigation: 200–280 points, draggable, persistent; double-click resets. Accessibility adjustment provides an alternate resizing path.
- Below 1100 points: icon rail with accessible full names and tooltips.
- Below 1400 points: inspector opens in a native sheet instead of reducing the workspace to an unreadable sliver. Main structural gutters are 16 points.
- The shared inspector belongs to Explore and Applications. Other destinations retain their own contextual detail/preview workflows instead of displaying an unrelated previously selected scan node beside every page.
- Explorer uses three-spine composition; folder records use a ledger; duplicate/media review retains split preview chambers; monitoring uses a dominant CPU chart and subordinate diagnostics; settings use a category rail and terraced field surfaces.

## Route/feature inventory

Every route remains wired to its existing engine and actions. “Shared” means the new global chassis wraps a deliberately planar existing list/table, not that the route was replaced with mock content.

| Group | Route | Composition and migration |
|---|---|---|
| Navigate | Explore | Three-spine; measured squarified treemap; 12 retained views; keyboard-accessible alternate list |
| Navigate | Duplicates | Split review chamber, new surfaces, existing verification/keeper/removal logic |
| Navigate | Applications | Shared ledger chassis, existing inventory and uninstall review |
| Navigate | Monitor | Control tower; dominant measured CPU history, memory diagnostics, native process table |
| Navigate | Snapshots | Shared ledger chassis; real saved snapshots, comparison/export retained |
| Insights | Smart Clean | Metal review surfaces, existing recommendation evidence and staged cleanup |
| Insights | Litter Score | Instrument housing; existing measured score/unknown states |
| Insights | Forecast | Metal chart/evidence surfaces; existing forecast assumptions/history |
| Insights | What If? | Tiered simulation summary; sandboxed actions retained |
| Insights | Dev Caches | Shared ledger chassis; flat existing tool/project rows |
| Insights | Health | Metal evidence panels; unsupported physical checks remain unknown |
| Insights | Budgets | Metal budget panels; thresholds and native editor retained |
| Insights | Live Feed | Shared live-workspace chassis; existing event controls retained |
| Insights | Lifecycle | Shared timeline/ledger chassis; existing metadata retained |
| Insights | Provenance | Metal evidence surfaces; existing confidence and source semantics |
| Insights | Compression | Metal summary panel; existing capability/safety checks |
| Insights | Containers | Shared ledger chassis; existing runtime/storage operations |
| Insights | Privacy | Shared findings ledger chassis; existing scanner and evidence |
| Insights | Photos | Adaptive metric deck, metal panels, actual local media |
| Insights | Storage Map | Metal capacity/accounting surfaces; existing logical/physical distinctions |
| More Tools | Similar Files | Split media review, metal panels; similarity stays distinct from exact duplicates |
| More Tools | Duplicate Monitor | Metal monitoring panels; existing watcher and verified results |
| More Tools | Folders | Native sortable multi-select table, resizable columns, persistent optional columns, staged bulk review, breadcrumbs/history/filter, real measurement freshness |
| More Tools | Progress | Metal progression/quest/achievement surfaces; existing XP engine |
| Professional | Dev Projects | Shared ledger chassis; existing scanner and actions |
| Professional | 3D & Creative | Shared ledger chassis; existing cache tools |
| Professional | Video Caches | Shared ledger chassis; existing cache tools |

Explorer retains Treemap, Sunburst, Flame, Bubbles, MindMap, Sizes, Age, Grid, Radial, Icicle, Treelist and ExtCloud. None is renamed or removed to match the eight-view reference sample.

## Interaction/state contracts

- Navigation is a real button with an accessible name and selected trait; the active route scrolls into view. The main 20 routes follow the supplied order; all seven additional routes remain in explicit groups.
- Global Search uses the existing indexed search service. ⌘F/⌘K focus it. Navigation leaves the result surface without erasing the query. Clearing and selecting results remain explicit actions.
- Scan/Cancel, snapshot, inspector, cleanup queue and Settings retain native handlers and shortcuts. Unsupported snapshot capture is disabled until a scan exists.
- New Window (⌘N) reopens the primary workspace after its last window was closed, including when Settings or the menu-bar utility remains available.
- Scan progress is indeterminate: the scanner does not know a trustworthy final denominator. Actual file count, rate, elapsed time and paths remain visible; the previous synthetic denominator is no longer displayed as a percentage.
- Partial-scan notices persist, link to a real coverage sheet, and expose unreadable paths plus the native permission route.
- Overview says “Staged for review,” not “Cleanable” based on gross category size. Moving to Trash does not claim immediately reclaimed physical space.
- Overview metrics switch from one horizontal strip to two protected rows when necessary. Duplicate quick-action buttons were removed from that strip; Smart Clean and Queue remain available through their persistent navigation/actions. Settings has a bounded resizable layout instead of a fixed-size canvas.
- Duplicate/similar review uses `AdaptivePreviewSplit`: a resizable side preview on wide workspaces and a collapsible lower preview on compact ones. It no longer forces two incompatible fixed-width panes into a narrow window. Inspector mode controls use compact native segments rather than a horizontally clipped row of oversized plates.
- Treemap cells now use their actual layout origins. Their areas remain determined by measured bytes; decorative preferred sizes are never substituted. Named accessibility actions and a native alternate list support non-pointer navigation.
- Folder records support native selection, Shift/Cmd multiselect, header sorting, column resizing, optional column visibility, contextual Open/Reveal/Inspect/Copy/Stage, and a selection review bar. Removal still runs only through existing review/confirmation flows.
- Header sorting is delegated back to the measurement engine before its display limit is applied, and toolbar sorting clears the header comparator. Optional column visibility requires macOS 14.4; macOS 13 retains all columns with the same native sorting/selection controls and an explicit availability explanation.
- Inspector supports Contents, File Types, Largest and Oldest; unknown dates are explicitly omitted from Oldest. Finder reveal, copy path, preview, app artifacts and staged cleanup remain available.

## Notifications and jobs

`Navigation/ActivityCenter.swift` is local-only, retains the latest 200 summaries, deduplicates identical events within five seconds, and tracks read state separately from OS delivery. Reading an event is explicit; there is no remote push/email delivery.

The Activity & Jobs sheet exposes the running disk scan and native cancel/view actions. Other feature jobs remain in their existing destinations; this is not a new persistent scheduler or resumable queue.

OS notifications still use `UserNotifications`, check authorization and respect existing category preferences. Foreground events use in-app feedback/history instead of a duplicate OS banner. Low-space alerts also enter local history and an actionable banner; weekly reminders are recorded when delivered in the foreground. Notification opens select the appropriate native destination. These routing paths require runtime consent/deep-link verification.

## Preferences

Settings retains General, Scanning, Menu Bar and About, adds Appearance, and preserves existing settings controls. Appearance offers sculpted-frame and static-effect flags plus comfortable/standard/dense native-list rows. The product remains graphite/dark; the frame flag is not an unimplemented light theme. Native system permission dialogs are not restyled.

The menu-bar utility and separate About window also receive the shared native metal housing. Existing menu-bar measurements and actions remain unchanged; confirmation sheets keep OS-owned modal behavior.

## Validation

Build/unit-test evidence and remaining visual gates are recorded in `VALIDATION.md`.

No “100% verified,” performance improvement, complete accessibility certification, or pixel-identical claim is made without the corresponding test evidence. In particular, the universal master specification's optional component encyclopedia is not a claim that 260 distinct product components were created.
