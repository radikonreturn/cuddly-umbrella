import 'format_info.dart';

class ExtractResponse {
  final String title;
  final String? thumbnail;
  final int? duration;
  final List<FormatInfo> formats;

  ExtractResponse({
    required this.title,
    this.thumbnail,
    this.duration,
    required this.formats,
  });

  factory ExtractResponse.fromJson(Map<String, dynamic> json) {
    var list = json['formats'] as List? ?? [];
    List<FormatInfo> formatList = list.map((i) => FormatInfo.fromJson(i as Map<String, dynamic>)).toList();

    return ExtractResponse(
      title: json['title'] as String? ?? 'Unknown Title',
      thumbnail: json['thumbnail'] as String?,
      duration: json['duration'] as int?,
      formats: formatList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'thumbnail': thumbnail,
      'duration': duration,
      'formats': formats.map((f) => f.toJson()).toList(),
    };
  }

  String get formattedDuration {
    if (duration == null) return "Unknown duration";
    final minutes = duration! ~/ 60;
    final seconds = duration! % 60;
    return "$minutes:${seconds.toString().padLeft(2, '0')}";
  }
}
