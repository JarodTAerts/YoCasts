# Skill: Garmin Custom View with Tap-Target Buttons

## When to Use
When building a full-screen custom `WatchUi.View` on Garmin Connect IQ that needs tappable circular or rectangular buttons with coordinate-based hit testing (e.g., detail screens, player controls, action screens).

## Pattern

### View Class (extends WatchUi.View)
- Declare button positions as `const` (`CX`, `CY`, `R`) and expose touch radius as `public const`
- Draw buttons as `fillCircle` with icons inside (play triangle via `fillPolygon`, arrows, checkmarks)
- Add text labels below buttons with `FONT_XTINY`
- Use brand colors from `CacheManager.loadPodcasts()` + `DataFormat.lookupPodcastColors()`

### Delegate Class (extends WatchUi.InputDelegate)
- **MUST use InputDelegate, NOT BehaviorDelegate** — BehaviorDelegate converts all taps into `onSelect()` and kills `onTap()` coordinate-based hit testing
- Use `onTap(ClickEvent)` with `getCoordinates()` and circle hit test: `(dx*dx + dy*dy) <= (r*r)`
- **Hardcode button positions in delegate** — Monkey C `const` can't be accessed statically across classes
- Add `onSwipe(SWIPE_RIGHT)` → `popView` for back navigation
- Add `onKey(KEY_ESC)` → `popView` for physical back button
- Map `KEY_ENTER/KEY_START` to primary action

### Marquee Text (optional)
- Timer.Timer at 150ms, 3-phase: pause (15 ticks) → scroll (2px/tick) → pause (10 ticks) → reset
- Use `dc.setClip()` / `dc.clearClip()` for container clipping
- `onMarqueeTick()` must be `public` (not private) for method reference

## Reference Files
- `source/views/EpisodeDetailView.mc` — Play + Download buttons at bottom
- `source/views/NowPlayingView.mc` — Skip/Play/Skip buttons at center
- `source/views/DownloadsView.mc` — Item tap zones (rectangular hit test)

## Anti-Patterns
- ❌ `BehaviorDelegate` with `onTap()` — `onTap` never fires because `onSelect` consumes first
- ❌ `ClassName.CONST` for cross-class constant access — fails in Monkey C strict mode
- ❌ `fillPolygon` with `as Array<Array<Number>>` cast — use untyped array literals
