import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';

import 'package:nerds/widgets/drawer.dart';
import 'package:nerds/widgets/sticker_pack_item.dart';
import 'package:nerds/constants/constants.dart';
import 'package:nerds/models/sticker_data.dart';
import 'package:nerds/utils/logger.dart';

class StickersScreen extends StatefulWidget {
  /// 🔑 GlobalKey to access this screen from anywhere
  static final GlobalKey<StickersScreenState> globalKey = GlobalKey();

  const StickersScreen({super.key});

  @override
  State<StickersScreen> createState() => StickersScreenState();
}

class StickersScreenState extends State<StickersScreen> {
  bool _isLoading = true;
  StickerData? _stickerData;
  String? _loadError;

  /// 🔁 Refresh function callable from FCM or other screens
  Future<void> refreshStickerData() async {
    log.i("🔁 Triggered sticker refresh from external source...");
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    await _loadStickers();

    if (!mounted || _loadError != null) return;
    Fluttertoast.showToast(
      msg: "✅ Sticker packs refreshed",
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: Colors.black87,
      textColor: Colors.white,
      fontSize: 16.0,
    );
  }

  /// 📦 Loads sticker data from remote source
  Future<void> _loadStickers() async {
    try {
      final dio = Dio();
      final response = await dio.get<Map<String, dynamic>>(
        "$baseURL/json/sticker_packs.json",
      );

      if (!mounted) return;

      final payload = response.data;
      if (payload != null) {
        setState(() {
          _stickerData = StickerData.fromJson(payload);
          _isLoading = false;
          _loadError = null;
        });
        log.i("✅ Sticker data loaded successfully");
      } else {
        setState(() {
          _isLoading = false;
          _loadError = 'Empty response from server';
        });
        log.w("⚠️ Data is null");
      }
    } catch (e) {
      log.e("❌ Error loading stickers: $e");
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = '$e';
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadStickers();
  }

  void _popOrHome(BuildContext context) {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        _popOrHome(context);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: () => _popOrHome(context),
          ),
          title: const Text("Nerds Stickers"),
        ),
        drawer: const Drawer(child: MyDrawer()),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Could not load sticker packs',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _loadError = null;
                  });
                  _loadStickers();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final packs = _stickerData?.stickerPacks ?? [];
    return ListView.builder(
      itemCount: packs.length,
      itemBuilder: (context, index) {
        final pack = packs[index];
        return GestureDetector(
          onTap: () async {
            final updated = await context.push(
              '/sticker-pack-info',
              extra: {
                'stickerPack': pack,
              },
            );

            if (updated == true && mounted) {
              await refreshStickerData();
            }
          },
          child: StickerPackItem(stickerPack: pack),
        );
      },
    );
  }
}
