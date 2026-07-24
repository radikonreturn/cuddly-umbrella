import 'dart:async';
import 'dart:convert';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/video_info.dart';
import '../models/library_item.dart';
import '../services/api_service.dart';
import '../services/download_service.dart';

// Services
final apiServiceProvider = Provider<ApiService>((ref) => ApiService());
final downloadServiceProvider = Provider<DownloadService>((ref) => DownloadService());

// Extraction State Model
class ExtractionState {
  final bool isLoading;
  final String? error;
  final VideoInfo? videoInfo;

  ExtractionState({
    this.isLoading = false,
    this.error,
    this.videoInfo,
  });

  ExtractionState copyWith({
    bool? isLoading,
    String? error,
    VideoInfo? videoInfo,
  }) {
    return ExtractionState(
      isLoading: isLoading ?? this.isLoading,
      error: error, // Can pass null to clear error
      videoInfo: videoInfo ?? this.videoInfo,
    );
  }
}

// Extraction Notifier
class ExtractionNotifier extends StateNotifier<ExtractionState> {
  final ApiService _apiService;

  ExtractionNotifier(this._apiService) : super(ExtractionState());

  void reset() {
    state = ExtractionState();
  }

  Future<void> extract(String url) async {
    state = ExtractionState(isLoading: true);
    try {
      final videoInfo = await _apiService.extractVideo(url);
      state = ExtractionState(videoInfo: videoInfo);
    } catch (e) {
      state = ExtractionState(error: e.toString().replaceAll('Exception: ', ''));
    }
  }
}

final extractionStateProvider = StateNotifierProvider<ExtractionNotifier, ExtractionState>((ref) {
  return ExtractionNotifier(ref.watch(apiServiceProvider));
});

// Active Download Model
class ActiveDownload {
  final DownloadTask task;
  final double progress;
  final TaskStatus status;
  final String title;
  final String? thumbnail;

  ActiveDownload({
    required this.task,
    required this.progress,
    required this.status,
    required this.title,
    this.thumbnail,
  });

  ActiveDownload copyWith({
    double? progress,
    TaskStatus? status,
  }) {
    return ActiveDownload(
      task: task,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      title: title,
      thumbnail: thumbnail,
    );
  }
}

// Download Queue Notifier
class DownloadQueueNotifier extends StateNotifier<List<ActiveDownload>> {
  final Ref _ref;
  StreamSubscription? _subscription;

  DownloadQueueNotifier(this._ref) : super([]) {
    _init();
  }

  void _init() {
    _subscription = _ref.read(downloadServiceProvider).updates.listen((update) async {
      final task = update.task;
      if (task is! DownloadTask) return;

      Map<String, dynamic> metadata = {};
      try {
        metadata = jsonDecode(task.metaData);
      } catch (_) {}

      final title = metadata['title'] ?? task.filename;
      final thumbnail = metadata['thumbnail'];

      final existingIndex = state.indexWhere((element) => element.task.taskId == task.taskId);

      if (update is TaskProgressUpdate) {
        final progress = update.progress;
        if (existingIndex != -1) {
          state = [
            for (int i = 0; i < state.length; i++)
              if (i == existingIndex)
                state[i].copyWith(progress: progress)
              else
                state[i]
          ];
        } else {
          state = [
            ...state,
            ActiveDownload(
              task: task,
              progress: progress,
              status: TaskStatus.running,
              title: title,
              thumbnail: thumbnail,
            ),
          ];
        }
      } else if (update is TaskStatusUpdate) {
        final status = update.status;

        if (status == TaskStatus.complete) {
          await _ref.read(downloadServiceProvider).addToLibrary(task);
          _ref.read(libraryProvider.notifier).loadLibrary();
          // Remove from active queue
          state = state.where((element) => element.task.taskId != task.taskId).toList();
        } else if (status == TaskStatus.canceled || status == TaskStatus.failed) {
          // Remove from active queue
          state = state.where((element) => element.task.taskId != task.taskId).toList();
        } else {
          if (existingIndex != -1) {
            state = [
              for (int i = 0; i < state.length; i++)
                if (i == existingIndex)
                  state[i].copyWith(status: status)
                else
                  state[i]
            ];
          } else {
            state = [
              ...state,
              ActiveDownload(
                task: task,
                progress: 0.0,
                status: status,
                title: title,
                thumbnail: thumbnail,
              ),
            ];
          }
        }
      }
    });
  }

  Future<void> startDownload(VideoInfo videoInfo, FormatInfo format, String originalUrl) async {
    await _ref.read(downloadServiceProvider).startDownload(videoInfo, format, originalUrl);
  }

  Future<void> pause(String taskId) async {
    await _ref.read(downloadServiceProvider).pauseTask(taskId);
  }

  Future<void> resume(String taskId) async {
    await _ref.read(downloadServiceProvider).resumeTask(taskId);
  }

  Future<void> cancel(String taskId) async {
    await _ref.read(downloadServiceProvider).cancelTask(taskId);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final downloadQueueProvider = StateNotifierProvider<DownloadQueueNotifier, List<ActiveDownload>>((ref) {
  return DownloadQueueNotifier(ref);
});

// Library Notifier
class LibraryNotifier extends StateNotifier<List<LibraryItem>> {
  final DownloadService _downloadService;

  LibraryNotifier(this._downloadService) : super([]) {
    loadLibrary();
  }

  Future<void> loadLibrary() async {
    state = await _downloadService.getLibrary();
  }

  Future<void> deleteItem(String id) async {
    await _downloadService.removeFromLibrary(id);
    await loadLibrary();
  }
}

final libraryProvider = StateNotifierProvider<LibraryNotifier, List<LibraryItem>>((ref) {
  return LibraryNotifier(ref.watch(downloadServiceProvider));
});
