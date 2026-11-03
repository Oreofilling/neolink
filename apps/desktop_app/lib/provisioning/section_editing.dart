// Draft <-> field value plumbing for config sections. Form widgets address a
// draft by (section name, field name) instead of per-section copyWith, and the
// controller's config.get prefill goes through the same entry so masked
// password skipping and capability gating live in exactly one place.
library;

import 'package:communication_domain/communication_domain.dart';

/// Secret-like fields: read-back values may be device-masked (all '*');
/// masked values never enter a draft.
const _secretFields = {'password', 'secret', 'pin'};

bool _isMasked(Object? value) =>
    value is String && value.isNotEmpty && value.contains('*');

/// Current value of a draft field (form initial value / payload preview).
Object? fieldValue(ConfigSection section, String field) {
  switch (section) {
    case WifiSection(:final ssid, :final password, :final bssid):
      return switch (field) {
        'ssid' => ssid,
        'password' => password,
        'bssid' => bssid,
        _ => null,
      };
    case CellularSection(
        :final apn,
        :final username,
        :final password,
        :final pin,
        :final auth,
        :final roaming,
      ):
      return switch (field) {
        'apn' => apn,
        'username' => username,
        'password' => password,
        'pin' => pin,
        'auth' => auth,
        'roaming' => roaming,
        _ => null,
      };
    case HalowSection(:final ssid, :final password, :final country):
      return switch (field) {
        'ssid' => ssid,
        'password' => password,
        'country' => country,
        _ => null,
      };
    case CommSection(:final type):
      return field == 'type' ? type.wireName : null;
    case EthernetSection():
      return null;
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
      return switch (field) {
        'enable' => enable,
        'host' => host,
        'port' => port,
        'client_id' => clientId,
        'username' => username,
        'password' => password,
        'tls' => tls,
        'topic' => topic,
        'qos' => qos,
        _ => null,
      };
    case WebhookSection(:final enable, :final url, :final secret, :final header):
      return switch (field) {
        'enable' => enable,
        'url' => url,
        'secret' => secret,
        'header' => header,
        _ => null,
      };
  }
}

/// Returns a new section with one field replaced (no in-place mutation).
/// Unknown fields return the section unchanged (capability declaration and
/// section shape are enforced by the validation layer).
ConfigSection applyFieldValue(ConfigSection section, String field, Object? value) {
  switch (section) {
    case WifiSection(:final ssid, :final password, :final bssid):
      return switch (field) {
        'ssid' => WifiSection(ssid: value as String, password: password, bssid: bssid),
        'password' => WifiSection(ssid: ssid, password: value as String, bssid: bssid),
        'bssid' => WifiSection(ssid: ssid, password: password, bssid: value as String?),
        _ => section,
      };
    case CellularSection(:final apn, :final username, :final password, :final pin, :final auth, :final roaming):
      return switch (field) {
        'apn' => CellularSection(apn: value as String, username: username, password: password, pin: pin, auth: auth, roaming: roaming),
        'username' => CellularSection(apn: apn, username: value as String?, password: password, pin: pin, auth: auth, roaming: roaming),
        'password' => CellularSection(apn: apn, username: username, password: value as String?, pin: pin, auth: auth, roaming: roaming),
        'pin' => CellularSection(apn: apn, username: username, password: password, pin: value as String?, auth: auth, roaming: roaming),
        'auth' => CellularSection(apn: apn, username: username, password: password, pin: pin, auth: value as String?, roaming: roaming),
        'roaming' => CellularSection(apn: apn, username: username, password: password, pin: pin, auth: auth, roaming: value as bool?),
        _ => section,
      };
    case HalowSection(:final ssid, :final password, :final country):
      return switch (field) {
        'ssid' => HalowSection(ssid: value as String, password: password, country: country),
        'password' => HalowSection(ssid: ssid, password: value as String, country: country),
        'country' => HalowSection(ssid: ssid, password: password, country: value as String?),
        _ => section,
      };
    case CommSection():
      if (field == 'type' && value is CommunicationMode) {
        return CommSection(type: value);
      }
      return section;
    case EthernetSection():
      return section;
    case MqttSection(:final enable, :final host, :final port, :final clientId, :final username, :final password, :final tls, :final topic, :final qos):
      return switch (field) {
        'enable' => MqttSection(enable: value as bool, host: host, port: port, clientId: clientId, username: username, password: password, tls: tls, topic: topic, qos: qos),
        'host' => MqttSection(enable: enable, host: value as String, port: port, clientId: clientId, username: username, password: password, tls: tls, topic: topic, qos: qos),
        'port' => MqttSection(enable: enable, host: host, port: value as int, clientId: clientId, username: username, password: password, tls: tls, topic: topic, qos: qos),
        'client_id' => MqttSection(enable: enable, host: host, port: port, clientId: value as String?, username: username, password: password, tls: tls, topic: topic, qos: qos),
        'username' => MqttSection(enable: enable, host: host, port: port, clientId: clientId, username: value as String?, password: password, tls: tls, topic: topic, qos: qos),
        'password' => MqttSection(enable: enable, host: host, port: port, clientId: clientId, username: username, password: value as String?, tls: tls, topic: topic, qos: qos),
        'tls' => MqttSection(enable: enable, host: host, port: port, clientId: clientId, username: username, password: password, tls: value as bool?, topic: topic, qos: qos),
        'topic' => MqttSection(enable: enable, host: host, port: port, clientId: clientId, username: username, password: password, tls: tls, topic: value as String?, qos: qos),
        'qos' => MqttSection(enable: enable, host: host, port: port, clientId: clientId, username: username, password: password, tls: tls, topic: topic, qos: value as int?),
        _ => section,
      };
    case WebhookSection(:final enable, :final url, :final secret, :final header):
      return switch (field) {
        'enable' => WebhookSection(enable: value as bool, url: url, secret: secret, header: header),
        'url' => WebhookSection(enable: enable, url: value as String, secret: secret, header: header),
        'secret' => WebhookSection(enable: enable, url: url, secret: value as String?, header: header),
        'header' => WebhookSection(enable: enable, url: url, secret: secret, header: value as String?),
        _ => section,
      };
  }
}

/// Empty draft for a section name; comm defaults to the first network
/// section the device declares.
ConfigSection defaultSectionFor(
  String name, {
  required Set<String> declaredNetworks,
}) {
  final fallbackNetwork = declaredNetworks.contains('wifi')
      ? CommunicationMode.wifi
      : CommunicationMode.values.firstWhere(
          (mode) => declaredNetworks.contains(mode.wireName),
          orElse: () => CommunicationMode.wifi,
        );
  return switch (name) {
    'wifi' => const WifiSection.empty(),
    'cellular' => const CellularSection.empty(),
    'halow' => const HalowSection(ssid: '', password: ''),
    'ethernet' => const EthernetSection(),
    'comm' => CommSection(type: fallbackNetwork),
    'mqtt' => const MqttSection(enable: false, host: '', port: 1883),
    'webhook' => const WebhookSection(enable: false, url: ''),
    _ => throw ArgumentError('unknown section name: $name'),
  };
}

/// Prefills a draft from config.get read-back: only declared fields are
/// applied; masked secrets are skipped so the user re-enters them instead of
/// sending the mask string back to the device.
ConfigSection prefillSection(
  ConfigSection section,
  Map<String, Object?> stored, {
  required List<String> declaredFields,
}) {
  var result = section;
  for (final field in declaredFields) {
    final value = stored[field];
    if (value == null) continue;
    if (_secretFields.contains(field) && _isMasked(value)) continue;
    if (fieldValue(result, field) == value) continue;
    // Type alignment: text controls give String, numeric fields int, bools.
    final aligned = switch (field) {
      'port' || 'qos' => value is int ? value : int.tryParse('$value'),
      'enable' || 'tls' || 'roaming' => value is bool ? value : null,
      'type' => value is String
          ? CommunicationMode.values
                .where((mode) => mode.wireName == value)
                .firstOrNull
          : null,
      'auth' => value is String ? value : null,
      _ => value is String ? value : null,
    };
    if (aligned == null) continue;
    result = applyFieldValue(result, field, aligned);
  }
  return result;
}
