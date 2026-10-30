/// 各平台 Service Data 值 → §4.2.2 的 27 字节广播数据重建。
///
/// Android/BlueZ 在 Service Data 值前自带 16 字节 UUID，WinRT/Apple 只给
/// UUID 之后的数据；两种形态都归一成 6 字节协议字段，再拼上固定头部
/// （02 01 06 | 17 21 | UUID 小端）交给 ble_adapter 的解析器。
library;

import 'package:ble_adapter/ble_adapter.dart';

/// 由 Service Data 值重建可解析的 27 字节广播数据；形态不符返回 null。
List<int>? buildAdvertisingData(List<int> serviceDataValue) {
  List<int> payload;
  if (serviceDataValue.length == 6) {
    payload = serviceDataValue;
  } else if (serviceDataValue.length == 22 &&
      _startsWithServiceUuid(serviceDataValue)) {
    payload = serviceDataValue.sublist(16);
  } else {
    return null;
  }
  return <int>[
    0x02, 0x01, 0x06, // Flags AD 结构
    0x17, 0x21, // Service Data：Length 23 + AD Type 0x21
    ...kCtProvServiceUuidLe, // UUID 小端（16 字节）
    ...payload, // format_version/model_code/mac_suffix/flags（6 字节）
  ];
}

bool _startsWithServiceUuid(List<int> value) {
  for (var i = 0; i < kCtProvServiceUuidLe.length; i++) {
    if (value[i] != kCtProvServiceUuidLe[i]) return false;
  }
  return true;
}

/// Complete Local Name（§4.2.3 scan response）→ 0x09 AD 结构重建；
/// 无名字或超长返回 null（名字合法性与 device_name 规则交给解析器）。
List<int>? buildScanResponse(String? localName) {
  if (localName == null || localName.isEmpty) return null;
  final codes = localName.codeUnits;
  if (codes.length > 29) return null;
  return <int>[codes.length + 1, 0x09, ...codes];
}

/// §4.2.1 device_name 形态：MODEL（2-10 个大写字母数字）+ '-' + 6 位大写十六进制。
final RegExp _ctNamePattern = RegExp(r'^([A-Z0-9]{2,10})-([0-9A-F]{6})$');

/// 已知型号名 → model_code 反查表（kModelCodeNames 的镜像）。
final Map<String, int> _modelNameToCode = {
  for (final entry in kModelCodeNames.entries) entry.value: entry.key,
};

/// 名称兜底解析：平台不透出 Service Data（如 Windows watcher 对 128-bit
/// Service Data 的支持不全）时，用 Scan Response 名字推导身份。
/// mac_suffix/model 段来自名字本身，广播负载字段（format_version/
/// flags/busy）未知，以 payloadFieldsReliable=false 标注。名字不合规
/// 返回 null。
CtDiscoveredDevice? ctInfoFromName(String? name) {
  if (name == null) return null;
  final match = _ctNamePattern.firstMatch(name);
  if (match == null) return null;
  final model = match.group(1)!;
  final macSuffix = match.group(2)!;
  final modelCode = _modelNameToCode[model];
  return CtDiscoveredDevice(
    formatVersion: 1,
    formatVersionSupported: true,
    payloadFieldsReliable: false,
    modelCode: modelCode,
    modelCodeName: modelCode == null ? null : model,
    macSuffix: macSuffix,
    advertisedName: name,
    displayName: name,
    nameSource: NameSource.scanResponse,
  );
}
