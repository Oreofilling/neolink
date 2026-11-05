// Native decode round trip against the real flutter_zxing.dll — the one
// path widget tests cannot cover (they inject fakes for the decoder).
//
// Runs only where the dll can be loaded: on Windows, after
// `flutter build windows` has produced it in the standard build output.
// The dll is preloaded by absolute path so flutter_zxing's bare-name
// DynamicLibrary.open resolves to the same already-loaded module. Anywhere
// else (CI, Linux) the suite skips with a note, and the fake-injected
// suites keep the wiring honest.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
// Unprefixed on purpose: `zx` below is the package's global Zxing instance,
// which an import prefix would shadow.
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:image/image.dart' as imglib;

import 'package:desktop_app/shell/widgets/qr_camera_scanner.dart';

const _kValidUri =
    'ctdev://guide-v1/A1B2C3?m=NE101&c=01&g=ne101_config_button_v1';

// Relative to the package directory (flutter test's working directory).
const _dllPath = r'build\windows\x64\runner\Release\flutter_zxing.dll';

void main() {
  if (!Platform.isWindows) {
    // ignore: avoid_print
    print('qr_native_test: skipped — Windows only');
    return;
  }
  final dll = File(_dllPath);
  if (!dll.existsSync()) {
    // ignore: avoid_print
    print('qr_native_test: skipped — $_dllPath not found (build the app first)');
    return;
  }
  DynamicLibrary.open(dll.absolute.path);

  test('production decoder reads an encoded spec QR from a PNG file', () async {
    // Round trip: encode the spec URI into a QR bitmap, wrap it as a PNG on
    // disk, then run the exact production decoder (PNG bytes -> RGB buffer
    // -> native zxing) over the file.
    final encoded = zx.encodeBarcode(
      contents: _kValidUri,
      params: EncodeParams(
        format: Format.qrCode,
        width: 400,
        height: 400,
        margin: 16,
        eccLevel: EccLevel.medium,
      ),
    );
    expect(encoded.isValid, isTrue, reason: encoded.error ?? 'encode failed');

    final data = encoded.data!;
    // The writer may return a matrix smaller than the request; a QR is
    // square, so the side is the exact square root of the byte count.
    final side = sqrt(data.length).round();
    expect(side * side, data.length, reason: 'expected a square bitmap');
    final bitmap = imglib.Image.fromBytes(
      width: side,
      height: side,
      bytes: data.buffer,
      bytesOffset: data.offsetInBytes,
      numChannels: 1,
    );
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'ctdev_native_roundtrip.png',
    );
    file.writeAsBytesSync(imglib.encodePng(bitmap));
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });

    final text = await zxingQrDecoder(file.path);
    expect(text, _kValidUri);
  });

  test('sample QR shipped with the box decodes when present', () async {
    // Optional extra: the sample PNG staged at F:\work on the build box.
    // Absent elsewhere, so the test adapts instead of failing.
    const sample = r'F:\work\ctdev_sample_ne101.png';
    if (!File(sample).existsSync()) {
      // ignore: avoid_print
      print('qr_native_test: sample PNG not present — skipped');
      return;
    }
    final text = await zxingQrDecoder(sample);
    expect(text, _kValidUri);
  });
}
