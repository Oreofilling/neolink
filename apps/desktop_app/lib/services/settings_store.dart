import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

/// Persisted tool settings. Null fields mean "not chosen, use the default"
/// (language: follow the system locale list; theme: light).
final class AppSettings {
  const AppSettings({this.theme, this.locale});

  final ThemeMode? theme;
  final Locale? locale;

  Map<String, Object?> toJson() => {
    if (theme != null) 'theme': theme!.name,
    if (locale != null) 'locale': locale!.languageCode,
  };
}

/// Tiny JSON settings file under %APPDATA%/NeoLink. Deliberately dependency
/// free: desktop-only, one small file, every failure degrades to "no stored
/// settings" instead of blocking startup.
final class SettingsStore {
  SettingsStore({String? directory})
    : _directory = directory ?? _defaultDirectory();

  /// Disabled store for tests: load returns null and save is a no-op.
  SettingsStore.none() : _directory = null;

  static String? _defaultDirectory() {
    final appData = Platform.environment['APPDATA'];
    return appData == null ? null : '$appData\\NeoLink';
  }

  final String? _directory;

  bool get enabled => _directory != null;

  /// Synchronous load at startup: the file is a few bytes and reading it
  /// before the first build avoids a locale flash.
  AppSettings? load() {
    final dir = _directory;
    if (dir == null) return null;
    try {
      final file = File('$dir\\settings.json');
      if (!file.existsSync()) return null;
      final data = jsonDecode(file.readAsStringSync());
      if (data is! Map<String, Object?>) return null;
      final theme = switch (data['theme']) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => null,
      };
      final locale = switch (data['locale']) {
        'zh' => const Locale('zh'),
        'en' => const Locale('en'),
        _ => null,
      };
      // All-null (empty object or only unknown values) reads as "no stored
      // settings", same as a missing file.
      if (theme == null && locale == null) return null;
      return AppSettings(theme: theme, locale: locale);
    } catch (_) {
      // Missing/corrupt/unreadable: fall back to defaults.
      return null;
    }
  }

  Future<void> save(AppSettings settings) async {
    final dir = _directory;
    if (dir == null) return;
    try {
      await Directory(dir).create(recursive: true);
      await File(
        '$dir\\settings.json',
      ).writeAsString('${jsonEncode(settings.toJson())}\n');
    } catch (_) {
      // Read-only profile or locked file: settings just don't persist.
    }
  }
}
