# YoCasts — Garmin Layout Reference (Pixel-Perfect)

> **Version:** 1.0  
> **Author:** Kaylee (Garmin Dev)  
> **Date:** 2026-04-13  
> **Device:** Garmin Venu 4 41mm — 390×390 round AMOLED  
> **Status:** Authoritative reference — all UI code must conform to this spec

---

## Table of Contents

1. [Round Screen Geometry](#1-round-screen-geometry)
2. [Font Reference](#2-font-reference)
3. [Drawing API Reference](#3-drawing-api-reference)
4. [Touch & Input Reference](#4-touch--input-reference)
5. [Home Menu Layout Spec](#5-home-menu-layout-spec)
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

## 5. Home Menu Layout Spec

### 5.1 — Overview

The home menu is a custom `View` (not Menu2) with three tappable "pills":

1. **Queue** — shows episode count
2. **Podcasts** — shows subscription count
3. **Now Playing** — shows current episode with progress

All pills are rounded rectangles drawn with `fillRoundedRectangle()`.

### 5.2 — Layout Constants

```monkeyc
// Screen metrics
const SCREEN_W = 390;
const SCREEN_H = 390;
const CENTER_X = 195;
const CENTER_Y = 195;

// Viewport (visible scrollable area)
const VIEWPORT_TOP = 50;           // Y start of visible area
const VIEWPORT_HEIGHT = 290;       // 50 to 340
const VIEWPORT_BOTTOM = 340;       // Y end of visible area

// Pill dimensions
const PILL_HEIGHT = 72;            // Queue & Podcasts pills
const NP_PILL_HEIGHT = 110;        // Now Playing pill (larger)
const PILL_GAP = 16;               // vertical gap between pills
const PILL_CORNER_RADIUS = 18;     // rounded corners
const PILL_SIDE_MARGIN = 30;       // minimum margin from pill edge to screen edge

// Content layout
const CONTENT_PADDING_TOP = 10;    // padding from viewport top to first pill
const CONTENT_START_Y = VIEWPORT_TOP + CONTENT_PADDING_TOP;  // = 60

// Total content height
// pill(72) + gap(16) + pill(72) + gap(16) + np(110) = 286
const TOTAL_CONTENT_HEIGHT = 286;

// Scroll
const SCROLL_STEP = 80;           // pixels per swipe/button press
const MAX_SCROLL = 0;             // 286 fits in 290, so no scroll needed!

// Title
const TITLE_Y = 15;               // "YoCasts" title at top, outside viewport
const TITLE_FONT = Graphics.FONT_MEDIUM;  // 56px
```

### 5.3 — Pill Y Positions (No-Scroll State)

Since total content (286px) fits within viewport (290px), scrolling is not needed for 3 items.

| Element | Content Y | Screen Y | Height | Width at Y |
|---|---|---|---|---|
| "YoCasts" title | — | 15 | 56 px | ~380 px (near-full) |
| Queue pill | 0 | 60 | 72 px | see below |
| Podcasts pill | 88 | 148 | 72 px | see below |
| Now Playing pill | 176 | 236 | 110 px | see below |

### 5.4 — Pill Width Calculation

Each pill's width adapts to the round screen. The pill must fit within the circle at both its top and bottom Y positions:

```monkeyc
function getPillWidth(pillScreenY as Number, pillHeight as Number) as Number {
    // Find narrowest usable width across the pill's vertical span
    var minWidth = 390;
    // Check top edge, middle, and bottom edge
    var widthTop = getWidthAtY(pillScreenY);
    var widthMid = getWidthAtY(pillScreenY + pillHeight / 2);
    var widthBot = getWidthAtY(pillScreenY + pillHeight);
    minWidth = min3(widthTop, widthMid, widthBot);
    // Apply side margin
    return minWidth - (2 * PILL_SIDE_MARGIN);
}
```

**Computed pill widths:**

| Pill | Screen Y Range | Narrowest Screen Width | Pill Width (−60px margins) | X Start | X End |
|---|---|---|---|---|---|
| Queue | 60–132 | 281 px (at Y=60) | 221 px | 85 | 306 |
| Podcasts | 148–220 | 374 px (at Y=148) | 314 px | 38 | 352 |
| Now Playing | 236–346 | 253 px (at Y=346) | 193 px | 99 | 292 |

**Wait — this shows a problem!** The Queue pill at Y=60 is severely constrained (221px), and the NP pill near the bottom is even worse (193px). This is why a center-weighted layout is critical.

### 5.5 — REVISED Optimal Layout (Center-Weighted)

To maximize usable width, we center the content vertically so pills are near Y=195:

```
Total content height = 286px
Center content at Y=195 → start at Y = 195 - 286/2 = 52

Queue:      Y=52  to Y=124  → narrowest width at Y=52: 265px
Podcasts:   Y=140 to Y=212  → narrowest width at Y=140: 374px → at Y=212: 388px
NP:         Y=228 to Y=338  → narrowest width at Y=338: 265px
```

Better, but the edges are still tight. **Revised approach: reduce vertical span.**

```
PILL_HEIGHT = 68;       // shave 4px
NP_PILL_HEIGHT = 100;   // shave 10px
PILL_GAP = 12;          // tighter gaps
Total = 68 + 12 + 68 + 12 + 100 = 260px
Center at 195 → start Y = 195 - 130 = 65

Queue:      Y=65  to Y=133  → narrowest at Y=65 = 286px → pill width = 226px
Podcasts:   Y=145 to Y=213  → narrowest at Y=145 = 261px → pill width = 201px... NO!
```

The narrowest at Y=145 is actually at Y=213: `2√(195²-18²) = 389px`. And at Y=145: `2√(195²-50²) = 377px`. So pill width = 377 - 60 = 317px. Let me recalculate properly.

### 5.6 — FINAL Layout Spec (Verified)

Centering the 260px content at screen center:

| Pill | Y Start | Y End | Height | Width at Y_start¹ | Width at Y_end¹ | Min Width | Pill Width² | Pill X |
|---|---|---|---|---|---|---|---|---|
| Queue | 65 | 133 | 68 | 286 | 369 | 286 | 226 | 82 → 308 |
| Podcasts | 145 | 213 | 68 | 377 | 389 | 377 | 317 | 37 → 354 |
| Now Playing | 225 | 325 | 100 | 384 | 299 | 299 | 239 | 76 → 315 |

¹ From geometry table: width = 2√(195² − (y−195)²)  
² Pill width = min width − 60px (30px margin each side)

**Simplified approach: Use a FIXED pill width based on the tightest constraint.**

Rather than computing per-pill widths (which creates visual inconsistency), use a uniform approach:

```
FIXED_PILL_WIDTH = 280px
PILL_X = (390 - 280) / 2 = 55
```

At Y=65: usable width = 286px. Pill at 280px fits with 3px margin per side (inside circle). ✓  
At Y=325: usable width = 299px. Pill at 280px fits with 10px margin per side. ✓

**But wait: at Y=65, the circle has width 286. Our pill is 280. The gap to the circle edge is only 3px per side.** The pill itself should have 30px visual margin from the circle's chord. So we need to ensure `pill_width + 2*margin ≤ usable_width`.

At Y=65: 280 + 0 = 280 < 286 ✓ (tight but inside circle)  
At Y=325: 280 + 0 = 280 < 299 ✓

For visual breathing room, let's use variable-width pills that respect the curve:

### 5.7 — DEFINITIVE Layout: Adaptive-Width Pills

```monkeyc
const PILL_H = 68;                  // Standard pill height
const NP_H = 100;                   // Now Playing pill height
const GAP = 12;                     // Gap between pills
const PILL_MARGIN = 20;             // Margin from circle edge to pill edge
const PILL_RADIUS = 18;             // Corner radius
const PILL_INNER_PAD_X = 16;        // Horizontal padding inside pill
const PILL_INNER_PAD_Y = 10;        // Vertical padding inside pill

// Content starts 65px from top, centered vertically
const FIRST_PILL_Y = 65;

// Y positions
const QUEUE_Y = 65;                 // Queue pill: 65–133
const PODCASTS_Y = 145;             // Podcasts pill: 145–213
const NP_Y = 225;                   // Now Playing pill: 225–325
```

**Per-pill adaptive width:**

```monkeyc
function drawPill(dc, y, height) {
    // Find the narrowest circle width across this pill's span
    var minW = 390;
    for (var scanY = y; scanY <= y + height; scanY += 5) {
        var w = getWidthAtY(scanY);
        if (w < minW) { minW = w; }
    }
    var pillW = minW - 2 * PILL_MARGIN;
    var pillX = (390 - pillW) / 2;
    dc.fillRoundedRectangle(pillX, y, pillW, height, PILL_RADIUS);
}
```

**Computed dimensions:**

| Pill | Y Range | Limiting Y | Circle Width There | −40px Margins | Pill Width | Pill X |
|---|---|---|---|---|---|---|
| Queue | 65–133 | 65 | 286 | 246 | **246** | 72 |
| Podcasts | 145–213 | 145 | 377 | 337 | **337** | 27 |
| Now Playing | 225–325 | 325 | 299 | 259 | **259** | 66 |

**This creates pills that gracefully follow the round screen curvature.** The widest pill is in the middle (Podcasts at 337px), and the edge pills (Queue, NP) are narrower to fit within the circle.

### 5.8 — Pill Internal Layout

Each pill contains text and optional icon:

#### Queue Pill (68px tall, ~246px wide)

```
┌──────────────────────────────────┐  Y=65
│ [♫]  Queue                       │  ← FONT_SMALL (46px), white
│       5 episodes                 │  ← FONT_XTINY (33px), gray
└──────────────────────────────────┘  Y=133
```

| Element | X Position | Y Position | Font | Color |
|---|---|---|---|---|
| Music icon | pillX + 16 | 65 + 12 = 77 | Custom drawn | 0x55AAFF |
| "Queue" | pillX + 48 | 65 + 11 = 76 | FONT_SMALL | White |
| "5 episodes" | pillX + 48 | 65 + 11 + 28 = 104 | FONT_XTINY | 0xAAAAAA |

#### Podcasts Pill (68px tall, ~337px wide)

```
┌──────────────────────────────────────────────────┐  Y=145
│ [🎧]  Podcasts                                    │  ← FONT_SMALL, white
│        5 subscriptions                            │  ← FONT_XTINY, gray
└──────────────────────────────────────────────────┘  Y=213
```

| Element | X Position | Y Position | Font | Color |
|---|---|---|---|---|
| Headphone icon | pillX + 16 | 145 + 12 = 157 | Custom drawn | 0x55AAFF |
| "Podcasts" | pillX + 48 | 145 + 11 = 156 | FONT_SMALL | White |
| "5 subscriptions" | pillX + 48 | 145 + 11 + 28 = 184 | FONT_XTINY | 0xAAAAAA |

#### Now Playing Pill (100px tall, ~259px wide)

```
┌────────────────────────────────────────┐  Y=225
│  NOW PLAYING                           │  ← FONT_XTINY, accent blue
│  Episode Title Goes Here...            │  ← FONT_SMALL, white (marquee if overflow)
│  Podcast Name • 12:34 / 45:00    [▶]  │  ← FONT_XTINY, gray + play button
│  ████████░░░░░░░░░░░░░░░░░░░░░░       │  ← progress bar
└────────────────────────────────────────┘  Y=325
```

| Element | X Position | Y Position | Font | Color |
|---|---|---|---|---|
| "NOW PLAYING" | pillX + 16 | 225 + 8 = 233 | FONT_XTINY | 0x55AAFF |
| Episode title | pillX + 16 | 233 + 22 = 255 | FONT_SMALL | White |
| Podcast + time | pillX + 16 | 255 + 26 = 281 | FONT_XTINY | 0xAAAAAA |
| Play/pause btn | pillX + pillW - 40 | 266 (center) | Drawn circle r=16 | 0x55AAFF |
| Progress bar | pillX + 16 | 308 | — (2px rect) | 0x55AAFF / 0x333333 |

### 5.9 — Title Bar

```
"YoCasts" centered at Y=20, FONT_MEDIUM (56px), accent blue (0x55AAFF)
Position: (195, 20), TEXT_JUSTIFY_CENTER
```

This sits in the narrow top zone. At Y=20, usable width = 172px. "YoCasts" in FONT_MEDIUM ≈ 6 chars × 23px = ~138px. Fits comfortably.

### 5.10 — Scroll Behavior

With the revised layout (260px content in 290px viewport), **no scrolling is needed for the home menu**. All three pills are visible at once. This eliminates an entire class of bugs (scroll offset, hit-test adjustment, viewport clipping).

If a "Now Playing" section grows (e.g., longer progress display), scrolling can be added with:
- Viewport: Y=50 to Y=340 (290px)
- Scroll step: 80px per swipe
- Content drawn at `screenY = contentY - scrollOffset`
- `dc.setClip(0, 50, 390, 290)` for viewport clipping

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
- Home menu → Custom View (needs rich NP pill, adaptive pills)
- Queue / Podcasts / Episodes → Menu2 (standard list, Garmin handles layout)
- Now Playing → Custom View (fully custom layout)

---

## Appendix A — Quick Reference Card

```
SCREEN: 390×390 round, center (195,195), radius 195
FONTS:  XTINY=33  TINY=41  SMALL=46  MEDIUM=56  LARGE=61
COLORS: bg=000000  text=FFFFFF  sub=AAAAAA  accent=55AAFF  pill=1A1A2E
TOUCH:  Min 56px tall targets. Use InputDelegate for custom views.
PILLS:  68px Queue/Podcasts, 100px NP. 12px gaps. Adaptive width.
VIEWPORT: Y=50 to Y=340 (290px). No scroll needed for 3 pills.
SAFE ZONE: Y=55 to Y=335 (≥268px wide everywhere)
```
