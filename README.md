# nerds — WhatsApp Sticker Packs

A Flutter app for discovering, creating, and keeping WhatsApp sticker packs
up to date.

- Browse **server-hosted sticker packs** and see install/update status in
  WhatsApp (consumer & business).
- **Create your own packs** (3–30 stickers) from your gallery or server
  stickers, with background cutout editing, image editing, and automatic
  WebP sizing to WhatsApp's limits (512×512 stickers, ≤50 KB tray).
- **Push updates**: FCM topics notify the app when server packs change, and
  the app refreshes pack data accordingly.
- Works against WhatsApp via a local Android plugin
  (`plugins/whatsapp_stickers_handler`).

## Getting started

```bash
# Requirements: Flutter (stable, 3.4x+), Android SDK with API 34
export PATH="$HOME/flutter/bin:$PATH"
flutter pub get
flutter run          # on an Android device/emulator
```

- **Android package**: `com.crigs.nerds_stickers`
- **Firebase**: `android/app/google-services.json` is committed; the app
  subscribes to the `stickers-update` FCM topic (and `test-notifications`
  when built with `--dart-define=ENABLE_TEST_NOTIFICATIONS=true`).
- **Server**: sticker manifest is fetched from `https://stickers.crigs.io`
  (configurable in `lib/constants/constants.dart`).

## Project structure

```
lib/
  main.dart        entrypoint: Firebase, services, FCM handling
  router/          go_router routes & screen args
  screens/         one file per screen
  services/        UserPackService, ServerStickerCacheService, LocalStorageService
  models/          server pack manifest model, local UserPack model
  utils/           webp encoding (WhatsApp limits), pack status, cutout ops
  widgets/         shared UI components
plugins/
  whatsapp_stickers_handler/   local Android plugin for WhatsApp pack integration
sticker_packs/                 seed/staging sticker content (not loaded at runtime)
```

More detail for contributors and AI dev sessions: **`AGENTS.md`**.

## Developing

```bash
flutter analyze      # keep clean
flutter test         # (test suite not yet established)
dart format lib/
```
