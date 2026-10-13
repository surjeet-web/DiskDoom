# DiskDoom Landing Page — Upgrade Instructions

## 1. Objective and source files

Convert the existing landing page for AlignUI into a complete DiskDoom product website. DiskDoom is a native Mac application for understanding storage, finding space-consuming files, reviewing cleanup opportunities, and monitoring disk usage.

Working folder: `/Users/surjeet/Desktop/DiskBuddy/landing page`

- **`landingpage.html`** is the full landing page. Use it as the foundation for the redesign, content, styling, and interactions.
- **`Disk manager hero animation.html`** is the supplied disk-scanning illustration. Incorporate this illustration into the hero of the full landing page.
- This document is an implementation brief only. It does not implement changes or require running commands.

Retain the existing HTML, CSS, and JavaScript approach. The result should feel designed specifically for DiskDoom, rather than like a UI-library template with its name replaced.

## 2. Brand and visual direction

- Use **DiskDoom** consistently in all public-facing content, including navigation, headings, footer, image descriptions, metadata, and download labels.
- Remove AlignUI branding, React/Tailwind/Figma marketing, component-library examples, package-installation instructions, unrelated social proof, and template-specific links.
- DiskBuddy appears in internal project and licensing names. Do not copy those names into marketing content or rename internal services as part of this website work.
- Preserve the strong parts of the current design: generous spacing, rounded cards, clear typography, orange accents, restrained gradients, and polished navigation.
- Keep the main page warm and light. Present the supplied dark illustration inside an intentional dark hero panel with a subtle transition into the surrounding page.
- Use dark surfaces again for selected product demonstrations or the closing call to action to create visual continuity.
- Use the actual DiskDoom icon and identity when suitable exported assets are supplied. Do not present the previous product's logo as DiskDoom's.
- Use clear, practical language. Emphasize visibility and user control rather than alarmist storage warnings.

## 3. Page structure and replacement map

Use this order:

1. Navigation
2. Hero with supplied illustration
3. Concise capability strip
4. Main product screenshot
5. Core feature cards
6. Interactive visualization showcase
7. Professional workflows
8. Extended feature overview
9. How it works
10. Cleanup control and permissions
11. Trial and pricing
12. Frequently asked questions
13. Final call to action
14. Footer

Adapt existing sections as follows:

| Existing content | DiskDoom replacement |
| --- | --- |
| AlignUI navigation and component search | DiskDoom navigation and download action |
| UI-library hero and floating component cards | Storage-focused hero and supplied disk illustration |
| Marquee and adoption metrics | Factual capability strip |
| Components feature grid | Core DiskDoom features |
| Code playground | Storage visualization showcase |
| Industry templates | Developer, video, and creative workflows |
| Figma synchronization section | Extended tools or cleanup-control section |
| Installation/build steps | Scan, explore, review workflow |
| Testimonials and team claims | Genuine product screenshots and useful feature detail; testimonials only when supplied |
| Start-building CTA | Download DiskDoom CTA |
| AlignUI footer | Product, support, and legal links |

## 4. Navigation

Show the DiskDoom logo and name, followed by:

- Features
- Visualizations
- For Professionals
- Pricing
- FAQ
- **Download for Mac** as the primary action

Each section link must reach the corresponding section. Keep the floating navigation readable against both light and dark backgrounds. Ensure anchored headings remain visible below it.

Replace the existing component-search field with a simpler navigation layout. Provide a usable mobile menu rather than only hiding desktop links.

## 5. Hero content

Use the following proposed copy:

**Eyebrow:** Disk space, made visible.

**Headline:** See what’s taking space. Take back control.

**Description:** DiskDoom helps you explore your Mac’s storage, find large files and duplicates, and review what to clear—all in one native app.

**Primary action:** Download for Mac

**Secondary action:** Explore the features

**Supporting line:** 14-day trial · Native macOS app · Review before cleanup

The current app source includes a 14-day trial. Confirm that this remains the shipping offer before publishing. Add minimum macOS and architecture information only after confirming the release requirements.

Keep the headline stable and readable. Avoid recycling the existing UI-library typing phrases.

### Supplied illustration integration

- Use the illustration from `Disk manager hero animation.html` as the hero's main visual.
- Preserve its hard-drive imagery, floating file-category layers, scan sweep, orange glow, and storage bars.
- Treat it as an illustration of disk analysis, not a screenshot of the actual DiskDoom interface.
- Keep important visual details visible. Avoid excessive cropping of category cards and lower storage bars.
- Place it beside the copy on large screens and below the copy on small screens.
- The source illustration is a standalone, full-viewport document. Adapt its layout to the hero container; its fixed positioning and hidden page overflow must not take over the landing page.
- Isolate illustration styling and behavior from the main page. Both files contain generic identifiers and animation names, including `stage`, `wrap`, `bar`, `num`, and `pulse`; resolve those conflicts during integration.
- Scale the artwork according to the available hero area rather than the entire browser window.
- Keep its example GB values illustrative. They must not look like a live scan of the visitor's Mac or a promise of recoverable space.
- Respect reduced-motion preferences for both CSS and JavaScript animation. Use a static, complete illustration in that mode.
- Pause animation when off-screen or when the browser tab is hidden. Avoid duplicate animation loops after visibility changes.
- Preserve an accessible description and provide a static fallback if animation cannot run.
- Review the embedded image assets for suitable file size and loading behavior while preserving their visual quality.

## 6. Capability strip and product screenshot

Replace unverified customer counts and adoption metrics with short capability labels:

**Visual storage maps · Duplicate detection · App cleanup · Professional cache tools · Storage monitoring**

Below the hero, show a genuine DiskDoom screenshot with this heading:

**Your storage, explained visually.**

Supporting copy: “Move from a disk overview to the folders and files behind it. Compare sizes, inspect details, and decide what deserves a closer look.”

Use an actual current app capture, preferably Explore with a populated treemap and inspector. Keep screenshot data anonymous. In drafts, explicitly mark any missing screenshot as an asset placeholder rather than inventing an interface.

## 7. Core feature cards

Give each card a concise benefit, a real app image or relevant visual, and a short explanation.

### See where your space goes

Explore storage through proportional maps, folder hierarchies, file-size views, and file-age views. Drill into the parts of a scan that matter.

### Find duplicate files

Review matching files together and choose which copies to keep. Describe file duplicate detection without implying automatic duplicate removal inside Apple Photos libraries.

### Review apps and associated files

Inspect installed applications and detected related artifacts before choosing what to remove. Avoid promising that every trace of every application is found.

### Turn findings into a cleanup plan

Review Smart Clean recommendations and selected items before cleanup. Keep the distinction between suggested cleanup and completed removal clear.

### Follow storage changes

Use snapshots, monitoring, and storage history to understand changes over time. Forecasts are estimates based on available history.

### Browse folders with context

Inspect folder sizes, navigate paths, and search indexed scan results. Do not imply that unreadable or excluded files are always searchable.

## 8. Visualization showcase

Replace the code playground with a product-focused showcase headed:

**One disk. More ways to understand it.**

The current app exposes these 12 Explore views:

| App view | Website explanation |
| --- | --- |
| Treemap | Compare folder sizes as proportional tiles. |
| Sunburst | Explore folder depth in a circular map. |
| Flame | Follow the largest branches of a scan. |
| Bubbles | Compare folders using size-scaled circles. |
| MindMap | Trace parent and child folder relationships. |
| Sizes | Find the largest mapped folders. |
| Age | Compare indexed files by modification age. |
| Grid | Browse folders as sortable size cards. |
| Radial | Inspect folder levels in depth rings. |
| Icicle | Compare folder sizes across hierarchy levels. |
| Treelist | Expand the folder hierarchy as a list. |
| ExtCloud | See which file types consume the most space. |

Feature a manageable selection of large previews, such as Treemap, Sunburst, Sizes, and Age, with a compact list of the remaining views. ExtCloud means a file-extension visualization; do not market it as cloud-storage integration.

When a visitor changes tabs, update the preview, title, and description together. Support keyboard navigation and clear selected states. Use actual screenshots or clearly labeled sample data; the website does not scan the visitor's computer.

## 9. Professional workflows

Heading: **Made for the files your work leaves behind.**

### Developers

Introduce Dev Projects and Dev Caches as tools for inspecting development workspaces and recognized cache locations. Mention individual build systems or package managers only when supported by the shipping release.

### Video editors

Introduce Video Caches for inspecting recognized video-application cache locations. The current UI references Final Cut Pro, Premiere, After Effects, DaVinci Resolve, Motion, Compressor, Shotcut, and HandBrake. Verify the shipped coverage before using these names in public copy.

### 3D and creative professionals

Introduce 3D & Creative tools for reviewing recognized creative-application storage and caches. Use verified supported applications as examples once confirmed.

Use restrained text labels rather than an endorsement-style logo wall. Explain that detected cache locations are candidates for review, not universally disposable files. Keep source projects and original media distinct from caches.

## 10. Extended feature coverage

Include a compact “More tools for understanding your Mac” section. The following is an inventory of source-visible features, not confirmation that each is release-ready. Match public claims to the shipping app and use screenshots to confirm final descriptions.

| Feature | Information to cover |
| --- | --- |
| Storage | Physical storage, volumes, and measured capacity. |
| Folders | Folder browsing, paths, and size inspection. |
| Smart Clean | Reviewable cleanup recommendations. |
| Litter Score | An overview of detected storage clutter; explain the score if featured. |
| Forecast | History-based storage projections, with sufficient-history requirements. |
| What If? | Estimates for potential cleanup scenarios before taking action. |
| Dev Caches | Recognized development-cache locations. |
| Health | Available disk-health information; avoid promises to predict drive failure. |
| Budgets | Storage budget tracking; confirm alert behavior before describing it. |
| Live Feed | Observed file activity within the feature's monitoring scope. |
| Lifecycle | Application lifecycle information exposed by the app. |
| Provenance | Available file-origin information; do not promise complete attribution. |
| Compression | Selected-file compression where supported; savings are estimates. |
| Containers | Inspection of application containers and their storage. |
| Privacy | The specific privacy-related findings the shipping app provides; not antivirus or secure erasure. |
| Photos | Photo-library structure and storage analysis. |
| Monitor | System/resource monitoring and process information. |
| Snapshots | Saved scan information and comparisons, not file backups. |
| Global search | Search across app sections, views, applications, and indexed files. |
| Menu bar | Quick access to monitoring information. |
| Widget and Quick Look | Include only after confirming availability and release-specific OS requirements. |

Do not make every secondary feature a full-width section. Use grouped cards or expandable details to keep the page easy to scan.

## 11. How it works

Heading: **From full disk to a clearer picture.**

1. **Choose what to scan.** Open DiskDoom, select a scan target, and grant the access needed for the locations you want to inspect.
2. **Explore what is taking space.** Review storage maps, large items, duplicates, and detected cleanup opportunities.
3. **Review and take action.** Inspect selected items and confirm cleanup. Standard file cleanup moves permitted items to the macOS Trash.

Use screenshots or simple product-related illustrations instead of terminal commands.

## 12. Cleanup control, permissions, and privacy

Heading: **You decide what goes.**

Explain the actual workflow in plain language:

- Users review selected items before standard cleanup.
- Standard file cleanup uses macOS Trash rather than permanent deletion.
- Protected system locations are blocked by the cleanup service.
- Permission restrictions can limit scan coverage or prevent an operation.
- Full Disk Access allows inspection of additional protected locations; explain when the app requests it.
- Moving files to Trash is not the same as immediately recovering disk space. Space recovery depends on emptying Trash and filesystem behavior.

Describe scanning as work performed by the Mac app. Licensing uses an online service, so do not claim the entire app never connects to the internet. Publish broader privacy claims only when supported by the actual data flows and privacy policy.

Avoid absolute claims such as “zero risk,” “every file is recoverable,” or “guaranteed space savings.” Keep this section focused on useful product behavior rather than long disclaimers.

## 13. Trial, pricing, and download details

Heading: **Start with a clearer view of your Mac.**

Use the current 14-day trial as the draft offer, subject to confirmation for release. Do not invent a Free/Pro/Business comparison, price, discount, subscription model, lifetime license, or refund guarantee.

Obtain and include:

- Final price, currency, and applicable tax wording.
- One-time or recurring billing terms.
- Number of Macs included in a license.
- Trial limitations and behavior after expiration.
- Update entitlement and upgrade policy.
- Refund terms.
- Official checkout URL.
- Official download URL, file type, current version, release date, and download size.
- Minimum supported macOS version and supported processor architectures.

The main project includes macOS 13.0 deployment settings, while some targets specify macOS 14.0. Verify the main app and optional feature requirements against the shipping build before publishing compatibility claims.

Use labeled placeholders in drafts for missing commercial details. Do not expose those placeholders or nonfunctional purchase buttons on the published page. If sales information is not ready, use an accurate trial/download section instead of a fabricated pricing table.

## 14. Frequently asked questions

Include these questions with short, accurate answers:

**What is DiskDoom?**  
A native Mac app for exploring storage, finding large files and duplicates, and reviewing cleanup opportunities.

**Does the website scan my Mac?**  
No. The website shows the product; scanning happens in the installed Mac application.

**Does cleanup permanently delete files?**  
Standard file cleanup moves permitted items to the macOS Trash. Review the selection before confirming. Emptying Trash is a separate action.

**Why does DiskDoom request Full Disk Access?**  
Some locations are protected by macOS. Access determines what the app can inspect; limited permissions can produce an incomplete view.

**Why might storage totals differ from Finder or macOS Settings?**  
Scan scope, permissions, measurement timing, and filesystem accounting can produce different totals. Avoid implying that every displayed size equals immediately recoverable space.

**Can it scan external drives?**  
Describe supported drive selection and volume inspection after confirming the shipping scan-target workflow. Do not promise every filesystem or network volume.

**Can it remove duplicate photos from Apple Photos?**  
Do not promise duplicate cleanup inside a Photos library. The current Photos view says in-library duplicate detection is unavailable and directs users to Photos for library-managed cleanup. General file duplicate detection is a separate feature.

**Are forecasts and compression savings guaranteed?**  
No. Forecasts depend on available history, and compression savings depend on the selected files and supported filesystem behavior.

**Does DiskDoom work offline?**  
Explain local scanning separately from license activation and validation. Confirm the final offline-grace policy before publishing its duration or limitations.

**How long is the trial, and what happens afterward?**  
The source currently implements a 14-day trial. Confirm the exact post-trial behavior and publish it alongside the offer.

**Which Macs are supported?**  
State verified minimum macOS and architecture requirements, including any different requirements for optional features.

**How do I activate or move a license?**  
Explain activation using the purchase email and license key, plus deactivation on a Mac. Add the confirmed device limit and support link.

## 15. Closing call to action and footer

**Closing heading:** Make room for what matters.

**Supporting copy:** Get a clearer picture of your Mac’s storage and choose your next cleanup with confidence.

**Primary action:** Download for Mac

**Secondary action:** View pricing, when pricing is available.

Repeat the confirmed trial and compatibility information without adding new claims.

Footer groups:

- Product: Features, Visualizations, Download, Release Notes.
- Help: FAQ, Getting Started, Contact Support.
- Legal: Privacy Policy, Terms, License Agreement, Refund Policy where applicable.

Use real destinations and a confirmed support address. Include the current copyright year and confirmed legal owner. Remove the old brand's social links, oversized wordmark, attribution text, and unrelated navigation.

## 16. Interaction, accessibility, and mobile requirements

- Preserve semantic headings and a clear reading order.
- Ensure text, links, controls, and focus states have sufficient contrast.
- Support keyboard access for navigation, showcase tabs, and FAQ controls.
- Expose open/closed states for the mobile menu and FAQ items.
- Keep a visible normal pointer; decorative cursor effects must not interfere with use.
- Make content available without depending on scroll-reveal animation or JavaScript execution.
- Honor reduced motion across the entire page, including counters, typing effects, scrolling, canvas particles, and illustration loops.
- On mobile, stack text and media cleanly, prevent horizontal overflow, and keep buttons easy to tap.
- Use readable screenshot previews with enlargement where needed instead of shrinking important app text beyond usefulness.
- Keep primary download links consistent throughout the page. Every visible action must have an intentional destination or behavior.
- Avoid simulated successful downloads, checkout messages, or scan results.

## 17. Loading and discoverability

- Give the hero illustration and screenshots defined layout space to prevent content jumps.
- Optimize the illustration's embedded image assets and defer below-the-fold media appropriately.
- Keep animation lightweight and avoid redundant scroll, pointer, and animation handlers inherited from the template.
- Ensure key marketing copy is present as readable page text rather than only inside images.
- Use a DiskDoom favicon and social preview image.
- Proposed page title: **DiskDoom — Visual Disk Space Analyzer for Mac**.
- Proposed description: **Explore your Mac’s storage with DiskDoom. Visualize disk usage, find large files and duplicates, and review cleanup opportunities in one native app.**
- Set the canonical address and social-sharing URLs only after the official domain is confirmed.
- Use product metadata that matches the published offer. Do not invent ratings, review counts, prices, or awards.

## 18. Assets and decisions needed

Collect these before completing the public page:

1. Approved DiskDoom logo, app icon, favicon, and social image.
2. Current screenshots for Explore, Duplicates, Applications, cleanup review, monitoring, and professional tools.
3. Additional visualization screenshots for the interactive showcase.
4. Confirmed release feature list and compatibility information.
5. Download, checkout, documentation, release-note, and support destinations.
6. Final trial, license, pricing, refund, and update terms.
7. Privacy policy and legal-owner details.
8. Genuine testimonials or reviews, if available; otherwise omit them.

## 19. Completion criteria for the future implementation

- The full page is unmistakably about DiskDoom.
- The supplied disk illustration is integrated into the main hero and scales within it.
- The page includes the core product story, feature coverage, professional workflows, pricing/trial information, FAQ, and support details.
- AlignUI-specific branding, examples, claims, and links are removed.
- Screenshots reflect the actual product; illustrative values are not presented as real user results.
- Public feature claims match the shipping release.
- All actions and navigation destinations work.
- Mobile layouts, keyboard operation, readable contrast, and reduced-motion behavior are supported.
- No draft placeholders, invented reviews, unsupported performance claims, or unconfirmed commercial terms remain in the published page.

## 20. Reference basis

This brief was prepared by reading the two landing-page files and relevant app sources, including navigation and visualization definitions, the Trash service, licensing code, product view text, and deployment settings. The source establishes useful product context but does not establish release readiness or final commercial terms.

No app code or landing-page code was executed to prepare this document.
