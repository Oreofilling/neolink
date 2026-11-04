// Stage 3: strict parser tests for the ctdev:// guide QR URI
// (firmware docs/CT_DEVICE_QR_SPEC.md §2-§6). Everything that does not
// match the grammar exactly must be rejected — the QR is a hint, never
// a connection.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:desktop_app/provisioning/device_qr_uri.dart';

void main() {
  const validUri =
      'ctdev://guide-v1/A1B2C3?m=NE101&c=01&g=ne101_config_button_v1';

  group('accepts spec-conforming URIs', () {
    test('parses the spec example', () {
      final uri = DeviceQrUri.tryParse(validUri)!;
      expect(uri.macSuffix, 'A1B2C3');
      expect(uri.model, 'NE101');
      expect(uri.channelMask, 0x01);
      expect(uri.hasBle, isTrue);
      expect(uri.hasAccessPoint, isFalse);
      expect(uri.hasCtDisc, isFalse);
      expect(uri.guideId, 'ne101_config_button_v1');
    });

    test('query order does not matter', () {
      final uri = DeviceQrUri.tryParse(
        'ctdev://guide-v1/9F8E7D?g=ne101_config_button_v1&c=03&m=NE101',
      )!;
      expect(uri.macSuffix, '9F8E7D');
      expect(uri.channelMask, 0x03);
      expect(uri.hasBle, isTrue);
      expect(uri.hasAccessPoint, isTrue);
    });

    test('all three channel bits may be set', () {
      final uri = DeviceQrUri.tryParse(
        'ctdev://guide-v1/A1B2C3?m=NE101&c=07&g=ne101_config_button_v1',
      )!;
      expect(uri.hasBle, isTrue);
      expect(uri.hasAccessPoint, isTrue);
      expect(uri.hasCtDisc, isTrue);
    });

    test('model may use the full charset', () {
      final uri = DeviceQrUri.tryParse(
        'ctdev://guide-v1/A1B2C3?m=CT-2_X9&c=04&g=abc-123_x',
      )!;
      expect(uri.model, 'CT-2_X9');
      expect(uri.hasCtDisc, isTrue);
    });
  });

  group('rejects malformed URIs', () {
    test('empty input', () {
      expect(DeviceQrUri.tryParse(''), isNull);
    });

    test('wrong scheme', () {
      expect(
        DeviceQrUri.tryParse(
          'http://guide-v1/A1B2C3?m=NE101&c=01&g=ne101_config_button_v1',
        ),
        isNull,
      );
      expect(
        DeviceQrUri.tryParse(
          'CTDEV://guide-v1/A1B2C3?m=NE101&c=01&g=ne101_config_button_v1',
        ),
        isNull,
      );
    });

    test('wrong authority', () {
      expect(
        DeviceQrUri.tryParse(
          'ctdev://guide-v2/A1B2C3?m=NE101&c=01&g=ne101_config_button_v1',
        ),
        isNull,
      );
    });

    test('uppercase authority is rejected', () {
      expect(
        DeviceQrUri.tryParse(
          'ctdev://GUIDE-V1/A1B2C3?m=NE101&c=01&g=ne101_config_button_v1',
        ),
        isNull,
      );
    });

    test('MAC suffix: wrong length', () {
      for (final suffix in ['A1B2C', 'A1B2C33', 'A1B2C3D']) {
        expect(
          DeviceQrUri.tryParse(
            'ctdev://guide-v1/$suffix?m=NE101&c=01&g=ne101_config_button_v1',
          ),
          isNull,
          reason: suffix,
        );
      }
    });

    test('MAC suffix: lowercase hex rejected', () {
      expect(
        DeviceQrUri.tryParse(
          'ctdev://guide-v1/a1b2c3?m=NE101&c=01&g=ne101_config_button_v1',
        ),
        isNull,
      );
    });

    test('MAC suffix: non-hex characters rejected', () {
      expect(
        DeviceQrUri.tryParse(
          'ctdev://guide-v1/G1B2C3?m=NE101&c=01&g=ne101_config_button_v1',
        ),
        isNull,
      );
    });

    test('extra path segment rejected', () {
      expect(
        DeviceQrUri.tryParse(
          'ctdev://guide-v1/A1B2C3/extra?m=NE101&c=01&g=ne101_config_button_v1',
        ),
        isNull,
      );
    });

    test('missing query rejected', () {
      expect(DeviceQrUri.tryParse('ctdev://guide-v1/A1B2C3'), isNull);
    });

    test('missing query field rejected', () {
      expect(
        DeviceQrUri.tryParse('ctdev://guide-v1/A1B2C3?m=NE101&c=01'),
        isNull,
      );
      expect(
        DeviceQrUri.tryParse('ctdev://guide-v1/A1B2C3?c=01&g=cfg_v1'),
        isNull,
      );
    });

    test('unknown query field rejected', () {
      expect(
        DeviceQrUri.tryParse(
          'ctdev://guide-v1/A1B2C3?m=NE101&c=01&g=cfg_v1&x=1',
        ),
        isNull,
      );
    });

    test('duplicate query field rejected', () {
      expect(
        DeviceQrUri.tryParse(
          'ctdev://guide-v1/A1B2C3?m=NE101&m=NE102&c=01&g=cfg_v1',
        ),
        isNull,
      );
    });

    test('empty query value rejected', () {
      expect(
        DeviceQrUri.tryParse('ctdev://guide-v1/A1B2C3?m=&c=01&g=cfg_v1'),
        isNull,
      );
    });

    test('fragment rejected', () {
      expect(
        DeviceQrUri.tryParse(
          'ctdev://guide-v1/A1B2C3?m=NE101&c=01&g=cfg_v1#top',
        ),
        isNull,
      );
    });

    test('second question mark rejected', () {
      expect(
        DeviceQrUri.tryParse(
          'ctdev://guide-v1/A1B2C3?m=NE101&c=01&g=cfg_v1?x',
        ),
        isNull,
      );
    });

    test('model charset violations rejected', () {
      // lowercase, too long (17), illegal punctuation
      for (final model in ['ne101', 'NE1011234567890XY', 'NE.101']) {
        expect(
          DeviceQrUri.tryParse(
            'ctdev://guide-v1/A1B2C3?m=$model&c=01&g=cfg_v1',
          ),
          isNull,
          reason: model,
        );
      }
    });

    test('channels: non-hex, wrong length, zero, reserved bits', () {
      for (final channels in ['1', '0X', 'ZZ', '00', '08', 'FF', '9']) {
        expect(
          DeviceQrUri.tryParse(
            'ctdev://guide-v1/A1B2C3?m=NE101&c=$channels&g=cfg_v1',
          ),
          isNull,
          reason: channels,
        );
      }
    });

    test('guide id charset violations rejected', () {
      for (final guideId in ['CFG_V1', 'cfg v1', 'cfg.v1']) {
        expect(
          DeviceQrUri.tryParse(
            'ctdev://guide-v1/A1B2C3?m=NE101&c=01&g=$guideId',
          ),
          isNull,
          reason: guideId,
        );
      }
    });

    test('guide id longer than 48 chars rejected', () {
      final longId = 'a' * 49;
      expect(
        DeviceQrUri.tryParse(
          'ctdev://guide-v1/A1B2C3?m=NE101&c=01&g=$longId',
        ),
        isNull,
      );
    });

    test('payload over 128 bytes rejected', () {
      // 16-char model + 48-char guide + padding pushes past 128 chars.
      final fatUri = 'ctdev://guide-v1/A1B2C3?m=NE1011234567890&c=01'
          '&g=${'a' * 48}&pad=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';
      expect(fatUri.length, greaterThan(128));
      expect(DeviceQrUri.tryParse(fatUri), isNull);
    });

    test('non-ASCII rejected', () {
      expect(
        DeviceQrUri.tryParse(
          'ctdev://guide-v1/A1B2C3?m=NE101&c=01&g=配置',
        ),
        isNull,
      );
    });

    test('whitespace inside values rejected, surrounding trimmed', () {
      expect(
        DeviceQrUri.tryParse(
          'ctdev://guide-v1/A1B2C3?m=NE101&c=01&g=cfg v1',
        ),
        isNull,
      );
      // Decode engines sometimes emit leading/trailing spaces; the parser
      // trims them (documented tolerance) and accepts the URI.
      expect(
        DeviceQrUri.tryParse(
          ' ctdev://guide-v1/A1B2C3?m=NE101&c=01&g=cfg_v1 ',
        ),
        isNotNull,
      );
    });

    test('percent-encoding rejected', () {
      expect(
        DeviceQrUri.tryParse(
          'ctdev://guide-v1/A1B2C3?m=NE101&c=01&g=cfg%5Fv1',
        ),
        isNull,
      );
    });
  });
}
