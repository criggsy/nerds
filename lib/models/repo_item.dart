class RepoItem {
  final String name;
  final String path;
  final String packVersion;
  final bool isFolder;
  final List<RepoItem>? children;

  const RepoItem({
    required this.name,
    required this.path,
    required this.packVersion,
    required this.isFolder,
    this.children,
  });

  factory RepoItem.fromJson(Map<String, dynamic> json) {
    return RepoItem(
      name: json['name'],
      path: json['path'],
      packVersion: json['packVersion'],
      isFolder: json['isFolder'],
      children: json['children'] != null
          ? (json['children'] as List)
              .map((child) => RepoItem.fromJson(child))
              .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'path': path,
      'packVersion': packVersion,
      'isFolder': isFolder,
      'children': children?.map((child) => child.toJson()).toList(),
    };
  }
}
