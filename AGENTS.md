# AGENTS.md — guide for AI-assisted development

Read this first in every session. It encodes the project context that isn't
obvious from the file tree alone.

## What this app is

**nerds** (package name `nerds`, Android package `com.crigs.nerds_stickers`)
is a Flutter app that manages WhatsApp sticker packs:

- Browses **server-hosted sticker packs** (manifest from
  `https://stickers.crigs.io`, see `lib/constants/constants.dart`).
- Lets users **create/edit their own packs**: pick gallery/camera photos or
  server stickers, cut out backgrounds (interactive viewer), edit images,
  enforce WhatsApp's limits, and keep packs in sync with WhatsApp on-device.
- **Push notifications** (Firebase Cloud Messaging, topics `stickers-update`
  and optional `test-notifications`) trigger a refresh of server packs.

Primary target platform: **Android**. Other folders (ios/linux/windows/web,
macos) exist because Flutter scaffolds them, but features (especially the
native plugin below) are Android-first.

## Repository layout

```
lib/
  main.dart                  App entry: Firebase init, services init, FCM listeners
  constants/constants.dart   Server baseURL, app constants
  models/                    StickerData (server manifest model), UserPack (local pack)
  router/app_router.dart     go_router: all routes, args via state.extra Maps
  screens/                   one file per screen (see route list in app_router.dart)
  services/                  app services (singletons, see below)
  utils/                     webp encoding, WhatsApp pack status, config repair, cutout ops
  widgets/                   reusable UI (drawer, add-to-pack sheet, interactive viewer)
plugins/
  whatsapp_stickers_handler/  LOCAL plugin (path dep) bridging to Android's WhatsApp
                              sticker system (MethodChannel 'whatsapp_stickers_handler')
sticker_packs/               server-side seed content (8 numbered packs + sticker_packs.json)
```

## Architecture

- **State management**: plain Flutter — `ChangeNotifier` singletons +
  `ListenableBuilder`/`context.watch`-style consumption. No Riverpod/Bloc.
- **Routing**: `go_router` (`lib/router/app_router.dart`). Screen args are
  passed as `Map<String, dynamic>` via `state.extra` (not typed params) —
  add new screens there.
- **Screen → services**: screens call service singletons directly; there is
  no repository layer.
- **UI**: Material 3 theme defined in `main.dart` (default dark, teal accent).
  `analysis_options.yaml` uses `flutter_lints` + several explicit exclusions
  (platform dirs, `use_super_parameters`, etc.).

### Services (all singletons, initialized in `main()`)

| Service | Purpose |
|---|---|
| `LocalStorageService` | `SharedPreferences` persistence of the `UserPack` list **as a JSON string list** under key `user_packs`. Must `await initialize()` before use. Stores *absolute file paths*, not bytes. |
| `UserPackService` | Core domain service (`ChangeNotifier`). Create/delete packs, add/remove stickers (from URL, XFile, or raw bytes), version bumps, and **three migration passes** (PNG→webp, tray size limits, 512×512 square canvas). Packs live at `<docs>/user_packs/<id>/sticker_N.webp` + `tray.webp`. |
| `ServerStickerCacheService` | Downloads + caches the server manifest and sticker images under `<docs>/server_sticker_cache/` for offline use. |

### WhatsApp integration (the native plugin)

`plugins/whatsapp_stickers_handler` talks to Android via
`MethodChannel('whatsapp_stickers_handler')`. Key APIs (see
`lib/whatsapp_stickers_handler.dart` in the plugin):

- `isWhatsAppInstalled` / consumer vs business variants, `launchWhatsApp()`
- `getInstalledImageDataVersion(identifier)` — the version WhatsApp recorded
  for a pack (int as string).
- `isStickerPackInstalled(id)`
- `repairUserPackStickerRefsToWebp`, `regenerateConfigFile` — called via
  `lib/utils/sticker_config_utils.dart` (raw MethodChannel, no typed wrapper).

**Pack version scheme (important)**: `imageDataVersion` / `packVersion` are
**integer strings**. Any change to a pack's images must bump it by exactly +1
or WhatsApp won't refresh the pack in-app.

### WhatsApp limits (enforced; keep in sync if you touch encoding)

- 3–30 stickers per pack
- Stickers: WebP, min 512×512 **square** canvas
- Tray: WebP, 24–512 px, ≤ 50 KB
- Enforcement lives in `lib/utils/sticker_webp_utils.dart`
  (`encodeImageBytesToStickerWebP`, `encodeStickerBytesToTrayWebP`,
  `stickerWebpNeeds512SquareCanvas`, `trayWebpExceedsWhatsappLimits`)

## Where things live (layout B)

| What | Where | Role |
|---|---|---|
| `~/dev/nerds` (local machine, Omniarchy) | **this dir** | AI workbench: editing, `flutter analyze/test`, VS Code bridge. Flutter SDK at `~/flutter`. |
| `github.com/criggsy/nerds` | remote | Source of truth / sync hub. Push here after each task. |
| `~/GitHub/nerds` (server 192.168.0.210) | `ssh server` | Build/hosting copy: Android SDK + any device/emulator. Update with `git fetch origin && git checkout -B main origin/main` after pushing. |
| `/mnt/server/GitHub/nerds` | CIFS mount | Dead archive — an old view of the server copy. Do NOT edit or develop here (CIFS: no symlinks/inotify breaks tooling). |
| `sticker-updater` (server-side intake API, `https://stickers.crigs.io`) | `ssh server 'cd ~/GitHub/sticker-updater'` | Separate Python project, lives and runs on the server only. Not part of this repo. |

Rules of thumb: develop and verify locally, push to GitHub, pull on the server only
when building for Android or testing push-notifications.

## Common commands

```bash
export PATH="$HOME/flutter/bin:$PATH"
flutter pub get
flutter analyze            # should stay near-zero issues
flutter test               # (no tests yet)
dart format lib/
```

Dart SDK constraint: `>=3.5.3 <4.0.0`. Flutter stable 3.47.x verified.

## Conventions

- Services are singletons with `instance` getter and a private constructor;
  domain mutations go through `UserPackService` (not direct file writes from
  screens — though some screens do small file ops, keep that pattern minimal).
- Errors to the user via `SnackBar`/`AlertDialog`; logging via
  `lib/utils/logger.dart` (`log.i/log.e`, wraps `package:logger`).
- Screens keep UI logic inline in the State; extract to `widgets/` when
  reused in 2+ places.
- Commits: imperative subject (`feat:`, `fix:`, `chore:`), single coherent
  change per commit, verify with `flutter analyze` before committing.

## Gotchas

- **Never develop on the mount** (`/mnt/server/GitHub/...` is CIFS): no symlink/
  inotify support breaks Flutter tooling. Local `~/dev/nerds` is the workbench
  (layout B, see table above).
- `google-services.json` (Android, Firebase) is committed; updating Firebase
  config requires touching `android/app/google-services.json`.
- Push refresh goes through `StickersScreen.globalKey.currentState?.refreshStickerData()`
  (GlobalKey coupling — awkward but functional; don't widen it unnecessarily).
- `sticker_packs/` at repo root is **seed content** mirrored/staged by the
  server-side `sticker-updater` project — it is not loaded by the app at
  runtime, and the server's live manifest comes from `stickers.crigs.io`.
- The local plugin must stay a path dependency (`plugins/whatsapp_stickers_handler`)
  in `pubspec.yaml`; `flutter pub get` generates the plugin symlinks.
- `user_packs` metadata in SharedPreferences holds absolute paths — moving the
  app's documents dir or reinstalling invalidates them; migration passes in
  `UserPackService.load()` handle on-disk drift.
- No test suite exists yet. Verification = `flutter analyze` + running on an
  Android device/emulator for behavior changes.

## Verification

No test suite exists yet. `flutter analyze` must stay free of issues;
behavior changes are verified on an Android device/emulator.
