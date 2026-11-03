/// 配置节联合类型（决策 C-04）：七个节各为一个不可变值对象，字段集与
/// CT_CONFIG_SCHEMA.md 一一对应。可选字段用可空类型，null 表示「用户未
/// 提供」，序列化时省略。
library;

/// 活动网络类型（comm.type 与设备形态共用词表）。
enum CommunicationMode {
  wifi('wifi'),
  cat1('cellular'),
  wifiHalow('halow'),
  ethernet('ethernet');

  const CommunicationMode(this.wireName);

  /// 协议 wire 名（comm.type 的取值）。
  final String wireName;
}

/// 配置节基类：name 即 config.set 顶层的节名。
sealed class ConfigSection {
  const ConfigSection(this.name);
  final String name;
}

final class WifiSection extends ConfigSection {
  const WifiSection({required this.ssid, required this.password, this.bssid})
      : super('wifi');
  const WifiSection.empty() : this(ssid: '', password: '');

  /// 1~31 字节；隐藏网络直接输入 SSID。
  final String ssid;

  /// 8~63 字节；空串表示开放网络（载荷省略）。
  final String password;

  /// 锁定特定 AP；仅能力声明 bssid 的设备（NE301）。
  final String? bssid;
}

final class CellularSection extends ConfigSection {
  const CellularSection({
    required this.apn,
    this.username,
    this.password,
    this.pin,
    this.auth,
    this.roaming,
  }) : super('cellular');
  const CellularSection.empty() : this(apn: '');

  /// 1~64 字节；能力声明免配置卡（fields 不含 apn）时省略。
  final String apn;
  final String? username;
  final String? password;

  /// 4~8 位数字。
  final String? pin;

  /// none / pap / chap / pap_or_chap，缺省 none。
  final String? auth;

  /// 仅能力声明 roaming 的设备（NE301）。
  final bool? roaming;
}

final class HalowSection extends ConfigSection {
  const HalowSection({
    required this.ssid,
    required this.password,
    this.country,
  }) : super('halow');

  /// 1~32 字节。
  final String ssid;

  /// 8~63 字节；空串表示开放网络。
  final String password;

  /// 两位大写国家/区域代码（如 CN、US）。
  final String? country;
}

/// Ethernet/PoE 插线即用（DHCP），无可写字段。
final class EthernetSection extends ConfigSection {
  const EthernetSection() : super('ethernet');
}

/// 活动网络选择器：写入即切换；type 必须是能力中声明的网络节。
final class CommSection extends ConfigSection {
  const CommSection({required this.type}) : super('comm');
  final CommunicationMode type;
}

final class MqttSection extends ConfigSection {
  const MqttSection({
    required this.enable,
    required this.host,
    required this.port,
    this.clientId,
    this.username,
    this.password,
    this.tls,
    this.topic,
    this.qos,
  }) : super('mqtt');

  final bool enable;

  /// 域名或 IP 字面量，≤128 字节。
  final String host;

  /// 1..65535；启用 TLS 时推荐 8883。
  final int port;
  final String? clientId;
  final String? username;
  final String? password;
  final bool? tls;

  /// 数据上报主题，不得包含 +/# 通配符。
  final String? topic;

  /// 0..2，缺省 0。
  final int? qos;
}

final class WebhookSection extends ConfigSection {
  const WebhookSection({
    required this.enable,
    required this.url,
    this.secret,
    this.header,
  }) : super('webhook');

  final bool enable;

  /// http/https 绝对 URI，≤256 字节。
  final String url;

  /// 签名密钥；仅能力声明 secret 的设备（NE301）。
  final String? secret;

  /// 「Key: Value」附加请求头；能力未声明时不得提交。
  final String? header;
}
