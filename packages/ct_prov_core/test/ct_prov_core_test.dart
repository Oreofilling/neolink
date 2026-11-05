import 'package:ct_prov_core/ct_prov_core.dart';
import 'package:test/test.dart';

void main() {
  test('操作集为 v2.0 全集 6 个', () {
    expect(ProvOp.values.length, 6);
    expect(ProvOp.configSet.wireName, 'config.set');
  });

  test('错误码 9 个且不含运行时联网错误', () {
    expect(ProvErrorCode.values.length, 9);
    expect(ProvErrorCode.values.map((e) => e.wireName),
        isNot(contains('WIFI_AUTH_FAILED')));
  });
}
