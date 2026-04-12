# Decision Log

## Garmin App MVP Scaffolding (2026-04-12)

**Author:** Kaylee (Garmin Dev)  
**Status:** Approved (implementation complete)

Created the full `YoCastsGarmin/` Connect IQ project with mock data service. The app has 5 screens, Menu2 navigation, and an `IPodcastService` interface that `MockPodcastService` implements. The mock data uses Dictionary keys matching PocketCasts API field names for easy swap to real service.

### Key Implementation Decisions

1. **Menu2 returned directly from `getInitialView()`** — no wrapper View for the home screen. Cleaner and avoids view stack issues.
2. **NowPlayingView uses delegate-holds-view-reference pattern** — delegate calls `setView()` to get a reference for controlling playback. This is the standard CIQ pattern since delegates can't access the view stack.
3. **Mock data normalizes the Up Next structure** — real API returns `{order: [...], episodes: {...}}` but mock uses a simple array. The real PocketCastsService should normalize this in its `getQueue()` method.
4. **No `static` functions used** — Monkey C supports them but they cause issues in some SDK versions. Instance methods throughout.
5. **`getInitialView()` has no explicit return type annotation** — SDK will reject override if typed.

### Impact

- **Mal (Architecture):** IPodcastService interface ready for service implementation. Dictionary models align with API response structure.
- **Zoe (Testing):** Fixtures available for UI logic testing without live API.
- **Team:** Scaffolding complete and ready for real API integration.
