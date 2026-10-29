import 'package:provisioning_session/provisioning_session.dart';
import 'package:test/test.dart';

void main() {
  test('状态机含环境自检起点', () {
    expect(SessionPhase.values.first, SessionPhase.selfChecking);
    expect(SessionPhase.values.contains(SessionPhase.cleaning), isTrue);
  });
}
