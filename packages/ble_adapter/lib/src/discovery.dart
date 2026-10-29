/// §4 发现解析：Advertising Data 27B 布局、Scan Response 名称与
/// META Characteristic。解析只做字段提取与协议语义（未知型号降级、
/// BUSY 违规组合按不可配置、保留位忽略、format_version 不支持即停），
/// 不做策略（是否展示、是否连接由上层决定）。
library;

/// Service UUID `7B1E0001-9D5B-4B5B-8F6D-2A4C0B7E0100` 的广播小端字节序。
const List<int> kCtProvServiceUuidLe = [
  0x00, 0x01, 0x7E, 0x0B, 0x4C, 0x2A, 0x6D, 0x8F,
  0x5B, 0x4B, 0x5B, 0x9D, 0x01, 0x00, 0x1E, 0x7B,
];

/// 已知 model_code 到型号名映射（未知型号不拒绝，仅无名）。
const Map<int, String> kModelCodeNames = {0x01: 'NE101', 0x02: 'NE301'};

/// 名称字符集与长度界：A-Z 0-9 -，9 到 17 字节。
final RegExp _namePattern = RegExp(r'^[A-Z0-9-]{9,17}$');

/// 名称来源。
enum NameSource { scanResponse, derived }

/// 一台被发现的 CT 设备（广播负载 + 可选 Scan Response 名称）。
final class CtDiscoveredDevice {
  const CtDiscoveredDevice({
    required this.formatVersion,
    required this.formatVersionSupported,
    required this.payloadFieldsReliable,
    this.modelCode,
    this.modelCodeName,
    this.macSuffix,
    this.busy,
    this.provisionable,
    this.advertisedName,
    this.displayName,
    this.nameSource = NameSource.derived,
    this.nameInvalid = false,
  });

  final int formatVersion;
  final bool formatVersionSupported;

  /// format_version 不支持时负载字段一律不解释。
  final bool payloadFieldsReliable;
  final int? modelCode;

  /// 已知型号名；未知型号为 null。
  final String? modelCodeName;
  final String? macSuffix;
  final bool? busy;
  final bool? provisionable;

  /// Scan Response 中的 Complete Local Name；缺失或非法时为 null。
  final String? advertisedName;

  /// 展示名：广播名合法时即广播名，否则按 model_code + mac_suffix 生成。
  final String? displayName;
  final NameSource nameSource;
  final bool nameInvalid;

  /// 型号是否已知（未知型号仍可解析与连接）。
  bool get modelCodeKnown => modelCodeName != null;
}

/// 解析 Advertising Data。非 27B、AD 结构或 UUID 不匹配返回 null
/// （调用方应先按 Service UUID 过滤再交给本函数）。
CtDiscoveredDevice? parseAdvertisingData(List<int> advData) {
  if (advData.length != 27) return null;
  // Flags：02 01 06；Service Data：Length 0x17 + AD Type 0x21 + UUID 小端。
  if (advData[0] != 0x02 || advData[1] != 0x01 || advData[2] != 0x06) return null;
  if (advData[3] != 0x17 || advData[4] != 0x21) return null;
  for (var i = 0; i < kCtProvServiceUuidLe.length; i++) {
    if (advData[5 + i] != kCtProvServiceUuidLe[i]) return null;
  }

  final formatVersion = advData[21];
  final supported = formatVersion == 0x01;
  if (!supported) {
    // §4.2.2：不支持即停止解释后续字段，仍可按 Service UUID 展示并连接。
    return CtDiscoveredDevice(
      formatVersion: formatVersion,
      formatVersionSupported: false,
      payloadFieldsReliable: false,
    );
  }

  final modelCode = advData[22];
  final macSuffix = advData
      .sublist(23, 26)
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join();
  final flags = advData[26];
  // 保留位忽略；BUSY=1 时即使 PROVISIONABLE=1 也按不可配置处理（违规组合）。
  final busy = (flags & 0x01) != 0;
  final provisionable = !busy && (flags & 0x02) != 0;
  final modelName = kModelCodeNames[modelCode];

  return CtDiscoveredDevice(
    formatVersion: formatVersion,
    formatVersionSupported: true,
    payloadFieldsReliable: true,
    modelCode: modelCode,
    modelCodeName: modelName,
    macSuffix: macSuffix,
    busy: busy,
    provisionable: provisionable,
    displayName: _tempName(modelName, macSuffix),
  );
}

/// 应用 Scan Response（Complete Local Name）。null 表示本次未取到
/// Scan Response，维持临时名。返回新对象，不改动原记录。
CtDiscoveredDevice applyScanResponse(CtDiscoveredDevice device, List<int>? scanResponse) {
  String? name;
  var invalid = false;
  if (scanResponse != null && scanResponse.length >= 2 && scanResponse[1] == 0x09) {
    final candidate = String.fromCharCodes(scanResponse.sublist(2));
    if (_namePattern.hasMatch(candidate)) {
      name = candidate;
    } else {
      invalid = true;
    }
  }
  return CtDiscoveredDevice(
    formatVersion: device.formatVersion,
    formatVersionSupported: device.formatVersionSupported,
    payloadFieldsReliable: device.payloadFieldsReliable,
    modelCode: device.modelCode,
    modelCodeName: device.modelCodeName,
    macSuffix: device.macSuffix,
    busy: device.busy,
    provisionable: device.provisionable,
    advertisedName: name,
    displayName: name ?? device.displayName,
    nameSource: name == null ? NameSource.derived : NameSource.scanResponse,
    nameInvalid: invalid,
  );
}

/// META Characteristic 内容（§4.3，≤20 字节）。
final class CtMetaInfo {
  const CtMetaInfo({
    required this.protocolVersion,
    required this.busy,
    required this.provisionable,
    required this.name,
  });

  final int protocolVersion;
  final bool busy;
  final bool provisionable;
  final String name;

  /// META 名称与广播名完全一致才算匹配（§4.3 要求两者一致）。
  bool matches(String? advertisedName) => advertisedName == name;
}

/// 解析 META。空数据、协议版本不支持或 name_length 与实际不符返回 null。
CtMetaInfo? parseMeta(List<int> meta) {
  if (meta.length < 3 || meta.length > 20) return null;
  if (meta[0] != 0x01) return null;
  if (meta[2] != meta.length - 3) return null;
  final flags = meta[1];
  final busy = (flags & 0x01) != 0;
  return CtMetaInfo(
    protocolVersion: meta[0],
    busy: busy,
    provisionable: !busy && (flags & 0x02) != 0,
    name: String.fromCharCodes(meta.sublist(3)),
  );
}

String _tempName(String? modelName, String macSuffix) =>
    '${modelName ?? 'NE'}-$macSuffix';
