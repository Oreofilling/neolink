/// 通讯模式与节配置领域层（骨架）：联合配置类型（决策 C-04）。
/// 字段门控与校验在 M3 填充；schema 见 CT_CONFIG_SCHEMA.md。
library;

enum CommunicationMode { wifi, cat1, wifiHalow, ethernet }

sealed class ConfigSection {
  const ConfigSection(this.name);
  final String name;
}

final class WifiSection extends ConfigSection {
  const WifiSection({required this.ssid, required this.password, this.bssid}) : super('wifi');
  const WifiSection.empty() : this(ssid: '', password: '');
  final String ssid;
  final String password;
  final String? bssid; // 仅能力声明 bssid 的设备（NE301）
}

final class CellularSection extends ConfigSection {
  const CellularSection({required this.apn, this.username, this.password, this.pin, this.auth}) : super('cellular');
  const CellularSection.empty() : this(apn: '');
  final String apn;
  final String? username;
  final String? password;
  final String? pin;
  final String? auth;
}

final class MqttSection extends ConfigSection {
  const MqttSection({required this.enable, required this.host, required this.port}) : super('mqtt');
  final bool enable;
  final String host;
  final int port;
}

final class WebhookSection extends ConfigSection {
  const WebhookSection({required this.enable, required this.url, this.secret}) : super('webhook');
  final bool enable;
  final String url;
  final String? secret; // 仅能力声明 secret 的设备（NE301）
}
