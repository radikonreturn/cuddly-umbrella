import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/providers.dart';

class DownloadQueueScreen extends ConsumerWidget {
  const DownloadQueueScreen({super.key});

  String _getStatusText(TaskStatus status) {
    switch (status) {
      case TaskStatus.enqueued:
        return 'Sırada bekliyor...';
      case TaskStatus.running:
        return 'İndiriliyor...';
      case TaskStatus.paused:
        return 'Duraklatıldı';
      case TaskStatus.failed:
        return 'Hata oluştu';
      case TaskStatus.complete:
        return 'Tamamlandı';
      case TaskStatus.canceled:
        return 'İptal edildi';
      case TaskStatus.waitingToRetry:
        return 'Yeniden deneniyor...';
      default:
        return 'Hazırlanıyor...';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeDownloads = ref.watch(downloadQueueProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Aktif İndirmeler'),
        centerTitle: true,
      ),
      body: activeDownloads.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.cloud_download_outlined,
                      size: 80,
                      color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Aktif İndirme Bulunmuyor',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Ana sayfadan bir link yapıştırıp indirme başlattığınızda burada listelenecektir.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: activeDownloads.length,
              itemBuilder: (context, index) {
                final download = activeDownloads[index];
                final isRunning = download.status == TaskStatus.running;
                final isPaused = download.status == TaskStatus.paused;
                
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Small Thumbnail Preview
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: download.thumbnail != null
                              ? CachedNetworkImage(
                                  imageUrl: download.thumbnail!,
                                  width: 70,
                                  height: 70,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(
                                    color: Colors.grey.shade200,
                                    child: const Center(
                                      child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    ),
                                  ),
                                  errorWidget: (context, url, error) => Container(
                                    color: Colors.grey.shade200,
                                    child: const Icon(Icons.broken_image, size: 24),
                                  ),
                                )
                              : Container(
                                  width: 70,
                                  height: 70,
                                  color: Theme.of(context).colorScheme.primaryContainer,
                                  child: Icon(
                                    Icons.movie,
                                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 12),

                        // Title, Progress Bar, Actions
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                download.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _getStatusText(download.status),
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: isPaused
                                          ? Colors.orange
                                          : Theme.of(context).colorScheme.secondary,
                                    ),
                              ),
                              const SizedBox(height: 8),

                              // Progress Row
                              Row(
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: download.progress < 0 ? 0.0 : download.progress,
                                        backgroundColor: Colors.grey.shade200,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    download.progress < 0
                                        ? '0.0%'
                                        : '${(download.progress * 100).toStringAsFixed(1)}%',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Action Buttons: Pause/Resume, Cancel
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (isRunning)
                              IconButton(
                                icon: const Icon(Icons.pause),
                                color: Theme.of(context).colorScheme.primary,
                                onPressed: () {
                                  ref.read(downloadQueueProvider.notifier).pause(download.task.taskId);
                                },
                              )
                            else if (isPaused)
                              IconButton(
                                icon: const Icon(Icons.play_arrow),
                                color: Colors.green,
                                onPressed: () {
                                  ref.read(downloadQueueProvider.notifier).resume(download.task.taskId);
                                },
                              ),
                            IconButton(
                              icon: const Icon(Icons.cancel_outlined),
                              color: Theme.of(context).colorScheme.error,
                              onPressed: () {
                                ref.read(downloadQueueProvider.notifier).cancel(download.task.taskId);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
