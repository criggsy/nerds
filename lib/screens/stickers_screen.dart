import 'package:flutter/material.dart';
import 'package:nerds/Widgets/drawer.dart';
import 'package:nerds/constants/constants.dart';
import 'package:nerds/models/sticker_data.dart';
import 'package:dio/dio.dart';
import 'package:nerds/Widgets/sticker_pack_item.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:nerds/utils/logger.dart';

class StickersScreen extends StatefulWidget {
  static const routeName = '/';

  /// 🔑 GlobalKey to access this screen from anywhere
  static final GlobalKey<StickersScreenState> globalKey = GlobalKey();

  const StickersScreen({super.key});

  @override
  State<StickersScreen> createState() => StickersScreenState();
}

class StickersScreenState extends State<StickersScreen> {
  bool _isLoading = false;

  late StickerData stickerData;
  late Dio dio;
  var downloads = <Future>[];
  Response? data;

  /// 🔁 Refresh function callable from FCM or other screens
  Future<void> refreshStickerData() async {
    log.i("🔁 Triggered sticker refresh from external source...");
    setState(() => _isLoading = true);
    await _loadStickers();

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
      dio = Dio();
      data = await dio.get("$baseURL/json/sticker_packs.json");

      if (data?.data != null) {
        setState(() {
          stickerData = StickerData.fromJson(data!.data);
          _isLoading = false;
        });
        log.i("✅ Sticker data loaded successfully");
      } else {
        setState(() => _isLoading = false);
        log.w("⚠️ Data is null");
      }
    } catch (e) {
      setState(() => _isLoading = false);
      log.e("❌ Error loading stickers: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    _isLoading = true;
    _loadStickers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Nerds Stickers")),
      drawer: const Drawer(child: MyDrawer()),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: stickerData.stickerPacks?.length ?? 0,
              itemBuilder: (context, index) {
                final pack = stickerData.stickerPacks![index];
                return GestureDetector(
                  onTap: () async {
                    final updated = await Navigator.of(context).pushNamed(
                      '/sticker-pack-info',
                      arguments: {
                        'stickerPack': pack,
                      },
                    );

                    if (updated == true) {
                      setState(() {
                        // Option 1: Just trigger rebuild for UI refresh
                      });

                      // Option 2 (recommended): reload versions from disk if they might have changed
                      await refreshStickerData();
                    }
                  },
                  child: StickerPackItem(stickerPack: pack),
                );
              },
            ),
    );
  }
}
