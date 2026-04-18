import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';

import 'package:nerds/services/user_pack_service.dart';
import 'package:nerds/utils/app_messaging.dart';

/// Long-press on a server sticker → add into a user pack (new or existing).
Future<void> showAddStickerToUserPackSheet(
  BuildContext context, {
  required String imageUrl,
  String? fileNameHint,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  'Add to My Pack',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 4),
              ListTile(
                leading: const Icon(Icons.add_photo_alternate_outlined),
                title: const Text('Create new pack'),
                subtitle: const Text(
                  'Name the pack, then add more stickers (3–30 total for WhatsApp)',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push(
                    '/user-packs/new',
                    extra: <String, dynamic>{
                      'seedStickerUrl': imageUrl,
                    },
                  );
                },
              ),
              const Divider(height: 1),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Existing packs',
                  style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                        color: Colors.grey,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              ListenableBuilder(
                listenable: UserPackService.instance,
                builder: (context, _) {
                  final packs = UserPackService.instance.packs;
                  if (packs.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Text(
                        'You have no saved packs yet. Use “Create new pack” above.',
                      ),
                    );
                  }
                  return ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: packs.length,
                      itemBuilder: (c, i) {
                        final p = packs[i];
                        final full = p.stickerPaths.length >=
                            UserPackService.maxStickers;
                        return ListTile(
                          leading: const Icon(Icons.collections_outlined),
                          title: Text(p.name),
                          subtitle: Text(
                            '${p.stickerPaths.length} / ${UserPackService.maxStickers} stickers',
                          ),
                          enabled: !full,
                          onTap: full
                              ? null
                              : () async {
                                  Navigator.pop(ctx);
                                  try {
                                    await UserPackService.instance
                                        .addStickerFromUrl(
                                      p.id,
                                      imageUrl,
                                      fileNameHint: fileNameHint,
                                    );
                                    if (context.mounted) {
                                      Fluttertoast.showToast(
                                        msg: 'Added to ${p.name}',
                                        gravity: ToastGravity.BOTTOM,
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      await showAppErrorDialog(
                                        context,
                                        '$e',
                                        title: 'Couldn’t add sticker',
                                      );
                                    }
                                  }
                                },
                        );
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}
