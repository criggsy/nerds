import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:nerds/utils/logger.dart';

/// Renders FCM `notification`-payload messages as real Android system
/// notifications while the app process is alive (foreground/background).
///
/// `firebase_messaging` hands those messages to `onMessage` when the app is
/// running, but does not show anything itself — only when the process is
/// terminated does FCM's own service render the banner. This service closes
/// that gap so the user sees a heads-up in every app state.
class ForegroundNotificationService {
  ForegroundNotificationService._();

  static final ForegroundNotificationService instance =
      ForegroundNotificationService._();

  static const String channelId = 'stickers-update';
  static const int _stableId = 4821;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: android),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          channelId,
          'Sticker updates',
          description: 'Server-sticker-pack updates',
          importance: Importance.max,
        ));
  }

  Future<void> show(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    try {
      await _plugin.show(
        id: _stableId, // stable id: replace rather than stack repeats
        title: notification.title,
        body: notification.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            'Sticker updates',
            channelDescription: 'Server-sticker-pack updates',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
      );
    } catch (e) {
      log.e('Foreground notification display failed: $e');
    }
  }
}
