import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nerds/screens/home_screen.dart';
import 'package:nerds/screens/stickers_screen.dart';
import 'package:nerds/screens/sticker_pack_info.dart';
import 'package:nerds/screens/information_screen.dart';
import 'package:nerds/screens/notification_test_screen.dart';
import 'package:nerds/screens/create_user_pack_screen.dart';
import 'package:nerds/screens/server_sticker_picker_screen.dart';
import 'package:nerds/screens/user_pack_detail_screen.dart';
import 'package:nerds/models/sticker_data.dart';
import 'package:nerds/services/user_pack_service.dart';

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/stickers',
        name: 'stickers',
        builder: (context, state) => StickersScreen(
          key: StickersScreen.globalKey,
        ),
      ),
      GoRoute(
        path: '/sticker-pack-info',
        name: 'sticker-pack-info',
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>?;
          final pack = args?['stickerPack'] as StickerPacks?;
          if (pack == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Sticker pack')),
              body: const Center(child: Text('Pack not found')),
            );
          }
          return StickerPackInfoScreen(
            key: ValueKey('sticker-pack-info-${pack.identifier}'),
            stickerPack: pack,
          );
        },
      ),
      GoRoute(
        path: '/user-packs/new',
        name: 'user-pack-new',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return CreateUserPackScreen(
            seedStickerUrl: extra?['seedStickerUrl'] as String?,
          );
        },
      ),
      GoRoute(
        path: '/pick-server-stickers',
        name: 'pick-server-stickers',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final slots = extra?['remainingSlots'] as int? ?? 30;
          return ServerStickerPickerScreen(remainingSlots: slots);
        },
      ),
      GoRoute(
        path: '/user-packs/:packId',
        name: 'user-pack-detail',
        builder: (context, state) {
          final id = state.pathParameters['packId']!;
          final pack = UserPackService.instance.getById(id);
          if (pack == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('My pack')),
              body: const Center(child: Text('Pack not found')),
            );
          }
          return UserPackDetailScreen(
            key: ValueKey('user-pack-$id'),
            pack: pack,
          );
        },
      ),
      GoRoute(
        path: '/information',
        name: 'information',
        builder: (context, state) => const InformationScreen(),
      ),
      GoRoute(
        path: '/notification-test',
        name: 'notification-test',
        builder: (context, state) => const NotificationTestScreen(),
      ),
    ],
  );
}
