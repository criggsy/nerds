import 'package:flutter/material.dart';
import 'package:nerds/screens/stickers_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:nerds/utils/logger.dart';
import 'package:nerds/services/local_storage_service.dart';
import 'package:nerds/router/app_router.dart';
import 'package:go_router/go_router.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

enum PopupMenuOptions {
  staticStickers,
  remoteStickers,
  informations,
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Initialize local storage service
  await LocalStorageService.instance.initialize();

  // Subscribe to production topic
  await FirebaseMessaging.instance.subscribeToTopic("stickers-update");

  // 🔧 Subscribe to test topic for development/testing
  // You can enable this by setting an environment variable or debug flag
  const bool enableTestNotifications =
      bool.fromEnvironment('ENABLE_TEST_NOTIFICATIONS', defaultValue: false);
  if (enableTestNotifications) {
    await FirebaseMessaging.instance.subscribeToTopic("test-notifications");
    log.i(
        "🧪 Test notifications enabled - subscribed to 'test-notifications' topic");
  }

  // ✅ Check for notification that launched the app
  RemoteMessage? initialMessage =
      await FirebaseMessaging.instance.getInitialMessage();

  if (initialMessage != null) {
    log.i("📦 App launched from terminated state by a notification");
    // Delay the refresh until UI is ready
    Future.delayed(const Duration(seconds: 2), () {
      StickersScreen.globalKey.currentState?.refreshStickerData();
    });
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();

    // 🔔 Foreground push handling
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      log.i('🟢 Foreground notification: ${message.notification?.title}');
      StickersScreen.globalKey.currentState?.refreshStickerData();

      if (message.notification != null && navigatorKey.currentContext != null) {
        final context = navigatorKey.currentContext!;
        Future.delayed(Duration.zero, () {
          if (context.mounted) {
            showDialog(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: Text(message.notification!.title ?? 'Notification'),
                content: Text(message.notification!.body ?? ''),
                actions: [
                  TextButton(
                    child: const Text("OK"),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  )
                ],
              ),
            );
          }
        });
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      log.i('🚀 App opened from notification');

      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        // Navigate to stickers screen using GoRouter
        GoRouter.of(ctx).go('/');

        // Store context for async operation
        final context = ctx;
        Future.delayed(const Duration(milliseconds: 500), () {
          if (context.mounted) {
            StickersScreen.globalKey.currentState?.refreshStickerData();
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: AppRouter.router,
      title: "WhatsApp Stickers",
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.teal,
        scaffoldBackgroundColor: Colors.white,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.teal,
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(backgroundColor: Colors.black),
        cardColor: const Color(0xFF1E1E1E),
        iconTheme: const IconThemeData(color: Colors.tealAccent),
      ),
      themeMode: ThemeMode.dark, // 🔁 You can toggle this dynamically later
      debugShowCheckedModeBanner: false,
    );
  }
}
