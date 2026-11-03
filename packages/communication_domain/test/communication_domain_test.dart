import 'package:communication_domain/communication_domain.dart';
import 'package:test/test.dart';

void main() {
  test('通讯模式四选一且与发现通道不同类型', () {
    expect(CommunicationMode.values.length, 4);
    expect(CommunicationMode.wifi.name, 'wifi');
  });

  test('节联合类型携带节名', () {
    const s = WifiSection(ssid: 'Office-2.4G', password: 'example-password');
    expect(s.name, 'wifi');
    expect(
        WebhookSection(enable: true, url: 'https://ops.example.com/hooks').name,
        'webhook');
  });
}
