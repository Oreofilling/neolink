/// 载荷组装：把节对象按能力 fields 过滤成 config.set 的 data 结构。
/// 约束：调用方应先通过 [validateSection]（本层不再校验值，只做门控与
/// 省略），未声明的字段一律不进载荷。
library;

import 'sections.dart';
import 'validation.dart';

/// 单节载荷：只含已声明且用户提供的字段；空字符串密码省略（开放网络）。
Map<String, Object?> buildSectionPayload(
  ConfigSection section, {
  required List<String> declaredFields,
}) {
  switch (section) {
    case WifiSection(:final ssid, :final password, :final bssid):
      return {
        if (declaredFields.contains('ssid') && ssid.isNotEmpty) 'ssid': ssid,
        if (declaredFields.contains('password') && password.isNotEmpty)
          'password': password,
        if (declaredFields.contains('bssid') &&
            bssid != null &&
            bssid.isNotEmpty)
          'bssid': bssid,
      };
    case CellularSection(
        :final apn,
        :final username,
        :final password,
        :final pin,
        :final auth,
        :final roaming,
      ):
      return {
        if (declaredFields.contains('apn') && apn.isNotEmpty) 'apn': apn,
        if (_present(username, declaredFields, 'username'))
          'username': username,
        if (_present(password, declaredFields, 'password'))
          'password': password,
        if (_present(pin, declaredFields, 'pin')) 'pin': pin,
        if (_present(auth, declaredFields, 'auth')) 'auth': auth,
        if (roaming != null && declaredFields.contains('roaming'))
          'roaming': roaming,
      };
    case HalowSection(:final ssid, :final password, :final country):
      return {
        if (declaredFields.contains('ssid') && ssid.isNotEmpty) 'ssid': ssid,
        if (declaredFields.contains('password') && password.isNotEmpty)
          'password': password,
        if (_present(country, declaredFields, 'country')) 'country': country,
      };
    // 无可写字段：空节对象表示「确认使用 DHCP/插线即用」。
    case EthernetSection():
      return {};
    case CommSection(:final type):
      return {
        if (declaredFields.contains('type')) 'type': type.wireName,
      };
    case MqttSection(
        :final enable,
        :final host,
        :final port,
        :final clientId,
        :final username,
        :final password,
        :final tls,
        :final topic,
        :final qos,
      ):
      return {
        if (declaredFields.contains('enable')) 'enable': enable,
        if (declaredFields.contains('host') && host.isNotEmpty) 'host': host,
        if (declaredFields.contains('port')) 'port': port,
        if (_present(clientId, declaredFields, 'client_id'))
          'client_id': clientId,
        if (_present(username, declaredFields, 'username'))
          'username': username,
        if (_present(password, declaredFields, 'password'))
          'password': password,
        if (tls != null && declaredFields.contains('tls')) 'tls': tls,
        if (_present(topic, declaredFields, 'topic')) 'topic': topic,
        if (qos != null && declaredFields.contains('qos')) 'qos': qos,
      };
    case WebhookSection(
        :final enable,
        :final url,
        :final secret,
        :final header,
      ):
      return {
        if (declaredFields.contains('enable')) 'enable': enable,
        if (declaredFields.contains('url') && url.isNotEmpty) 'url': url,
        if (_present(secret, declaredFields, 'secret')) 'secret': secret,
        if (_present(header, declaredFields, 'header')) 'header': header,
      };
  }
}

bool _present(String? value, List<String> declared, String field) =>
    value != null && value.isNotEmpty && declared.contains(field);

/// 多节组装结果：payload 可直接作 config.set 的 data；问题按节收集
/// （节名作 field），有问题的节不进载荷。
final class ConfigPayload {
  const ConfigPayload(this.payload, this.problems);
  final Map<String, Map<String, Object?>> payload;
  final List<FieldProblem> problems;
}

/// 组装多节载荷。[sectionFields] 是能力声明的「节名 → fields」映射；
/// 不在其中的节属于能力未声明（SECTION_NOT_SUPPORTED），整节拒绝。
ConfigPayload assembleConfigPayload(
  Map<String, ConfigSection> sections, {
  required Map<String, List<String>> sectionFields,
}) {
  final payload = <String, Map<String, Object?>>{};
  final problems = <FieldProblem>[];
  for (final entry in sections.entries) {
    final fields = sectionFields[entry.key];
    if (fields == null) {
      problems.add(FieldProblem(entry.key, FieldProblemCode.notDeclared));
      continue;
    }
    payload[entry.key] = buildSectionPayload(
      entry.value,
      declaredFields: fields,
    );
  }
  return ConfigPayload(payload, problems);
}
