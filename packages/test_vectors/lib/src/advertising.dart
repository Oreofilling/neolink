/// 广播发现族向量：Advertising Data 27B 布局、Scan Response 名称、META Characteristic。
/// 字节依据 CT_PROV_PROTOCOL.md §4（UUID 小端、偏移表、示例字节逐字节对齐）。
library;

/// Advertising Data 向量。expect 为 Client 解析后的发现记录；
/// `modelCodeName` 仅在已知映射时出现，未知型号仍可解析与连接。
final class AdvertisingVector {
  const AdvertisingVector({
    required this.id,
    required this.description,
    required this.advData,
    required this.expect,
  });

  final String id;
  final String description;
  final List<int> advData;
  final Map<String, Object?> expect;
}

/// Scan Response 名称向量。`scanResponse` 为 null 时模拟名称缺失，
/// expect.tempDisplayName 给出按 model_code + mac_suffix 生成的临时名。
final class NameVector {
  const NameVector({
    required this.id,
    required this.description,
    this.scanResponse,
    required this.expect,
  });

  final String id;
  final String description;
  final List<int>? scanResponse;
  final Map<String, Object?> expect;
}

/// META Characteristic 向量（§4.3 二进制结构，≤20 字节）。
final class MetaVector {
  const MetaVector({
    required this.id,
    required this.description,
    required this.meta,
    required this.expect,
  });

  final String id;
  final String description;
  final List<int> meta;
  final Map<String, Object?> expect;
}

/// CT-Prov Service UUID `7B1E0001-9D5B-4B5B-8F6D-2A4C0B7E0100` 的广播小端字节序。
const List<int> kServiceUuidLe = [
  0x00, 0x01, 0x7E, 0x0B, 0x4C, 0x2A, 0x6D, 0x8F, //
  0x5B, 0x4B, 0x5B, 0x9D, 0x01, 0x00, 0x1E, 0x7B,
];

/// 拼装完整 Advertising Data：`02 01 06` + `17 21` + UUID 小端 + 6 字节发现负载。
List<int> _adv({
  required int formatVersion,
  required int modelCode,
  required List<int> macSuffix,
  required int flags,
}) => [
  0x02, 0x01, 0x06, 0x17, 0x21, ...kServiceUuidLe, //
  formatVersion, modelCode, ...macSuffix, flags,
];

/// 拼装 Complete Local Name 的 Scan Response（Length = 1 + name 字节数）。
List<int> _scanRsp(String name) => [1 + name.length, 0x09, ...name.codeUnits];

/// 拼装 META：protocol_version + flags + name_length + ASCII 名称。
List<int> _meta({required int flags, required String name}) =>
    [0x01, flags, name.length, ...name.codeUnits];

final List<AdvertisingVector> kAdvertisingVectors = [
  AdvertisingVector(
    id: 'adv-baseline-ne101',
    description: '协议 §4.2.2 示例逐字节：NE101 / A1B2C3 / PROVISIONABLE',
    advData: _adv(formatVersion: 0x01, modelCode: 0x01, macSuffix: [0xA1, 0xB2, 0xC3], flags: 0x02),
    expect: {
      'formatVersion': 1,
      'modelCode': 0x01,
      'modelCodeName': 'NE101',
      'macSuffix': 'A1B2C3',
      'busy': false,
      'provisionable': true,
    },
  ),
  AdvertisingVector(
    id: 'adv-ne301',
    description: 'NE301 型号码 / 84C102 / PROVISIONABLE',
    advData: _adv(formatVersion: 0x01, modelCode: 0x02, macSuffix: [0x84, 0xC1, 0x02], flags: 0x02),
    expect: {
      'formatVersion': 1,
      'modelCode': 0x02,
      'modelCodeName': 'NE301',
      'macSuffix': '84C102',
      'busy': false,
      'provisionable': true,
    },
  ),
  AdvertisingVector(
    id: 'adv-unknown-model',
    description: '未知 model_code=0x3C：不隐藏不拒绝，仍解析 mac_suffix 并允许连接',
    advData: _adv(formatVersion: 0x01, modelCode: 0x3C, macSuffix: [0xA1, 0xB2, 0xC3], flags: 0x02),
    expect: {
      'formatVersion': 1,
      'modelCode': 0x3C,
      'modelCodeKnown': false,
      'macSuffix': 'A1B2C3',
      'busy': false,
      'provisionable': true,
    },
  ),
  AdvertisingVector(
    id: 'adv-busy',
    description: 'BUSY=1：显示为不可配置，不自动连接',
    advData: _adv(formatVersion: 0x01, modelCode: 0x01, macSuffix: [0xA1, 0xB2, 0xC3], flags: 0x01),
    expect: {
      'formatVersion': 1,
      'modelCode': 0x01,
      'modelCodeName': 'NE101',
      'macSuffix': 'A1B2C3',
      'busy': true,
      'provisionable': false,
    },
  ),
  AdvertisingVector(
    id: 'adv-busy-combo-invalid',
    description: 'Server 违规组合 BUSY=1 且 PROVISIONABLE=1：Client 一律按不可配置处理',
    advData: _adv(formatVersion: 0x01, modelCode: 0x01, macSuffix: [0xA1, 0xB2, 0xC3], flags: 0x03),
    expect: {
      'formatVersion': 1,
      'modelCode': 0x01,
      'modelCodeName': 'NE101',
      'macSuffix': 'A1B2C3',
      'busy': true,
      'provisionable': false,
      'comboViolation': true,
    },
  ),
  AdvertisingVector(
    id: 'adv-reserved-bits',
    description: '保留位被置 1（flags=0xFE）：Server 违规，Client 忽略保留位',
    advData: _adv(formatVersion: 0x01, modelCode: 0x01, macSuffix: [0xA1, 0xB2, 0xC3], flags: 0xFE),
    expect: {
      'formatVersion': 1,
      'modelCode': 0x01,
      'modelCodeName': 'NE101',
      'macSuffix': 'A1B2C3',
      'busy': false,
      'provisionable': true,
      'reservedBitsIgnored': true,
    },
  ),
  AdvertisingVector(
    id: 'adv-not-provisionable',
    description: 'flags=0：既不 BUSY 也不可配置（如产测模式），正常展示为不可配置',
    advData: _adv(formatVersion: 0x01, modelCode: 0x01, macSuffix: [0xA1, 0xB2, 0xC3], flags: 0x00),
    expect: {
      'formatVersion': 1,
      'modelCode': 0x01,
      'modelCodeName': 'NE101',
      'macSuffix': 'A1B2C3',
      'busy': false,
      'provisionable': false,
    },
  ),
  AdvertisingVector(
    id: 'adv-unsupported-format',
    description: 'format_version=0x02：停止解释后续字段，仍可按 Service UUID 展示并连接',
    advData: _adv(formatVersion: 0x02, modelCode: 0x01, macSuffix: [0xA1, 0xB2, 0xC3], flags: 0x02),
    expect: {
      'formatVersion': 2,
      'formatVersionSupported': false,
      'payloadFieldsReliable': false,
    },
  ),
];

final List<NameVector> kNameVectors = [
  NameVector(
    id: 'name-baseline',
    description: '协议 §4.2.3 示例逐字节：NE101-A1B2C3（12B）',
    scanResponse: _scanRsp('NE101-A1B2C3'),
    expect: {'name': 'NE101-A1B2C3', 'modelPrefix': 'NE101', 'macSuffix': 'A1B2C3'},
  ),
  NameVector(
    id: 'name-min-9',
    description: '最短名称 9B：MODEL 2 位 + - + 6 位 MAC 后缀',
    scanResponse: _scanRsp('NE-ABCDEF'),
    expect: {'name': 'NE-ABCDEF', 'modelPrefix': 'NE', 'macSuffix': 'ABCDEF'},
  ),
  NameVector(
    id: 'name-max-17',
    description: '最长名称 17B：MODEL 10 位 + - + 6 位 MAC 后缀',
    scanResponse: _scanRsp('NE12345678-ABCDEF'),
    expect: {'name': 'NE12345678-ABCDEF', 'modelPrefix': 'NE12345678', 'macSuffix': 'ABCDEF'},
  ),
  NameVector(
    id: 'name-missing-scanrsp',
    description: 'Scan Response 暂缺：按 model_code + mac_suffix 生成临时名，收到后再更新',
    scanResponse: null,
    expect: {
      'name': null,
      'tempDisplayName': 'NE101-A1B2C3',
      'source': 'derived',
    },
  ),
  NameVector(
    id: 'name-invalid-charset',
    description: '名称含小写字母（仅允许 A-Z 0-9 -）：解析失败，回退临时名',
    scanResponse: _scanRsp('ne101-abc123'),
    expect: {'name': null, 'tempDisplayName': 'NE101-A1B2C3', 'source': 'derived', 'invalidCharset': true},
  ),
];

final List<MetaVector> kMetaVectors = [
  MetaVector(
    id: 'meta-baseline',
    description: '§4.3 基线：protocol_version=1 + flags + 名称（与 Scan Response 一致）',
    meta: _meta(flags: 0x02, name: 'NE101-A1B2C3'),
    expect: {
      'protocolVersion': 1,
      'busy': false,
      'provisionable': true,
      'name': 'NE101-A1B2C3',
      'matchesScanResponse': true,
    },
  ),
  MetaVector(
    id: 'meta-max-20',
    description: '20B 上限边界：3 + 17B 名称，MTU 23 下一次 Read 可返回',
    meta: _meta(flags: 0x02, name: 'NE12345678-ABCDEF'),
    expect: {
      'protocolVersion': 1,
      'busy': false,
      'provisionable': true,
      'name': 'NE12345678-ABCDEF',
      'matchesScanResponse': true,
    },
  ),
  MetaVector(
    id: 'meta-name-mismatch',
    description: 'META 名称与 Scan Response 不一致（§4.3 要求完全一致）：标记违规',
    meta: _meta(flags: 0x02, name: 'NE301-84C102'),
    expect: {
      'protocolVersion': 1,
      'busy': false,
      'provisionable': true,
      'name': 'NE301-84C102',
      'matchesScanResponse': false,
    },
  ),
];
