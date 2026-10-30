import 'package:ble_adapter/ble_adapter.dart';
import 'package:ble_universal/src/ct_adv_source.dart';
import 'package:test/test.dart';

/// NE301 广播协议字段（§4.2.2）：format_version 0x01、model_code 0x02、
/// MAC 后缀 AA:BB:CC、flags 0x00。
const List<int> kNe301Payload = [0x01, 0x02, 0xAA, 0xBB, 0xCC, 0x00];

void main() {
  group('buildAdvertisingData', () {
    test('stripped value (6B) reconstructs the 27-byte layout', () {
      final adv = buildAdvertisingData(kNe301Payload);
      expect(adv, isNotNull);
      final bytes = adv!;
      expect(bytes.length, 27);
      expect(bytes.sublist(0, 5), [0x02, 0x01, 0x06, 0x17, 0x21]);
      expect(bytes.sublist(5, 21), kCtProvServiceUuidLe);
      expect(bytes.sublist(21), kNe301Payload);

      final info = parseAdvertisingData(bytes);
      expect(info, isNotNull);
      expect(info!.modelCodeName, 'NE301');
      expect(info.macSuffix?.toUpperCase(), 'AABBCC');
      expect(info.formatVersionSupported, isTrue);
    });

    test('uuid-prefixed value (22B) yields the same 27 bytes', () {
      final prefixed = [...kCtProvServiceUuidLe, ...kNe301Payload];
      expect(
        buildAdvertisingData(prefixed),
        buildAdvertisingData(kNe301Payload),
      );
    });

    test('wrong uuid prefix is rejected', () {
      final wrongUuid = [...kCtProvServiceUuidLe]..[0] ^= 0xFF;
      expect(buildAdvertisingData([...wrongUuid, ...kNe301Payload]), isNull);
    });

    test('wrong lengths are rejected', () {
      expect(buildAdvertisingData(kNe301Payload.sublist(0, 5)), isNull);
      expect(buildAdvertisingData([...kNe301Payload, 0x00]), isNull);
      expect(buildAdvertisingData(const []), isNull);
    });
  });

  group('buildScanResponse', () {
    test('wraps the local name in a 0x09 AD structure', () {
      final response = buildScanResponse('NE301-AABBCC');
      expect(response, isNotNull);
      expect(response!.length, 14);
      expect(response[0], 13); // len = type(1) + name(12)
      expect(response[1], 0x09);
      expect(String.fromCharCodes(response.sublist(2)), 'NE301-AABBCC');
    });

    test('empty names yield null', () {
      expect(buildScanResponse(null), isNull);
      expect(buildScanResponse(''), isNull);
    });

    test('round-trips through applyScanResponse', () {
      final adv = buildAdvertisingData(kNe301Payload)!;
      final info = applyScanResponse(
        parseAdvertisingData(adv)!,
        buildScanResponse('NE301-AABBCC'),
      );
      expect(info.advertisedName, 'NE301-AABBCC');
      expect(info.nameInvalid, isFalse);
    });
  });

  group('ctInfoFromName', () {
    test('derives identity from a known model name', () {
      final info = ctInfoFromName('NE101-BBC6DC');
      expect(info, isNotNull);
      expect(info!.modelCode, 0x01);
      expect(info.modelCodeName, 'NE101');
      expect(info.macSuffix, 'BBC6DC');
      expect(info.displayName, 'NE101-BBC6DC');
      expect(info.advertisedName, 'NE101-BBC6DC');
      expect(info.nameSource, NameSource.scanResponse);
      // 广播负载未取到：字段可靠性标注为 false。
      expect(info.payloadFieldsReliable, isFalse);
      expect(info.busy, isNull);
      expect(info.provisionable, isNull);
    });

    test('unknown model keeps the name but drops the code', () {
      final info = ctInfoFromName('XY-112233');
      expect(info, isNotNull);
      expect(info!.modelCode, isNull);
      expect(info.modelCodeName, isNull);
      expect(info.macSuffix, '112233');
      expect(info.displayName, 'XY-112233');
    });

    test('rejects non-conforming names', () {
      expect(ctInfoFromName(null), isNull);
      expect(ctInfoFromName(''), isNull);
      expect(ctInfoFromName('ne101-bbc6dc'), isNull); // 小写
      expect(ctInfoFromName('NE101-bbc6dc'), isNull); // 后缀小写
      expect(ctInfoFromName('NE101-BBC6DCX'), isNull); // 后缀 7 位
      expect(ctInfoFromName('NE101-BBC6D'), isNull); // 后缀 5 位
      expect(ctInfoFromName('N-BBC6DC'), isNull); // MODEL 过短
      expect(ctInfoFromName('NE101BBC6DC'), isNull); // 缺连字符
      expect(ctInfoFromName('NE101-P-BBC6DC'), isNull); // 双连字符
    });
  });
}
