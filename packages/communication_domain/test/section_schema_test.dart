// M3 schema 层测试：七节字段校验（长度按 UTF-8 字节）、能力门控、载荷
// 组装（未声明字段不提交也不静默丢弃）。规则来源 CT_CONFIG_SCHEMA.md。
library;

import 'package:communication_domain/communication_domain.dart';
import 'package:test/test.dart';

void main() {
  group('wifi 节', () {
    const declared = ['ssid', 'password'];

    test('有效凭据通过并完整进载荷', () {
      const section = WifiSection(
        ssid: 'Office-2.4G',
        password: 'example-password',
      );
      expect(validateSection(section, declaredFields: declared), isEmpty);
      expect(buildSectionPayload(section, declaredFields: declared), {
        'ssid': 'Office-2.4G',
        'password': 'example-password',
      });
    });

    test('空密码表示开放网络：载荷省略 password', () {
      const section = WifiSection(ssid: 'OpenNet', password: '');
      expect(validateSection(section, declaredFields: declared), isEmpty);
      expect(
        buildSectionPayload(section, declaredFields: declared),
        {'ssid': 'OpenNet'},
      );
    });

    test('密码 8~63 字节：过短报 tooShort', () {
      const section = WifiSection(ssid: 'Net', password: 'short');
      final problems = validateSection(section, declaredFields: declared);
      expect(
        problems,
        contains(
          predicate<FieldProblem>(
            (p) => p.field == 'password' && p.code == FieldProblemCode.tooShort,
          ),
        ),
      );
    });

    test('SSID 为空报 required；31 字节为上限（按字节计）', () {
      expect(
        validateSection(
          const WifiSection(ssid: '', password: 'example-password'),
          declaredFields: declared,
        ),
        contains(
          predicate<FieldProblem>(
            (p) => p.field == 'ssid' && p.code == FieldProblemCode.required,
          ),
        ),
      );
      // 32 个 ASCII 字节超上限；31 字节通过。
      const tooLong = WifiSection(
          ssid: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', password: 'x8charss');
      expect(
        validateSection(tooLong, declaredFields: declared),
        contains(
          predicate<FieldProblem>(
            (p) => p.field == 'ssid' && p.code == FieldProblemCode.tooLong,
          ),
        ),
      );
      const edge = WifiSection(
          ssid: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', password: 'x8charss');
      expect(
        validateSection(edge, declaredFields: declared),
        isEmpty,
      );
    });

    test('bssid 需能力声明且格式为冒号分隔十六进制', () {
      // 能力不含 bssid：非空值报 notDeclared（不静默丢弃）。
      expect(
        validateSection(
          const WifiSection(
              ssid: 'Net', password: 'x8charss', bssid: 'AA:BB:CC:DD:EE:FF'),
          declaredFields: declared,
        ),
        contains(
          predicate<FieldProblem>(
            (p) => p.field == 'bssid' && p.code == FieldProblemCode.notDeclared,
          ),
        ),
      );
      // 声明后格式错误报 invalidFormat。
      expect(
        validateSection(
          const WifiSection(
              ssid: 'Net', password: 'x8charss', bssid: 'AABBCCDDEEFF'),
          declaredFields: const ['ssid', 'password', 'bssid'],
        ),
        contains(
          predicate<FieldProblem>(
            (p) =>
                p.field == 'bssid' && p.code == FieldProblemCode.invalidFormat,
          ),
        ),
      );
      // 合法 bssid 进载荷。
      expect(
        buildSectionPayload(
          const WifiSection(
              ssid: 'Net', password: 'x8charss', bssid: 'aa:bb:cc:dd:ee:ff'),
          declaredFields: const ['ssid', 'password', 'bssid'],
        ),
        containsPair('bssid', 'aa:bb:cc:dd:ee:ff'),
      );
    });
  });

  group('cellular 节', () {
    const declared = ['apn', 'username', 'password', 'pin', 'auth', 'roaming'];

    test('手工 APN 完整提交', () {
      const section = CellularSection(
        apn: 'cmiot.iot',
        username: 'device',
        password: 'example-password',
        pin: '1234',
        auth: 'chap',
        roaming: true,
      );
      expect(validateSection(section, declaredFields: declared), isEmpty);
      expect(
        buildSectionPayload(section, declaredFields: declared),
        {
          'apn': 'cmiot.iot',
          'username': 'device',
          'password': 'example-password',
          'pin': '1234',
          'auth': 'chap',
          'roaming': true,
        },
      );
    });

    test('免配置卡：apn 未声明时省略且不报错', () {
      const section = CellularSection.empty();
      expect(validateSection(section, declaredFields: const []), isEmpty);
      expect(buildSectionPayload(section, declaredFields: const []), {});
    });

    test('PIN 4~8 位数字；auth 枚举；roaming 需声明', () {
      expect(
        validateSection(
          const CellularSection(apn: 'cmiot.iot', pin: '12'),
          declaredFields: declared,
        ),
        contains(
          predicate<FieldProblem>(
            (p) => p.field == 'pin' && p.code == FieldProblemCode.invalidFormat,
          ),
        ),
      );
      expect(
        validateSection(
          const CellularSection(apn: 'cmiot.iot', auth: 'ms-chap'),
          declaredFields: declared,
        ),
        contains(
          predicate<FieldProblem>(
            (p) => p.field == 'auth' && p.code == FieldProblemCode.invalidValue,
          ),
        ),
      );
      expect(
        validateSection(
          const CellularSection(apn: 'cmiot.iot', roaming: true),
          declaredFields: const ['apn'],
        ),
        contains(
          predicate<FieldProblem>(
            (p) =>
                p.field == 'roaming' && p.code == FieldProblemCode.notDeclared,
          ),
        ),
      );
    });

    test('APN 1~64 字节', () {
      expect(
        validateSection(
          CellularSection(apn: 'a' * 65),
          declaredFields: const ['apn'],
        ),
        contains(
          predicate<FieldProblem>(
            (p) => p.field == 'apn' && p.code == FieldProblemCode.tooLong,
          ),
        ),
      );
      expect(
        validateSection(
          CellularSection(apn: 'a' * 64),
          declaredFields: const ['apn'],
        ),
        isEmpty,
      );
    });
  });

  group('halow 与 ethernet 节', () {
    test('halow：ssid 1~32B、country 两位大写、开放网络', () {
      expect(
        validateSection(
          const HalowSection(
              ssid: 'CT-HaLow', password: 'example-password', country: 'CN'),
          declaredFields: const ['ssid', 'password', 'country'],
        ),
        isEmpty,
      );
      expect(
        buildSectionPayload(
          const HalowSection(ssid: 'CT-HaLow', password: '', country: 'CN'),
          declaredFields: const ['ssid', 'password', 'country'],
        ),
        {'ssid': 'CT-HaLow', 'country': 'CN'},
      );
      expect(
        validateSection(
          const HalowSection(
              ssid: 'CT-HaLow', password: 'x8charss', country: 'cn'),
          declaredFields: const ['ssid', 'password', 'country'],
        ),
        contains(
          predicate<FieldProblem>(
            (p) =>
                p.field == 'country' &&
                p.code == FieldProblemCode.invalidFormat,
          ),
        ),
      );
    });

    test('ethernet：无可写字段，载荷为空对象', () {
      expect(
        validateSection(const EthernetSection(), declaredFields: const []),
        isEmpty,
      );
      expect(
        buildSectionPayload(const EthernetSection(), declaredFields: const []),
        {},
      );
    });
  });

  group('comm 节', () {
    test('type 必须是设备声明的网络节之一', () {
      const wifiComm = CommSection(type: CommunicationMode.wifi);
      expect(
        validateSection(
          wifiComm,
          declaredFields: const ['type'],
          declaredNetworks: const {'wifi', 'cellular'},
        ),
        isEmpty,
      );
      expect(
        buildSectionPayload(
          wifiComm,
          declaredFields: const ['type'],
        ),
        {'type': 'wifi'},
      );
      // 设备未声明 halow 节却选择 halow：invalidValue。
      expect(
        validateSection(
          const CommSection(type: CommunicationMode.wifiHalow),
          declaredFields: const ['type'],
          declaredNetworks: const {'wifi', 'cellular'},
        ),
        contains(
          predicate<FieldProblem>(
            (p) => p.field == 'type' && p.code == FieldProblemCode.invalidValue,
          ),
        ),
      );
      // 通讯模式四选一且与发现通道不同类型（保留既有语义）。
      expect(CommunicationMode.values, hasLength(4));
      expect(CommunicationMode.cat1.wireName, 'cellular');
      expect(CommunicationMode.wifiHalow.wireName, 'halow');
    });
  });

  group('mqtt 节', () {
    const declared = [
      'enable',
      'host',
      'port',
      'client_id',
      'username',
      'password',
      'tls',
      'topic',
      'qos',
    ];

    test('完整提交；可选字段省略不进载荷', () {
      const full = MqttSection(
        enable: true,
        host: 'mqtt.example.com',
        port: 8883,
        clientId: 'NE101202610270001',
        username: 'device',
        password: 'example-secret',
        tls: true,
        topic: 'ct/NE101202610270001/data',
        qos: 1,
      );
      expect(validateSection(full, declaredFields: declared), isEmpty);
      expect(
        buildSectionPayload(full, declaredFields: declared),
        {
          'enable': true,
          'host': 'mqtt.example.com',
          'port': 8883,
          'client_id': 'NE101202610270001',
          'username': 'device',
          'password': 'example-secret',
          'tls': true,
          'topic': 'ct/NE101202610270001/data',
          'qos': 1,
        },
      );

      const minimal =
          MqttSection(enable: false, host: 'mqtt.example.com', port: 1883);
      expect(
        buildSectionPayload(minimal, declaredFields: declared),
        {'enable': false, 'host': 'mqtt.example.com', 'port': 1883},
      );
    });

    test('port 1..65535；qos 0..2；topic 禁通配符', () {
      expect(
        validateSection(
          const MqttSection(enable: true, host: 'h', port: 0),
          declaredFields: declared,
        ),
        contains(
          predicate<FieldProblem>(
            (p) => p.field == 'port' && p.code == FieldProblemCode.invalidValue,
          ),
        ),
      );
      expect(
        validateSection(
          const MqttSection(enable: true, host: 'h', port: 1883, qos: 3),
          declaredFields: declared,
        ),
        contains(
          predicate<FieldProblem>(
            (p) => p.field == 'qos' && p.code == FieldProblemCode.invalidValue,
          ),
        ),
      );
      expect(
        validateSection(
          const MqttSection(
              enable: true, host: 'h', port: 1883, topic: 'ct/+/data'),
          declaredFields: declared,
        ),
        contains(
          predicate<FieldProblem>(
            (p) =>
                p.field == 'topic' && p.code == FieldProblemCode.invalidFormat,
          ),
        ),
      );
    });
  });

  group('webhook 节', () {
    const declared = ['enable', 'url', 'secret', 'header'];

    test('url 须 http/https 绝对地址；secret 与 header 需声明', () {
      expect(
        validateSection(
          const WebhookSection(
            enable: true,
            url: 'https://ops.example.com/hooks/camera',
            secret: 'whsec_example',
            header: 'X-API-Key: abc123',
          ),
          declaredFields: declared,
        ),
        isEmpty,
      );
      expect(
        validateSection(
          const WebhookSection(enable: true, url: 'ftp://example.com/hook'),
          declaredFields: declared,
        ),
        contains(
          predicate<FieldProblem>(
            (p) => p.field == 'url' && p.code == FieldProblemCode.invalidFormat,
          ),
        ),
      );
      // 能力不含 secret：非空值报 notDeclared。
      expect(
        validateSection(
          const WebhookSection(
              enable: true, url: 'https://e/h', secret: 's3cret'),
          declaredFields: const ['enable', 'url', 'header'],
        ),
        contains(
          predicate<FieldProblem>(
            (p) =>
                p.field == 'secret' && p.code == FieldProblemCode.notDeclared,
          ),
        ),
      );
      // header 缺冒号分隔符。
      expect(
        validateSection(
          const WebhookSection(
              enable: true, url: 'https://e/h', header: 'NoColon'),
          declaredFields: declared,
        ),
        contains(
          predicate<FieldProblem>(
            (p) =>
                p.field == 'header' && p.code == FieldProblemCode.invalidFormat,
          ),
        ),
      );
    });
  });

  group('多节载荷组装', () {
    test('网络节与服务节一次提交；未声明节报节级问题', () {
      final result = assembleConfigPayload(
        {
          'wifi': const WifiSection(ssid: 'Office-2.4G', password: 'x8charss'),
          'mqtt': const MqttSection(
              enable: true, host: 'mqtt.example.com', port: 8883),
        },
        sectionFields: const {
          'wifi': ['ssid', 'password'],
          'mqtt': ['enable', 'host', 'port'],
        },
      );
      expect(result.problems, isEmpty);
      expect(result.payload, {
        'wifi': {'ssid': 'Office-2.4G', 'password': 'x8charss'},
        'mqtt': {'enable': true, 'host': 'mqtt.example.com', 'port': 8883},
      });

      final unknown = assembleConfigPayload(
        {'ethernet': const EthernetSection()},
        sectionFields: const {
          'wifi': ['ssid'],
        },
      );
      expect(
        unknown.problems,
        contains(
          predicate<FieldProblem>(
            (p) =>
                p.field == 'ethernet' && p.code == FieldProblemCode.notDeclared,
          ),
        ),
      );
      expect(unknown.payload, isEmpty);
    });
  });
}
