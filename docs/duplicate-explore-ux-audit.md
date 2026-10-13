# Duplicate Finder + 12 Explore views — UX delivery

## P0 Intake · G1 PASS

INPUT DETECTION
- Input type: mixed (feature request, process specification, codebase).
- Platform / category / complexity: macOS desktop / disk utility / Complex.
- Top tasks: **T1** find verified duplicates; **T2** choose the copy to retain and review cleanup safely; **T3** understand where storage goes in 12 Explore views.
- Entry modes: first run, returning cached scan, sidebar/keyboard, rescan, selected chart node. No external URL deep-link is implemented; “deep-link” below means a direct in-app sidebar or menu shortcut, not a claimed URL route.
- Coverage: visual partial (source, not screenshots), logic partial (local interactions reviewed), data partial (live filesystem not available), interactions partial (no observed usability sessions). Mode: fused. Confidence tags: [CONFIRMED] code behavior; [HIGH CONFIDENCE] static UX assessment; [ASSUMPTION] untested user behavior.

## P1 Inventory · G2 PASS

Screen IDs, including visible alternate states: **S01** window (ready/scanning/failed/scan available); **S02** duplicates (scan-first, hashing, no results, results); **S03** cleanup queue (empty, staged, partial failure); **S04** cleanup confirmation (pending/working/failure); **S05** inspector (nothing selected, real file/folder, aggregate/partial); **S06** Explore overview/switcher (scan-first, scan available); **S07** Treemap; **S08** Sunburst; **S09** Flame; **S10** Bubbles; **S11** MindMap; **S12** Sizes (unfiltered, search, no matches); **S13** Age (empty, age selected); **S14** Grid; **S15** Radial; **S16** Icicle; **S17** Treelist; **S18** ExtCloud (empty, extension selected). S07–S18 share ready/empty and selection/focus states where applicable; a new scan invalidates old focus. S02, S03, S04, S06 are Tier A; S01 is shared Tier A shell; S05 and S07–S18 are Tier B. No Tier C screens are changed.

Component inventory (tier, ID): Tier 1 **C01** main sidebar, **C02** scan status, **C03** cleanup queue CTA, **C04** duplicate summary/filters, **C05** duplicate group/keep row, **C06** Explore view switcher, **C07** visualization title/usage hint, **C08** empty/loading/error, **C09** back/breadcrumb, **C10** inspector close/actions. Tier 2 **C11** chart mark + keyboard alternative, **C12** file/context actions, **C13** hash/progress display, **C14** category legend, **C15** age/extension buckets. Tier 3 **C16** treemap geometry, **C17** radial hit-testing, **C18** record-index grouping, **C19** scan-tree drill path, **C20** cleanup safety guards. Tier-3 cases prioritized for S02, S05, S07, S12, S13, S15, S18 (other visualizers retain existing renderer for now).

Entities: `ScannedRecord` → `DuplicateFinder` → `DuplicateSet`/`DuplicateFile` → selected keep (`AppState.duplicateKeeps`) → `CleanupItem` → confirmation → `TrashService`; `ScanNode` (real/collapsed/synthetic/partial) → 12 modes → selection/inspector. Counts are estimates until confirmed by filesystem/cleanup. A synthetic aggregate is never a real cleanup target.

## P2 Structure · G3 PASS

IA: S01 sidebar → S02 duplicates → S03 queue → S04 confirmation; S01 → S06 Explore → S07–S18 visualization → S05 inspector; S06 → S02 via sidebar. Native back from drilled chart returns to parent; close from S03/S04/S05 returns to presenting screen. Toolbar search is scoped to its actual consumers (Sizes / Applications).

| Screen(s) | Parent | Entry points (normal; direct in-app) | Exit(s) | States beyond common ready/empty |
|---|---|---|---|---|
| S01 | OS window | launch; `openWindow(id: "main")` | close window; menu-bar re-entry | ready, scanning, failed, done |
| S02 | S01 sidebar | sidebar Duplicates; ⌘2 | sidebar Explore; cleanup queue | no scan, hashing, no matches, results, filter-no-matches |
| S03 | S02/S01 | duplicate CTA; toolbar ⇧⌘K | X/Escape; S04 | empty, pending, staged, partial failure |
| S04 | S03 | queue confirm; return to active sheet after app switch | X/Escape; success back to queue | disabled, active, partial failure |
| S05 | S06 | select any chart node; toolbar ⇧⌘I after selection | X/toolbar toggle; sidebar | no selection, real, synthetic/partial |
| S06 | S01 sidebar | sidebar Explore; ⌘1 | sidebar Duplicates; mode switch | scan-first, ready, filtered |
| S07–S18 | S06 | click mode; View menu ⌥⌘1–8 (9–12: menu item) | mode switch; sidebar; S05; chart Back when drilled | selected, focused, hovered where applicable; S12 search, S13 bucket, S18 kind |

Deep-link contract: app has **no** external URL deep links [CONFIRMED]. Direct sidebar/menu navigation works after cached scans; tests must verify orientation when entering mid-task. No URL routing is implied by this table.

Interaction matrix: select folder → inspector (all modes with node marks); double-click folder → drill (where supported); choose keep → exactly one retained per duplicate group; stage → queue only, never delete; confirm → Trash, subject to protections; back/close → prior content. Canvas charts have visible keyboard-reachable alternatives (Sunburst level menu; Radial folder buttons); the shared Top folders menu is a shortcut for the 12 largest top-level folders, not an exhaustive chart replacement. Empty/error states must offer a next action.

## P3 Krug audit · G4 PASS (static; no user-test verdicts)

Tier-A **K1/K3/K9 scan simulation** (first 3 seconds; parsed purpose; trap; model; verdict):

| Screen | Eye lands on | Parsed purpose | First plausible wrong click / risk | Verdict |
|---|---|---|---|---|
| S01 | scan CTA → sidebar → status | start/inspect scan | chart tabs unavailable before scan [CONFIRMED] | self-explanatory |
| S02 | count → size picker → groups | find and clean duplicates | “Only show reclaimable” did not filter [CONFIRMED]; “Select All” implied manual selection required [HIGH CONFIDENCE] | needs thought |
| S03 | queue count → rows → Trash CTA | review staged files | scan byte estimate can differ from actual filesystem [CONFIRMED] | self-explanatory |
| S04 | irreversible wording → confirm | move reviewed files | confusing move-to-Trash vs. permanently delete [ASSUMPTION] | self-explanatory |
| S06 | storage strip → 12 chips → chart | compare storage views | horizontal off-screen choices not obvious [HIGH CONFIDENCE] | needs thought |

K2 question-mark ledger (per top-task flow):

| # | Step | Question | Cause | Cost | Sev | Fix |
|---|---|---|---|---:|---:|---|
| 1 | S02 | Which copy is kept? | row default disagreed with bulk fallback | 5+ s | 4 | single shared keep policy |
| 2 | S02 | Did “reclaimable only” change anything? | inert toggle | 2 s | 3 | functional filter / rename |
| 3 | S02→S03 | Does Stage delete now? | weak staging language | 2 s | 3 | explicit “review in queue” |
| 4 | S06 | Where are the other modes? | clipped horizontal strip | 2 s | 2 | menu + active mode name |
| 5 | S06→S12 | Why does Search work only here? | unscoped toolbar field | 5+ s | 3 | scope field to consuming tabs |
| 6 | S15→S05 | Can this aggregate be deleted? | inspector unguarded | 5+ s | 4 | hide unsafe actions |

Baseline 6 question marks / 8 steps ≈ **0.75 per step** (target ≤0.5); [HIGH CONFIDENCE], to validate in tests.

K4 convention: native sidebar/menu/confirmation and Finder reveal **keep**; an inert filter and gesture-only chart selection are **unjustified deviations** (Sev 3). One-click Sunburst drill versus double-click elsewhere is a **clarity inconsistency** (Sev 2); standardize in a later phase after observed testing.

K5 hierarchy: S02 intended “verified groups → keep decision → stage review”; perceived “hash → totals → select all” (mismatch); S06 intended “current view → chart → alternative modes”; perceived “overview → crowded strip” (mismatch). Areas discernible: sidebar, results, inspector. Noise (shouting/disorganization/clutter, each 0–3): S02 **1/1/2**; S06 **1/1/2**. Clickability: gesture-only chart marks and inert toggle (Sev 3). Remove inert controls; double active mode/purpose prominence, not decoration.

K6 word budget: S02 scan-first technical explanation ≈17 words → “Scan to find byte-identical files.” (6, −65%); S06 strip instruction is terse but hidden modes need an explicit menu, not more instructions. S03 safety copy stays because it is consequential. Avoid making “reclaimable” sound guaranteed: it is an estimate.

K7 choice scent: S02 “Keep” names outcome; “Stage” must predict the queue, not deletion. Show the suggested default before a user decides. S06 names of 12 modes are weak scent without short descriptions [ASSUMPTION→test T3].

K8 trunk tests (ID/name/sections/local nav/here/search): S01 **6/6** when search relevant; S02 **5/6** before clear local filter scope; S03/S04 **5/6** (minimal modal nav exception); S06 **4/6** before active name/search scope. Name contract: “Duplicates” → S02 Duplicates; “Explore” → S06 Explore; “Cleanup Queue” → S03 Queue (acceptable equivalent). Navigation levels covered: sidebar → view → chart drill/inspector → queue confirm. Back and inspector exit are explicit. Search must not pretend to apply to every mode.

Tier-B K2/K5/K6/K8.3 by visualization:

| Screen | Question / hierarchy / copy / page-name verdict |
|---|---|
| S05 | synthetic aggregate appears actionable (Sev 4); hide destructive controls, explain estimates; title Inspector matches toolbar |
| S07 Treemap | hover-only tiny cells; visible folder alternative needed (Sev 2); name matches chip |
| S08 Sunburst | inner click drills, outer selects (Sev 2); explain rings/keyboard alternative; name matches |
| S09 Flame | Back jumps to root (Sev 2); breadcrumb depth later; name matches |
| S10 Bubbles | double-click drill not discoverable (Sev 2); menu/row alternative; name matches |
| S11 MindMap | nested double-click affordance uncertain (Sev 2); test with mouse/keyboard; name matches |
| S12 Sizes | search works, header says Top Sizes vs chip Sizes (acceptable); filtered empty state needed (Sev 2) |
| S13 Age | “Never modified” treated as old (Sev 3); avoid cleanup nudge; name matches |
| S14 Grid | root Back fallback redundant (Sev 1 kayak); label matches |
| S15 Radial | chart-only interaction and unrelated second-ring ordering (Sev 3); list alternative; name matches |
| S16 Icicle | double-click on buttons uncertain (Sev 2); menu alternative; name matches |
| S17 Treelist | collapsed node expand affordance hidden (Sev 2); visible action; name matches |
| S18 ExtCloud | top-30 file list with no explicit limit (Sev 2); state cap; name matches |

K10 goodwill ledger, T1→T2 path: 100 → inert filter −10 = 90 → misleading keep indicator −20 = 70 → safety review/Trash confirmation +10 = **80**; honest scan limitations/disabled unsafe actions +5 = 85 after fixes. No measured user goodwill claimed.

K11 form/error recovery: no text-entry form in S02; size picker and search preserve input; deletion is queued and independently confirmed. File disappeared/changed since scan requires an honest “re-scan before staging” or refusal, not silent success [ASSUMPTION→test T2]. K12 mobile/touch: **not applicable** (desktop-only); reallocate its 5 points to top-task clarity. K13 accessibility: keyboardable sidebar and native buttons pass; gesture-only Canvas marks and click-only duplicate rows fail (Sev 3); use explicit buttons/list alternatives, meaningful labels, Reduce Motion. K14 ethics: no dark patterns observed; never imply “automatically safe to delete.” K15 testing in P6; K16 scorecard in P4.

## P4 Synthesis · G5 PASS

Anti-patterns [CONFIRMED]: (1) duplicate KEEP displayed differently from what Stage All retains (Sev **4**); (2) synthetic aggregate receives unsafe inspector actions (Sev **4**); (3) inert duplicate filter (Sev **3**); (4) global search implies unsupported modes (Sev **3**); (5) chart-only selection strands keyboard users (Sev **3**). [HIGH CONFIDENCE] hidden Explore choices hurt discovery (Sev **2**).

Desktop scorecard, static estimate only: weights/ratings = top-task 25×3/5=15; questions 15×3/5=9; navigation 15×3/5=9; hierarchy 10×3/5=6; word economy 5×4/5=4; convention 5×3/5=3; goodwill 10×3/5=6; error recovery 5×3/5=3; a11y 8×2/5=3.2; ethics 2×5/5=2. **Total 60.2/100.** Mobile's unused weight 5 is allocated to top-task clarity (20→25). This is a heuristic, not a user-test result.

Ranked backlog: **1** keep/stage contract Sev4; **2** synthetic/partial inspector safety Sev4; **3** duplicate filter/search/clear result states Sev3; **4** keyboard alternative for Canvas charts Sev3; **5** age advice/coverage honesty Sev3; **6** toolbar search scope Sev3; **7** switcher discoverability Sev2; **8** scan-root drill reset Sev2; **9** remaining visualization-specific gestures/drill depth Sev2; **10** minor breadcrumb polish Sev1 (log, do not prioritize).

## P5 Build plan · G6 PASS

Dependency graph (acyclic): **B1** shared keep policy & safe inspector guards → **B2** duplicate result UI/filter and queue labels → **B3** Explore mode orientation/search scope + scan-root reset → **B4** honest record/age state and accessible Radial alternative → **B5** dedicated tests + usability validation → **B6** follow-up rendering/gesture refinements driven by tests. P0 items B1 dependencies: existing `DuplicateSet`/`ScanNode`/`AppState.stage`; B2 depends on B1; B3 depends on `AppState.ExploreView`; B4 depends on B3 and `state.ageBuckets`. Preserve existing renderers and native macOS controls. No dependency on cleanup execution changes. The implementation in this change targets B1–B4; B5 is scripted below, not claimed as a completed user test.

## P6 Test plan · G7 PASS

### Follow-up visualization UX implementation (static; not a user-test result)

- Flame and Icicle now expose depth-aware Back/breadcrumb navigation rather than resetting to the scan root. Flame has an explicit Open button on browsable rows; Icicle has a keyboard-accessible Open folder menu and context action.
- Bubbles separates Select from Open with native, keyboard-accessible buttons. Flame, Bubbles, and Treelist expose an Index action on collapsed folders instead of relying on double-click or a context menu. Focused charts resolve their current folder from the live scan tree after indexing.
- Remaining visualization gesture work (notably MindMap and other Canvas marks) is still backlog item 9. Validate discoverability and keyboard flow in T3 before treating it as resolved.

3 participants: novice Mac user, frequent storage-cleanup user, accessibility/keyboard-focused user (recruit loosely). One morning monthly, ≈60 minutes each: 4m intro/consent, 2m background, 3m first-screen tour, 35m tasks, 5m probing, 5m wrap. Use safe fixture files in a test folder; never clean participant data. Observe silently, ask “What are you thinking?” only.

- **T1 find duplicates:** “These two folders contain repeated photos. Find the identical copies and tell me how much space you might recover.” Success: reaches Duplicates and interprets hash-verified set + estimate; cap 10m.
- **T2 keep/review:** “Keep the copy in Documents and prepare the other copy for cleanup, but stop before moving anything.” Success: chosen KEEP matches the one retained in the queue; can cancel/undo queue; cap 12m. Probe [ASSUMPTION] response to a missing/changed file and meaning of Move to Trash.
- **T3 map storage:** “Find the biggest folder, then use a different view to inspect a second-level folder without the mouse.” Success: discovers modes, selects a folder/inspector with keyboard and returns; cap 13m. Probe [ASSUMPTION] comprehension of 12 mode names and whether descriptions help.

Observer sheet: participant __ / build __ / T1 outcome __ / T2 outcome __ / T3 outcome __ / first wrong click per task __ / questions spoken __ / stuck >5s __ / accessibility blocker __ / top-3 observed problems __. Debrief after all three: tally repeated issues before discussing fixes; rank top ≈10 by severity, assign owners, limit next cycle to capacity; ignore Sev1 kayak detours. Capture a fresh scorecard only after observing users.

## Self-audit (provided process + delivery checklist)

- [x] G1 input, category, platform, complexity, top 3 tasks explicitly listed.
- [x] G2 IDs for every visible surface/state and tiered components.
- [x] G3 parent, two direct entry points, exits, state matrix; unsupported external URLs not invented.
- [x] G4 K1–K9 on Tier-A; Tier-B scoped checks; K10–K16 once, desktop K12 N/A.
- [x] G5 ≥3 anti-patterns, shown score arithmetic, severity-ranked backlog.
- [x] G6 acyclic build order with dependencies for P0 items.
- [x] G7 3 tasks mapped to top tasks, assumption probes and debrief sheet.
- [ ] Run real 3-user study (test script only; not falsely marked complete).
