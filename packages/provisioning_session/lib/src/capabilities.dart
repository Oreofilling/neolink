/// communication.capabilities.get 的解析结果（§8）。
///
/// 形状校验策略与 DeviceInfoResult 一致：设备是自家固件，节对象缺必需
/// 字段或类型不符属于协议违例，显式抛错而不是静默缺省；`name` 保持
/// 原样透传，未识别的节由 UI 降级展示为不可配置（§8 规则），解析层
/// 不做白名单。
library;

import 'package:ct_prov_core/ct_prov_core.dart';

import 'session_exception.dart';

/// 节类别（§8 kind 取值）。
enum ConfigSectionKind { network, selector, service }

/// 按 wire 名反查节类别；未知取值返回 null（由调用方决定降级方式）。
ConfigSectionKind? configSectionKindFromWire(String name) {
  switch (name) {
    case 'network':
      return ConfigSectionKind.network;
    case 'selector':
      return ConfigSectionKind.selector;
    case 'service':
      return ConfigSectionKind.service;
    default:
      return null;
  }
}

/// 一个配置节的能力声明。
final class ConfigSection {
  const ConfigSection({
    required this.name,
    required this.kind,
    required this.configurable,
    required this.scannable,
    required this.fields,
  });

  final String name;
  final ConfigSectionKind kind;

  /// false 时只读展示，config.set 写入该节会得到 SECTION_NOT_SUPPORTED。
  final bool configurable;

  /// true 时支持 communication.scan。
  final bool scannable;

  /// config.set 可提交的字段集；未列出的字段不得提交。
  final List<String> fields;
}

/// 能力读取结果：节列表 + 当前活动网络节名（仅展示用途）。
final class CapabilitiesResult {
  const CapabilitiesResult({
    required this.sections,
    required this.currentNetwork,
  });

  final List<ConfigSection> sections;

  /// current.network；从未配置过时为 null。
  final String? currentNetwork;

  factory CapabilitiesResult.fromResponse(ProvResponse response) {
    if (!response.ok) {
      throw ProvSessionException(
        'capabilities_error',
        '${response.error?.codeName}: ${response.error?.message}',
      );
    }
    // 响应 op 名存在两种约定：固件实现为「完整请求 op + .result」
    // （device.info.get.result，真机 F1 已验证），协议文档示例则去掉
    // 动词后缀（communication.capabilities.result）。自家固件两代并存，
    // 解析层两者都收。
    const acceptedOps = {
      'communication.capabilities.result',
      'communication.capabilities.get.result',
    };
    if (!acceptedOps.contains(response.opName)) {
      throw ProvSessionException('capabilities_op', response.opName);
    }
    final sections = response.data?['sections'];
    if (sections is! List) {
      throw const ProvSessionException(
        'capabilities_shape',
        'sections must be an array',
      );
    }
    final parsed = <ConfigSection>[];
    for (final entry in sections) {
      parsed.add(_sectionFrom(entry));
    }
    String? currentNetwork;
    final current = response.data?['current'];
    if (current is Map) {
      final network = current['network'];
      if (network is! String?) {
        throw const ProvSessionException(
          'capabilities_shape',
          'current.network must be a string or null',
        );
      }
      currentNetwork = network;
    }
    return CapabilitiesResult(sections: parsed, currentNetwork: currentNetwork);
  }

  static ConfigSection _sectionFrom(Object? entry) {
    if (entry is! Map) {
      throw const ProvSessionException(
        'capabilities_shape',
        'section entry must be an object',
      );
    }
    final name = entry['name'];
    final kindName = entry['kind'];
    final configurable = entry['configurable'];
    final scannable = entry['scannable'];
    final fields = entry['fields'];
    if (name is! String || kindName is! String) {
      throw const ProvSessionException(
        'capabilities_shape',
        'section name/kind must be strings',
      );
    }
    final kind = configSectionKindFromWire(kindName);
    if (kind == null) {
      throw ProvSessionException(
          'capabilities_shape', 'unknown kind: $kindName');
    }
    if (configurable is! bool) {
      throw const ProvSessionException(
        'capabilities_shape',
        'configurable must be a boolean',
      );
    }
    if (fields == null) {
      // fields 可选（如只读节）；缺省视为空集。
      return ConfigSection(
        name: name,
        kind: kind,
        configurable: configurable,
        scannable: scannable is bool ? scannable : false,
        fields: const <String>[],
      );
    }
    if (fields is! List || fields.any((field) => field is! String)) {
      throw const ProvSessionException(
        'capabilities_shape',
        'fields must be an array of strings',
      );
    }
    return ConfigSection(
      name: name,
      kind: kind,
      configurable: configurable,
      scannable: scannable is bool ? scannable : false,
      fields: List<String>.from(fields),
    );
  }
}
