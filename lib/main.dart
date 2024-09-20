import 'package:flutter/material.dart';
import 'package:nerds/screens/information_screen.dart';
import 'package:nerds/screens/sticker_pack_info.dart';
import 'package:nerds/screens/stickers_screen.dart';
// Import your StickerPacks model

enum PopupMenuOptions {
  staticStickers,
  remoteStickers,
  informations,
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "WhatsApp Stickers",
      theme: ThemeData(
        primarySwatch: Colors.teal,
      ),
      debugShowCheckedModeBanner: false,
      onGenerateRoute: (settings) {
        if (settings.name == StickersScreen.routeName) {
          return MaterialPageRoute(
            builder: (ctx) => const StickersScreen(),
            settings: const RouteSettings(
              arguments: "remoteStickers",
            ),
          );
        } else if (settings.name == StickerPackInfoScreen.routeName) {
          final args = settings.arguments as Map<String, dynamic>?;
          if (args != null) {
            return MaterialPageRoute(
              builder: (ctx) => const StickerPackInfoScreen(),
              settings: RouteSettings(
                arguments: args,
              ),
            );
          }
        } else if (settings.name == InformationScreen.routeName) {
          return MaterialPageRoute(
            builder: (ctx) => const InformationScreen(),
          );
        }
        return null;
      },
      initialRoute: StickersScreen.routeName,
    );
  }
}