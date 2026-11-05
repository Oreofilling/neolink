// Receipt export helpers (v7d product asks #5/#6): plain-text renderers
// for a single receipt and the whole in-memory run history, plus one save
// dialog wrapper. Formatting is pure and unit-tested; the file write is
// best-effort — a cancelled dialog, a missing platform channel (widget
// tests) or an IO error all resolve to `false`, never an exception in the
// caller.
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../app_metadata.dart';
import '../l10n/app_localizations.dart';
import '../provisioning/provisioning_controller.dart';

/// Full local timestamp for exports (receipts keep second precision —
/// provisioning runs are minutes apart, and audits want the exact stamp).
String exportStamp(DateTime at) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${at.year}-${two(at.month)}-${two(at.day)} '
      '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
}

/// One receipt as plain text — mirrors what the result card shows, in a
/// shape that survives a paste into a ticket or a log.
String formatReceiptText(SessionReceipt receipt, AppLocalizations l) {
  final buffer = StringBuffer()
    ..writeln('NeoLink v$appVersion — ${l.exportReceiptTitle}')
    ..writeln('${l.resultDeviceLabel}: ${receipt.deviceName}')
    ..writeln('${l.resultSerialLabel}: ${receipt.serialNumber}')
    ..writeln('${l.resultModelLabel}: ${receipt.model}')
    ..writeln(
      '${l.exportSectionsLabel}: ${receipt.sections.isEmpty ? '—' : receipt.sections.join(', ')}',
    )
    ..writeln('${l.resultAppliedAtLabel}: ${exportStamp(receipt.appliedAt)}');
  return buffer.toString();
}

/// The whole run history as plain text, newest first (same order the
/// history page lists).
String formatHistoryText(List<SessionReceipt> receipts, AppLocalizations l) {
  final buffer = StringBuffer()
    ..writeln('NeoLink v$appVersion — ${l.exportRunTitle}')
    ..writeln('${l.exportGeneratedLabel}: ${exportStamp(DateTime.now())}')
    ..writeln();
  if (receipts.isEmpty) {
    buffer.writeln(l.histEmpty);
    return buffer.toString();
  }
  for (final receipt in receipts.reversed) {
    buffer
      ..writeln('${l.exportReceiptTitle} ${exportStamp(receipt.appliedAt)}')
      ..writeln(
        '  ${l.resultDeviceLabel}: ${receipt.deviceName.isEmpty ? receipt.serialNumber : receipt.deviceName}',
      )
      ..writeln('  ${l.resultSerialLabel}: ${receipt.serialNumber}')
      ..writeln('  ${l.resultModelLabel}: ${receipt.model}')
      ..writeln(
        '  ${l.exportSectionsLabel}: ${receipt.sections.isEmpty ? '—' : receipt.sections.join(', ')}',
      )
      ..writeln();
  }
  return buffer.toString();
}

/// Save-text-elsewhere flow: native save dialog → write. Returns true only
/// when the bytes landed on disk.
Future<bool> exportTextFile(String defaultName, String text) async {
  try {
    final location = await getSaveLocation(suggestedName: defaultName);
    if (location == null) return false;
    await File(location.path).writeAsString(text, flush: true);
    return true;
  } catch (_) {
    // Cancelled dialog, missing channel (tests), or IO failure — the caller
    // shows its failure feedback; nothing here is worth a crash.
    return false;
  }
}
