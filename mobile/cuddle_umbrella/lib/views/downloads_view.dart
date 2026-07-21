import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/download_provider.dart';
import '../theme.dart';

class DownloadsView extends ConsumerWidget {
  const DownloadsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('İndirilenler'),
        actions: [
          if (downloads.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Geçmişi Temizle',
              onPressed: () {
                ref.read(downloadProvider.notifier).clearHistory();
              },
            ),
        ],
      ),
      body: downloads.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.download_for_offline_outlined,
                    size: 80,
                    color: AppTheme.textMediumEmphasis.withOpacity(0.4),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Henüz indirme yapılmadı.',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppTheme.textMediumEmphasis.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: downloads.length,
              itemBuilder: (context, index) {
                final item = downloads[index];
                return _buildDownloadCard(context, ref, item);
              },
            ),
    );
  }

  Widget _buildDownloadCard(BuildContext context, WidgetRef ref, DownloadItem item) {
    final isDownloading = item.status == TaskStatus.running;
    final isEnqueued = item.status == TaskStatus.enqueued;
    final isPaused = item.status == TaskStatus.paused;
    final isFailed = item.status == TaskStatus.failed;
    final isCanceled = item.status == TaskStatus.canceled;
    final isComplete = item.status == TaskStatus.complete;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.quality,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.primaryColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _statusLabel(item.status),
                            style: TextStyle(
                              fontSize: 12,
                              color: _statusColor(item.status),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _buildActionButtons(ref, item),
              ],
            ),
            if (isDownloading || isPaused || isEnqueued) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: isEnqueued ? null : item.progress,
                  backgroundColor: AppTheme.textMediumEmphasis.withOpacity(0.1),
                  valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isEnqueued ? 'Bekleniyor...' : '${(item.progress * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMediumEmphasis),
                  ),
                  if (isDownloading)
                    const Text(
                      'İndiriliyor...',
                      style: TextStyle(fontSize: 11, color: AppTheme.textMediumEmphasis),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(WidgetRef ref, DownloadItem item) {
    if (item.status == TaskStatus.running) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.pause_circle_outline, color: AppTheme.secondaryColor),
            onPressed: () => ref.read(downloadProvider.notifier).pauseDownload(item.taskId),
          ),
          IconButton(
            icon: const Icon(Icons.cancel_outlined, color: AppTheme.errorColor),
            onPressed: () => ref.read(downloadProvider.notifier).cancelDownload(item.taskId),
          ),
        ],
      );
    }

    if (item.status == TaskStatus.paused) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.play_circle_outline, color: AppTheme.successColor),
            onPressed: () => ref.read(downloadProvider.notifier).resumeDownload(item.taskId),
          ),
          IconButton(
            icon: const Icon(Icons.cancel_outlined, color: AppTheme.errorColor),
            onPressed: () => ref.read(downloadProvider.notifier).cancelDownload(item.taskId),
          ),
        ],
      );
    }

    if (item.status == TaskStatus.enqueued) {
      return IconButton(
        icon: const Icon(Icons.cancel_outlined, color: AppTheme.errorColor),
        onPressed: () => ref.read(downloadProvider.notifier).cancelDownload(item.taskId),
      );
    }

    if (item.status == TaskStatus.complete) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.share_outlined, color: AppTheme.primaryColor),
            onPressed: () {
              if (item.localPath != null) {
                final file = File(item.localPath!);
                if (file.existsSync()) {
                  Share.shareXFiles([XFile(item.localPath!)], text: item.title);
                } else {
                  // Fallback: share link
                  Share.share(item.url, subject: item.title);
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppTheme.textMediumEmphasis),
            onPressed: () => ref.read(downloadProvider.notifier).deleteHistoryItem(item.taskId),
          ),
        ],
      );
    }

    // Failed or Canceled
    return IconButton(
      icon: const Icon(Icons.delete_outline, color: AppTheme.textMediumEmphasis),
      onPressed: () => ref.read(downloadProvider.notifier).deleteHistoryItem(item.taskId),
    );
  }

  String _statusLabel(TaskStatus status) {
    switch (status) {
      case TaskStatus.enqueued:
        return 'Sırada';
      case TaskStatus.running:
        return 'İndiriliyor';
      case TaskStatus.complete:
        return 'Tamamlandı';
      case TaskStatus.failed:
        return 'Hata Oluştu';
      case TaskStatus.canceled:
        return 'İptal Edildi';
      case TaskStatus.paused:
        return 'Duraklatıldı';
      default:
        return 'Bilinmiyor';
    }
  }

  Color _statusColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.enqueued:
        return AppTheme.textMediumEmphasis;
      case TaskStatus.running:
        return AppTheme.primaryColor;
      case TaskStatus.complete:
        return AppTheme.successColor;
      case TaskStatus.failed:
        return AppTheme.errorColor;
      case TaskStatus.canceled:
        return AppTheme.textMediumEmphasis.withOpacity(0.7);
      case TaskStatus.paused:
        return AppTheme.secondaryColor;
      default:
        return AppTheme.textMediumEmphasis;
    }
  }
}
