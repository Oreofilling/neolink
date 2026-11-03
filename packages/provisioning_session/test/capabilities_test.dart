import 'package:ct_prov_core/ct_prov_core.dart';
import 'package:provisioning_session/provisioning_session.dart';
import 'package:test/test.dart';

ProvResponse okResponse(Map<String, Object?> data) => ProvResponse(
      id: 2,
      opName: 'communication.capabilities.result',
      ok: true,
      data: data,
    );

void main() {
  test('解析 NE301 形态全集（§8 示例）', () {
    final result = CapabilitiesResult.fromResponse(
      okResponse({
        'sections': [
          {
            'name': 'wifi',
            'kind': 'network',
            'configurable': true,
            'scannable': true,
            'fields': ['ssid', 'password', 'bssid'],
          },
          {
            'name': 'cellular',
            'kind': 'network',
            'configurable': true,
            'fields': ['apn'],
          },
          {'name': 'ethernet', 'kind': 'network', 'configurable': false},
          {'name': 'comm', 'kind': 'selector', 'configurable': true},
          {
            'name': 'mqtt',
            'kind': 'service',
            'configurable': true,
            'fields': ['enable', 'host', 'port'],
          },
        ],
        'current': {'network': 'wifi'},
      }),
    );

    expect(result.sections, hasLength(5));
    final wifi = result.sections.first;
    expect(wifi.name, 'wifi');
    expect(wifi.kind, ConfigSectionKind.network);
    expect(wifi.configurable, isTrue);
    expect(wifi.scannable, isTrue);
    expect(wifi.fields, ['ssid', 'password', 'bssid']);
    // scannable 缺失按 false；configurable=false 只读展示。
    final cellular = result.sections[1];
    expect(cellular.scannable, isFalse);
    final ethernet = result.sections[2];
    expect(ethernet.configurable, isFalse);
    expect(ethernet.fields, isEmpty);
    expect(result.sections[3].kind, ConfigSectionKind.selector);
    expect(result.sections[4].kind, ConfigSectionKind.service);
    expect(result.currentNetwork, 'wifi');
  });

  test('current.network 为 null（从未配置）', () {
    final result = CapabilitiesResult.fromResponse(
      okResponse({
        'sections': [],
        'current': {'network': null},
      }),
    );
    expect(result.currentNetwork, isNull);
  });

  test('current 整体缺失时 currentNetwork 为 null', () {
    final result = CapabilitiesResult.fromResponse(
      okResponse({'sections': []}),
    );
    expect(result.currentNetwork, isNull);
  });

  test('未知节名保持原样透传（由 UI 降级展示，§8 规则）', () {
    final result = CapabilitiesResult.fromResponse(
      okResponse({
        'sections': [
          {
            'name': 'lte_backup',
            'kind': 'network',
            'configurable': true,
          },
        ],
      }),
    );
    expect(result.sections.single.name, 'lte_backup');
  });

  group('形状违例抛 capabilities_shape', () {
    void expectShapeError(Map<String, Object?> data, String message) {
      expect(
        () => CapabilitiesResult.fromResponse(okResponse(data)),
        throwsA(
          isA<ProvSessionException>()
              .having((error) => error.reason, 'reason', 'capabilities_shape')
              .having((error) => error.message, 'message', message),
        ),
      );
    }

    test('sections 缺失', () {
      expectShapeError({}, 'sections must be an array');
    });

    test('节条目不是对象', () {
      expectShapeError({
        'sections': ['wifi'],
      }, 'section entry must be an object');
    });

    test('kind 未知', () {
      expectShapeError({
        'sections': [
          {'name': 'x', 'kind': 'mystery', 'configurable': true},
        ],
      }, 'unknown kind: mystery');
    });

    test('configurable 非 bool', () {
      expectShapeError({
        'sections': [
          {'name': 'x', 'kind': 'network', 'configurable': 'yes'},
        ],
      }, 'configurable must be a boolean');
    });

    test('fields 非字符串数组', () {
      expectShapeError({
        'sections': [
          {
            'name': 'x',
            'kind': 'network',
            'configurable': true,
            'fields': [1]
          },
        ],
      }, 'fields must be an array of strings');
    });
  });

  test('失败响应抛 capabilities_error', () {
    final response = ProvResponse(
      id: 2,
      opName: 'communication.capabilities.result',
      ok: false,
      error: const ProvError(
        codeName: 'UNSUPPORTED_OPERATION',
        message: 'not implemented',
      ),
    );
    expect(
      () => CapabilitiesResult.fromResponse(response),
      throwsA(
        isA<ProvSessionException>()
            .having((error) => error.reason, 'reason', 'capabilities_error'),
      ),
    );
  });

  test('文档风格的响应 op（去掉 .get）同样接受', () {
    final response = ProvResponse(
      id: 2,
      opName: 'communication.capabilities.result',
      ok: true,
      data: const {'sections': []},
    );
    expect(
      () => CapabilitiesResult.fromResponse(response),
      returnsNormally,
    );
  });

  test('op 名不符抛 capabilities_op', () {
    final response = ProvResponse(
      id: 2,
      opName: 'device.info.result',
      ok: true,
      data: const {'sections': []},
    );
    expect(
      () => CapabilitiesResult.fromResponse(response),
      throwsA(
        isA<ProvSessionException>()
            .having((error) => error.reason, 'reason', 'capabilities_op'),
      ),
    );
  });

  test('节类别反查：已知取值与未知回退', () {
    expect(configSectionKindFromWire('network'), ConfigSectionKind.network);
    expect(configSectionKindFromWire('selector'), ConfigSectionKind.selector);
    expect(configSectionKindFromWire('service'), ConfigSectionKind.service);
    expect(configSectionKindFromWire('mesh'), isNull);
  });
}
