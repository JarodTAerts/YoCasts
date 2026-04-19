# YoCasts — Garmin Layout Reference (Pixel-Perfect)

> **Version:** 2.0  
> **Author:** Kaylee (Garmin Dev)  
> **Date:** 2026-04-13  
> **Device:** Garmin Venu 4 41mm — 390×390 round AMOLED  
> **Status:** Authoritative reference — all UI code must conform to this spec  
> **v2.0 change:** Section 5 rewritten for split-dock home menu design

---

## Table of Contents

1. [Round Screen Geometry](#1-round-screen-geometry)
2. [Font Reference](#2-font-reference)
3. [Drawing API Reference](#3-drawing-api-reference)
4. [Touch & Input Reference](#4-touch--input-reference)
5. [Home Menu Layout Spec — Split-Dock Design](#5-home-menu-layout-spec--split-dock-design)
6. [List View Layout Spec](#6-list-view-layout-spec)
7. [Now Playing Screen Layout Spec](#7-now-playing-screen-layout-spec)
8. [Color Palette](#8-color-palette)
9. [Design Patterns & Anti-Patterns](#9-design-patterns--anti-patterns)

---

## 1. Round Screen Geometry

### 1.1 — Display Properties

| Property | Value |
|---|---|
| Resolution | 390 × 390 px |
| Shape | Round (full circle, NO flat tire) |
| Display type | AMOLED (true black = zero power) |
| Center point | (195, 195) |
| Radius | 195 px |
| PPI | 460 |
| Physical diameter | ~30.4 mm (1.2 inches) |

**Key fact:** The Venu 4 41mm has a FULLY round display with NO flat tire cutoff. All 390×390 pixels within the circle are usable.

### 1.2 — Coordinate System

- Origin `(0, 0)` is **top-left** corner of the bounding square
- `dc.getWidth()` = `dc.getHeight()` = 390
- Pixels outside the inscribed circle (the four corners) are **not visible** but can still be drawn to without error
- The circle equation: `(x - 195)² + (y - 195)² ≤ 195²`

### 1.3 — Usable Width at Each Y Position

This is the **critical table** for layout. At any Y position, the usable horizontal width is:

```
width = 2 × √(195² - (y - 195)²)
```

| Y | Distance from Center | Usable Width | X Start | X End | Notes |
|---|---|---|---|---|---|
| 0 | -195 | 0 | — | — | Top pixel (point) |
| 10 | -185 | 123 | 133 | 257 | Very narrow |
| 20 | -175 | 172 | 109 | 281 | |
| 30 | -165 | 208 | 91 | 299 | |
| 40 | -155 | 237 | 77 | 313 | Min for text content |
| 50 | -145 | 261 | 65 | 325 | |
| 60 | -135 | 281 | 54 | 336 | Good for titles |
| 70 | -125 | 299 | 45 | 345 | |
| 80 | -115 | 315 | 38 | 353 | |
| 90 | -105 | 329 | 31 | 359 | |
| 100 | -95 | 341 | 25 | 365 | |
| 110 | -85 | 351 | 20 | 371 | Wide enough for most content |
| 120 | -75 | 360 | 15 | 375 | |
| 130 | -65 | 368 | 11 | 379 | |
| 140 | -55 | 374 | 8 | 382 | |
| 150 | -45 | 380 | 5 | 385 | |
| 160 | -35 | 384 | 3 | 387 | Near-full width |
| 170 | -25 | 387 | 2 | 388 | |
| 180 | -15 | 389 | 1 | 389 | |
| 190 | -5 | 390 | 0 | 390 | Effectively full width |
| 195 | 0 | 390 | 0 | 390 | Center — maximum width |
| 200 | 5 | 390 | 0 | 390 | Effectively full width |
| 210 | 15 | 389 | 1 | 389 | |
| 220 | 25 | 387 | 2 | 388 | |
| 230 | 35 | 384 | 3 | 387 | |
| 240 | 45 | 380 | 5 | 385 | |
| 250 | 55 | 374 | 8 | 382 | |
| 260 | 65 | 368 | 11 | 379 | |
| 270 | 75 | 360 | 15 | 375 | |
| 280 | 85 | 351 | 20 | 371 | |
| 290 | 95 | 341 | 25 | 365 | |
| 300 | 105 | 329 | 31 | 359 | |
| 310 | 115 | 315 | 38 | 353 | |
| 320 | 125 | 299 | 45 | 345 | |
| 330 | 135 | 281 | 54 | 336 | |
| 340 | 145 | 261 | 65 | 325 | |
| 350 | 155 | 237 | 77 | 313 | |
| 360 | 165 | 208 | 91 | 299 | |
| 370 | 175 | 172 | 109 | 281 | |
| 380 | 185 | 123 | 133 | 257 | Very narrow |
| 390 | 195 | 0 | — | — | Bottom pixel (point) |

### 1.4 — Safe Zones

**Maximum inscribed square** (fits entirely within the circle):
- Side: 276 px (195 × √2)
- Bounds: (57, 57) to (333, 333)
- Use case: Content guaranteed visible on any round display

**Practical content zone** (inner 80% with padding):
- Y range: 55 to 335 (280px tall)
- At Y=55, width = 268px → left margin ~61px
- At Y=335, width = 268px → left margin ~61px
- This zone has ≥268px width everywhere

**Viewport zone** (where scrollable content should be drawn):
- Y range: 50 to 340 (290px tall)
- Width at edges: ~261px
- Width at center: 390px

### 1.5 — Screen Zones Diagram

```
              ╭────────────────────╮
           ╱         DEAD ZONE       ╲         Y=0
         ╱     (< 208px wide, tight)    ╲      Y=30
       ╱                                  ╲    Y=50
      │  ┌──────────────────────────────┐  │   Y=55
      │  │                              │  │
      │  │      SAFE CONTENT ZONE       │  │
      │  │                              │  │
      │  │   268px+ wide everywhere     │  │
      │  │                              │  │
      │  │   Use for primary content:   │  │
      │  │   pills, text, controls      │  │   Y=195 (center)
      │  │                              │  │
      │  │                              │  │
      │  │                              │  │
      │  │                              │  │
      │  └──────────────────────────────┘  │   Y=335
       ╲                                  ╱    Y=340
         ╲                              ╱      Y=360
           ╲         DEAD ZONE       ╱         Y=370
              ╰────────────────────╯           Y=390
```

### 1.6 — Practical Width Lookup Function

In Monkey C, compute the available width at any Y:

```monkeyc
function getWidthAtY(y as Number) as Number {
    var dy = y - 195;
    if (dy < -195 || dy > 195) { return 0; }
    var r2 = 195 * 195;
    var w = Math.sqrt(r2 - dy * dy).toNumber() * 2;
    return w;
}

function getMarginAtY(y as Number) as Number {
    return (390 - getWidthAtY(y)) / 2;
}
```

---

## 2. Font Reference

### 2.1 — System Font Pixel Heights (Venu 4 41mm / 390×390)

These are the **actual pixel heights** returned by `dc.getFontHeight()` on 390×390 Garmin devices. Measured and verified.

| Font Constant | Pixel Height | Weight | Recommended Use |
|---|---|---|---|
| `FONT_XTINY` | 33 px | Regular | Timestamps, micro-labels |
| `FONT_TINY` | 41 px | Bold | Subtitles, secondary info |
| `FONT_SMALL` | 46 px | Bold | Body text, list items |
| `FONT_MEDIUM` | 56 px | Bold | Titles, primary labels |
| `FONT_LARGE` | 61 px | Bold | Screen headers, emphasis |
| `FONT_NUMBER_MILD` | 72 px | Numeric | Small numbers |
| `FONT_NUMBER_MEDIUM` | 84 px | Numeric | Medium numbers |
| `FONT_NUMBER_HOT` | 122 px | Numeric | Large numbers/timers |
| `FONT_NUMBER_THAI_HOT` | 144 px | Numeric | XL numbers |

### 2.2 — Font Usage Guide for YoCasts

| UI Element | Font | Height | Rationale |
|---|---|---|---|
| Screen title ("YoCasts") | `FONT_LARGE` | 61 px | Prominent, visible at glance |
| Pill primary label | `FONT_SMALL` | 46 px | Readable without dominating |
| Pill subtitle / count | `FONT_XTINY` | 33 px | Secondary info, compact |
| "NOW PLAYING" label | `FONT_XTINY` | 33 px | Category label, not title |
| NP episode title | `FONT_SMALL` | 46 px | Must be readable |
| NP podcast name | `FONT_XTINY` | 33 px | Secondary, below title |
| Time display (elapsed/total) | `FONT_XTINY` | 33 px | Compact but legible |
| Progress percentage | `FONT_TINY` | 41 px | Noticeable but not dominant |
| Empty state message | `FONT_SMALL` | 46 px | Clear and readable |
| Loading text | `FONT_SMALL` | 46 px | Temporary, needs to be visible |

### 2.3 — Character Width Estimates

Approximate character widths measured with `dc.getTextWidthInPixels()` at each font size. These are **average** widths — actual varies by character (e.g., "W" is wider than "i").

| Font | Avg Char Width | Chars in 300px | Chars in 250px | Chars in 200px |
|---|---|---|---|---|
| `FONT_XTINY` (33px) | ~14 px | ~21 | ~18 | ~14 |
| `FONT_TINY` (41px) | ~17 px | ~18 | ~15 | ~12 |
| `FONT_SMALL` (46px) | ~19 px | ~16 | ~13 | ~11 |
| `FONT_MEDIUM` (56px) | ~23 px | ~13 | ~11 | ~9 |
| `FONT_LARGE` (61px) | ~25 px | ~12 | ~10 | ~8 |

**Always use `dc.getTextWidthInPixels(text, font)` at runtime** — these estimates are for layout planning only. Use `truncateText()` helper with binary search for pixel-accurate truncation.

### 2.4 — Font Height vs Line Spacing

Font height from `getFontHeight()` includes built-in leading. For multi-line text:

| Font | Font Height | Recommended Line Gap | Total Line Height |
|---|---|---|---|
| `FONT_XTINY` | 33 px | 4 px | 37 px |
| `FONT_TINY` | 41 px | 4 px | 45 px |
| `FONT_SMALL` | 46 px | 6 px | 52 px |
| `FONT_MEDIUM` | 56 px | 6 px | 62 px |

---

## 3. Drawing API Reference

### 3.1 — Key Dc Methods

```monkeyc
// Text
dc.drawText(x, y, font, text, justification)
dc.getTextWidthInPixels(text, font)
dc.getFontHeight(font)

// Shapes
dc.fillRoundedRectangle(x, y, width, height, cornerRadius)
dc.drawRoundedRectangle(x, y, width, height, cornerRadius)
dc.fillRectangle(x, y, width, height)
dc.fillCircle(cx, cy, radius)
dc.drawCircle(cx, cy, radius)
dc.drawArc(cx, cy, radius, direction, startAngle, endAngle)

// Colors
dc.setColor(foreground, background)
dc.clear()  // fills with background color

// Clipping (for scroll viewports & marquee)
dc.setClip(x, y, width, height)
dc.clearClip()

// Polygons (for custom icons)
dc.fillPolygon(points)  // points = [[x1,y1], [x2,y2], ...]
```

### 3.2 — Text Justification Flags

```monkeyc
// Horizontal
Graphics.TEXT_JUSTIFY_LEFT
Graphics.TEXT_JUSTIFY_CENTER
Graphics.TEXT_JUSTIFY_RIGHT

// Vertical (combine with | operator)
Graphics.TEXT_JUSTIFY_VCENTER  // y is vertical center of text

// Common combinations:
Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER  // centered both axes
Graphics.TEXT_JUSTIFY_LEFT                                     // left-aligned, y is top of text
```

**Important:** Without `TEXT_JUSTIFY_VCENTER`, the `y` parameter is the **top** of the text. With `VCENTER`, `y` is the vertical midpoint.

### 3.3 — Clipping for Viewports

```monkeyc
// Set viewport clip for scrollable area
dc.setClip(0, viewportTop, 390, viewportHeight);

// Draw content at positions relative to scroll offset
var drawY = viewportTop + itemY - scrollOffset;
dc.drawText(x, drawY, font, text, justify);

// IMPORTANT: Always clear clip after drawing viewport content
dc.clearClip();
```

---

## 4. Touch & Input Reference

### 4.1 — Delegate Types

| Delegate | Base Class | Use Case |
|---|---|---|
| `InputDelegate` | — | Custom views needing raw touch coordinates (`onTap`, `onDrag`, `onSwipe`, `onKey`) |
| `BehaviorDelegate` | `InputDelegate` | Device-agnostic views where logical actions matter more than coordinates (`onSelect`, `onNextPage`, `onBack`) |

**CRITICAL:** `BehaviorDelegate` converts ALL screen taps into `onSelect()` calls via its behavior translator. If `onSelect()` returns `true`, `onTap()` is **NEVER** called. **Always use `InputDelegate` for custom drawn views that need tap-coordinate hit testing.**

Use `BehaviorDelegate` only for simple screens where device-agnostic behavior is desired (e.g., Now Playing: SELECT = play/pause).

### 4.2 — Touch Event API

```monkeyc
// ClickEvent (from onTap)
function onTap(clickEvent as ClickEvent) as Boolean {
    var coords = clickEvent.getCoordinates();  // returns [x, y] Array
    var tapX = coords[0] as Number;
    var tapY = coords[1] as Number;
    // hit-test against known regions
    return true;  // consumed
}

// SwipeEvent (from onSwipe)
function onSwipe(swipeEvent as SwipeEvent) as Boolean {
    var dir = swipeEvent.getDirection();
    // WatchUi.SWIPE_UP, SWIPE_DOWN, SWIPE_LEFT, SWIPE_RIGHT
    return true;
}

// DragEvent (from onDrag) - for smooth scrolling
function onDrag(dragEvent as DragEvent) as Boolean {
    // dragEvent has no public delta method in older CIQ
    // Use onSwipe for discrete scroll, or track start/current positions
    return true;
}

// KeyEvent (from onKey) - for physical buttons
function onKey(keyEvent as KeyEvent) as Boolean {
    var key = keyEvent.getKey();
    // WatchUi.KEY_ENTER, KEY_ESC, KEY_UP, KEY_DOWN, KEY_START
    return true;
}
```

### 4.3 — Touch Target Sizing

| Guideline | Value | Source |
|---|---|---|
| Minimum touch target | 44 × 44 px | WCAG AAA / industry standard |
| Recommended target | 48 × 48 px | Material Design wearable |
| Garmin recommendation | ≥36 × 36 px | Garmin UX guidelines |
| **YoCasts standard** | **≥56 px tall** | Our pills are 68-105px, well above minimum |

**Key rule:** Every tappable element must be at least 56px tall. Our pill heights (68px for Queue/Podcasts, 105px for Now Playing) exceed this comfortably.

### 4.4 — Hit Testing Pattern

For scroll-aware hit testing:

```monkeyc
function isPointInPill(tapY as Number, pillScreenY as Number, pillHeight as Number) as Boolean {
    return (tapY >= pillScreenY && tapY < pillScreenY + pillHeight);
}

// For circular buttons (play/pause):
function isPointInCircle(tapX as Number, tapY as Number,
                         cx as Number, cy as Number, radius as Number) as Boolean {
    var dx = tapX - cx;
    var dy = tapY - cy;
    return (dx * dx + dy * dy) <= (radius * radius);
}
```

### 4.5 — Scroll Behavior

| Property | Value | Rationale |
|---|---|---|
| Scroll method | `onSwipe(SWIPE_UP/DOWN)` | Discrete steps, reliable on Garmin |
| Scroll step | 80 px | One full pill height + gap, feels natural |
| Scroll boundary | Clamp to [0, maxScroll] | No overscroll/bounce (keep it simple) |
| Max scroll | `contentHeight - viewportHeight` | Never scroll past last item |
| Scroll animation | None (instant) | Garmin CPU can't do smooth scroll well |
| Button scroll | KEY_UP / KEY_DOWN | Same 80px step as swipe |

---

## 5. Home Menu Layout Spec — Split-Dock Design

> **Replaces:** Previous single-zone pill layout (v1.0)  
> **Design:** Two-zone split screen — scrollable menu + fixed "Now Playing" dock

### 5.1 — Overview

The home screen is divided into two zones:

1. **Upper 2/3 — Scrollable Menu (Y=0 to Y=260):** Tappable pill/card items (Queue, Podcasts, Settings) that scroll vertically. Items scroll _under_ the dock when swiping.
2. **Bottom 1/3 — Static Now Playing Dock (Y=260 to Y=390):** Fixed overlay showing current playback info, progress, and a play/pause tap zone at the bottom edge.

The dock is rendered **on top of** the scrollable content. The scrollable zone's drawing is clipped at Y=260 so items disappear behind the dock as they scroll past.

### 5.2 — Full Screen Layout Diagram

```
                ╭──────────────────╮
             ╱                        ╲        Y=0
           ╱   ┌─────── YoCasts ──────┐  ╲     Y=15 (title)
         ╱     └──────────────────────┘    ╲
        │                                    │  Y=40
        │  ┌────────────────────────────┐    │
        │  │         QUEUE              │    │  Y=50 ── pill top
        │  │         3 episodes         │    │
        │  └────────────────────────────┘    │  Y=110
        │                                    │
        │  ┌──────────────────────────────┐  │
        │  │         PODCASTS             │  │  Y=122 ── pill top
        │  │         5 subscriptions      │  │
        │  └──────────────────────────────┘  │  Y=182
        │                                    │
        │  ┌──────────────────────────────┐  │
        │  │    ⚙    SETTINGS             │  │  Y=194 ── pill top
        │  │         Playback, downloads  │  │
        │  └──────────────────────────────┘  │  Y=254
  ─ ─ ─│─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─│─ Y=260 ══ DOCK TOP
        │  ┄┄┄┄┄┄┄ divider line ┄┄┄┄┄┄┄┄┄  │  Y=260 (1px line)
        │                                    │
        │     The Daily • NYT               │  Y=268 podcast name
        │     Why AI Can't Replace...       │  Y=302 episode title
        │                                    │
        │     ████████░░░░░░░░░░░░░         │  Y=338 progress bar
        │        12:34 / 45:00              │  Y=346 time display
         ╲                                ╱
           ╲        [ ▶ ]              ╱     Y=375 play/pause
             ╲                      ╱        Y=385
                ╰──────────────────╯         Y=390
```

### 5.3 — Zone Boundaries

| Zone | Y Start | Y End | Height | Purpose |
|---|---|---|---|---|
| Title area | 0 | 40 | 40 px | "YoCasts" header (in top dead zone) |
| Scrollable menu | 40 | 260 | 220 px | Tappable pill items, scrollable |
| **Dock** | **260** | **390** | **130 px** | **Fixed Now Playing overlay** |
| Dock info zone | 260 | 365 | 105 px | Podcast/episode/progress (tap → NP screen) |
| Dock play/pause zone | 365 | 390 | 25 px | Bottom-edge tap → toggle playback |

### 5.4 — Now Playing Dock (Y=260–390)

The dock is a **fixed overlay** that never scrolls. It is drawn _after_ the scrollable content, covering anything beneath it. Scrollable items are clipped at Y=260 via `dc.setClip()`.

#### 5.4.1 — Dock Layout Constants

```monkeyc
// Zone boundary
const DOCK_TOP = 260;
const DOCK_BOTTOM = 390;               // screen bottom
const DOCK_HEIGHT = 130;               // 390 - 260

// Element Y positions (top of text/element)
const DOCK_DIVIDER_Y = 260;           // 1px divider line
const DOCK_PODCAST_Y = 268;           // Podcast name text top
const DOCK_EPISODE_Y = 302;           // Episode title text top
const DOCK_PROGRESS_Y = 338;          // Progress bar top
const DOCK_TIME_Y = 346;              // Time text top
const DOCK_PLAYPAUSE_Y = 375;         // Play/Pause icon center

// Touch zones
const DOCK_PLAYPAUSE_ZONE_TOP = 365;  // Y=365–390 → play/pause
const DOCK_INFO_ZONE_TOP = 260;       // Y=260–365 → navigate to NP screen

// Progress bar
const PROGRESS_BAR_HEIGHT = 4;
const PROGRESS_BAR_RADIUS = 2;        // corner radius for rounded ends
const PROGRESS_BAR_WIDTH = 200;       // fixed width, centered

// Margins
const DOCK_TEXT_MARGIN = 20;           // margin from circle edge to text
```

#### 5.4.2 — Pixel-Perfect Width Table (Dock Zone)

These are the exact usable widths at each key Y position in the dock, computed from `width = 2√(195² − (y−195)²)`:

| Y | dy (y−195) | Circle Width | −40px Margins | Available for Content | Used By |
|---|---|---|---|---|---|
| 260 | 65 | 368 px | 328 px | 328 px | Dock top edge |
| 268 | 73 | 362 px | 322 px | 322 px | **Podcast name** |
| 270 | 75 | 360 px | 320 px | 320 px | (reference) |
| 280 | 85 | 351 px | 311 px | 311 px | |
| 290 | 95 | 341 px | 301 px | 301 px | |
| 300 | 105 | 329 px | 289 px | 289 px | |
| 302 | 107 | 326 px | 286 px | 286 px | **Episode title** |
| 310 | 115 | 315 px | 275 px | 275 px | |
| 320 | 125 | 299 px | 259 px | 259 px | |
| 330 | 135 | 281 px | 241 px | 241 px | |
| 335 | 140 | 271 px | 231 px | 231 px | Episode text bottom |
| 338 | 143 | 265 px | 225 px | 225 px | **Progress bar** |
| 340 | 145 | 261 px | 221 px | 221 px | (reference) |
| 346 | 151 | 247 px | 207 px | 207 px | **Time display** |
| 350 | 155 | 237 px | 197 px | 197 px | |
| 360 | 165 | 208 px | 168 px | 168 px | |
| 365 | 170 | 191 px | 151 px | 151 px | Play/pause zone top |
| 370 | 175 | 172 px | 132 px | 132 px | (reference) |
| 375 | 180 | 150 px | 110 px | 110 px | **Play/pause icon** |
| 378 | 183 | 135 px | 95 px | 95 px | |
| 380 | 185 | 123 px | 83 px | 83 px | |
| 385 | 190 | 88 px | 48 px | 48 px | Tight dead zone |
| 390 | 195 | 0 px | — | — | Screen bottom |

#### 5.4.3 — Dock Background

**Recommended:** Solid black background with subtle top divider.

Connect IQ has **no alpha blending**, so true semi-transparent gradients are not possible. Instead:

```monkeyc
// Step 1: Clip scrollable content at dock boundary
dc.setClip(0, 0, 390, DOCK_TOP);  // scrollable area only
// ... draw scrollable items ...
dc.clearClip();

// Step 2: Draw solid dock background
dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
dc.fillRectangle(0, DOCK_TOP, 390, DOCK_HEIGHT);

// Step 3: Subtle top divider line
dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
dc.fillRectangle(getMarginAtY(DOCK_TOP), DOCK_TOP, getWidthAtY(DOCK_TOP), 1);

// Step 4: Draw dock content elements on top
// ... podcast name, episode title, progress bar, time, play/pause ...
```

**Alternative (pseudo-gradient):** Draw 3–4 horizontal lines at decreasing brightness above the divider for a fade effect:
```monkeyc
dc.setColor(0x111111, Graphics.COLOR_TRANSPARENT);
dc.fillRectangle(getMarginAtY(258), 258, getWidthAtY(258), 1);
dc.setColor(0x222222, Graphics.COLOR_TRANSPARENT);
dc.fillRectangle(getMarginAtY(259), 259, getWidthAtY(259), 1);
dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
dc.fillRectangle(getMarginAtY(260), 260, getWidthAtY(260), 1);
```

#### 5.4.4 — Podcast Name (Y=268)

| Property | Value |
|---|---|
| Y position | 268 (top of text) |
| Y range | 268–301 (33px font height) |
| Font | `FONT_XTINY` (33 px) |
| Color | `0xAAAAAA` (secondary gray) |
| Alignment | `TEXT_JUSTIFY_CENTER` at X=195 |
| Max text width | 322 px (circle width 362 − 40px margins) |
| Overflow | Marquee scroll (3-phase: pause → scroll 2px/tick → pause → reset) |
| Content | Podcast name, e.g. "The Daily" |

#### 5.4.5 — Episode Title (Y=302)

| Property | Value |
|---|---|
| Y position | 302 (top of text) |
| Y range | 302–335 (33px font height) |
| Font | `FONT_XTINY` (33 px) |
| Color | `0xFFFFFF` (primary white) |
| Alignment | `TEXT_JUSTIFY_CENTER` at X=195 |
| Max text width | 286 px (circle width 326 − 40px margins) |
| Overflow | Marquee scroll (same timer as podcast name, staggered start) |
| Content | Episode title, e.g. "Why AI Can't Replace Podcasters" |

**Note:** Both podcast name and episode title use FONT_XTINY in the dock. This is intentional — the dock is a compact summary. The full Now Playing screen uses larger fonts for these elements.

#### 5.4.6 — Progress Bar (Y=338)

| Property | Value |
|---|---|
| Y position | 338 (top of bar) |
| Height | 4 px |
| Y range | 338–342 |
| Total width | 200 px, centered (X=95 to X=295) |
| Corner radius | 2 px (rounded ends via `fillRoundedRectangle`) |
| Background color | `0x333333` (full bar track) |
| Fill color | `0x55AAFF` (accent blue, proportional to elapsed/total) |
| Available width at Y=338 | 265 px (225 px with margins) — 200px bar fits ✓ |

```monkeyc
// Background track
dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
dc.fillRoundedRectangle(95, 338, 200, 4, 2);

// Filled portion (proportional to playback progress)
var fillW = (elapsed * 200.0 / total).toNumber();
if (fillW > 0) {
    dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
    dc.fillRoundedRectangle(95, 338, fillW, 4, 2);
}
```

#### 5.4.7 — Time Display (Y=346)

| Property | Value |
|---|---|
| Y position | 346 (top of text) |
| Y range | 346–379 (33px font height) |
| Font | `FONT_XTINY` (33 px) |
| Color | `0xAAAAAA` (secondary gray) |
| Alignment | `TEXT_JUSTIFY_CENTER` at X=195 |
| Max text width | 207 px (circle width 247 − 40px margins) |
| Format | `"12:34 / 45:00"` (elapsed / total) |
| Text width estimate | 14 chars × ~14px = ~196 px → fits in 207 px ✓ |

#### 5.4.8 — Play/Pause Button (Y=365–390)

This button lives in the round screen's **dead zone** — intentionally. It mirrors how Garmin system buttons conform to the bottom edge.

| Property | Value |
|---|---|
| Icon center | (195, 378) |
| Icon radius | 10 px |
| Icon type | Play triangle (▶) or Pause bars (❚❚), drawn with `fillPolygon`/`fillRectangle` |
| Icon color | `0x55AAFF` (accent blue) |
| Available width at Y=378 | 135 px (icon at 20px wide fits easily) |
| Touch target zone | **Y=365 to Y=390** (25 px tall, full circle width at each Y) |
| Touch width at Y=375 | 150 px centered (X=120 to X=270) |
| Action | Tap → toggle play/pause |

```monkeyc
// Play icon (triangle pointing right)
var cx = 195;
var cy = 378;
var sz = 8;
dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
dc.fillPolygon([[cx - sz, cy - sz], [cx - sz, cy + sz], [cx + sz, cy]]);

// Pause icon (two vertical bars)
// dc.fillRectangle(cx - 7, cy - 8, 5, 16);
// dc.fillRectangle(cx + 2, cy - 8, 5, 16);
```

**Visual note:** The play/pause icon partially overlaps with the time text visually (time text extends to Y=379, icon centered at Y=378). This is acceptable — the icon is drawn on top of the time text's lower portion, and the dead zone narrowing naturally frames the icon.

#### 5.4.9 — Dock Touch Zones

```
Y=260 ┬──────────────────────── Dock top
      │                                     ─┐
      │   Podcast name                       │
      │   Episode title                      │  TAP → Navigate to
      │   ████ progress ░░░░                 │  full Now Playing
      │   12:34 / 45:00                      │  screen
      │                                     ─┘
Y=365 ┼──────────────────────── Zone boundary
      │         [ ▶ ]                       ─┐  TAP → Toggle
Y=390 ┴──────────────────────── Screen bottom ┘  play/pause
```

```monkeyc
function onTap(clickEvent as ClickEvent) as Boolean {
    var coords = clickEvent.getCoordinates();
    var tapY = coords[1] as Number;

    if (tapY >= DOCK_PLAYPAUSE_ZONE_TOP) {
        // Bottom zone: toggle play/pause
        _service.togglePlayPause();
        WatchUi.requestUpdate();
        return true;
    } else if (tapY >= DOCK_TOP) {
        // Dock info zone: navigate to full Now Playing screen
        WatchUi.pushView(new NowPlayingView(_service), new NowPlayingDelegate(_service), WatchUi.SLIDE_UP);
        return true;
    }
    // ... handle scrollable zone taps above Y=260 ...
    return false;
}
```

#### 5.4.10 — Dock Detail Diagram

```
Y=260  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄  1px divider (0x333333)
       │←──── 368px circle width ────→│
Y=268  │  ←20→ Podcast Name (XTINY) ←20→ │     322px text area
       │                                   │
       │         (4px gap)                 │
Y=302  │  ←20→ Episode Title (XTINY) ←20→│     286px text area
       │                                   │
       │         (3px gap)                 │
Y=338  │      ┌══════════════════┐         │     200px progress bar
       │      │████████░░░░░░░░░░│         │     4px tall, centered
Y=342  │      └══════════════════┘         │
       │         (4px gap)                 │
Y=346  │    12:34 / 45:00 (XTINY)         │     207px text area
       │                                   │
  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─  Y=365 play/pause zone
       │                                   │
Y=375    ╲      [ ▶ ] (10px r)        ╱       150px wide
Y=378      ╲        icon center     ╱         135px wide
              ╲                  ╱
Y=390            ╰────────────╯                 Screen bottom
```

#### 5.4.11 — Dock Font Summary

| Element | Font | Height | Color | Max Width | Marquee |
|---|---|---|---|---|---|
| Podcast name | FONT_XTINY | 33 px | 0xAAAAAA | 322 px | Yes |
| Episode title | FONT_XTINY | 33 px | 0xFFFFFF | 286 px | Yes |
| Time display | FONT_XTINY | 33 px | 0xAAAAAA | 207 px | No |
| Progress bar | — | 4 px | 0x55AAFF / 0x333333 | 200 px | — |
| Play/Pause icon | Drawn | 20 px | 0x55AAFF | — | — |

### 5.5 — Scrollable Menu Zone (Y=0–260)

#### 5.5.1 — Layout Constants

```monkeyc
// Scrollable zone
const SCROLL_ZONE_TOP = 40;            // content starts here (below title)
const SCROLL_ZONE_BOTTOM = 260;        // dock covers everything below
const SCROLL_ZONE_HEIGHT = 220;        // 260 - 40

// Pill dimensions
const PILL_HEIGHT = 60;                // each menu item pill
const PILL_GAP = 12;                   // vertical gap between pills
const PILL_MARGIN = 20;                // margin from circle edge to pill edge
const PILL_CORNER_RADIUS = 16;        // rounded corners
const PILL_INNER_PAD_X = 16;          // horizontal padding inside pill
const PILL_INNER_PAD_Y = 8;           // vertical padding inside pill

// Menu items (3 pills × 60 + 2 gaps × 12 = 204px)
const TOTAL_MENU_HEIGHT = 204;

// Y positions (default scroll offset = 0)
const QUEUE_Y = 50;                    // Queue pill: 50–110
const PODCASTS_Y = 122;               // Podcasts pill: 122–182
const SETTINGS_Y = 194;               // Settings pill: 194–254

// Scroll
const SCROLL_STEP = 72;               // pixels per swipe (pill + gap)
const MAX_SCROLL_3_ITEMS = 0;         // 204px fits in 220px — no scroll needed!

// Title
const TITLE_Y = 12;                    // "YoCasts" header
const TITLE_FONT = Graphics.FONT_MEDIUM;  // 56px
```

**Content positioning rationale:** 3 items at 204px total fit within the 220px scrollable viewport (Y=40 to Y=260) with 8px to spare. No scrolling needed for 3 items. When more items are added in future, scrolling activates automatically.

#### 5.5.2 — Pill Positions & Width Calculations

Each pill's width adapts to the round screen at its Y position. The constraining width is the **minimum circle width** across the pill's vertical span, minus margins.

```monkeyc
function getScrollPillWidth(pillY as Number) as Number {
    var minW = 390;
    for (var y = pillY; y <= pillY + PILL_HEIGHT; y += 5) {
        var w = getWidthAtY(y);
        if (w < minW) { minW = w; }
    }
    return minW - 2 * PILL_MARGIN;  // 20px margin each side
}
```

**Computed pill dimensions:**

| Pill | Y Range | Constraining Y | Circle Width | −40px Margins | Pill Width | Pill X |
|---|---|---|---|---|---|---|
| Queue | 50–110 | Y=50 | 261 px | 221 px | **221 px** | 85 |
| Podcasts | 122–182 | Y=122 | 362 px | 322 px | **322 px** | 34 |
| Settings | 194–254 | Y=254 | 372 px | 332 px | **332 px** | 29 |

**Width verification at constraining Y:**
- Queue at Y=50: `2√(195² − 145²) = 2√17000 = 260.8` → 261 px ✓
- Podcasts at Y=122: `2√(195² − 73²) = 2√32696 = 361.6` → 362 px ✓
- Settings at Y=254: `2√(195² − 59²) = 2√34544 = 371.7` → 372 px ✓

All pills end above Y=260 (Settings bottom = Y=254), so all items are fully visible with no scroll in the default state. ✓

#### 5.5.3 — Queue Pill (Y=50–110, 221px wide)

```
        ╱                                  ╲
       │  ┌─────────────────────────────┐   │  Y=50
       │  │  [♫]  Queue                 │   │  ← FONT_SMALL (46px), white
       │  │        3 episodes           │   │  ← FONT_XTINY (33px), gray
       │  └─────────────────────────────┘   │  Y=110
       │         221px wide                  │
```

| Element | Position | Font | Color | Notes |
|---|---|---|---|---|
| Music note icon | pillX + 16, Y=50+10 = 60 | Drawn (circle+stem) | 0x55AAFF | 20×24px |
| "Queue" | pillX + 48, Y=50+8 = 58 | FONT_SMALL (46px) | 0xFFFFFF | Primary label |
| "3 episodes" | pillX + 48, Y=50+34 = 84 | FONT_XTINY (33px) | 0xAAAAAA | Dynamic count |
| Pill background | X=85, Y=50 | — | 0x1A1A2E | fillRoundedRect, r=16 |

**Text budget:** "Queue" in FONT_SMALL ≈ 5 chars × 19px = 95px. Available: 221 − 48 − 16 = 157px. ✓

#### 5.5.4 — Podcasts Pill (Y=122–182, 322px wide)

```
       │  ┌──────────────────────────────────────┐  │  Y=122
       │  │  [🎧]  Podcasts                       │  │  ← FONT_SMALL, white
       │  │         5 subscriptions               │  │  ← FONT_XTINY, gray
       │  └──────────────────────────────────────┘  │  Y=182
       │              322px wide                     │
```

| Element | Position | Font | Color | Notes |
|---|---|---|---|---|
| Headphone icon | pillX + 16, Y=122+10 = 132 | Drawn (arc+cups) | 0x55AAFF | 22×20px |
| "Podcasts" | pillX + 48, Y=122+8 = 130 | FONT_SMALL (46px) | 0xFFFFFF | Primary label |
| "5 subscriptions" | pillX + 48, Y=122+34 = 156 | FONT_XTINY (33px) | 0xAAAAAA | Dynamic count |
| Pill background | X=34, Y=122 | — | 0x1A1A2E | fillRoundedRect, r=16 |

#### 5.5.5 — Settings Pill (Y=194–254, 332px wide)

```
       │  ┌──────────────────────────────────────┐  │  Y=194
       │  │  [⚙]  Settings                       │  │  ← FONT_SMALL, white
       │  │        Playback, downloads            │  │  ← FONT_XTINY, gray
       │  └──────────────────────────────────────┘  │  Y=254
       │              332px wide                     │
```

| Element | Position | Font | Color | Notes |
|---|---|---|---|---|
| Gear icon | pillX + 16, Y=194+10 = 204 | Drawn (see §5.5.6) | 0x55AAFF | 22×22px |
| "Settings" | pillX + 48, Y=194+8 = 202 | FONT_SMALL (46px) | 0xFFFFFF | Primary label |
| "Playback, downloads" | pillX + 48, Y=194+34 = 228 | FONT_XTINY (33px) | 0xAAAAAA | Static hint |
| Pill background | X=29, Y=194 | — | 0x1A1A2E | fillRoundedRect, r=16 |

#### 5.5.6 — Gear Icon (⚙) Drawing Spec

The gear icon is drawn with Graphics primitives — no Unicode or bitmap dependency.

```monkeyc
function drawGearIcon(dc as Dc, cx as Number, cy as Number) as Void {
    var outerR = 11;
    var innerR = 5;
    var toothW = 4;
    var toothH = 4;

    // Gear body (filled circle)
    dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
    dc.fillCircle(cx, cy, outerR);

    // Center hole (background color)
    dc.setColor(0x1A1A2E, Graphics.COLOR_TRANSPARENT);  // pill bg color
    dc.fillCircle(cx, cy, innerR);

    // 6 teeth at 0°, 60°, 120°, 180°, 240°, 300°
    dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
    for (var i = 0; i < 6; i++) {
        var angle = i * 60.0 * Math.PI / 180.0;
        var tx = cx + (outerR * Math.cos(angle)).toNumber() - toothW / 2;
        var ty = cy - (outerR * Math.sin(angle)).toNumber() - toothH / 2;
        dc.fillRectangle(tx, ty, toothW, toothH);
    }
}
```

| Property | Value |
|---|---|
| Center | (pillX + 27, pillY + 21) |
| Outer radius | 11 px |
| Inner radius (hole) | 5 px |
| Teeth | 6 rectangular teeth, 4×4 px each |
| Color | 0x55AAFF (accent blue) |
| Bounding box | ~26×26 px |

#### 5.5.7 — Scrollable Zone Diagram

```
Y=0    ·               (screen top — dead zone)
       ·
Y=12   ·     "YoCasts"  (FONT_MEDIUM, 0x55AAFF, centered)
       ·
Y=40   ┄┄┄┄┄  scroll viewport top  ┄┄┄┄┄

Y=50   ┌──────────────────┐   Queue (221px)
Y=110  └──────────────────┘
                                     ↕ 12px gap
Y=122  ┌────────────────────────┐   Podcasts (322px)
Y=182  └────────────────────────┘
                                     ↕ 12px gap
Y=194  ┌─────────────────────────┐  Settings (332px)
Y=254  └─────────────────────────┘

Y=260  ══════════════════════════════  DOCK BOUNDARY (items clip here)
```

#### 5.5.8 — Scroll Behavior

| Property | Value | Notes |
|---|---|---|
| Scroll method | `onSwipe(SWIPE_UP/DOWN)` + `KEY_UP/DOWN` | Discrete steps |
| Scroll step | 72 px | One pill + gap (60 + 12) |
| Default scroll offset | 0 | All 3 items visible |
| Max scroll (3 items) | 0 | Content (204px) fits in viewport (220px) |
| Max scroll (N items) | `max(0, N*72 - 12 - 220)` | For future items |
| Scroll animation | None (instant snap) | Garmin CPU limitation |
| Boundary clamping | `scrollOffset = clamp(scrollOffset, 0, maxScroll)` | No overscroll |

**Future-proofing:** When more menu items are added (e.g., History, Discover), scrolling activates automatically. The 4th item at Y=266 would be partially hidden behind the dock, requiring one scroll step to reveal.

#### 5.5.9 — Clipping at Dock Boundary

Items that scroll into the dock zone are hidden by clipping:

```monkeyc
// Before drawing scrollable items:
dc.setClip(0, 0, 390, DOCK_TOP);  // only draw above Y=260

// Draw each pill at its Y position (adjusted for scroll offset)
for (var i = 0; i < menuItems.size(); i++) {
    var itemY = QUEUE_Y + i * (PILL_HEIGHT + PILL_GAP) - scrollOffset;
    if (itemY + PILL_HEIGHT > 0 && itemY < DOCK_TOP) {
        drawPill(dc, itemY, menuItems[i]);
    }
}

// Clear clip before drawing dock
dc.clearClip();
// ... draw dock on top ...
```

Items partially within the clip boundary are automatically cropped — no manual calculation needed. This creates the "scroll under the dock" visual effect.

### 5.6 — Title Bar

```
"YoCasts" centered at Y=12, FONT_MEDIUM (56px), accent blue (0x55AAFF)
Position: (195, 12), TEXT_JUSTIFY_CENTER
```

At Y=12, usable width = ~140px. "YoCasts" in FONT_MEDIUM ≈ 6 chars × 23px = ~138px. Tight fit but legible. The title is in the top dead zone, consistent with Garmin system app headers.

### 5.7 — Settings Page Spec

Navigated to from the Settings pill on the home menu. Uses `WatchUi.Menu2` for standard list behavior.

#### 5.7.1 — Settings Menu Items

| Item | Label | Sub-Label | Action | Status |
|---|---|---|---|---|
| Playback Speed | "Playback Speed" | "1.0x" (current value) | Future: cycle 0.5–3.0x | Placeholder |
| Auto-Download | "Auto-Download" | "Off" | Future: toggle on/off | Placeholder |
| Stream Quality | "Stream Quality" | "Standard" | Future: Low/Standard/High | Placeholder |
| Clear Cache | "Clear Cache" | "2.1 MB used" | Clears Application.Storage | Placeholder |
| About | "About" | "YoCasts v1.0" | Shows version info | Active |

#### 5.7.2 — Settings Page Layout

```monkeyc
// Settings uses Menu2 — Garmin handles all layout, scrolling, and round adaptation
var menu = new WatchUi.Menu2({:title => "Settings"});
menu.addItem(new WatchUi.MenuItem("Playback Speed", "1.0x", :playbackSpeed, {}));
menu.addItem(new WatchUi.MenuItem("Auto-Download", "Off", :autoDownload, {}));
menu.addItem(new WatchUi.MenuItem("Stream Quality", "Standard", :streamQuality, {}));
menu.addItem(new WatchUi.MenuItem("Clear Cache", "2.1 MB", :clearCache, {}));
menu.addItem(new WatchUi.MenuItem("About", "YoCasts v1.0", :about, {}));
WatchUi.pushView(menu, new SettingsDelegate(), WatchUi.SLIDE_LEFT);
```

#### 5.7.3 — Settings Navigation

- **Entry:** Tap Settings pill on home menu → `pushView` with `SLIDE_LEFT`
- **Back:** Swipe right or KEY_ESC → `popView` with `SLIDE_RIGHT`
- **Item action:** Tap or SELECT → item-specific handler (placeholder toast for v1)

### 5.8 — Complete Draw Order

The home screen `onUpdate(dc)` must draw in this exact order:

```
1. Clear screen (black)
2. Draw "YoCasts" title at Y=12
3. Set clip to (0, 0, 390, 260)       ← scrollable zone only
4. Draw menu pills (Queue, Podcasts, Settings) adjusted for scroll offset
5. Clear clip
6. Draw dock background (solid black, Y=260–390)
7. Draw dock divider line (Y=260, 1px, 0x333333)
8. Draw podcast name (Y=268)
9. Draw episode title (Y=302)
10. Draw progress bar (Y=338)
11. Draw time display (Y=346)
12. Draw play/pause icon (Y=378)
```

---

## 6. List View Layout Spec

### 6.1 — List Screens (Queue, Podcasts, Episodes)

These screens use `WatchUi.Menu2`, which handles layout, scrolling, and round-screen adaptation natively. No custom drawing needed.

### 6.2 — Menu2 Item Spec

| Property | Value |
|---|---|
| Primary label | Episode/podcast title, truncated with `...` if too long |
| Sub-label | Context info (podcast name, duration, episode count) |
| Icon | Optional — v1 uses text-only |
| Selection behavior | Tap or SELECT button → navigate |

### 6.3 — Custom List View (If Menu2 Is Insufficient)

If we ever need a custom scrollable list (e.g., for richer item rendering), here's the spec:

```
Item height:    72 px (fits touch target minimum of 44px with padding)
Item gap:       4 px
Item margin:    adaptive per Y (getMarginAtY)
Item padding:   16 px horizontal, 10 px vertical
Corner radius:  14 px

Visible items:  ~4 items on screen (290px viewport ÷ 76px per item)
Scroll step:    76 px (one item)

Item layout:
┌──────────────────────────────────┐
│  Title text (FONT_SMALL)         │  Y + 12
│  Subtitle (FONT_XTINY)          │  Y + 44
└──────────────────────────────────┘
```

### 6.4 — Round Screen Edge Item Handling

Items near the top/bottom of the viewport get narrower. Use these rules:

1. **Fade effect:** Items partially within the dead zone (Y < 50 or Y > 340) should have reduced opacity or be clipped
2. **Width adaptation:** Each item's width matches the circle at its Y position
3. **Text truncation:** Recalculate available text width per item based on its Y position
4. **Center focus:** The currently-focused item should be rendered near the vertical center

---

## 7. Now Playing Screen Layout Spec

### 7.1 — Full-Screen Layout

```
┌──────────────────────────────────────────┐
│              ╭── Progress Arc ──╮         │
│            ╱                      ╲       │
│          ╱                          ╲     │
│         │                            │    │
│         │   Podcast Name             │    │   Y=80, FONT_XTINY, gray
│         │                            │    │
│         │   Episode Title            │    │   Y=130, FONT_MEDIUM, white
│         │   (2 lines max, marquee)   │    │   Y=186, FONT_MEDIUM (line 2)
│         │                            │    │
│         │         [⏮] [▶] [⏭]       │    │   Y=235 (button center)
│         │                            │    │
│         │    12:34 / 45:00           │    │   Y=290, FONT_TINY, gray
│         │                            │    │
│          ╲                          ╱     │
│            ╲                      ╱       │
│              ╰────────────────────╯       │
└──────────────────────────────────────────┘
```

### 7.2 — Element Positions

| Element | X | Y | Font | Color | Alignment |
|---|---|---|---|---|---|
| Progress arc | center | — | — | 0x55AAFF | `drawArc()` |
| Arc background | center | — | — | 0x333333 | `drawArc()` |
| Podcast name | 195 | 80 | FONT_XTINY (33px) | 0xAAAAAA | CENTER |
| Episode title L1 | 195 | 135 | FONT_MEDIUM (56px) | White | CENTER |
| Episode title L2 | 195 | 185 | FONT_MEDIUM (56px) | White | CENTER |
| Skip back icon | 110 | 245 | Custom drawn, r=24 | 0xAAAAAA | — |
| Play/pause icon | 195 | 245 | Custom drawn, r=32 | 0x55AAFF | — |
| Skip fwd icon | 280 | 245 | Custom drawn, r=24 | 0xAAAAAA | — |
| Time display | 195 | 300 | FONT_TINY (41px) | 0xAAAAAA | CENTER |

### 7.3 — Progress Arc

```monkeyc
// Background arc (full circle, dark gray)
dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
dc.setPenWidth(6);
dc.drawArc(195, 195, 185, Graphics.ARC_CLOCKWISE, 0, 360);

// Progress arc (accent blue, proportional to playback)
dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
var progressDegrees = (elapsed * 360.0 / total).toNumber();
// Arc starts at top (90°), goes clockwise
dc.drawArc(195, 195, 185, Graphics.ARC_CLOCKWISE, 90, 90 - progressDegrees);
```

| Property | Value |
|---|---|
| Center | (195, 195) |
| Radius | 185 px (10px inset from screen edge) |
| Pen width | 6 px |
| Background color | 0x333333 |
| Progress color | 0x55AAFF |
| Start angle | 90° (12 o'clock position) |
| Direction | Clockwise |

### 7.4 — Control Buttons

| Button | Center | Radius | Touch Radius | Icon | Color |
|---|---|---|---|---|---|
| Skip back (−30s) | (110, 245) | 24 px | 30 px | "◀◀" or custom | 0xAAAAAA |
| Play/pause | (195, 245) | 32 px | 38 px | ▶ / ❚❚ | 0x55AAFF |
| Skip forward (+30s) | (280, 245) | 24 px | 30 px | "▶▶" or custom | 0xAAAAAA |

**Touch radius** is larger than visual radius to provide a comfortable tap target. The gap between button edges (110+30=140 to 195-38=157) is 17px — sufficient to prevent mis-taps.

### 7.5 — Text Width Constraints

At key Y positions on the Now Playing screen:

| Y | Circle Width | −40px Margins | Available for Text |
|---|---|---|---|
| 80 (podcast name) | 315 | 275 | 275 px |
| 135 (episode L1) | 371 | 331 | 331 px |
| 185 (episode L2) | 389 | 349 | 349 px |
| 300 (time) | 329 | 289 | 289 px |

---

## 8. Color Palette

### 8.1 — Core Colors

| Name | Hex | RGB | Usage |
|---|---|---|---|
| **Background** | `0x000000` | (0, 0, 0) | Screen background (AMOLED true black) |
| **Primary text** | `0xFFFFFF` | (255, 255, 255) | Titles, labels, primary content |
| **Secondary text** | `0xAAAAAA` | (170, 170, 170) | Subtitles, timestamps, secondary info |
| **Accent blue** | `0x55AAFF` | (85, 170, 255) | Icons, highlights, progress, accent |
| **Pill background** | `0x1A1A2E` | (26, 26, 46) | Rounded pill fill (dark navy) |
| **Pill selected** | `0x2A2A4E` | (42, 42, 78) | Pill hover/pressed state |
| **Progress bg** | `0x333333` | (51, 51, 51) | Progress bar/arc background track |
| **Disabled** | `0x666666` | (102, 102, 102) | Inactive/unavailable items |
| **Error/warning** | `0xFF5555` | (255, 85, 85) | Error states, sync failures |
| **Success** | `0x55FF55` | (85, 255, 85) | Completion indicators |

### 8.2 — AMOLED Optimization

- **Black pixels = zero power.** Keep backgrounds pure black (`0x000000`)
- **Minimize bright areas.** Use accent color sparingly — for highlights only
- **White text on black** provides maximum contrast and minimal power draw
- **Avoid full-screen bright elements.** Large white/colored areas drain battery

---

## 9. Design Patterns & Anti-Patterns

### 9.1 — DO ✓

- **DO** compute pill widths based on the Y position's available circle width
- **DO** use `InputDelegate` (not `BehaviorDelegate`) for custom views with tap targets
- **DO** keep touch targets ≥ 56px tall
- **DO** center content vertically to maximize usable width
- **DO** use `dc.setClip()` for viewport/marquee text clipping
- **DO** use `dc.getTextWidthInPixels()` for pixel-accurate text truncation
- **DO** use `TEXT_JUSTIFY_CENTER | TEXT_JUSTIFY_VCENTER` for centered labels
- **DO** keep AMOLED-friendly dark backgrounds
- **DO** clamp scroll offset to [0, maxScroll]
- **DO** test hit zones with the scroll offset factored in

### 9.2 — DON'T ✗

- **DON'T** use `BehaviorDelegate` for custom drawn views that need `onTap()` coordinates — `onSelect()` will eat all taps
- **DON'T** use fixed-width pills that ignore round screen geometry — they'll clip or look wrong
- **DON'T** guess at font sizes — always reference the table in §2.1
- **DON'T** draw content in the dead zones (Y < 40 or Y > 350) — it'll be clipped by the circle
- **DON'T** use `using Toybox.X as X` — use `import Toybox.X` instead (types won't resolve)
- **DON'T** assume `Menu2` items can be updated after construction — they can't dynamically change
- **DON'T** animate scroll on Garmin — CPU is too limited, use instant snap
- **DON'T** rely on character-count truncation — use pixel-width measurement

### 9.3 — Menu2 vs Custom View Decision Guide

| Requirement | Use Menu2 | Use Custom View |
|---|---|---|
| Standard list of items | ✓ | |
| Need tap coordinate hit-testing | | ✓ |
| Rich item rendering (progress bars, icons) | | ✓ |
| Need consistent Garmin look & feel | ✓ | |
| Dynamic item content (updates after creation) | | ✓ |
| Minimum code / maintenance | ✓ | |
| Custom scroll behavior | | ✓ |

**YoCasts approach:**
- Home menu → Custom View with **split-dock layout** (scrollable pills + fixed NP dock overlay)
- Queue / Podcasts / Episodes → Menu2 (standard list, Garmin handles layout)
- Settings → Menu2 (standard list with placeholder items)
- Now Playing → Custom View (fully custom layout)

---

## Appendix A — Quick Reference Card

```
SCREEN:     390×390 round, center (195,195), radius 195
FONTS:      XTINY=33  TINY=41  SMALL=46  MEDIUM=56  LARGE=61
COLORS:     bg=000000  text=FFFFFF  sub=AAAAAA  accent=55AAFF  pill=1A1A2E
TOUCH:      Min 56px tall targets. Use InputDelegate for custom views.

HOME SCREEN (Split-Dock):
  SCROLL ZONE:  Y=0 to Y=260 (menu pills scroll here)
  DOCK ZONE:    Y=260 to Y=390 (fixed Now Playing overlay)
  PILLS:        60px tall, 12px gaps. Queue(Y=50), Podcasts(Y=122), Settings(Y=194)
  DOCK:         Podcast(Y=268), Episode(Y=302), Progress(Y=338), Time(Y=346)
  PLAY/PAUSE:   Touch zone Y=365–390 (dead zone, intentional)
  DOCK TAP:     Y=260–365 → NP screen, Y=365–390 → toggle playback
  CLIP:         dc.setClip(0,0,390,260) for scrollable; dock draws on top
```
