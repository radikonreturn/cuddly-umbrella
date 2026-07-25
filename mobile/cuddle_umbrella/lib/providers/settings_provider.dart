import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Keys ────────────────────────────────────────────────────────────────────
const _kThemeMode = 'settings_theme_mode'; // 0=system,1=light,2=dark
const _kBackendUrl = 'settings_backend_url';
const _kDefaultBackendUrl = 'http://127.0.0.1:8000';

// ─── Model ───────────────────────────────────────────────────────────────────
class AppSettings {
  final ThemeMode themeMode;
  final String backendUrl;

  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.backendUrl = _kDefaultBackendUrl,
  });

  AppSettings copyWith({ThemeMode? themeMode, String? backendUrl}) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      backendUrl: backendUrl ?? this.backendUrl,
    );
  }
}

// ─── Notifier ────────────────────────────────────────────────────────────────
class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final themeModeIndex = prefs.getInt(_kThemeMode) ?? 0;
    final backendUrl =
        prefs.getString(_kBackendUrl) ?? _kDefaultBackendUrl;

    state = AppSettings(
      themeMode: ThemeMode.values[themeModeIndex.clamp(0, 2)],
      backendUrl: backendUrl,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kThemeMode, mode.index);
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setBackendUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final cleaned = url.trim().replaceAll(RegExp(r'/$'), '');
    await prefs.setString(_kBackendUrl, cleaned);
    state = state.copyWith(backendUrl: cleaned);
  }

  Future<void> resetBackendUrl() async {
    await setBackendUrl(_kDefaultBackendUrl);
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────
final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});
