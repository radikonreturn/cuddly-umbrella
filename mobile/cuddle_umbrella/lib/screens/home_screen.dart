import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/providers.dart';
import '../main.dart';
import 'main_navigation_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _urlController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  // Returns true if the URL is a YouTube link that needs format selection
  bool _isYouTubeUrl(String url) =>
      url.contains('youtube.com') || url.contains('youtu.be');

  // Paste from clipboard helper
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    if (data != null && data.text != null) {
      setState(() {
        _urlController.text = data.text!;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Bağlantı yapıştırıldı!')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pano boş veya metin içermiyor.')),
      );
    }
  }

  // Formatting helpers
  String _formatDuration(int? seconds) {
    if (seconds == null) return '--:--';
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$secs' : '$minutes:$secs';
  }

  String _formatBytes(int? bytes) {
    if (bytes == null || bytes <= 0) return 'Bilinmiyor';
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  @override
  Widget build(BuildContext context) {
    final extractState = ref.watch(extractionStateProvider);
    final videoInfo = extractState.videoInfo;
    final url = _urlController.text.trim();

    // Format picker is only shown for YouTube. Every other platform (X, Instagram, …)
    // auto-downloads via the listener below without ever showing this screen.
    final hasVideoInfo = videoInfo != null && _isYouTubeUrl(url);

    // Auto-download listener for non-YouTube platforms
    ref.listen<ExtractionState>(extractionStateProvider, (previous, next) {
      if (next.videoInfo != null &&
          !next.isLoading &&
          previous?.videoInfo != next.videoInfo) {
        final info = next.videoInfo!;
        final shared = ref.read(sharedUrlProvider);
        final currentUrl = _urlController.text.trim().isNotEmpty
            ? _urlController.text.trim()
            : shared.trim();

        if (currentUrl.isNotEmpty && !_isYouTubeUrl(currentUrl)) {
          if (info.formats.isNotEmpty) {
            ref
                .read(downloadQueueProvider.notifier)
                .startDownload(info, info.formats.first, currentUrl);
            ref.read(extractionStateProvider.notifier).reset();
            _urlController.clear();

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('İndirme otomatik olarak başlatıldı!'),
                duration: Duration(seconds: 2),
              ),
            );
            ref.read(navigationIndexProvider.notifier).state = 1;
          } else {
            ref.read(extractionStateProvider.notifier).reset();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('İndirilebilir format bulunamadı.')),
            );
          }
        }
      }
    });

    ref.listen<String>(sharedUrlProvider, (previous, next) {
      if (next.isNotEmpty) {
        _urlController.text = next;
      }
    });

    return Scaffold(
      appBar: AppBar(
        leading: hasVideoInfo
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  ref.read(extractionStateProvider.notifier).reset();
                },
              )
            : null,
        title: Text(hasVideoInfo ? 'Format Seçin' : 'Cuddle Umbrella'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: hasVideoInfo
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Video Details Preview Card
                  Card(
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Thumbnail
                        if (videoInfo.thumbnail != null)
                          CachedNetworkImage(
                            imageUrl: videoInfo.thumbnail!,
                            height: 200,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: Colors.grey.shade300,
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: Colors.grey.shade300,
                              child: const Icon(Icons.broken_image, size: 64),
                            ),
                          )
                        else
                          Container(
                            height: 200,
                            color: Colors.grey.shade300,
                            child: const Icon(Icons.movie, size: 64),
                          ),

                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                videoInfo.title,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.timer_outlined, size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Süre: ${_formatDuration(videoInfo.duration)}',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Kullanılabilir Formatlar',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (videoInfo.formats.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'İndirilebilir progressive format bulunamadı.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: videoInfo.formats.length,
                      itemBuilder: (context, index) {
                        final format = videoInfo.formats[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                              child: Icon(
                                format.hasVideo
                                    ? Icons.video_library
                                    : Icons.audiotrack,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            title: Text(
                              format.quality.isNotEmpty
                                  ? format.quality
                                  : 'Bilinmeyen Çözünürlük',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              'Uzantı: ${format.ext.toUpperCase()} • Boyut: ${_formatBytes(format.fileSizeApprox)}',
                            ),
                            trailing: ElevatedButton.icon(
                              onPressed: () {
                                ref
                                    .read(downloadQueueProvider.notifier)
                                    .startDownload(
                                      videoInfo,
                                      format,
                                      _urlController.text.trim(),
                                    );
                                ref
                                    .read(extractionStateProvider.notifier)
                                    .reset();
                                _urlController.clear();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'İndirme başlatıldı! Aktif İndirmelere yönlendiriliyorsunuz...',
                                    ),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                                ref
                                        .read(navigationIndexProvider.notifier)
                                        .state =
                                    1;
                              },
                              icon: const Icon(Icons.download, size: 16),
                              label: const Text('İndir'),
                              style: ElevatedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Welcome Card / Header
                  Card(
                    elevation: 0,
                    color: Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Icon(
                            Icons.umbrella,
                            size: 64,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Video Downloader',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                                ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'YouTube, Instagram veya X platformlarından link yapıştırarak videoları indirin.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Link Input Row
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _urlController,
                          decoration: InputDecoration(
                            hintText: 'Video linkini buraya yapıştırın',
                            prefixIcon: const Icon(Icons.link),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          onSubmitted: (url) {
                            if (url.trim().isNotEmpty) {
                              ref
                                  .read(extractionStateProvider.notifier)
                                  .extract(url.trim());
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        onPressed: _pasteFromClipboard,
                        icon: const Icon(Icons.content_paste),
                        tooltip: 'Yapıştır',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Extract Button
                  ElevatedButton.icon(
                    onPressed: extractState.isLoading
                        ? null
                        : () {
                            final url = _urlController.text.trim();
                            if (url.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Lütfen geçerli bir bağlantı girin.',
                                  ),
                                ),
                              );
                              return;
                            }
                            ref
                                .read(extractionStateProvider.notifier)
                                .extract(url);
                          },
                    icon: extractState.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search),
                    label: Text(
                      extractState.isLoading
                          ? 'Analiz Ediliyor...'
                          : 'Videoyu Çözümle',
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Loading state
                  if (extractState.isLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Column(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text(
                              'Video bilgileri alınıyor, lütfen bekleyin...',
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Error state
                  if (extractState.error != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    extractState.error!,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onErrorContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: () {
                                final url = _urlController.text.trim();
                                if (url.isNotEmpty) {
                                  ref
                                      .read(extractionStateProvider.notifier)
                                      .extract(url);
                                }
                              },
                              child: const Text('Tekrar Dene'),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
