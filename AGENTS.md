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

## Where things live (layout A — server-first, since 2026-10-07)

Server connection: `ssh -o BatchMode=yes crigs@192.168.0.210 '...'` (the Mac's SSH config alias is **capital-S `Server`** — do NOT use lowercase `server`: it misses the config block and the tailnet mDNS resolves that name to a different host that refuses SSH).

| What | Where | Role |
|---|---|---|
| `~/GitHub/nerds` (server 192.168.0.210) | **primary workbench** | Editing, `flutter analyze`/`test`, Android builds (`~/flutter` 3.47.x, `~/Android` SDK), device/emulator + FCM testing. |
| `github.com/criggsy/nerds` | remote | Source of truth / sync hub. **Mac is the sole pusher** — the server has no GitHub creds. |
| Local mirror (macbook-air `~/Documents/dev/nerds`; Omniarchy `~/dev/nerds`) | push relay / offline fallback | Not the development site. Sync from the server (repo + `.git`) then `git push origin main`: `rsync -az -e 'ssh -o BatchMode=yes' crigs@192.168.0.210:GitHub/nerds/ <local-mirror>/` |
| `/mnt/server/GitHub/nerds` (Omniarchy only) | CIFS mount | Dead archive — an old view of the server copy. Do NOT edit or develop here (CIFS: no symlinks/inotify breaks tooling). |
| `sticker-updater` (server-side intake API, `https://stickers.crigs.io`) | server `~/GitHub/sticker-updater` | Separate Python project, lives and runs on the server only. Not part of this repo. |

Flow for every task:
1. **Server**: edit → `flutter analyze` → `flutter test` → (behavior changes: build/install on device or test FCM) → `git commit`.
2. **Mac**: rsync the repo (incl. `.git`) off the server → `git push origin main` (verify the remote is an ancestor of the server HEAD first — `git fetch`, check `git log origin/main..main` makes sense).
3. Resuming on a stale copy: clean tree → `git fetch origin && git checkout -B main origin/main`.

Rules of thumb: develop, verify, and build on the server; GitHub is the checkpoint; the Mac is the only machine that pushes.

## Common commands

Run on the **server** in `~/GitHub/nerds` (same commands work in the local mirrors).

```bash
export PATH="$HOME/flutter/bin:$PATH"
flutter pub get
flutter analyze            # should stay near-zero issues
flutter test               # (no tests yet)
dart format lib/
```

Dart SDK constraint: `>=3.5.3 <4.0.0`.

**Toolchain (server `~/flutter`; local mirrors must be ≥ this too): floor versions, do not build with older SDKs.**

| Piece | Version | Where |
|---|---|---|
| Flutter | **≥ 3.47.2** (stable) | server `~/flutter` is 3.47.2 (upgraded 2026-08 from 3.35.3); macbook-air `~/Documents/dev/flutter` is 3.47.6; Omniarchy `~/flutter` |
| Gradle (wrapper) | **8.14.3** (`-all` app / `-bin` plugin) | `android/gradle/wrapper/gradle-wrapper.properties` + plugin copy. 8.14.0 404s on the distribution CDN — don't pin it. |
| Android Gradle Plugin | **8.11.1** | `android/settings.gradle` (`com.android.application`) + plugin `android/build.gradle` buildscript classpath |
| Kotlin (KGP) | **2.2.20** | `android/settings.gradle` + plugin `ext.kotlin_version` |

Flutter 3.47's Gradle plugin hard-fails builds below these minimums (no
"skip" flag worth using). If a build fails with "X version is lower than
Flutter's minimum supported version", bump the corresponding line above, commit,
and push via the Mac (the server has no GitHub creds).

Android builds: `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk` (server).

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
  inotify support breaks Flutter tooling. The server-native `~/GitHub/nerds` is the
  workbench (see "Where things live").
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
