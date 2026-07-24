class LibraryItem {
  final String id;
  final String title;
  final String filePath;
  final String? thumbnailPath;
  final int fileSize;
  final int? duration;
  final DateTime downloadedAt;

  LibraryItem({
    required this.id,
    required this.title,
    required this.filePath,
    this.thumbnailPath,
    required this.fileSize,
    this.duration,
    required this.downloadedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'filePath': filePath,
      'thumbnailPath': thumbnailPath,
      'fileSize': fileSize,
      'duration': duration,
      'downloadedAt': downloadedAt.toIso8601String(),
    };
  }

  factory LibraryItem.fromJson(Map<String, dynamic> json) {
    return LibraryItem(
      id: json['id'] ?? '',
      title: json['title'] ?? 'Untitled Video',
      filePath: json['filePath'] ?? '',
      thumbnailPath: json['thumbnailPath'],
      fileSize: json['fileSize'] ?? 0,
      duration: json['duration'],
      downloadedAt: DateTime.tryParse(json['downloadedAt'] ?? '') ?? DateTime.now(),
    );
  }
}
