import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:nerds/widgets/drawer.dart';
import 'package:nerds/constants/constants.dart';
import 'package:nerds/models/sticker_data.dart';
import 'package:nerds/models/user_pack.dart';
import 'package:nerds/services/user_pack_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StickerData? _stickerData;
  bool _loadingServer = true;
  String? _serverError;

  @override
  void initState() {
    super.initState();
    _loadServerPacks();
  }

  Future<void> _loadServerPacks() async {
    setState(() {
      _loadingServer = true;
      _serverError = null;
    });
    try {
      final dio = Dio();
      final res = await dio.get<Map<String, dynamic>>(
        '$baseURL/json/sticker_packs.json',
      );
      if (!mounted) return;
      final data = res.data;
      if (data == null) {
        setState(() {
          _stickerData = null;
          _loadingServer = false;
          _serverError = 'Empty response';
        });
        return;
      }
      setState(() {
        _stickerData = StickerData.fromJson(data);
        _loadingServer = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _serverError = '$e';
        _loadingServer = false;
      });
    }
  }

  Future<void> _onRefresh() async {
    await Future.wait([
      _loadServerPacks(),
      UserPackService.instance.load(),
    ]);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nerds Stickers'),
        centerTitle: true,
      ),
      drawer: const Drawer(child: MyDrawer()),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
                child: _sectionTitle(context, 'Server stickers')),
            SliverToBoxAdapter(child: _buildServerSection(context)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: FilledButton.icon(
                  onPressed: () => context.push('/image-editor'),
                  icon: const Icon(Icons.auto_fix_high_outlined),
                  label: const Text('Create sticker image'),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Divider(height: 1, color: cs.outlineVariant),
              ),
            ),
            SliverToBoxAdapter(child: _sectionTitle(context, 'Your packs')),
            SliverToBoxAdapter(child: _buildUserPacksSection(context)),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  Widget _buildServerSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loadingServer) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_serverError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Could not load server packs',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  _serverError!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: _loadServerPacks,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final packs = _stickerData?.stickerPacks ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  packs.isEmpty
                      ? 'No packs on the server yet.'
                      : '${packs.length} pack${packs.length == 1 ? '' : 's'} available',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ),
              TextButton(
                onPressed: () => context.push('/stickers'),
                child: const Text('See all'),
              ),
            ],
          ),
        ),
        if (packs.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 140,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: packs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final pack = packs[index];
                return _ServerPackCard(
                  stickerPack: pack,
                  onAfterDetail: _loadServerPacks,
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildUserPacksSection(BuildContext context) {
    return ListenableBuilder(
      listenable: UserPackService.instance,
      builder: (context, _) {
        final packs = UserPackService.instance.packs;
        if (packs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(
                      Icons.collections_outlined,
                      size: 48,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No packs yet',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Create a pack with your own photos, then add it to WhatsApp.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => context.push('/user-packs/new'),
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Create pack'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${packs.length} local pack${packs.length == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => context.push('/user-packs/new'),
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('New pack'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: packs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                return _UserPackHomeCard(pack: packs[index]);
              },
            ),
          ],
        );
      },
    );
  }
}

class _ServerPackCard extends StatelessWidget {
  final StickerPacks stickerPack;
  final VoidCallback onAfterDetail;

  const _ServerPackCard({
    required this.stickerPack,
    required this.onAfterDetail,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tray = stickerPack.trayImageFile;
    final id = stickerPack.identifier ?? '';

    return SizedBox(
      width: 108,
      child: Material(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            final updated = await context.push(
              '/sticker-pack-info',
              extra: {'stickerPack': stickerPack},
            );
            if (updated == true && context.mounted) {
              onAfterDetail();
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: tray != null && tray.isNotEmpty
                        ? Image.network(
                            '$baseURL/sticker-packs/$id/$tray',
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => ColoredBox(
                              color: cs.surfaceContainerHigh,
                              child: Icon(Icons.broken_image_outlined,
                                  color: cs.outline),
                            ),
                          )
                        : ColoredBox(
                            color: cs.surfaceContainerHigh,
                            child:
                                Icon(Icons.image_outlined, color: cs.outline),
                          ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  stickerPack.name ?? 'Pack',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UserPackHomeCard extends StatelessWidget {
  final UserPack pack;

  const _UserPackHomeCard({required this.pack});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final thumb = pack.thumbnailPath;

    Widget leading;
    if (thumb != null &&
        thumb.isNotEmpty &&
        !kIsWeb &&
        File(thumb).existsSync()) {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(thumb),
          width: 56,
          height: 56,
          fit: BoxFit.cover,
        ),
      );
    } else {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ColoredBox(
          color: cs.surfaceContainerHighest,
          child: SizedBox(
            width: 56,
            height: 56,
            child: Icon(Icons.collections_outlined, color: cs.outline),
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: leading,
        title: Text(
          pack.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${pack.stickerPaths.length} sticker${pack.stickerPaths.length == 1 ? '' : 's'} · v${pack.packVersion ?? '1'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: Icon(Icons.chevron_right, color: cs.outline),
        onTap: () => context.push('/user-packs/${pack.id}'),
      ),
    );
  }
}
