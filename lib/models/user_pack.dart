class UserPack {
  final String id;
  final String name;
  final DateTime createdAt;
  final List<String> stickerPaths;
  final String? thumbnailPath;
  final String? packVersion;

  const UserPack({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.stickerPaths,
    this.thumbnailPath,
    this.packVersion,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'stickerPaths': stickerPaths,
      'thumbnailPath': thumbnailPath,
      'packVersion': packVersion,
    };
  }

  factory UserPack.fromJson(Map<String, dynamic> json) {
    return UserPack(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      stickerPaths: List<String>.from(json['stickerPaths'] as List),
      thumbnailPath: json['thumbnailPath'] as String?,
      packVersion: json['packVersion'] as String?,
    );
  }
}
