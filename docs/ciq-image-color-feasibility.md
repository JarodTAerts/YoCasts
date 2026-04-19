# CIQ Image & Color Feasibility Report

> **Author:** Kaylee (Garmin Dev)  
> **Date:** 2026-07-15  
> **Status:** Research Complete  
> **Objective:** Evaluate podcast artwork thumbnails + per-item brand colors in list views

---

## Executive Summary

**Verdict: FEASIBLE with caveats.** CIQ has all the APIs we need — runtime image downloads, custom RGB colors, alpha blending, and rounded rectangles. The Venu 4's 768 KB memory budget easily handles 15 thumbnails. The main constraint is that **images can't be persisted to `Application.Storage`** — they live in graphics memory only and must be re-downloaded per app session. For the Podcasts list (which changes rarely), this is acceptable.

---

## 1. makeImageRequest() — Runtime Image Downloads

### API Signature (CIQ API 1.2.0+)

```monkeyc
Communications.makeImageRequest(
    url as String,
    parameters as Dictionary or Null,
    options as {
        :palette    as Array<Number>,
        :maxWidth   as Number,
        :maxHeight  as Number,
        :dithering  as Communications.Dithering,
        :packingFormat as Communications.PackingFormat
    },
    responseCallback as Method(responseCode as Number,
                               data as BitmapResource or BitmapReference or Null) as Void
) as Void
```

### Supported Formats (API 4.2.0+, Venu 4 ✅)

| Packing Format | Type | Best For | Transfer Size | Decode Speed |
|---|---|---|---|---|
| `PACKING_FORMAT_DEFAULT` | Lossless native | All images | Large | Very fast |
| `PACKING_FORMAT_PNG` | Lossless compressed | Icons, logos | Small | Slow |
| `PACKING_FORMAT_JPG` | Lossy compressed | Photos | Small | Medium |
| `PACKING_FORMAT_YUV` | Lossy compressed | Photos w/ alpha | Small | Fast |

**Recommendation:** Use `PACKING_FORMAT_JPG` for podcast artwork — smallest transfer, fast decode, acceptable quality at 30×30px.

### Key Constraints

- **One request at a time** — CIQ queues image requests sequentially. Loading 15 images will take several seconds.
- **Max response size** — same ~32 KB limit as `makeWebRequest()`, but 30×30 JPG is typically 1-3 KB, well under the limit.
- **HTTPS required** — PocketCasts artwork URLs use HTTPS, so no issues.
- **Error code `-1006` (UNABLE_TO_PROCESS_IMAGE)** — returned if the image format can't be decoded.
- **Phone/Wi-Fi required** — images are fetched over the network, not available offline.

### Code: Load an Image from URL

```monkeyc
import Toybox.Communications;
import Toybox.WatchUi;
import Toybox.Graphics;

class PodcastListView extends WatchUi.View {
    // Store downloaded bitmaps keyed by podcast index
    private var _thumbnails as Array<BitmapResource or BitmapReference or Null>;
    private var _loadIndex as Number = 0;

    function initialize() {
        View.initialize();
        _thumbnails = new Array<BitmapResource or BitmapReference or Null>[15];
        for (var i = 0; i < 15; i++) { _thumbnails[i] = null; }
    }

    //! Load a single podcast thumbnail
    function loadThumbnail(index as Number, artworkUrl as String) as Void {
        _loadIndex = index;
        Communications.makeImageRequest(
            artworkUrl,
            null,
            {
                :maxWidth  => 30,
                :maxHeight => 30,
                :packingFormat => Communications.PACKING_FORMAT_JPG
            },
            method(:onImageReceived)
        );
    }

    //! Callback — store the bitmap and trigger redraw
    function onImageReceived(responseCode as Number,
                             data as WatchUi.BitmapResource
                                  or Graphics.BitmapReference
                                  or Null) as Void {
        if (responseCode == 200 && data != null) {
            _thumbnails[_loadIndex] = data;
            // Chain-load the next thumbnail
            _loadIndex++;
            if (_loadIndex < _podcasts.size()) {
                loadThumbnail(_loadIndex,
                    (_podcasts[_loadIndex] as Dictionary)["artwork_url"] as String);
            }
            WatchUi.requestUpdate();
        }
    }
}
```

---

## 2. BitmapResource vs loadResource() — Caching

| Feature | `WatchUi.loadResource()` | `makeImageRequest()` |
|---|---|---|
| Source | Static app resources (drawables.xml) | Runtime URL download |
| Return type | `BitmapResource` | `BitmapResource or BitmapReference or Null` |
| Persistence | Always available (compiled into PRG) | Lives in graphics memory only |
| Can store in Application.Storage? | ❌ No | ❌ No |
| Memory pool | Graphics pool (auto-managed) | Graphics pool (auto-managed) |
| Can be evicted? | No | Possibly — check via `BitmapReference.isCached()` |

### Caching Strategy

**Images CANNOT be persisted.** `Application.Storage` only accepts `ValueType` (primitives, arrays, dictionaries) — not bitmap objects.

**Recommended approach:**
1. Store artwork URLs in `Application.Storage` alongside podcast metadata (already available from API: `artwork_url` field).
2. On view show, check if bitmaps are in memory. If not, re-download.
3. Use `BitmapReference.isCached()` to detect eviction before drawing.
4. Consider a fallback placeholder (colored circle with first letter of podcast name) while images load.

```monkeyc
function onUpdate(dc as Graphics.Dc) as Void {
    // Draw thumbnail if available, fallback to colored initial
    var bmp = _thumbnails[i];
    if (bmp != null) {
        if (bmp instanceof Graphics.BitmapReference && !(bmp as Graphics.BitmapReference).isCached()) {
            // Bitmap was evicted — re-download
            loadThumbnail(i, artworkUrl);
            drawFallbackIcon(dc, x, y, podcast);
        } else {
            dc.drawBitmap(x, y, bmp);
        }
    } else {
        drawFallbackIcon(dc, x, y, podcast);
    }
}

//! Draw a colored circle with the podcast's first letter as fallback
private function drawFallbackIcon(dc as Graphics.Dc, x as Number,
                                   y as Number, podcast as Dictionary) as Void {
    var color = podcast["author_color"] as Number;  // e.g. 0xFF5500
    dc.setColor(color, Graphics.COLOR_TRANSPARENT);
    dc.fillCircle(x + 15, y + 15, 15);
    dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
    var name = podcast["title"] as String;
    dc.drawText(x + 15, y + 4, Graphics.FONT_XTINY,
                name.substring(0, 1),
                Graphics.TEXT_JUSTIFY_CENTER);
}
```

---

## 3. Custom RGB Colors — dc.setColor() + fillRectangle()

### ✅ Full custom RGB support

Colors in CIQ are just `Number` values. Any hex value like `0xFF5500` works directly — no need to use `Graphics.COLOR_*` constants.

```monkeyc
// Direct hex color — works perfectly
dc.setColor(0xFF5500, Graphics.COLOR_TRANSPARENT);
dc.fillRoundedRectangle(x, y, width, height, radius);
```

### Graphics.createColor() (API 4.2.0+, Venu 4 ✅)

For constructing colors from individual ARGB channels:

```monkeyc
// Create a semi-transparent brand color overlay
var brandColor = Graphics.createColor(128, 255, 85, 0);  // 50% alpha, orange
dc.setColor(brandColor, Graphics.COLOR_TRANSPARENT);
dc.fillRoundedRectangle(x, y, width, height, 12);
```

### Converting Proxy Hex Strings to Colors

The proxy returns `author_color` as a string (e.g., `"#F44336"`). Convert to a CIQ color integer:

```monkeyc
//! Parse "#RRGGBB" hex string to CIQ color Number
function parseHexColor(hex as String) as Number {
    if (hex.length() < 7) { return 0x333333; }  // fallback dark gray
    // Skip the '#' prefix
    var r = hexToDec(hex.substring(1, 3));
    var g = hexToDec(hex.substring(3, 5));
    var b = hexToDec(hex.substring(5, 7));
    return (r << 16) | (g << 8) | b;
}

//! Convert 2-char hex string to decimal (0-255)
function hexToDec(hex as String) as Number {
    var result = 0;
    for (var i = 0; i < hex.length(); i++) {
        var c = hex.substring(i, i + 1);
        var val = 0;
        if (c.equals("A") || c.equals("a")) { val = 10; }
        else if (c.equals("B") || c.equals("b")) { val = 11; }
        else if (c.equals("C") || c.equals("c")) { val = 12; }
        else if (c.equals("D") || c.equals("d")) { val = 13; }
        else if (c.equals("E") || c.equals("e")) { val = 14; }
        else if (c.equals("F") || c.equals("f")) { val = 15; }
        else { val = c.toNumber(); }
        result = result * 16 + val;
    }
    return result;
}
```

**Alternative:** Have the proxy return colors as integers directly (e.g., `"author_color_int": 16007990`) to avoid on-watch parsing.

---

## 4. Memory Impact Analysis

### Venu 4 41mm Memory Budget

| Resource | Value |
|---|---|
| **Foreground app memory** | **768 KB** |
| **Display color depth** | 16-bit (65,536 colors) |
| **Bytes per pixel (16-bit)** | 2 bytes |
| **Bytes per pixel (32-bit w/ alpha)** | 4 bytes |

### Thumbnail Memory Calculation

For 30×30px thumbnails on a 16-bit display:

```
Per thumbnail: 30 × 30 × 2 = 1,800 bytes = 1.76 KB
15 thumbnails: 15 × 1,800 = 27,000 bytes = 26.4 KB
```

With alpha channel (32-bit, needed for transparency):

```
Per thumbnail: 30 × 30 × 4 = 3,600 bytes = 3.5 KB
15 thumbnails: 15 × 3,600 = 54,000 bytes = 52.7 KB
```

### Total Memory Budget

| Component | Estimate |
|---|---|
| App code + strings | ~50 KB |
| View state / variables | ~10 KB |
| Service + cache dictionaries | ~30 KB |
| **15 thumbnails (16-bit)** | **~27 KB** |
| **15 thumbnails (32-bit)** | **~53 KB** |
| **Total (16-bit)** | **~117 KB** |
| **Total (32-bit)** | **~143 KB** |
| **Remaining (16-bit)** | **~651 KB** |
| **Remaining (32-bit)** | **~625 KB** |

**Verdict:** ✅ **Plenty of headroom.** Even with 32-bit alpha thumbnails we use under 20% of available memory. The earlier "no artwork in v1" decision was based on the 128 KB minimum-spec assumption — the Venu 4 has 6× more memory.

### Optimization: Smaller Thumbnails

If we go 24×24px instead of 30×30:

```
Per thumbnail (16-bit): 24 × 24 × 2 = 1,152 bytes = 1.13 KB
15 thumbnails: 15 × 1,152 = 16.9 KB
```

---

## 5. Alpha / Transparency Support

### ✅ Supported on Venu 4

CIQ 4.0.0+ supports alpha blending:

- **`Graphics.createColor(alpha, r, g, b)`** — creates ARGB color values
- **`Graphics.BLEND_MODE_SOURCE_OVER`** — standard Porter-Duff compositing: `S + (1 - S.a) * D`
- **`dc.setBlendMode(Graphics.BLEND_MODE_SOURCE_OVER)`** — enable alpha compositing
- **`BufferedBitmap` with `:alphaBlending => Graphics.ALPHA_BLENDING_FULL`** — full alpha for off-screen surfaces
- **`COLOR_TRANSPARENT`** — fully transparent background color

### Using Alpha for Text on Colored Backgrounds

```monkeyc
// Draw a semi-transparent brand color background behind text
dc.setColor(Graphics.createColor(60, 255, 85, 0), Graphics.COLOR_TRANSPARENT);
dc.fillRoundedRectangle(pillX, pillY, pillW, PILL_HEIGHT, 12);

// Draw text on top — fully opaque white
dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
dc.drawText(pillX + 48, pillY + 8, Graphics.FONT_SMALL, title,
            Graphics.TEXT_JUSTIFY_LEFT);
```

**Note:** `BLEND_MODE_MULTIPLY` and `BLEND_MODE_ADDITIVE` require a GPU and are marked "Only supported on devices with GPU." The Venu 4 has GPU support (AMOLED display), so these should work.

---

## 6. Rounded Corners / Pill Shapes

### ✅ Already in use

We already draw rounded rectangles in `HomeMenuView.mc`:

```monkeyc
dc.fillRoundedRectangle(pillX, drawY, PILL_WIDTH, PILL_HEIGHT, PILL_CORNER_RADIUS);
```

For podcast list items with brand-color backgrounds:

```monkeyc
// Per-item colored background with rounded corners
var brandColor = podcast["author_color_int"] as Number;
// Dim the color for AMOLED (avoid full-brightness backgrounds)
var dimColor = dimForAmoled(brandColor, 40);  // 40% brightness
dc.setColor(dimColor, Graphics.COLOR_TRANSPARENT);
dc.fillRoundedRectangle(itemX, itemY, itemW, itemH, 10);
```

### Dimming Colors for AMOLED

Full-brightness brand colors would burn the eyes on AMOLED. Dim them:

```monkeyc
//! Dim a color to a percentage of brightness (0-100)
function dimForAmoled(color as Number, pct as Number) as Number {
    var r = ((color >> 16) & 0xFF) * pct / 100;
    var g = ((color >> 8) & 0xFF) * pct / 100;
    var b = (color & 0xFF) * pct / 100;
    return (r << 16) | (g << 8) | b;
}
```

---

## 7. List Rendering — Integration with Existing Views

### HomeMenuView (Custom View) — ✅ Easy

Our `HomeMenuView` already uses a fully custom draw loop. Adding icons and colors is straightforward.

### SubscribedView / QueueView / EpisodeListView (Menu2) — ⚠️ Limited

These use `WatchUi.Menu2`, which does **not** support:
- Custom per-item background colors
- Bitmap icons from runtime-downloaded images
- Custom draw calls per item

**Menu2 does support:**
- `MenuItem` with icon (but only from static `BitmapResource` via `loadResource()`, not downloaded images)
- Custom `MenuItem` subclasses with custom draw delegates (API 3.2.0+ — `CustomMenuItem`)

### CustomMenuItem — The Bridge

`WatchUi.CustomMenuItem` (API 3.2.0+) allows fully custom drawing per menu item:

```monkeyc
class PodcastMenuItem extends WatchUi.CustomMenuItem {
    private var _title as String;
    private var _brandColor as Number;
    private var _thumbnail as BitmapResource or BitmapReference or Null;

    function initialize(id as Object, title as String,
                        brandColor as Number) {
        CustomMenuItem.initialize(id, {});
        _title = title;
        _brandColor = brandColor;
        _thumbnail = null;
    }

    function setThumbnail(bmp as BitmapResource or BitmapReference or Null) as Void {
        _thumbnail = bmp;
    }

    //! Called by Menu2 to draw this item
    function draw(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();

        // 1. Draw brand-color background (dimmed for AMOLED)
        var dimColor = dimForAmoled(_brandColor, 25);
        dc.setColor(dimColor, Graphics.COLOR_BLACK);
        dc.clear();

        // 2. Draw thumbnail on the left (or fallback circle)
        var iconX = 8;
        var iconY = (h - 30) / 2;
        if (_thumbnail != null) {
            dc.drawScaledBitmap(iconX, iconY, 30, 30, _thumbnail);
        } else {
            // Fallback: colored circle with initial
            dc.setColor(_brandColor, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(iconX + 15, iconY + 15, 15);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(iconX + 15, iconY + 4, Graphics.FONT_XTINY,
                        _title.substring(0, 1),
                        Graphics.TEXT_JUSTIFY_CENTER);
        }

        // 3. Draw title text to the right of the icon
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(iconX + 38, 8, Graphics.FONT_SMALL, _title,
                    Graphics.TEXT_JUSTIFY_LEFT);
    }
}
```

### Full Custom View Alternative

If `CustomMenuItem` proves too limiting, we can convert the Podcasts list to a fully custom `View` like `HomeMenuView` — manual scrolling, manual hit detection, full draw control. This is more work but gives total freedom.

---

## 8. Sample Apps & References

| Sample | What it shows | Location |
|---|---|---|
| **ImageDownloader** | `makeImageRequest()` with packing formats | CIQ SDK samples/ImageDownloader |
| **MonkeyMusic** | Audio provider with custom list rendering | garmin/connectiq-apps on GitHub |
| **garmin-podcasts** | Open-source podcast app (community) | GitHub search "garmin podcasts connect iq" |
| **drawBitmap2** | Tint, transform, sub-region rendering | API docs Dc.drawBitmap2() |

### drawBitmap2() — Advanced Bitmap Rendering

`dc.drawBitmap2()` (API 4.2.0+) supports:
- `:tintColor` — colorize grayscale bitmaps
- `:filterMode` — bilinear filtering for scaled images
- `:transform` — AffineTransform for rotation/scaling
- Sub-region rendering via `:bitmapX`, `:bitmapY`, `:bitmapWidth`, `:bitmapHeight`

```monkeyc
dc.drawBitmap2(x, y, bitmap, {
    :bitmapWidth => 30,
    :bitmapHeight => 30,
    :filterMode => Graphics.FILTER_MODE_BILINEAR
});
```

---

## 9. Recommended Implementation Plan

### Phase 1: Brand Colors (Low Risk, High Impact)

1. Add `author_color` to podcast data model (proxy already whitelists this field).
2. Convert Podcasts list from `Menu2` to either `CustomMenuItem` or full custom `View`.
3. Draw dimmed brand-color rounded-rect backgrounds per item.
4. Add first-letter fallback icons (colored circles).
5. Memory cost: ~0 KB additional (colors are just integers).

### Phase 2: Artwork Thumbnails (Medium Risk, High Impact)

1. Add thumbnail download queue — load images sequentially after podcast list is shown.
2. Store bitmap references in a per-view array.
3. Draw bitmaps at 30×30px with `drawScaledBitmap()` or `drawBitmap2()`.
4. Show first-letter fallback while images load.
5. Memory cost: ~27 KB for 15 thumbnails (16-bit).
6. UX: Images appear progressively as they download (1-3 seconds total for 15 small JPGs).

### Phase 3: Polish

1. Add `drawBitmap2()` with bilinear filtering for smoother scaling.
2. Consider caching artwork URLs to skip lookup on next session.
3. Add loading shimmer/fade animation for thumbnails.

---

## 10. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| makeImageRequest() fails on some URLs | Medium | Low | Fallback to first-letter icon, log error |
| 15 sequential downloads too slow | Low | Medium | Progressive loading with fallback; user sees text immediately |
| Graphics memory eviction | Low | Low | Check `isCached()` before draw, re-download if evicted |
| Menu2 → CustomMenuItem complexity | Medium | Medium | Prototype first; fall back to full custom View if needed |
| AMOLED burn-in from bright colors | Low | Medium | Dim all brand colors to 20-30% brightness |
| Hex color parsing edge cases | Low | Low | Have proxy return integer colors instead of hex strings |

---

## Conclusion

**All six capabilities are confirmed feasible on the Venu 4 41mm:**

1. ✅ `makeImageRequest()` loads PNG/JPG/YUV from URLs at runtime
2. ✅ Downloaded bitmaps can be stored in memory (not disk) and drawn with `drawBitmap()`
3. ✅ `dc.setColor()` + `fillRoundedRectangle()` draws colored backgrounds per item
4. ✅ 15 thumbnails at 30×30 use ~27 KB — well within 768 KB budget
5. ✅ Custom RGB colors work as plain hex integers (`0xFF5500`)
6. ✅ Custom views support full draw control; `CustomMenuItem` enables per-item rendering in Menu2

**Recommendation:** Start with Phase 1 (brand colors only) — it's zero additional memory, zero network requests, and immediately makes the podcast list more visually distinctive. Add artwork thumbnails in Phase 2 once the custom list rendering is stable.
