/// JSON 信封族向量：§6 信封形状、六操作（§7–§11）、九错误码（§12）与非法输入。
/// jsonText 逐字取自协议文档示例；NE101 / NE301 两种形态都在。
library;

import 'dart:convert';

/// 信封向量。expect 为 null 时表示负载本身非法（invalidReason 说明原因）。
final class EnvelopeVector {
  const EnvelopeVector({
    required this.id,
    required this.description,
    required this.jsonText,
    this.expect,
    this.invalidReason,
  });

  final String id;
  final String description;
  final String jsonText;
  final Map<String, Object?>? expect;

  /// 非法原因：BOM 前缀 / 顶层非对象 / 整数用浮点表达 / 尾部多余内容。
  /// 字段值为跨端稳定的标识符，见各向量 expect 为空的条目。
  final String? invalidReason;

  List<int> get wireBytes => utf8.encode(jsonText);
}

final List<EnvelopeVector> kEnvelopeVectors = [
  // ---- 请求（六操作全集） ----
  EnvelopeVector(
    id: 'env-req-device-info',
    description: '§7 请求：device.info.get',
    jsonText: '{"id":1,"op":"device.info.get","data":{}}',
    expect: const {'kind': 'request', 'id': 1, 'op': 'device.info.get', 'data': {}},
  ),
  EnvelopeVector(
    id: 'env-req-capabilities',
    description: '§8 请求：communication.capabilities.get（文档 §6.1 示例）',
    jsonText: '{"id":12,"op":"communication.capabilities.get","data":{}}',
    expect: const {'kind': 'request', 'id': 12, 'op': 'communication.capabilities.get', 'data': {}},
  ),
  EnvelopeVector(
    id: 'env-req-scan',
    description: '§9 请求：communication.scan（首扫省略 cursor）',
    jsonText: '{"id":3,"op":"communication.scan","data":{"section":"wifi"}}',
    expect: const {
      'kind': 'request',
      'id': 3,
      'op': 'communication.scan',
      'data': {'section': 'wifi'},
    },
  ),
  EnvelopeVector(
    id: 'env-req-scan-cursor',
    description: '§9 请求：携不透明 cursor 翻页',
    jsonText: '{"id":4,"op":"communication.scan","data":{"section":"wifi","cursor":"opaque-1"}}',
    expect: const {
      'kind': 'request',
      'id': 4,
      'op': 'communication.scan',
      'data': {'section': 'wifi', 'cursor': 'opaque-1'},
    },
  ),
  EnvelopeVector(
    id: 'env-req-config-set-multi',
    description: '§10 请求：config.set 多节写（文档示例，wifi + mqtt）',
    jsonText: '{"id":20,"op":"config.set","data":{"wifi":{"ssid":"Office-2.4G","password":"example-password"},'
        '"mqtt":{"enable":true,"host":"mqtt.example.com","port":8883,"username":"device",'
        '"password":"example-secret","tls":true}}}',
    expect: const {
      'kind': 'request',
      'id': 20,
      'op': 'config.set',
      'data': {
        'wifi': {'ssid': 'Office-2.4G', 'password': 'example-password'},
        'mqtt': {
          'enable': true,
          'host': 'mqtt.example.com',
          'port': 8883,
          'username': 'device',
          'password': 'example-secret',
          'tls': true,
        },
      },
    },
  ),
  EnvelopeVector(
    id: 'env-req-config-get',
    description: '§10 可选操作请求：config.get',
    jsonText: '{"id":21,"op":"config.get","data":{}}',
    expect: const {'kind': 'request', 'id': 21, 'op': 'config.get', 'data': {}},
  ),
  EnvelopeVector(
    id: 'env-req-session-close',
    description: '§11 请求：session.close',
    jsonText: '{"id":32,"op":"session.close","data":{}}',
    expect: const {'kind': 'request', 'id': 32, 'op': 'session.close', 'data': {}},
  ),

  // ---- 成功响应 ----
  EnvelopeVector(
    id: 'env-resp-device-info-ne101',
    description: '§7 响应：NE101 电池供电形态（文档示例）',
    jsonText: '{"id":1,"op":"device.info.result","ok":true,"data":{"device_name":"NE101-A1B2C3",'
        '"serial_number":"NE101202610270001","model":"NE101","firmware":"1.8.0",'
        '"power":["battery"],"protocol_version":1}}',
    expect: const {
      'kind': 'response',
      'id': 1,
      'op': 'device.info.result',
      'ok': true,
      'data': {
        'device_name': 'NE101-A1B2C3',
        'serial_number': 'NE101202610270001',
        'model': 'NE101',
        'firmware': '1.8.0',
        'power': ['battery'],
        'protocol_version': 1,
      },
    },
  ),
  EnvelopeVector(
    id: 'env-resp-device-info-ne301',
    description: '§7 响应：NE301 外部供电形态',
    jsonText: '{"id":1,"op":"device.info.result","ok":true,"data":{"device_name":"NE301-84C102",'
        '"serial_number":"NE301202610270001","model":"NE301","firmware":"1.8.0",'
        '"power":["external"],"protocol_version":1}}',
    expect: const {
      'kind': 'response',
      'id': 1,
      'op': 'device.info.result',
      'ok': true,
      'data': {
        'device_name': 'NE301-84C102',
        'serial_number': 'NE301202610270001',
        'model': 'NE301',
        'firmware': '1.8.0',
        'power': ['external'],
        'protocol_version': 1,
      },
    },
  ),
  EnvelopeVector(
    id: 'env-resp-capabilities-ne301',
    description: '§8 响应：NE301 含 comm 节（文档完整示例）',
    jsonText: '{"id":2,"op":"communication.capabilities.result","ok":true,"data":{"sections":['
        '{"name":"wifi","kind":"network","configurable":true,"scannable":true,"fields":["ssid","password","bssid"]},'
        '{"name":"cellular","kind":"network","configurable":true,"fields":["apn","username","password","pin","auth","roaming"]},'
        '{"name":"halow","kind":"network","configurable":true,"scannable":true,"fields":["ssid","password","country"]},'
        '{"name":"ethernet","kind":"network","configurable":false,"fields":[]},'
        '{"name":"comm","kind":"selector","configurable":true,"fields":["type"]},'
        '{"name":"mqtt","kind":"service","configurable":true,"fields":["enable","host","port","client_id","username","password","tls","topic","qos"]},'
        '{"name":"webhook","kind":"service","configurable":true,"fields":["enable","url","secret","header"]}],'
        '"current":{"network":"wifi"}}}',
    expect: const {
      'kind': 'response',
      'id': 2,
      'op': 'communication.capabilities.result',
      'ok': true,
      'data': {
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
            'fields': ['apn', 'username', 'password', 'pin', 'auth', 'roaming'],
          },
          {
            'name': 'halow',
            'kind': 'network',
            'configurable': true,
            'scannable': true,
            'fields': ['ssid', 'password', 'country'],
          },
          {'name': 'ethernet', 'kind': 'network', 'configurable': false, 'fields': []},
          {'name': 'comm', 'kind': 'selector', 'configurable': true, 'fields': ['type']},
          {
            'name': 'mqtt',
            'kind': 'service',
            'configurable': true,
            'fields': ['enable', 'host', 'port', 'client_id', 'username', 'password', 'tls', 'topic', 'qos'],
          },
          {
            'name': 'webhook',
            'kind': 'service',
            'configurable': true,
            'fields': ['enable', 'url', 'secret', 'header'],
          },
        ],
        'current': {'network': 'wifi'},
      },
    },
  ),
  EnvelopeVector(
    id: 'env-resp-capabilities-ne101',
    description: '§8 响应：NE101 形态（无 comm 节；wifi 无 bssid、cellular 无 roaming）',
    jsonText: '{"id":2,"op":"communication.capabilities.result","ok":true,"data":{"sections":['
        '{"name":"wifi","kind":"network","configurable":true,"scannable":true,"fields":["ssid","password"]},'
        '{"name":"cellular","kind":"network","configurable":true,"fields":["apn","username","password","pin","auth"]},'
        '{"name":"mqtt","kind":"service","configurable":true,"fields":["enable","host","port","client_id","username","password","tls","topic","qos"]},'
        '{"name":"webhook","kind":"service","configurable":true,"fields":["enable","url","secret","header"]}],'
        '"current":null}}',
    expect: const {
      'kind': 'response',
      'id': 2,
      'op': 'communication.capabilities.result',
      'ok': true,
      'data': {
        'sections': [
          {
            'name': 'wifi',
            'kind': 'network',
            'configurable': true,
            'scannable': true,
            'fields': ['ssid', 'password'],
          },
          {
            'name': 'cellular',
            'kind': 'network',
            'configurable': true,
            'fields': ['apn', 'username', 'password', 'pin', 'auth'],
          },
          {
            'name': 'mqtt',
            'kind': 'service',
            'configurable': true,
            'fields': ['enable', 'host', 'port', 'client_id', 'username', 'password', 'tls', 'topic', 'qos'],
          },
          {
            'name': 'webhook',
            'kind': 'service',
            'configurable': true,
            'fields': ['enable', 'url', 'secret', 'header'],
          },
        ],
        'current': null,
      },
    },
  ),
  EnvelopeVector(
    id: 'env-resp-scan-page1',
    description: '§9 响应：扫描第 1 页（more=true 携带下一页 cursor）',
    jsonText: '{"id":3,"op":"communication.scan.result","ok":true,"data":{"section":"wifi",'
        '"items":[{"network_id":"Office-2.4G","display_name":"Office-2.4G","signal":-48,"channel":6}],'
        '"more":true,"cursor":"opaque-2"}}',
    expect: const {
      'kind': 'response',
      'id': 3,
      'op': 'communication.scan.result',
      'ok': true,
      'data': {
        'section': 'wifi',
        'items': [
          {'network_id': 'Office-2.4G', 'display_name': 'Office-2.4G', 'signal': -48, 'channel': 6},
        ],
        'more': true,
        'cursor': 'opaque-2',
      },
    },
  ),
  EnvelopeVector(
    id: 'env-resp-scan-page-last',
    description: '§9 响应：末页（more=false 时 cursor 为空串）',
    jsonText: '{"id":4,"op":"communication.scan.result","ok":true,"data":{"section":"wifi",'
        '"items":[{"network_id":"Lab-5G","display_name":"Lab-5G","signal":-71,"channel":36}],'
        '"more":false,"cursor":""}}',
    expect: const {
      'kind': 'response',
      'id': 4,
      'op': 'communication.scan.result',
      'ok': true,
      'data': {
        'section': 'wifi',
        'items': [
          {'network_id': 'Lab-5G', 'display_name': 'Lab-5G', 'signal': -71, 'channel': 36},
        ],
        'more': false,
        'cursor': '',
      },
    },
  ),
  EnvelopeVector(
    id: 'env-resp-config-set',
    description: '§10 响应：多节写入成功，apply=reconnect（仅展示提示）',
    jsonText: '{"id":20,"op":"config.set.result","ok":true,"data":{"stored":["wifi","mqtt"],"apply":"reconnect"}}',
    expect: const {
      'kind': 'response',
      'id': 20,
      'op': 'config.set.result',
      'ok': true,
      'data': {
        'stored': ['wifi', 'mqtt'],
        'apply': 'reconnect',
      },
    },
  ),
  EnvelopeVector(
    id: 'env-resp-config-get',
    description: '§10 响应：config.get 返回节名→持久化值映射（密码掩码由实现决定）',
    jsonText: '{"id":21,"op":"config.get.result","ok":true,"data":{"wifi":{"ssid":"Office-2.4G",'
        '"password":"********"}}}',
    expect: const {
      'kind': 'response',
      'id': 21,
      'op': 'config.get.result',
      'ok': true,
      'data': {
        'wifi': {'ssid': 'Office-2.4G', 'password': '********'},
      },
    },
  ),
  EnvelopeVector(
    id: 'env-resp-session-close',
    description: '§11 响应：session.close 永远成功，响应后 Server 主动断开',
    jsonText: '{"id":32,"op":"session.close.result","ok":true,"data":{}}',
    expect: const {'kind': 'response', 'id': 32, 'op': 'session.close.result', 'ok': true, 'data': {}},
  ),

  // ---- 失败响应（九错误码各一） ----
  EnvelopeVector(
    id: 'env-err-unsupported-operation',
    description: '§6.3 形状 + UNSUPPORTED_OPERATION：设备不支持 config.get',
    jsonText: '{"id":21,"op":"config.get.result","ok":false,"error":{"code":"UNSUPPORTED_OPERATION",'
        '"message":"operation is not supported"}}',
    expect: const {
      'kind': 'response',
      'id': 21,
      'op': 'config.get.result',
      'ok': false,
      'error': {'code': 'UNSUPPORTED_OPERATION'},
    },
  ),
  EnvelopeVector(
    id: 'env-err-busy',
    description: 'BUSY：写入期间收到 communication.scan',
    jsonText: '{"id":3,"op":"communication.scan.result","ok":false,"error":{"code":"BUSY",'
        '"message":"writing configuration"}}',
    expect: const {
      'kind': 'response',
      'id': 3,
      'op': 'communication.scan.result',
      'ok': false,
      'error': {'code': 'BUSY'},
    },
  ),
  EnvelopeVector(
    id: 'env-err-section-not-supported',
    description: 'SECTION_NOT_SUPPORTED：对 ethernet（configurable=false）或未声明节写入',
    jsonText: '{"id":20,"op":"config.set.result","ok":false,"error":{"code":"SECTION_NOT_SUPPORTED",'
        '"message":"section ethernet is not configurable"}}',
    expect: const {
      'kind': 'response',
      'id': 20,
      'op': 'config.set.result',
      'ok': false,
      'error': {'code': 'SECTION_NOT_SUPPORTED'},
    },
  ),
  EnvelopeVector(
    id: 'env-err-field-not-supported',
    description: 'FIELD_NOT_SUPPORTED：NE101 的 wifi 节提交 bssid',
    jsonText: '{"id":20,"op":"config.set.result","ok":false,"error":{"code":"FIELD_NOT_SUPPORTED",'
        '"message":"field wifi.bssid is not declared"}}',
    expect: const {
      'kind': 'response',
      'id': 20,
      'op': 'config.set.result',
      'ok': false,
      'error': {'code': 'FIELD_NOT_SUPPORTED'},
    },
  ),
  EnvelopeVector(
    id: 'env-err-invalid-argument',
    description: 'INVALID_ARGUMENT：字段类型/范围/组合非法（示例：port 超范围）',
    jsonText: '{"id":20,"op":"config.set.result","ok":false,"error":{"code":"INVALID_ARGUMENT",'
        '"message":"mqtt.port out of range"}}',
    expect: const {
      'kind': 'response',
      'id': 20,
      'op': 'config.set.result',
      'ok': false,
      'error': {'code': 'INVALID_ARGUMENT'},
    },
  ),
  EnvelopeVector(
    id: 'env-err-storage-failed',
    description: 'STORAGE_FAILED：持久化失败（全有或全无，无节被写入）',
    jsonText: '{"id":20,"op":"config.set.result","ok":false,"error":{"code":"STORAGE_FAILED",'
        '"message":"nvs commit failed"}}',
    expect: const {
      'kind': 'response',
      'id': 20,
      'op': 'config.set.result',
      'ok': false,
      'error': {'code': 'STORAGE_FAILED'},
    },
  ),
  EnvelopeVector(
    id: 'env-err-internal-error',
    description: 'INTERNAL_ERROR：未归类内部错误',
    jsonText: '{"id":1,"op":"device.info.result","ok":false,"error":{"code":"INTERNAL_ERROR",'
        '"message":"unexpected"}}',
    expect: const {
      'kind': 'response',
      'id': 1,
      'op': 'device.info.result',
      'ok': false,
      'error': {'code': 'INTERNAL_ERROR'},
    },
  ),
  EnvelopeVector(
    id: 'env-err-unsupported-version',
    description: 'UNSUPPORTED_VERSION：协议版本不支持',
    jsonText: '{"id":1,"op":"device.info.result","ok":false,"error":{"code":"UNSUPPORTED_VERSION",'
        '"message":"protocol version not supported"}}',
    expect: const {
      'kind': 'response',
      'id': 1,
      'op': 'device.info.result',
      'ok': false,
      'error': {'code': 'UNSUPPORTED_VERSION'},
    },
  ),
  EnvelopeVector(
    id: 'env-err-invalid-message',
    description: 'INVALID_MESSAGE：JSON 或信封非法',
    jsonText: '{"id":1,"op":"device.info.result","ok":false,"error":{"code":"INVALID_MESSAGE",'
        '"message":"malformed envelope"}}',
    expect: const {
      'kind': 'response',
      'id': 1,
      'op': 'device.info.result',
      'ok': false,
      'error': {'code': 'INVALID_MESSAGE'},
    },
  ),

  // ---- 异步事件与异常输入 ----
  EnvelopeVector(
    id: 'env-event-protocol-error',
    description: '§6.4/§5 唯一异步事件：protocol.error（seq 单调递增）',
    jsonText: '{"seq":8,"event":"protocol.error","data":{}}',
    expect: const {'kind': 'event', 'seq': 8, 'event': 'protocol.error', 'data': {}},
  ),
  EnvelopeVector(
    id: 'env-unknown-op-request',
    description: '未知 op 请求：Client 可发出（Server 应回 UNSUPPORTED_OPERATION）',
    jsonText: '{"id":99,"op":"device.reboot","data":{}}',
    expect: const {'kind': 'request', 'id': 99, 'op': 'device.reboot', 'data': {}},
  ),
  EnvelopeVector(
    id: 'env-unmatched-response-id',
    description: '响应 id 无法关联任何在途请求：Client 必须忽略（§6.4）',
    jsonText: '{"id":77,"op":"device.info.result","ok":true,"data":{}}',
    expect: const {'kind': 'response', 'id': 77, 'op': 'device.info.result', 'ok': true, 'ignore': true},
  ),
  EnvelopeVector(
    id: 'env-invalid-bom',
    description: '非法输入：UTF-8 BOM 前缀（§6 禁止 BOM）',
    jsonText: '﻿{"id":1,"op":"device.info.get","data":{}}',
    invalidReason: 'bom',
  ),
  EnvelopeVector(
    id: 'env-invalid-not-object',
    description: '非法输入：顶层不是 object',
    jsonText: '[1,2,3]',
    invalidReason: 'not_object',
  ),
  EnvelopeVector(
    id: 'env-invalid-float-int',
    description: '非法输入：整数用浮点数表达（§6 禁止）',
    jsonText: '{"id":12.5,"op":"communication.capabilities.get","data":{}}',
    invalidReason: 'float_int',
  ),
  EnvelopeVector(
    id: 'env-invalid-trailing-garbage',
    description: '非法输入：合法 JSON 后有多余内容',
    jsonText: '{"id":1,"op":"device.info.get","data":{}} extra',
    invalidReason: 'trailing_garbage',
  ),
];
