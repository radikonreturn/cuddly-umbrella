import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';
import '../providers/providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final TextEditingController _backendUrlController = TextEditingController();
  bool _editingUrl = false;
  final String _appVersion = '1.0.0';

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _backendUrlController.dispose();
    super.dispose();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  void _startEditingUrl(String currentUrl) {
    _backendUrlController.text = currentUrl;
    setState(() => _editingUrl = true);
  }

  void _saveUrl() {
    final url = _backendUrlController.text.trim();
    if (url.isEmpty ||
        (!url.startsWith('http://') && !url.startsWith('https://'))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Geçersiz URL. http:// veya https:// ile başlamalıdır.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    ref.read(settingsProvider.notifier).setBackendUrl(url);
    setState(() => _editingUrl = false);
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sunucu adresi kaydedildi.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _resetUrl() {
    ref.read(settingsProvider.notifier).resetBackendUrl();
    setState(() => _editingUrl = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sunucu adresi varsayılana sıfırlandı.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _confirmClearLibrary() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kütüphaneyi Temizle'),
        content: const Text(
          'Tüm kütüphane kayıtları silinecek. Cihazınızdaki video dosyaları etkilenmez. Devam edilsin mi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Temizle'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final items = ref.read(libraryProvider);
      for (final item in items) {
        await ref.read(libraryProvider.notifier).deleteItem(item.id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kütüphane temizlendi.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final libraryCount = ref.watch(libraryProvider).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ayarlar'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // ── Görünüm ─────────────────────────────────────────────────────────
          _SectionHeader(title: 'Görünüm', icon: Icons.palette_outlined),
          _SettingsCard(
            children: [
              _ThemeTile(
                currentMode: settings.themeMode,
                onChanged: (mode) =>
                    ref.read(settingsProvider.notifier).setThemeMode(mode),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Sunucu ──────────────────────────────────────────────────────────
          _SectionHeader(title: 'Sunucu', icon: Icons.dns_outlined),
          _SettingsCard(
            children: [
              if (_editingUrl)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Backend Sunucu Adresi',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _backendUrlController,
                        autofocus: true,
                        keyboardType: TextInputType.url,
                        inputFormatters: [
                          FilteringTextInputFormatter.deny(RegExp(r'\s')),
                        ],
                        decoration: InputDecoration(
                          hintText: 'http://127.0.0.1:8000',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        onSubmitted: (_) => _saveUrl(),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () =>
                                setState(() => _editingUrl = false),
                            child: const Text('Vazgeç'),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: _resetUrl,
                            child: const Text('Varsayılan'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _saveUrl,
                            child: const Text('Kaydet'),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              else
                ListTile(
                  leading: Icon(Icons.cloud_outlined,
                      color: colorScheme.primary),
                  title: const Text('Sunucu Adresi'),
                  subtitle: Text(
                    settings.backendUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _startEditingUrl(settings.backendUrl),
                ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _InfoTile(
                icon: Icons.info_outline,
                iconColor: colorScheme.primary,
                title: 'Bağlantı',
                subtitle:
                    'Uygulamanın video indirmek için bağlandığı backend adresini değiştirin.',
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Depolama ────────────────────────────────────────────────────────
          _SectionHeader(title: 'Depolama', icon: Icons.folder_outlined),
          _SettingsCard(
            children: [
              ListTile(
                leading: Icon(Icons.video_library_outlined,
                    color: colorScheme.primary),
                title: const Text('Kütüphane Kayıtları'),
                subtitle: Text('$libraryCount video kayıtlı'),
                trailing: TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: libraryCount > 0 ? _confirmClearLibrary : null,
                  child: const Text('Temizle'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Hakkında ────────────────────────────────────────────────────────
          _SectionHeader(title: 'Hakkında', icon: Icons.info_outline),
          _SettingsCard(
            children: [
              _InfoTile(
                icon: Icons.umbrella,
                iconColor: colorScheme.primary,
                title: 'Cuddle Umbrella',
                subtitle: 'Sürüm $_appVersion',
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _InfoTile(
                icon: Icons.check_circle_outline,
                iconColor: Colors.green,
                title: 'Desteklenen Platformlar',
                subtitle: 'YouTube · Instagram · X (Twitter)',
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _InfoTile(
                icon: Icons.code,
                iconColor: colorScheme.secondary,
                title: 'Teknoloji',
                subtitle: 'Flutter · FastAPI · yt-dlp',
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Small Reusable Widgets ────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(children: children),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  const _InfoTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(title),
      subtitle: Text(subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              )),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  final ThemeMode currentMode;
  final ValueChanged<ThemeMode> onChanged;

  const _ThemeTile({required this.currentMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.brightness_6_outlined,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Text('Tema', style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.brightness_auto),
                label: Text('Sistem'),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode),
                label: Text('Açık'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode),
                label: Text('Koyu'),
              ),
            ],
            selected: {currentMode},
            onSelectionChanged: (set) => onChanged(set.first),
            style: ButtonStyle(
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
