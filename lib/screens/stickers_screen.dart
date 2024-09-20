import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nerds/Widgets/Drawer.dart';
import 'package:nerds/constants/constants.dart';
import 'package:nerds/models/sticker_data.dart';
import 'package:dio/dio.dart';
import 'package:nerds/widgets/sticker_pack_item.dart';

class StickersScreen extends StatefulWidget {
  static const routeName = '/';

  const StickersScreen({Key? key}) : super(key: key);

  @override
  State<StickersScreen> createState() => _StickersScreenState();
}

class _StickersScreenState extends State<StickersScreen> {
  bool _isLoading = false;

  late StickerData stickerData;

  List stickerPacks = [];
  List installedStickerPacks = [];
  late String stickerFetchType;
  late Dio dio;
  var downloads = <Future>[];
  var data;

void _loadStickers() async {
  try {
    if (stickerFetchType == 'staticStickers') {
      data = await rootBundle.loadString("sticker_packs/sticker_packs.json");
    } else {
      dio = Dio();
      data = await dio.get("${BASE_URL}/json/sticker_packs.json");
    }
    setState(() {
      if (data != null) {
        stickerData = StickerData.fromJson(jsonDecode(data.toString()));
        print("Sticker data loaded successfully");
      } else {
        print("Data is null");
      }
      _isLoading = false;
    });
  } catch (e) {
    print("Error loading stickers: $e");
  }
}

  @override
  didChangeDependencies() {
    var args = ModalRoute.of(context)?.settings.arguments as String?;
    stickerFetchType = args ?? "staticStickers";
    setState(() {
      _isLoading = true;
    });
    _loadStickers();
    super.didChangeDependencies();
  }

  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Nerds Stickers"),
      ),
      drawer: Drawer(
        child: MyDrawer(),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
        itemCount: stickerData.stickerPacks!.length,
        itemBuilder: (context, index) {
          return StickerPackItem(
            stickerPack: stickerData.stickerPacks![index],
            stickerFetchType: stickerFetchType,
          );
        },
      ),
    );
  }
}