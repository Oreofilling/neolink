/// universal_ble 具体适配层（ble_adapter 的可替换实现之一）。
///
/// 扫描侧把各平台 Service Data 归一成 §4.2.2 的 27 字节广播再交给
/// ble_adapter 解析；通道侧实现 [CtGattChannel] 的连接/配对/订阅序列。
/// Windows 优先真机 PoC 在此验证后冻结。
library;

export 'package:ble_adapter/ble_adapter.dart'
    show CtDiscoveredDevice, CtGattChannel, CtMetaInfo, parseMeta;

export 'src/ct_adv_source.dart';
export 'src/universal_ct_channel.dart';
export 'src/universal_ct_scanner.dart';
