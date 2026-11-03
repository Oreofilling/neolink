/// 字段校验（CT_CONFIG_SCHEMA.md 约束）：长度按 UTF-8 字节计；能力未
/// 声明的字段带非空值时报 notDeclared，绝不静默丢弃用户输入。
library;

import 'dart:convert';

import 'sections.dart';

/// 字段问题类型：UI 按 field 定位标注，code 驱动文案。
enum FieldProblemCode {
  /// 能力未声明该字段却携带了值（提交会被设备拒为 FIELD_NOT_SUPPORTED）。
  notDeclared,

  /// 必填字段为空。
  required,

  /// 低于最小长度（或最小值）。
  tooShort,

  /// 超过最大长度（或最大值）。
  tooLong,

  /// 格式非法（bssid/country/pin/topic/url/header 等）。
  invalidFormat,

  /// 取值不在枚举或范围内（auth/port/qos/comm.type 等）。
  invalidValue,
}

/// 单个字段的一条问题；detail 为诊断串（实际值/期望形状）。
final class FieldProblem {
  const FieldProblem(this.field, this.code, [this.detail = '']);
  final String field;
  final FieldProblemCode code;
  final String detail;

  @override
  bool operator ==(Object other) =>
      other is FieldProblem &&
      other.field == field &&
      other.code == code &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(field, code, detail);

  @override
  String toString() => '$field:${code.name}$detail';
}

int _bytes(String value) => utf8.encode(value).length;

/// 能力未声明而值非空：notDeclared；空值视为未提供，直接放行。
List<FieldProblem> _gate(String field, String value, List<String> declared) =>
    value.isEmpty || declared.contains(field)
        ? const []
        : [FieldProblem(field, FieldProblemCode.notDeclared)];

/// 非空字符串的长度区间校验（调用前确保已声明）。
FieldProblem? _length(String field, String value, int min, int max) {
  final length = _bytes(value);
  if (length < min) {
    return FieldProblem(field, FieldProblemCode.tooShort, '$length<$min');
  }
  if (length > max) {
    return FieldProblem(field, FieldProblemCode.tooLong, '$length>$max');
  }
  return null;
}

/// 密码类字段：空串视为「未提供」（开放网络/匿名），非空时 8..63 字节。
List<FieldProblem> _wifiPassword(
  String field,
  String value,
  List<String> declared,
) =>
    _gate(field, value, declared).isNotEmpty
        ? _gate(field, value, declared)
        : [
            if (value.isNotEmpty)
              if (_length(field, value, 8, 63) case final problem?) problem,
          ];

/// 可选字符串：null/空串省略；非空时先声明门控再校长度。
List<FieldProblem> _optional(
  String field,
  String? value,
  int max,
  List<String> declared,
) =>
    value == null || value.isEmpty
        ? const []
        : [
            ..._gate(field, value, declared),
            if (declared.contains(field))
              if (_length(field, value, 1, max) case final problem?) problem,
          ];

/// 必填字符串：空 → required；非空 → 声明门控 + 长度校验。
List<FieldProblem> _required(
  String field,
  String value,
  int max,
  List<String> declared,
) =>
    [
      if (value.isEmpty)
        FieldProblem(field, FieldProblemCode.required)
      else ...[
        ..._gate(field, value, declared),
        if (declared.contains(field))
          if (_length(field, value, 1, max) case final problem?) problem,
      ],
    ];

const _bssidPattern = r'^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$';
const _countryPattern = r'^[A-Z]{2}$';
const _pinPattern = r'^\d{4,8}$';
const _authValues = {'none', 'pap', 'chap', 'pap_or_chap'};

/// 校验一个配置节。[declaredFields] 是能力声明的该节 fields；
/// [declaredNetworks] 仅 comm 节需要（type 的合法取值集合）。
List<FieldProblem> validateSection(
  ConfigSection section, {
  required List<String> declaredFields,
  Set<String> declaredNetworks = const {},
}) {
  switch (section) {
    case WifiSection(:final ssid, :final password, :final bssid):
      return [
        ..._required('ssid', ssid, 31, declaredFields),
        ..._wifiPassword('password', password, declaredFields),
        if (bssid != null && bssid.isNotEmpty) ...[
          ..._gate('bssid', bssid, declaredFields),
          if (declaredFields.contains('bssid') &&
              !RegExp(_bssidPattern).hasMatch(bssid))
            const FieldProblem('bssid', FieldProblemCode.invalidFormat),
        ],
      ];
    case CellularSection(
        :final apn,
        :final username,
        :final password,
        :final pin,
        :final auth,
        :final roaming,
      ):
      return [
        // apn 未声明（免配置卡）时空值放行，声明时必填。
        if (apn.isNotEmpty) ..._required('apn', apn, 64, declaredFields),
        ..._optional('username', username, 64, declaredFields),
        ..._optional('password', password, 128, declaredFields),
        if (pin != null && pin.isNotEmpty) ...[
          ..._gate('pin', pin, declaredFields),
          if (declaredFields.contains('pin') &&
              !RegExp(_pinPattern).hasMatch(pin))
            const FieldProblem('pin', FieldProblemCode.invalidFormat),
        ],
        if (auth != null && auth.isNotEmpty) ...[
          ..._gate('auth', auth, declaredFields),
          if (declaredFields.contains('auth') && !_authValues.contains(auth))
            const FieldProblem('auth', FieldProblemCode.invalidValue),
        ],
        if (roaming != null) ..._gate('roaming', '$roaming', declaredFields),
      ];
    case HalowSection(:final ssid, :final password, :final country):
      return [
        ..._required('ssid', ssid, 32, declaredFields),
        ..._wifiPassword('password', password, declaredFields),
        if (country != null && country.isNotEmpty) ...[
          ..._gate('country', country, declaredFields),
          if (declaredFields.contains('country') &&
              !RegExp(_countryPattern).hasMatch(country))
            const FieldProblem('country', FieldProblemCode.invalidFormat),
        ],
      ];
    case EthernetSection():
      // 无可写字段：载荷恒为空对象。
      return const [];
    case CommSection(:final type):
      final wire = type.wireName;
      return [
        if (!declaredFields.contains('type'))
          const FieldProblem('type', FieldProblemCode.notDeclared)
        else if (!declaredNetworks.contains(wire))
          // type 必须是能力中声明的网络节。
          FieldProblem('type', FieldProblemCode.invalidValue, wire),
      ];
    case MqttSection(
        :final host,
        :final port,
        :final clientId,
        :final username,
        :final password,
        :final tls,
        :final topic,
        :final qos,
      ):
      return [
        if (!declaredFields.contains('enable'))
          const FieldProblem('enable', FieldProblemCode.notDeclared),
        ..._required('host', host, 128, declaredFields),
        if (!declaredFields.contains('port'))
          const FieldProblem('port', FieldProblemCode.notDeclared)
        else if (port < 1 || port > 65535)
          FieldProblem('port', FieldProblemCode.invalidValue, '$port'),
        ..._optional('client_id', clientId, 64, declaredFields),
        ..._optional('username', username, 64, declaredFields),
        ..._optional('password', password, 128, declaredFields),
        if (tls != null && !declaredFields.contains('tls'))
          const FieldProblem('tls', FieldProblemCode.notDeclared),
        if (topic != null && topic.isNotEmpty) ...[
          ..._gate('topic', topic, declaredFields),
          if (declaredFields.contains('topic')) ...[
            if (_length('topic', topic, 1, 128) case final problem?) problem,
            if (topic.contains('+') || topic.contains('#'))
              const FieldProblem('topic', FieldProblemCode.invalidFormat),
          ],
        ],
        if (qos != null) ...[
          if (!declaredFields.contains('qos'))
            const FieldProblem('qos', FieldProblemCode.notDeclared)
          else if (qos < 0 || qos > 2)
            FieldProblem('qos', FieldProblemCode.invalidValue, '$qos'),
        ],
      ];
    case WebhookSection(:final url, :final secret, :final header):
      return [
        if (!declaredFields.contains('enable'))
          const FieldProblem('enable', FieldProblemCode.notDeclared),
        if (url.isEmpty) ...[
          if (declaredFields.contains('url'))
            const FieldProblem('url', FieldProblemCode.required),
        ] else ...[
          ..._gate('url', url, declaredFields),
          if (declaredFields.contains('url')) ...[
            if (_length('url', url, 1, 256) case final problem?) problem,
            if (!_isHttpUrl(Uri.tryParse(url)))
              const FieldProblem('url', FieldProblemCode.invalidFormat),
          ],
        ],
        ..._optional('secret', secret, 128, declaredFields),
        if (header != null && header.isNotEmpty) ...[
          ..._gate('header', header, declaredFields),
          if (declaredFields.contains('header')) ...[
            if (_length('header', header, 1, 256) case final problem?) problem,
            if (!header.contains(':') || header.split(':').first.trim().isEmpty)
              const FieldProblem('header', FieldProblemCode.invalidFormat),
          ],
        ],
      ];
  }
}

bool _isHttpUrl(Uri? uri) =>
    uri != null &&
    (uri.isScheme('http') || uri.isScheme('https')) &&
    uri.host.isNotEmpty;
