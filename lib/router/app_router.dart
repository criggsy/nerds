import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nerds/screens/home_screen.dart';
import 'package:nerds/screens/stickers_screen.dart';
import 'package:nerds/screens/sticker_pack_info.dart';
import 'package:nerds/screens/information_screen.dart';
import 'package:nerds/screens/notification_test_screen.dart';
import 'package:nerds/screens/folder_stickers_screen.dart';
import 'package:nerds/screens/folder_detail_screen.dart';

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
          return StickerPackInfoScreen(
            key: ValueKey(
                'sticker-pack-info-${args?['stickerPack']?.identifier ?? 'default'}'),
          );
        },
      ),
      GoRoute(
        path: '/folder-stickers',
        name: 'folder-stickers',
        builder: (context, state) => const FolderStickersScreen(),
      ),
      GoRoute(
        path: '/folder-detail',
        name: 'folder-detail',
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>?;
          final folder = args?['folder'];
          if (folder == null) {
            return const Scaffold(
              body: Center(child: Text('Folder not found')),
            );
          }
          return FolderDetailScreen(folder: folder);
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
