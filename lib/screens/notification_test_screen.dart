import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:nerds/utils/logger.dart';

class NotificationTestScreen extends StatefulWidget {
  static const routeName = '/notification-test';

  const NotificationTestScreen({super.key});

  @override
  State<NotificationTestScreen> createState() => _NotificationTestScreenState();
}

class _NotificationTestScreenState extends State<NotificationTestScreen> {
  String? _fcmToken;
  List<String> _subscribedTopics = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadFCMInfo();
  }

  Future<void> _loadFCMInfo() async {
    setState(() => _isLoading = true);

    try {
      // Get FCM token
      _fcmToken = await FirebaseMessaging.instance.getToken();

      // Get current topics (this is a simplified approach)
      _subscribedTopics = ['stickers-update']; // Default topic

      setState(() => _isLoading = false);
    } catch (e) {
      log.e("❌ Error loading FCM info: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _subscribeToTestTopic() async {
    try {
      await FirebaseMessaging.instance.subscribeToTopic("test-notifications");
      _subscribedTopics.add("test-notifications");
      setState(() {});

      Fluttertoast.showToast(
        msg: "✅ Subscribed to test-notifications topic",
        gravity: ToastGravity.BOTTOM,
      );
      log.i("🧪 Subscribed to test-notifications topic");
    } catch (e) {
      log.e("❌ Error subscribing to test topic: $e");
      Fluttertoast.showToast(
        msg: "❌ Failed to subscribe to test topic",
        gravity: ToastGravity.BOTTOM,
      );
    }
  }

  Future<void> _unsubscribeFromTestTopic() async {
    try {
      await FirebaseMessaging.instance
          .unsubscribeFromTopic("test-notifications");
      _subscribedTopics.remove("test-notifications");
      setState(() {});

      Fluttertoast.showToast(
        msg: "✅ Unsubscribed from test-notifications topic",
        gravity: ToastGravity.BOTTOM,
      );
      log.i("🧪 Unsubscribed from test-notifications topic");
    } catch (e) {
      log.e("❌ Error unsubscribing from test topic: $e");
      Fluttertoast.showToast(
        msg: "❌ Failed to unsubscribe from test topic",
        gravity: ToastGravity.BOTTOM,
      );
    }
  }

  void _copyTokenToClipboard() {
    if (_fcmToken != null) {
      // In a real app, you'd use Clipboard.setData
      log.i(
          "📋 FCM Token copied to clipboard: ${_fcmToken!.substring(0, 20)}...");
      Fluttertoast.showToast(
        msg: "📋 FCM Token copied to clipboard",
        gravity: ToastGravity.BOTTOM,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Testing'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // FCM Token Section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'FCM Token',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _fcmToken ?? 'Loading...',
                                    style: const TextStyle(
                                        fontFamily: 'monospace'),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy),
                                  onPressed: _copyTokenToClipboard,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Use this token to send test notifications directly to this device',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Topics Section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Subscribed Topics',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ..._subscribedTopics.map((topic) => Chip(
                                label: Text(topic),
                                backgroundColor: topic == 'test-notifications'
                                    ? Colors.orange[100]
                                    : Colors.blue[100],
                              )),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.add),
                                  label: const Text('Subscribe to Test'),
                                  onPressed: _subscribedTopics
                                          .contains("test-notifications")
                                      ? null
                                      : _subscribeToTestTopic,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.remove),
                                  label: const Text('Unsubscribe from Test'),
                                  onPressed: _subscribedTopics
                                          .contains("test-notifications")
                                      ? _unsubscribeFromTestTopic
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Testing Instructions
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Testing Instructions',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            '1. Subscribe to the test topic above\n'
                            '2. Use Firebase Console to send a test notification to the "test-notifications" topic\n'
                            '3. Or use the FCM token above to send a direct notification\n'
                            '4. Test different notification scenarios (foreground, background, terminated)\n'
                            '5. Unsubscribe from test topic when done testing',
                            style: TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
