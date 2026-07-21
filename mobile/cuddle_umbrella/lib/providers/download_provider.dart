import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DownloadItem {
  final String taskId;
  final String title;
  final String url;
  final double progress;
  final TaskStatus status;
  final String? localPath;
  final String quality;

  DownloadItem({
    required this.taskId,
    required this.title,
    required this.url,
    required this.progress,
    required this.status,
    this.localPath,
    required this.quality,
  });

  DownloadItem copyWith({
    String? taskId,
    String? title,
    String? url,
    double? progress,
    TaskStatus? status,
    String? localPath,
    String? quality,
  }) {
    return DownloadItem(
      taskId: taskId ?? this.taskId,
      title: title ?? this.title,
      url: url ?? this.url,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      localPath: localPath ?? this.localPath,
      quality: quality ?? this.quality,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'taskId': taskId,
      'title': title,
      'url': url,
      'progress': progress,
      'status': status.index,
      'localPath': localPath,
      'quality': quality,
    };
  }

  factory DownloadItem.fromJson(Map<String, dynamic> map) {
    return DownloadItem(
      taskId: map['taskId'] as String,
      title: map['title'] as String,
      url: map['url'] as String,
      progress: (map['progress'] as num).toDouble(),
      status: TaskStatus.values[map['status'] as int],
      localPath: map['localPath'] as String?,
      quality: map['quality'] as String? ?? 'Unknown',
    );
  }
}

class DownloadNotifier extends StateNotifier<List<DownloadItem>> {
  static const String _keyHistory = 'download_history';

  DownloadNotifier() : super([]) {
    _loadHistory();
    _initDownloader();
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyRaw = prefs.getStringList(_keyHistory);
      if (historyRaw != null) {
        state = historyRaw
            .map((item) => DownloadItem.fromJson(jsonDecode(item) as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      // Handle loading failure gracefully
    }
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyRaw = state
          .map((item) => jsonEncode(item.toJson()))
          .toList();
      await prefs.setStringList(_keyHistory, historyRaw);
    } catch (e) {
      // Handle saving failure gracefully
    }
  }

  void _initDownloader() {
    // Configure notifications for background downloads
    FileDownloader().configureNotification(
      running: const TaskNotification('İndiriliyor', '{filename}'),
      complete: const TaskNotification('İndirme Tamamlandı', '{filename}'),
      error: const TaskNotification('Hata Oluştu', '{filename}'),
      paused: const TaskNotification('Duraklatıldı', '{filename}'),
      progressBar: true,
      tapOpensFile: true,
    );

    // Listen to updates from background downloader
    FileDownloader().updates.listen((update) {
      if (update is TaskStatusUpdate) {
        _handleStatusUpdate(update.task.taskId, update.status, update.task);
      } else if (update is TaskProgressUpdate) {
        _handleProgressUpdate(update.task.taskId, update.progress);
      }
    });
  }

  void _handleStatusUpdate(String taskId, TaskStatus status, DownloadTask task) async {
    int index = state.indexWhere((item) => item.taskId == taskId);
    if (index == -1) return;

    final currentItem = state[index];
    String? localPath = currentItem.localPath;

    if (status == TaskStatus.complete) {
      // Try to move the file to shared downloads storage for user access
      try {
        final sharedPath = await FileDownloader().moveToSharedStorage(task, SharedStorage.downloads);
        if (sharedPath != null) {
          localPath = sharedPath;
        } else {
          // Fallback to app directory path if shared storage is not accessible
          final path = await FileDownloader().localFilePath(task);
          localPath = path;
        }
      } catch (e) {
        final path = await FileDownloader().localFilePath(task);
        localPath = path;
      }
    }

    state = [
      for (int i = 0; i < state.length; i++)
        if (i == index)
          currentItem.copyWith(status: status, localPath: localPath, progress: status == TaskStatus.complete ? 1.0 : currentItem.progress)
        else
          state[i]
    ];
    
    _saveHistory();
  }

  void _handleProgressUpdate(String taskId, double progress) {
    int index = state.indexWhere((item) => item.taskId == taskId);
    if (index == -1) return;

    // Check if progress is negative (sometimes signifies status info)
    if (progress < 0) return;

    state = [
      for (int i = 0; i < state.length; i++)
        if (i == index)
          state[i].copyWith(progress: progress)
        else
          state[i]
    ];
  }

  Future<void> startDownload({
    required String title,
    required String downloadUrl,
    required String quality,
    required String extension,
  }) async {
    // Generate clean filename
    final safeTitle = title.replaceAll(RegExp(r'[\\/*?:""<>|]'), '');
    final filename = '${safeTitle}_$quality.$extension';

    // Create background downloader task
    final task = DownloadTask(
      url: downloadUrl,
      filename: filename,
      headers: {
        'User-Agent': 'CuddleUmbrellaMobile/1.0',
      },
      updates: Updates.statusAndProgress,
      requiresWiFi: false,
    );

    // Save to our in-app tracker
    final newItem = DownloadItem(
      taskId: task.taskId,
      title: title,
      url: downloadUrl,
      progress: 0.0,
      status: TaskStatus.enqueued,
      quality: quality,
    );

    state = [newItem, ...state];
    await _saveHistory();

    // Start download
    await FileDownloader().enqueue(task);
  }

  Future<void> pauseDownload(String taskId) async {
    final index = state.indexWhere((item) => item.taskId == taskId);
    if (index == -1) return;
    
    final task = await FileDownloader().taskForId(taskId);
    if (task != null) {
      await FileDownloader().pause(task);
    }
  }

  Future<void> resumeDownload(String taskId) async {
    final index = state.indexWhere((item) => item.taskId == taskId);
    if (index == -1) return;
    
    final task = await FileDownloader().taskForId(taskId);
    if (task != null) {
      await FileDownloader().resume(task);
    }
  }

  Future<void> cancelDownload(String taskId) async {
    final index = state.indexWhere((item) => item.taskId == taskId);
    if (index == -1) return;

    await FileDownloader().cancelTasksWithIds([taskId]);

    state = [
      for (final item in state)
        if (item.taskId == taskId)
          item.copyWith(status: TaskStatus.canceled)
        else
          item
    ];
    await _saveHistory();
  }

  Future<void> deleteHistoryItem(String taskId) async {
    state = state.where((item) => item.taskId != taskId).toList();
    await _saveHistory();
  }

  Future<void> clearHistory() async {
    state = [];
    await _saveHistory();
  }
}

final downloadProvider = StateNotifierProvider<DownloadNotifier, List<DownloadItem>>((ref) {
  return DownloadNotifier();
});
