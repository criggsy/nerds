import 'package:flutter/material.dart';
import 'package:nerds/constants/constants.dart';
import 'package:nerds/models/repo_item.dart';
import 'package:nerds/utils/logger.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class FolderDetailScreen extends StatefulWidget {
  final RepoItem folder;

  const FolderDetailScreen({
    super.key,
    required this.folder,
  });

  @override
  State<FolderDetailScreen> createState() => _FolderDetailScreenState();
}

class _FolderDetailScreenState extends State<FolderDetailScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.folder.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _shareFolder(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Folder info header
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[100],
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.blue[600],
                  child: const Icon(Icons.folder, color: Colors.white),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.folder.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        "${widget.folder.children?.length ?? 0} stickers",
                        style: TextStyle(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Images grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: widget.folder.children?.length ?? 0,
              itemBuilder: (context, index) {
                final image = widget.folder.children![index];
                return _buildImageTile(image);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageTile(RepoItem image) {
    final imageUrl = "$baseURL/${image.path}";

    return GestureDetector(
      onTap: () => _showImageDialog(image),
      onLongPress: () => _showImageOptions(image),
      child: Card(
        elevation: 2,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: FadeInImage(
            placeholder: const AssetImage("assets/images/logo.png"),
            image: NetworkImage(imageUrl),
            fit: BoxFit.cover,
            imageErrorBuilder: (context, error, stackTrace) {
              return Container(
                color: Colors.grey[300],
                child: const Icon(
                  Icons.broken_image,
                  color: Colors.grey,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _showImageDialog(RepoItem image) {
    final imageUrl = "$baseURL/${image.path}";

    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: FadeInImage(
                placeholder: const AssetImage("assets/images/logo.png"),
                image: NetworkImage(imageUrl),
                fit: BoxFit.contain,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.share),
                    label: const Text("Share"),
                    onPressed: () {
                      Navigator.pop(context);
                      _shareImage(image);
                    },
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.download),
                    label: const Text("Download"),
                    onPressed: () {
                      Navigator.pop(context);
                      _downloadImage(image);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showImageOptions(RepoItem image) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text("Share Image"),
              onTap: () {
                Navigator.pop(context);
                _shareImage(image);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text("Download Image"),
              onTap: () {
                Navigator.pop(context);
                _downloadImage(image);
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_browser),
              title: const Text("Open in Browser"),
              onTap: () {
                Navigator.pop(context);
                _openInBrowser(image);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _shareImage(RepoItem image) {
    final imageUrl = "$baseURL/${image.path}";
    Share.share(
      "Check out this sticker: $imageUrl",
      subject: "Sticker from ${widget.folder.name}",
    );
  }

  void _downloadImage(RepoItem image) {
    final imageUrl = "$baseURL/${image.path}";
    // TODO: Implement actual download functionality
    log.i("📥 Download requested for: $imageUrl");

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Download started for ${image.name}"),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openInBrowser(RepoItem image) async {
    final imageUrl = "$baseURL/${image.path}";
    final uri = Uri.parse(imageUrl);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      log.e("❌ Could not launch URL: $imageUrl");
    }
  }

  void _shareFolder() {
    final folderUrl = "$baseURL/stickers/${widget.folder.name}";
    Share.share(
      "Check out the ${widget.folder.name} sticker collection: $folderUrl",
      subject: "${widget.folder.name} Stickers",
    );
  }
}
