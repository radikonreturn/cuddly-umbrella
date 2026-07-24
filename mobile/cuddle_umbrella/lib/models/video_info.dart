class FormatInfo {
  final String formatId;
  final String quality;
  final String ext;
  final int? fileSizeApprox;
  final bool hasAudio;
  final bool hasVideo;

  FormatInfo({
    required this.formatId,
    required this.quality,
    required this.ext,
    this.fileSizeApprox,
    required this.hasAudio,
    required this.hasVideo,
  });

  factory FormatInfo.fromJson(Map<String, dynamic> json) {
    return FormatInfo(
      formatId: json['format_id'] ?? '',
      quality: json['quality'] ?? '',
      ext: json['ext'] ?? '',
      fileSizeApprox: json['filesize_approx'],
      hasAudio: json['has_audio'] ?? false,
      hasVideo: json['has_video'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'format_id': formatId,
      'quality': quality,
      'ext': ext,
      'filesize_approx': fileSizeApprox,
      'has_audio': hasAudio,
      'has_video': hasVideo,
    };
  }
}

class VideoInfo {
  final String title;
  final String? thumbnail;
  final int? duration;
  final List<FormatInfo> formats;

  VideoInfo({
    required this.title,
    this.thumbnail,
    this.duration,
    required this.formats,
  });

  factory VideoInfo.fromJson(Map<String, dynamic> json) {
    return VideoInfo(
      title: json['title'] ?? 'Unknown Title',
      thumbnail: json['thumbnail'],
      duration: json['duration'],
      formats: (json['formats'] as List? ?? [])
          .map((e) => FormatInfo.fromJson(e))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'thumbnail': thumbnail,
      'duration': duration,
      'formats': formats.map((e) => e.toJson()).toList(),
    };
  }
}
