# Real-device full batch - 2026-11-05 22:12

First green `NL_PROBE_MODE=full` batch against real NE101 hardware.
Three consecutive production cycles (scan -> pair -> caps -> config.get ->
config.set stored -> session.close -> disconnect) on the same device,
driven unattended from the build box.

## Result

```text
PROBE RESULT=device-found id=9c:13:9e:bb:c6:de model=NE101 mac=BBC6DC
PROBE CYCLE 1 PASS in 2s
PROBE CYCLE 2 PASS in 3s
PROBE CYCLE 3 PASS in 3s
PROBE RESULT=all-pass cycles=3
PROBE_EXIT=0
```

- App HEAD: 052c09a (probe close-wait accepts post-cleanup phases)
- Firmware: 7de7cd4 on hw-v1.2 (local; device flashed via idf.py flash)
- Machine: build box 192.168.93.9, Realtek BT 5.0 dongle (cycled once
  between rounds after a wedged scan), device NE101-P_BBC6DC on serial
- Command: `NL_PROBE_MODE=full NL_PROBE_CYCLES=3 flutter test
  integration_test\real_device_probe_test.dart -d windows`

## Device-side evidence (serial console, cycle excerpt)

```text
22:12:06 CT_PROV_BLE: D2C packet delivered (200 bytes)      <- device.info.get
22:12:06 CT_PROV_BLE: D2C packet delivered (608 bytes)      <- capabilities.get
22:12:06 CT_PROV_BLE: D2C packet queued behind in-flight packet (90 bytes)
22:12:07 CT_PROV_BLE: D2C packet delivered (269 bytes)      <- config.get
22:12:07 CT_PROV_BLE: D2C packet delivered (90 bytes)       <- config.set (queued, drained)
22:12:07 CT_PROV_BLE: D2C packet delivered (56 bytes)       <- session.close.result
22:12:07 CT_PROV_BLE: client disconnected, reason=534       <- doc-11 terminate after drain
```

Repeats identically for cycles 2 and 3. No `SLEEP: Entering deep sleep`
during any cycle: the config-mode window stayed open across the whole
batch (previously died at ~62 s mid config.set).

## Fixes this batch proved

1. firmware 8e5f9d2 - AP idle timer holds while a CT-Prov client is
   linked (`ct_prov_ble_client_connected` consulted by wifi.c timer_cb)
2. firmware 7de7cd4 - pipelined D2C responses queue one deep instead of
   being dropped (and no longer kill the in-flight packet)
3. app 052c09a - probe close wait accepts scanning/resultsAvailable/
   scanEmpty (the scan loop re-finds the advertising device before a
   poll can observe the transient scanning phase)
