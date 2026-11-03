// 设置存储单元测试：临时目录往返、半量字段、损坏/未知值降级、none() 禁用。
// 路径两侧同构（store 与测试都用 '<dir>\\settings.json'），任何 OS 上语义一致。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:desktop_app/services/settings_store.dart';

void main() {
  Directory tempDir() {
    final dir = Directory.systemTemp.createTempSync('neolink_settings_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    return dir;
  }

  test('round-trips theme and locale through the directory', () async {
    final dir = tempDir();
    final store = SettingsStore(directory: dir.path);
    expect(store.enabled, isTrue);
    expect(store.load(), isNull); // 尚无设置文件

    await store.save(
      const AppSettings(theme: ThemeMode.dark, locale: Locale('en')),
    );
    final loaded = store.load();
    expect(loaded?.theme, ThemeMode.dark);
    expect(loaded?.locale, const Locale('en'));
  });

  test('partial settings keep the unset field null', () async {
    final dir = tempDir();
    final store = SettingsStore(directory: dir.path);

    await store.save(const AppSettings(theme: ThemeMode.system));
    final loaded = store.load();
    expect(loaded?.theme, ThemeMode.system);
    expect(loaded?.locale, isNull); // 未选择语言 = 跟随系统
  });

  test('corrupt file degrades to defaults', () async {
    final dir = tempDir();
    File('${dir.path}\\settings.json').writeAsStringSync('{ not json');
    expect(SettingsStore(directory: dir.path).load(), isNull);
  });

  test('unknown enum values are ignored field-by-field', () async {
    final dir = tempDir();
    File('${dir.path}\\settings.json').writeAsStringSync(
      '{"theme":"neon","locale":"fr"}',
    );
    expect(SettingsStore(directory: dir.path).load(), isNull);
  });

  test('none() is inert: load returns null and save does not write', () async {
    final store = SettingsStore.none();
    expect(store.enabled, isFalse);
    expect(store.load(), isNull);
    await store.save(
      const AppSettings(theme: ThemeMode.dark, locale: Locale('zh')),
    ); // 不抛不写
  });
}
