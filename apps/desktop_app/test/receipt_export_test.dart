// v7d receipt export unit tests: the plain-text renderers are pure —
// header, field labels, section join, newest-first history order — and
// the save wrapper degrades to `false` when the platform channel is
// missing (exactly the widget-test environment).
library;

import 'dart:ui' show Locale; // Locale lives in dart:ui, not flutter_test

import 'package:flutter_test/flutter_test.dart';

import 'package:desktop_app/l10n/app_localizations.dart';
import 'package:desktop_app/provisioning/provisioning_controller.dart';
import 'package:desktop_app/services/receipt_export.dart';

SessionReceipt receipt({
  String deviceName = 'NE101-AABBCC',
  DateTime? appliedAt,
}) => SessionReceipt(
  deviceName: deviceName,
  serialNumber: 'NL24Q4001234',
  model: 'NE101',
  sections: const ['wifi', 'mqtt'],
  appliedAt: appliedAt ?? DateTime(2026, 11, 5, 14, 23, 5),
);

void main() {
  late AppLocalizations l;

  setUpAll(() async {
    l = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  test('exportStamp keeps second precision and zero padding', () {
    expect(exportStamp(DateTime(2026, 11, 5, 9, 3, 7)), '2026-11-05 09:03:07');
  });

  test('formatReceiptText carries identity, sections and full stamp', () {
    final text = formatReceiptText(receipt(), l);
    expect(text, contains('配置回执'));
    expect(text, contains('设备名称: NE101-AABBCC'));
    expect(text, contains('序列号: NL24Q4001234'));
    expect(text, contains('型号: NE101'));
    expect(text, contains('已写入模块: wifi, mqtt'));
    expect(text, contains('完成时间: 2026-11-05 14:23:05'));
  });

  test('formatHistoryText lists newest first and falls back to serial', () {
    final older = receipt(appliedAt: DateTime(2026, 11, 5, 10, 0, 0));
    final newer = receipt(
      deviceName: '',
      appliedAt: DateTime(2026, 11, 5, 11, 0, 0),
    );
    final text = formatHistoryText([older, newer], l);
    expect(text, contains('本次运行记录'));
    // Newer receipt first (history order), empty name falls to serial.
    expect(text.indexOf('11:00:00') < text.indexOf('10:00:00'), isTrue);
    expect(text, contains('设备名称: NL24Q4001234'));
  });

  test('formatHistoryText renders the empty marker with no receipts', () {
    final text = formatHistoryText(const [], l);
    expect(text, contains('本次运行记录'));
    expect(text, contains('暂无记录'));
  });

  test('exportTextFile returns false without a platform channel', () async {
    // No file_selector Windows implementation in the test VM: the save
    // dialog call must fail closed, never throw into the caller.
    expect(await exportTextFile('a.txt', 'x'), isFalse);
  });
}
