// M5 join 原语纯逻辑测试：结构体布局锁定（x64）、开放网络 profile XML
// 生成、candidateId → SSID 还原。wlanapi 调用本身在 Windows 真机 smoke 覆盖。
library;

import 'dart:ffi';

import 'package:ap_discovery_adapter/ap_discovery_adapter.dart';
import 'package:test/test.dart';

void main() {
  group('wlanapi enum pins (wlanapitypes.h)', () {
    // The bench hit WlanConnect rc=87 when temporary_profile was misread
    // as 2: that is discovery_secure, an OS-reserved mode that demands a
    // BSSID list. Pin the enum so the value never drifts again.
    test('connection mode: profile=0, temporary_profile=1', () {
      expect(kWlanConnectionModeProfile, 0);
      expect(kWlanConnectionModeTemporaryProfile, 1);
    });

    // autoconf_start..interface_state occupy 0-6; querying anything lower
    // than 7 returns a different payload than WLAN_CONNECTION_ATTRIBUTES.
    test('current_connection query opcode is 7', () {
      expect(kWlanOpcodeCurrentConnection, 7);
    });
  });

  group('FFI struct layout pins (x64)', () {
    // wlanapitypes.h: mode@0 + strProfile@8 + 两个指针 + 两个尾枚举。
    test('WLAN_CONNECTION_PARAMETERS sizeof 40', () {
      expect(sizeOf<WlanConnectionParameters>(), 40);
    });

    // isState@0 mode@4 profileName@8(512) ssid@524(32) … reason@576。
    test('WLAN_CONNECTION_ATTRIBUTES sizeof 580', () {
      expect(sizeOf<WlanConnectionAttributes>(), 580);
    });
  });

  group('openNetworkProfileXml', () {
    test('emits an open infrastructure profile naming the SSID', () {
      final xml = openNetworkProfileXml('NE101-P_BBC6DC');
      expect(xml, contains('<name>NE101-P_BBC6DC</name>'));
      expect(xml, contains('<authentication>open</authentication>'));
      expect(xml, contains('<encryption>none</encryption>'));
      expect(xml, contains('<connectionType>ESS</connectionType>'));
      // 无密码元素：开放网络 profile 绝不携带共享密钥。
      expect(xml.contains('sharedKey'), isFalse);
      expect(xml.contains('keyMaterial'), isFalse);
    });

    test('escapes XML metacharacters in the SSID', () {
      final xml = openNetworkProfileXml('A&B<C>"D"');
      expect(xml, contains('<name>A&amp;B&lt;C&gt;&quot;D&quot;</name>'));
    });
  });

  group('apSsidFromCandidateId', () {
    test('strips the ap: prefix', () {
      expect(apSsidFromCandidateId('ap:NE101-P_BBC6DC'), 'NE101-P_BBC6DC');
      expect(apSsidFromCandidateId('ap:CT-AP-A1B2C3'), 'CT-AP-A1B2C3');
    });

    test('returns null for non-AP ids (ble/ctdisc)', () {
      expect(apSsidFromCandidateId('ble:11:22:33:44:55:66'), isNull);
      expect(apSsidFromCandidateId('ctdisc:A1B2C3@Ethernet'), isNull);
    });
  });

  group('WlanRestorePoint', () {
    test('profileName null means plain disconnect on restore', () {
      const point = WlanRestorePoint(ssid: 'NE101-P_BBC6DC');
      expect(point.profileName, isNull);
      expect(point.ssid, 'NE101-P_BBC6DC');
    });
  });
}
