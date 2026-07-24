import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:background_downloader/background_downloader.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/video_info.dart';
import '../models/library_item.dart';

class DownloadService {
  final FileDownloader _downloader = FileDownloader();
  final String _prefKey = 'cuddle_umbrella_library';

  // Streams for progress and status updates
  Stream<TaskUpdate> get updates => _downloader.updates;

  DownloadService() {
    // Configure downloader
    _downloader.trackTasks();
  }

  Future<void> startDownload(VideoInfo videoInfo, FormatInfo format, String originalUrl) async {
    // Sanitize title to prevent OS file name errors
    final sanitizedTitle = videoInfo.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
    final filename = '$sanitizedTitle.${format.ext}';

    const String backendBaseUrl = String.fromEnvironment(
      'BACKEND_URL',
      defaultValue: 'http://10.0.2.2:8000',
    );

    // Build the proxy download URL
    final downloadUrl = '$backendBaseUrl/api/download?url=${Uri.encodeComponent(originalUrl)}&format_id=${format.formatId}';

    final task = DownloadTask(
      url: downloadUrl,
      headers: const {
        'User-Agent': 'CuddleUmbrellaMobile/1.0',
      },
      filename: filename,
      baseDirectory: BaseDirectory.applicationDocuments,
      updates: Updates.statusAndProgress,
      retries: 3,
      allowPause: true,
      metaData: jsonEncode({
        'title': videoInfo.title,
        'thumbnail': videoInfo.thumbnail,
        'duration': videoInfo.duration,
      }),
    );

    await _downloader.enqueue(task);
  }

  Future<void> pauseTask(String taskId) async {
    final task = await _downloader.taskForId(taskId);
    if (task is DownloadTask) {
      await _downloader.pause(task);
    }
  }

  Future<void> resumeTask(String taskId) async {
    final task = await _downloader.taskForId(taskId);
    if (task is DownloadTask) {
      await _downloader.resume(task);
    }
  }

  Future<void> cancelTask(String taskId) async {
    await _downloader.cancelTaskWithId(taskId);
  }

  // Library Persistence Methods
  Future<List<LibraryItem>> getLibrary() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefKey) ?? [];
    
    final items = list.map((e) => LibraryItem.fromJson(jsonDecode(e))).toList();
    
    // Clean up items whose files do not exist anymore on the disk
    final verifiedItems = <LibraryItem>[];
    for (var item in items) {
      if (await File(item.filePath).exists()) {
        verifiedItems.add(item);
      }
    }
    
    if (items.length != verifiedItems.length) {
      await saveLibrary(verifiedItems);
    }
    
    return verifiedItems;
  }

  Future<void> saveLibrary(List<LibraryItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final list = items.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_prefKey, list);
  }

  Future<void> addToLibrary(DownloadTask task) async {
    final filePath = await task.filePath();
    final file = File(filePath);
    if (!await file.exists()) return;

    final size = await file.length();
    final Map<String, dynamic> metadata = jsonDecode(task.metaData);

    final library = await getLibrary();
    
    // Prevent duplicates
    if (library.any((element) => element.filePath == filePath)) return;

    final item = LibraryItem(
      id: task.taskId,
      title: metadata['title'] ?? task.filename,
      filePath: filePath,
      thumbnailPath: metadata['thumbnail'],
      fileSize: size,
      duration: metadata['duration'],
      downloadedAt: DateTime.now(),
    );

    library.insert(0, item);
    await saveLibrary(library);
  }

  Future<void> removeFromLibrary(String id) async {
    final library = await getLibrary();
    final index = library.indexWhere((element) => element.id == id);
    if (index != -1) {
      final item = library[index];
      // Delete file
      try {
        final file = File(item.filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
      
      library.removeAt(index);
      await saveLibrary(library);
    }
  }
}
