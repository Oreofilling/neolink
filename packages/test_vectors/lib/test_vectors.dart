/// CT-Prov/1 协议黄金向量：广播发现 / GATT 分片 / JSON 信封三族。
/// 纯数据、零第三方依赖；NE101、NE301 固件与 NeoLink 桌面端共享同一组
/// （协议文档 §15 要求）。字节与 JSON 逐字取自 CT_PROV_PROTOCOL.md 示例。
library;

export 'src/advertising.dart';
export 'src/fragment.dart';
export 'src/envelope.dart';
