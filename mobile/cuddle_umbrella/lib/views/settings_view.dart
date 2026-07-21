import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';
import '../providers/download_provider.dart';
import '../theme.dart';

class SettingsView extends ConsumerStatefulWidget {
  const SettingsView({super.key});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  late final TextEditingController _apiUrlController;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _apiUrlController = TextEditingController(text: settings.apiUrl);
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    super.dispose();
  }

  void _saveSettings() async {
    final newUrl = _apiUrlController.text.trim();
    if (newUrl.isEmpty || !newUrl.startsWith(RegExp(r'https?://'))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen geçerli bir URL girin (http:// veya https:// ile başlamalıdır)'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }
    
    await ref.read(settingsProvider.notifier).setApiUrl(newUrl);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sunucu adresi başarıyla güncellendi'),
          backgroundColor: AppTheme.successColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ayarlar'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sunucu Yapılandırması',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _apiUrlController,
                      decoration: const InputDecoration(
                        labelText: 'API Sunucu Adresi',
                        hintText: 'http://10.0.2.2:8000',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () async {
                            await ref.read(settingsProvider.notifier).resetToDefaults();
                            final freshSettings = ref.read(settingsProvider);
                            _apiUrlController.text = freshSettings.apiUrl;
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Ayarlar sıfırlandı')),
                              );
                            }
                          },
                          child: const Text('Varsayılana Dön'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _saveSettings,
                          child: const Text('Kaydet'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              'Uygulama Seçenekleri',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Karanlık Tema'),
                    subtitle: const Text('Göz sağlığınızı korumak için karanlık modu kullanın'),
                    value: settings.darkTheme,
                    activeColor: AppTheme.primaryColor,
                    onChanged: (val) {
                      ref.read(settingsProvider.notifier).setDarkTheme(val);
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    title: const Text('İndirme Geçmişini Temizle'),
                    subtitle: const Text('Tüm indirme geçmişi kaydını cihazınızdan siler'),
                    trailing: const Icon(Icons.delete_outline, color: AppTheme.errorColor),
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Geçmişi Sil?'),
                          content: const Text('Tüm indirme geçmişini silmek istediğinize emin misiniz? Dosyalarınız silinmeyecektir.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('İptal'),
                            ),
                            TextButton(
                              onPressed: () async {
                                await ref.read(downloadProvider.notifier).clearHistory();
                                if (context.mounted) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('İndirme geçmişi temizlendi')),
                                  );
                                }
                              },
                              style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
                              child: const Text('Evet, Temizle'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            const Center(
              child: Text(
                'Cuddle Umbrella v1.0.0',
                style: TextStyle(
                  color: AppTheme.textMediumEmphasis,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
