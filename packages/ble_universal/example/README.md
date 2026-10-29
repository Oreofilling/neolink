# ct_prov_poc

CT-Prov/1 真机 PoC（F1 第 4 步）：扫描 → 连接（§3 序列）→ `device.info.get`
→ `session.close`，逐步日志。适配器实现见上级包 `ble_universal`。

## 运行

```powershell
cd packages/ble_universal/example
flutter pub get
flutter run -d windows
```

前提：

- Windows 主机带蓝牙射频（内置或 USB dongle）；
- 设备端固件进配置模式，按 §4.2 以 CT-Prov Service UUID 广播
  （低功耗相机仓库 hw-v1.2 分支，`ct_prov_app_start` 已接入配置模式）。

界面操作：Start scan → 列表点选设备 → 观察日志窗格；`roundtrip failed`
会给出具体一步的异常（连接/配对/MTU/写入/响应超时）。
