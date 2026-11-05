import 'package:ble_adapter/ble_adapter.dart';
import 'package:test/test.dart';
import 'package:test_vectors/test_vectors.dart' as tv;

/// 黄金向量驱动的 §4 发现解析测试：广播 27B 布局、Scan Response 名称、
/// META Characteristic 三族向量的 expect 即解析契约。
void main() {
  test('广播向量：解析字段与 expect 一致', () {
    for (final v in tv.kAdvertisingVectors) {
      final dev = parseAdvertisingData(v.advData);
      expect(dev, isNotNull, reason: '${v.id} 合法广播必须可解析');
      final e = v.expect;
      expect(dev!.formatVersion, e['formatVersion'],
          reason: '${v.id} format_version');
      if (e['formatVersionSupported'] == false) {
        // format_version 不支持：停止解释负载字段（§4.2.2）
        expect(dev.formatVersionSupported, isFalse, reason: '${v.id} 不支持标记');
        expect(dev.payloadFieldsReliable, isFalse, reason: '${v.id} 负载不可信标记');
        expect(dev.macSuffix, isNull, reason: '${v.id} 不解释 mac_suffix');
        continue;
      }
      expect(dev.formatVersionSupported, isTrue, reason: '${v.id} 支持标记');
      expect(dev.modelCode, e['modelCode'], reason: '${v.id} model_code');
      expect(dev.macSuffix, e['macSuffix'], reason: '${v.id} mac_suffix');
      if (e['modelCodeName'] != null) {
        expect(dev.modelCodeName, e['modelCodeName'], reason: '${v.id} 已知型号名');
      } else {
        expect(dev.modelCodeKnown, isFalse, reason: '${v.id} 未知型号不拒绝');
      }
      expect(dev.busy, e['busy'], reason: '${v.id} BUSY 位');
      expect(dev.provisionable, e['provisionable'],
          reason: '${v.id} PROVISIONABLE 位');
    }
  });

  test('广播解析：非法布局返回 null（长度、AD 结构、UUID 逐项校验）', () {
    expect(parseAdvertisingData([]), isNull, reason: '空广播');
    expect(parseAdvertisingData([0x02, 0x01, 0x06]), isNull, reason: '过短');
    final baseline = tv.kAdvertisingVectors.first.advData;
    expect(parseAdvertisingData([...baseline, 0x00]), isNull, reason: '长度非 27');
    final wrongUuid = List<int>.of(baseline)..[5] = 0xFF;
    expect(parseAdvertisingData(wrongUuid), isNull, reason: 'UUID 不匹配');
  });

  test('名称向量：Scan Response 应用后与 expect 一致', () {
    for (final v in tv.kNameVectors) {
      final base = parseAdvertisingData(tv.kAdvertisingVectors.first.advData)!;
      final dev = applyScanResponse(base, v.scanResponse);
      final e = v.expect;
      if (e['name'] != null) {
        expect(dev.advertisedName, e['name'], reason: '${v.id} 广播名');
        expect(dev.nameSource, NameSource.scanResponse, reason: '${v.id} 名称来源');
      } else {
        expect(dev.advertisedName, isNull, reason: '${v.id} 无广播名');
        expect(dev.displayName, e['tempDisplayName'], reason: '${v.id} 临时名回退');
        expect(dev.nameSource, NameSource.derived, reason: '${v.id} 名称来源');
      }
      // 展示名恒非空：广播名缺失或非法时回退临时名。
      expect(dev.displayName, e['name'] ?? e['tempDisplayName'],
          reason: '${v.id} 展示名');
      if (e['invalidCharset'] == true) {
        expect(dev.nameInvalid, isTrue, reason: '${v.id} 非法字符集标记');
      }
    }
  });

  test('META 向量：解析与名称一致性检查', () {
    final base = parseAdvertisingData(tv.kAdvertisingVectors.first.advData)!;
    // 各 META 向量对应自己的 Scan Response 名称（§4.3 要求两者一致）。
    final rspById = {
      'meta-baseline': tv.kNameVectors[0].scanResponse,
      'meta-max-20':
          tv.kNameVectors.firstWhere((n) => n.id == 'name-max-17').scanResponse,
      'meta-name-mismatch': tv.kNameVectors[0].scanResponse,
    };
    for (final v in tv.kMetaVectors) {
      final meta = parseMeta(v.meta);
      final e = v.expect;
      expect(meta, isNotNull, reason: '${v.id} META 必须可解析');
      expect(meta!.protocolVersion, e['protocolVersion'],
          reason: '${v.id} 协议版本');
      expect(meta.busy, e['busy'], reason: '${v.id} BUSY');
      expect(meta.provisionable, e['provisionable'],
          reason: '${v.id} PROVISIONABLE');
      expect(meta.name, e['name'], reason: '${v.id} 名称');
      final advertisedName =
          applyScanResponse(base, rspById[v.id]).advertisedName;
      expect(meta.matches(advertisedName), e['matchesScanResponse'],
          reason: '${v.id} 与广播名一致性');
    }
  });

  test('META 解析：非法输入返回 null', () {
    expect(parseMeta([]), isNull, reason: '空');
    expect(parseMeta([0x02, 0x00, 0x01, 0x41]), isNull, reason: '协议版本不支持');
    expect(parseMeta([0x01, 0x00, 0x05, 0x41]), isNull,
        reason: 'name_length 与长度不符');
  });
}
