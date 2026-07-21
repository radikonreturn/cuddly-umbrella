class FormatInfo {
  final String formatId;
  final String quality;
  final String ext;
  final int? filesizeApprox;
  final bool hasAudio;
  final bool hasVideo;

  FormatInfo({
    required this.formatId,
    required this.quality,
    required this.ext,
    this.filesizeApprox,
    required this.hasAudio,
    required this.hasVideo,
  });

  factory FormatInfo.fromJson(Map<String, dynamic> json) {
    return FormatInfo(
      formatId: json['format_id'] as String,
      quality: json['quality'] as String,
      ext: json['ext'] as String,
      filesizeApprox: json['filesize_approx'] as int?,
      hasAudio: json['has_audio'] as bool? ?? true,
      hasVideo: json['has_video'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'format_id': formatId,
      'quality': quality,
      'ext': ext,
      'filesize_approx': filesizeApprox,
      'has_audio': hasAudio,
      'has_video': hasVideo,
    };
  }

  String get formattedSize {
    if (filesizeApprox == null) return "Unknown size";
    final kb = filesizeApprox! / 1024;
    final mb = kb / 1024;
    if (mb >= 1) return "${mb.toStringAsFixed(1)} MB";
    return "${kb.toStringAsFixed(1)} KB";
  }
}
