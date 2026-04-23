# IMAGE_CRAB_CONVERTER — macOS App Specification
> A native macOS image viewer and batch processor with a warm, minimal coffee-toned aesthetic.

---

## Overview

Build a native macOS application called **Image_Crab_Converter** using **Swift + SwiftUI + AppKit** (hybrid where needed). The app has two primary modes accessible from a sidebar or tab bar:

1. **Viewer Mode** — Browse and inspect individual images with zoom/crop/resize tools
2. **Batch Mode** — Drag-and-drop multiple files, apply bulk operations (rename, crop, resize)

---

## Tech Stack

| Layer | Choice | Reason |
|---|---|---|
| Language | Swift 5.10+ | Native macOS, best performance |
| UI Framework | SwiftUI (primary) + AppKit (where SwiftUI lacks control) | Modern declarative UI with escape hatches |
| Image Processing | Core Image + ImageIO | Native, zero dependencies, fast |
| Persistence | UserDefaults (lightweight settings only) | No database needed |
| File I/O | Foundation FileManager | Standard |
| Minimum macOS | macOS 14 Sonoma | SwiftUI features, modern APIs |
| Architecture | MVVM | Clean separation, testable |
| No third-party dependencies | — | Keep it lean, native, App Store-ready |

---

## Design System

### Philosophy
**Refined minimalism.** Dense but not cluttered. Like a specialty coffee shop's interior — warm neutrals, intentional spacing, quiet confidence. Every element earns its place.

### Color Palette (CSS variable names for reference, use SwiftUI Color assets)

```
Background primary:    #F5EFE6   (warm off-white, linen)
Background secondary:  #EDE4D6   (slightly darker, panel backgrounds)
Background tertiary:   #E0D5C3   (sidebar, toolbars)
Surface elevated:      #FAF7F2   (cards, popups)
Accent primary:        #8B5E3C   (warm coffee brown — buttons, active states)
Accent hover:          #6F4A2F   (darker brown on hover)
Accent secondary:      #C4956A   (caramel — secondary actions, highlights)
Text primary:          #2C1D12   (deep espresso — main text)
Text secondary:        #6B5040   (medium brown — labels, hints)
Text tertiary:         #A08060   (light brown — placeholders, disabled)
Border:                #D4C5B0   (subtle warm dividers)
Destructive:           #B85C38   (terra cotta red — delete, destructive actions)
Success:               #6B8C5A   (muted olive green — success states)
```

### Typography

- **Display / App Name:** SF Pro Rounded (system, use `.rounded` design) — warm and friendly
- **UI Labels:** SF Pro Text — system standard, clean
- **Monospaced (patterns, file paths):** SF Mono — for rename pattern input fields
- **Font sizes:** Follow Apple HIG. Title: 15pt semibold, Body: 13pt regular, Caption: 11pt, Detail: 10pt

### Spacing & Layout
- Base unit: 8pt
- Inner padding for panels: 16pt
- Section gaps: 24pt
- Corner radius: 10pt for panels, 8pt for buttons, 6pt for smaller elements
- Toolbar height: 48pt
- Sidebar width: 220pt (collapsible)

### Visual Details
- Subtle grain texture overlay on backgrounds (use a very low-opacity noise layer) — optional but adds warmth
- Thin 1pt borders using `Border` color on panels
- Drop shadows: soft, warm-tinted (`Color.black.opacity(0.08)`, blur 12pt)
- Hover states: background fills with `Accent secondary` at 15% opacity
- Active/selected states: `Accent primary` fill, white text

---

## App Structure

```
Image_Crab_Converter/
├── App/
│   ├── Image_Crab_ConverterApp.swift    (entry point, menu bar setup)
│   └── AppDelegate.swift                (lifecycle, window management)
├── Models/
│   ├── ImageDocument.swift              (image file model)
│   ├── BatchJob.swift                   (batch operation model)
│   └── CropRegion.swift
├── ViewModels/
│   ├── ViewerViewModel.swift
│   └── BatchViewModel.swift
├── Views/
│   ├── MainWindowView.swift             (root split view)
│   ├── Viewer/
│   │   ├── ViewerView.swift
│   │   ├── ImageCanvasView.swift        (zoomable image display)
│   │   ├── ViewerToolbarView.swift
│   │   ├── CropOverlayView.swift
│   │   └── ResizeSheetView.swift
│   ├── Batch/
│   │   ├── BatchView.swift
│   │   ├── DropZoneView.swift
│   │   ├── FileListView.swift
│   │   ├── RenamePatternView.swift
│   │   ├── BatchCropView.swift
│   │   ├── BatchResizeView.swift
│   │   └── BatchProgressView.swift
│   └── Shared/
│       ├── SidebarView.swift
│       ├── CoffeeButton.swift           (custom styled button)
│       └── SectionHeader.swift
├── Services/
│   ├── ImageProcessor.swift             (crop, resize via Core Image)
│   ├── BatchProcessor.swift             (async batch execution)
│   └── FileRenamer.swift                (pattern-based rename logic)
└── Resources/
    ├── Assets.xcassets                  (colors, app icon)
    └── Image_Crab_Converter.entitlements
```

---

## Mode 1: Image Viewer

### Layout

```
┌─────────────────────────────────────────────────────────────────┐
│  [←] [→]   Image_Crab_Converter        [Viewer] [Batch]  [⚙]  │  ← Toolbar (48pt)
├──────────────┬──────────────────────────────────────────────────┤
│              │                                                    │
│  SIDEBAR     │              IMAGE CANVAS                         │
│  (220pt)     │         (zoomable, pannable)                      │
│              │                                                    │
│  File info   │                                                    │
│  ─────────   │                ┌──────────────┐                   │
│  Name        │                │              │                   │
│  Dimensions  │                │   [IMAGE]    │                   │
│  File size   │                │              │                   │
│  Format      │                └──────────────┘                   │
│  Created     │                                                    │
│  Modified    │                                                    │
│              │                                                    │
│  ─────────   │                                                    │
│  [Crop]      │                                                    │
│  [Resize]    │                                                    │
│              │                                                    │
├──────────────┴──────────────────────────────────────────────────┤
│   [-]  [100%]  [+]     Zoom: 125%     [Fit]  [Fill]            │  ← Bottom bar
└─────────────────────────────────────────────────────────────────┘
```

### Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `⌘ +` | Zoom in (increments: 10%, 25%, 50%, 75%, 100%, 125%, 150%, 200%, 300%, 400%) |
| `⌘ -` | Zoom out (same steps, reversed) |
| `⌘ 0` | Zoom to 100% (actual pixels) |
| `⌘ Shift 0` | Fit to window |
| `Space` (hold) | Temporary pan mode (grab cursor) |
| `⌘ Left/Right Arrow` | Previous / Next image in folder |
| `⌘ K` | Open Crop tool |
| `⌘ R` | Open Resize sheet |

### Image Canvas (`ImageCanvasView`)
- Implement using `NSScrollView` wrapped in `NSViewRepresentable` for smooth native scrolling and zooming, OR use SwiftUI's `MagnifyGesture` + scroll gesture combination
- Support pinch-to-zoom on trackpad (native macOS gesture)
- Zoom range: 1% to 3200%
- When zoomed beyond fit, show scrollbars (styled warm/minimal)
- Checkerboard pattern background for transparent PNGs
- Image centered when smaller than viewport
- Smooth animation on keyboard zoom changes (`withAnimation(.easeOut(duration: 0.15))`)

### Sidebar Info Panel
Display file metadata pulled via `ImageIO` / `FileManager`:
- Filename (truncated with ellipsis if long)
- Pixel dimensions (e.g., "3024 × 4032 px")
- File size (human-readable, e.g., "4.2 MB")
- Format (JPEG, PNG, HEIC, TIFF, GIF, WebP, BMP)
- Color space (sRGB, Display P3, etc.)
- DPI / resolution
- Date created, date modified
- EXIF data if available: Camera model, focal length, aperture, ISO, shutter speed

### Crop Tool
- Activated by sidebar button `[Crop]` or `⌘ K`
- Overlays a draggable/resizable selection rectangle on the canvas
- Selection handles at corners and edges (8 handles total)
- Show live dimensions of selection in a floating label (e.g., `840 × 560 px`)
- Aspect ratio lock toggle (free, 1:1, 4:3, 16:9, 3:2, custom)
- Buttons: `[Apply Crop]` (coffee brown, prominent) and `[Cancel]` (ghost/outline)
- On Apply: process with Core Image, offer Save As or overwrite dialog

### Resize Tool
- Activated by sidebar button `[Resize]` or `⌘ R`
- Opens as a sheet (modal) from the bottom of the window
- Fields:
  - Width (px) — editable
  - Height (px) — editable (auto-updates when width changes if lock is on)
  - `[🔒]` Aspect ratio lock toggle (default ON)
  - Resample method dropdown: `Lanczos` (default, best quality), `Bilinear`, `Nearest Neighbor`
  - Target file format: Same as original / JPEG / PNG / TIFF / WebP
  - Quality slider (for JPEG/WebP): 0–100%, default 85%
- Buttons: `[Resize & Save]`, `[Cancel]`

### Supported Formats (open)
JPEG, PNG, HEIC/HEIF, TIFF, GIF, BMP, WebP, PDF (first page preview), RAW (via ImageIO where supported)

---

## Mode 2: Batch Processing

### Layout

```
┌─────────────────────────────────────────────────────────────────┐
│  [←] [→]   Image_Crab_Converter        [Viewer] [Batch]  [⚙]  │
├──────────────────────────────┬──────────────────────────────────┤
│  DROP ZONE / FILE LIST       │   OPERATIONS PANEL               │
│  (left ~55%)                 │   (right ~45%)                   │
│                              │                                   │
│  ┌──────────────────────┐    │  ┌─ RENAME ─────────────────┐   │
│  │                      │    │  │ [x] Enable rename         │   │
│  │  Drop images here    │    │  │  Pattern: [IMG_{n}_{date}]│   │
│  │  or click to browse  │    │  │  Preview: IMG_001_2025... │   │
│  │                      │    │  └───────────────────────────┘   │
│  └──────────────────────┘    │                                   │
│                              │  ┌─ RESIZE ─────────────────┐   │
│  [file1.jpg]  3024×4032  4MB │  │ [x] Enable resize         │   │
│  [file2.png]  1920×1080  1MB │  │  Width:  [1920] px        │   │
│  [file3.heic] 4032×3024  6MB │  │  Height: [1080] px  [🔒]  │   │
│  ...                         │  │  Method: [Lanczos    ▾]   │   │
│                              │  └───────────────────────────┘   │
│  [Clear All]   3 files       │                                   │
│                              │  ┌─ CROP ───────────────────┐   │
│                              │  │ [x] Enable crop           │   │
│                              │  │  Mode: [Fixed size ▾]     │   │
│                              │  │  W: [800] H: [600] px     │   │
│                              │  │  Anchor: [Center ▾]       │   │
│                              │  └───────────────────────────┘   │
│                              │                                   │
│                              │  ┌─ OUTPUT ─────────────────┐   │
│                              │  │  Format: [Same as source▾]│   │
│                              │  │  Quality: [85%] ━━━━━●━━  │   │
│                              │  │  Destination: [Same folder]│   │
│                              │  │  [Browse...]               │   │
│                              │  └───────────────────────────┘   │
│                              │                                   │
│                              │   [▶ Run Batch]  ← big button    │
└──────────────────────────────┴──────────────────────────────────┘
```

### Drop Zone / File List

- Large drop zone shown when empty: dashed warm border, crab icon (🦀 or custom SF Symbol analog), text "Drop images here or click to browse"
- On file drop or browse: transition to file list view
- File list rows:
  - Thumbnail (32×32pt)
  - Filename
  - Pixel dimensions
  - File size
  - `[×]` remove button per row
- Multi-select support (click, Shift+click, ⌘+click)
- `[Clear All]` button bottom-left
- File count label bottom-right
- Allow adding more files by dropping onto the list (appends, deduplicates by path)
- Accept: JPEG, PNG, HEIC, TIFF, BMP, WebP, GIF

### Operations Panel

All operations are **independently togglable** via checkboxes. User can enable any combination.

#### 1. Rename

Toggle: `[☑] Enable Rename`

**Pattern field** (monospaced SF Mono input):

```
Pattern tokens:
  {n}        — auto-increment number (zero-padded, e.g., 001)
  {n:4}      — zero-padded to N digits (e.g., {n:4} → 0001)
  {name}     — original filename without extension
  {date}     — current system date (YYYYMMDD)
  {time}     — current system time (HHMMSS)
  {datetime} — YYYYMMDD_HHMMSS
  {ext}      — original file extension (lowercase)
  {width}    — image width in pixels
  {height}   — image height in pixels
```

Examples:
- `photo_{n:3}` → `photo_001.jpg`, `photo_002.jpg`
- `{name}_{date}` → `IMG_4821_20250418.jpg`
- `export_{datetime}_{n}` → `export_20250418_143022_001.jpg`
- `{width}x{height}_{n}` → `1920x1080_001.jpg`

**Start number** field: integer input, default `1`

**Live preview** below the pattern field — show first 3 filenames as they would appear:
```
Preview:
  photo_001.jpg
  photo_002.jpg
  photo_003.jpg
```

#### 2. Resize

Toggle: `[☑] Enable Resize`

- Width (px) — text field
- Height (px) — text field
- Aspect ratio lock `[🔒]` (default ON — auto-calculates height from width)
- If lock OFF: both fields independent
- Resample method dropdown: `Lanczos` / `Bilinear` / `Nearest Neighbor`
- "Resize only if larger" checkbox — skip files already smaller than target

#### 3. Crop

Toggle: `[☑] Enable Crop`

Mode dropdown:
- **Fixed Size** — crop to exact WxH pixels
  - Width and Height fields
  - Anchor point selector (3×3 grid: TL, TC, TR, ML, MC, MR, BL, BC, BR)
- **Aspect Ratio** — crop to ratio, maximizing area
  - Ratio selector: 1:1, 4:3, 3:2, 16:9, or custom (W:H fields)
  - Anchor point selector same as above

#### 4. Output Settings

- **Format:** Same as source / JPEG / PNG / TIFF / WebP
- **Quality:** Slider 1–100, shown as percentage (only active for JPEG/WebP)
- **Destination folder:**
  - Radio: `Same folder as source` (default) / `Custom folder`
  - If Custom: path field + `[Browse...]` button
- **Subfolder option:** Checkbox "Save to subfolder: `[converted]`" — creates a subfolder with given name inside destination

### Run Batch Button

- Large, full-width button at bottom of operations panel
- Label: `▶  Run Batch  (3 files)`
- Color: `Accent primary` (#8B5E3C) background, white text, 10pt corners
- Disabled (grayed) if no files loaded or no operations enabled

### Progress View

When batch runs, replace the Run button area with a progress section:
- Progress bar (warm brown fill)
- Current file label: `Processing file2.png... (2 / 3)`
- Per-file status icons in the file list: `✓` (done), `⏳` (processing), `✗` (error)
- `[Cancel]` button
- When done: summary label `"3 files processed successfully"` or `"2 done, 1 error"` with error detail expandable

---

## Menu Bar

### File Menu
```
File
  Open...                    ⌘O
  Open Recent                ▶
  ─────────────────────────────
  Close                      ⌘W
  Save                       ⌘S
  Save As...                 ⌘⇧S
  Export As...               ⌘⇧E
```

### View Menu
```
View
  Zoom In                    ⌘+
  Zoom Out                   ⌘-
  Actual Size (100%)         ⌘0
  Fit to Window              ⌘⇧0
  ─────────────────────────────
  Show Sidebar               ⌘⇧L
  Show Info Panel            ⌘I
```

### Image Menu
```
Image
  Crop...                    ⌘K
  Resize...                  ⌘R
  ─────────────────────────────
  Rotate Left                ⌘[
  Rotate Right               ⌘]
```

### Window Menu
```
Window
  Viewer Mode                ⌘1
  Batch Mode                 ⌘2
```

---

## App Icon & Branding

- App icon: A stylized crab (`🦀`) silhouette rendered in warm coffee brown on linen background
- Use SF Symbol `camera.aperture` or a custom crab shape as the icon base
- Icon should be designed for all macOS sizes: 16, 32, 64, 128, 256, 512, 1024pt

---

## Settings (Preferences)

Accessible via `⌘,` or menu `Image_Crab_Converter > Settings...`

- **Default zoom behavior:** Fit to window on open / 100% / Remember last
- **Interpolation quality:** Low / Medium / High (default)
- **Checkerboard for transparency:** ON/OFF
- **Sidebar visible by default:** ON/OFF
- **Default output format for batch:** Same as source / JPEG / PNG
- **Default JPEG quality:** slider 1–100 (default 85)
- **Default batch subfolder name:** text field (default `converted`)

---

## Implementation Notes

### Image Rendering
Use `NSImageView` inside `NSScrollView` (wrapped in SwiftUI via `NSViewRepresentable`) for the viewer canvas. This gives smooth native zoom/scroll behavior with proper trackpad gesture support. Alternatively use `CGContext` drawing in a custom `NSView` for pixel-perfect control.

### Zoom Implementation
```swift
// Zoom steps
let zoomSteps: [CGFloat] = [0.01, 0.05, 0.1, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0, 8.0, 16.0, 32.0]

func zoomIn() {
    let next = zoomSteps.first { $0 > currentZoom }
    currentZoom = next ?? zoomSteps.last!
}

func zoomOut() {
    let prev = zoomSteps.last { $0 < currentZoom }
    currentZoom = prev ?? zoomSteps.first!
}

func zoomToActual() {
    currentZoom = 1.0
}
```

### Batch Processing (Async)
Use Swift concurrency (`async/await` + `Task`) for batch processing to keep UI responsive:
```swift
func runBatch(files: [ImageDocument], job: BatchJob) async {
    for (index, file) in files.enumerated() {
        await updateProgress(current: index, total: files.count, filename: file.name)
        do {
            try await processFile(file, job: job)
            await markSuccess(file)
        } catch {
            await markError(file, error: error)
        }
    }
}
```

### File Rename Pattern Engine
Build a simple template substitution engine:
```swift
func applyPattern(_ pattern: String, to file: ImageDocument, index: Int, date: Date) -> String {
    var result = pattern
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd"
    let dateStr = formatter.string(from: date)
    formatter.dateFormat = "HHmmss"
    let timeStr = formatter.string(from: date)
    
    // Handle {n:digits} and {n}
    let paddingRegex = /\{n:(\d+)\}/
    // ... replace tokens
    result = result.replacingOccurrences(of: "{n}", with: String(format: "%03d", index))
    result = result.replacingOccurrences(of: "{date}", with: dateStr)
    result = result.replacingOccurrences(of: "{time}", with: timeStr)
    result = result.replacingOccurrences(of: "{name}", with: file.nameWithoutExtension)
    result = result.replacingOccurrences(of: "{width}", with: "\(file.width)")
    result = result.replacingOccurrences(of: "{height}", with: "\(file.height)")
    return result + "." + file.extension
}
```

### Entitlements
Required for App Sandbox (if targeting App Store):
- `com.apple.security.files.user-selected.read-write` — to read/write user-selected files
- `com.apple.security.files.downloads.read-write` — optional

---

## Quality Checklist

- [ ] All keyboard shortcuts work system-wide within app context
- [ ] Zoom is smooth with animation on keyboard trigger
- [ ] Pinch-to-zoom works on trackpad in viewer
- [ ] Batch progress never blocks UI thread
- [ ] Cancel button actually stops processing mid-batch
- [ ] Rename preview updates live as pattern is typed
- [ ] Aspect ratio lock works correctly in both single and batch resize
- [ ] Error handling: unsupported file gracefully shows error, continues batch
- [ ] App remembers window size and position between launches (`@AppStorage` or `NSWindowController` restoration)
- [ ] Accessible: VoiceOver labels on all controls
- [ ] Dark mode: NOT required (light coffee theme only, but ensure it doesn't break in dark mode system setting — use explicit color assets, not semantic colors)

---

## Out of Scope (v1.0)

- Cloud sync
- Slideshow mode
- RAW editing (develop)
- Layers / compositing
- Filters / color grading
- Undo history beyond single crop/resize
- Plugin system

---

*Spec version: 1.0 | Target: macOS 14+ | Language: Swift 5.10 | Framework: SwiftUI + AppKit*
