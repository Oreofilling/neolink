# M3 验收报告：配置表单与下发

- 日期：2026-11-03
- 基线：neolink `9a0cc95`（依赖 `653e07f` close 修复、`737e2f0` transport 修复）
- 验证环境：Windows 编译机（192.168.93.9），`val_m25` 流水线（pub get + gen-l10n + analyze + test）
- 结果：**analyze 零问题，40/40 测试通过**（见「验证记录」）
- 依据：NEOLINK_WINDOWS_DEV_PLAN §M3；NEOLINK_TECH_SELECTION §13.3 / §13.4

## 验证记录

| 项 | 结果 |
| --- | --- |
| provisioning_session analyze + test | 零问题 / 49 过 |
| discovery_domain analyze + test | 零问题 / 12 过 |
| ble_universal analyze + test | 零问题 / 38 过 |
| desktop_app analyze + test | 零问题 / 40 过 |
| Windows release 构建 + lock sanity | 通过（`653e07f` 时点，`desktop_app.exe` 已产出） |

验证载体为 fake transport（`test/provisioning_fakes.dart` 的 `FakeCtDevice`），三能力形态：
`ne101`（wifi/cellular/mqtt）、`ne301`（comm 选择器 + wifi/bssid + cellular/roaming + 只读 ethernet + mqtt + webhook/secret）、
`halow`（comm + 可扫描 halow 含 country + 免配置卡 cellular）。

## §13.3 通讯模式（四模式）

| 模式 | 必测项 | 实现 | 测试 | 结果 |
| --- | --- | --- | --- | --- |
| Wi-Fi | 扫描 | `scanNetworks` 游标分页（§9），扫描面板 + 选网回填 ssid | controller「network scan pages via cursor」；widget「M3 network scan」 | ✅ |
| Wi-Fi | 隐藏 SSID | 不经扫描、同一 ssid 字段手动输入（面板提示文案） | controller「§13.3 Wi-Fi: open network…」手输 ssid 路径 | ✅ |
| Wi-Fi | 开放网络（无密码） | 空密码合法：payload 省略 password 字段 | 同上测试断言 `lastConfigSet['wifi'] == {'ssid': …}` | ✅ |
| Wi-Fi | 密码长度校验 | 8~63 字节，逐字段标注 tooShort/tooLong | controller「client validation blocks submit…」 | ✅ |
| CAT1 | 自动 APN | 能力 `fields=[]`（免配置卡）→ 表单无可填字段，提交空节对象确认缺省 | controller「§13.3 CAT1: preconfigured SIM…」 | ✅ |
| CAT1 | 手工 APN | apn 1~64 字节，字段渲染由能力驱动 | controller「§13.3 CAT1: manual apn/pin/auth…」 | ✅ |
| CAT1 | PIN/认证字段 | pin 4~8 位数字（invalidFormat 标注）；auth 下拉 none/pap/chap/pap_or_chap | 同上（malformed pin 阻断 + 合法提交） | ✅ |
| CAT1 | 未声明字段拒绝 | 客户端 notDeclared 门控（不渲染 + 提交前阻断）；设备侧 FIELD_NOT_SUPPORTED 横幅 | controller「undeclared field is gated…」「device rejection…」 | ✅ |
| Wi-Fi HaLow | 扫描 | 可扫描节走同一 communication.scan；选网回填 ssid | controller「§13.3 HaLow: scan pick…」 | ✅ |
| Wi-Fi HaLow | 区域代码 | 扫描条目 extras.country 回填（仅能力声明 country 时）；国家码格式校验 | 同上（`country: 'CN'` 入载荷） | ✅ |
| Wi-Fi HaLow | 开放网络 | 空密码省略，同 Wi-Fi 语义 | payload 单元测试（M3-1）+ 同上 | ✅ |
| Ethernet | 只读节展示 | `configurable=false` → 勾选禁用 + 只读徽章，不进编辑轮 | controller「ne301 shape…」排除断言；widget 只读行 | ✅ |
| Ethernet | PoE 供电属性 | `device.info.power` 含 `poe` → ethernet 行 PoE 徽章（新增） | widget「M3 PoE: ethernet readonly row…」 | ✅ |

## §13.4 服务节（MQTT/Webhook）

| 用例 | 实现 | 测试 | 结果 |
| --- | --- | --- | --- |
| 能力未声明服务节 → 不显示入口 | 编辑轮 ⊆ 能力声明节（`beginEditing` 过滤） | controller「§13.4 undeclared service section…」 | ✅ |
| MQTT 字段提交 + config.get 预填 | 9 字段表单；预填跳过掩码密码；不支持 config.get 优雅降级 | controller「beginEditing prefills…」「unsupported config.get…」 | ✅ |
| 未声明字段 → FIELD_NOT_SUPPORTED | 客户端先行门控使其在正常流程不可达；设备拒绝时横幅展示错误码并保留草稿 | widget「M3 rejection…」 | ✅ |
| 与网络节同请求提交 | 单次 config.set 整体载荷 | controller「submit stores both sections…」「ne301 shape…」 | ✅ |
| 无活动网络时提交服务节 | 无网络活跃度门控；结果页展示 apply 生效提示 | controller「§13.4 service-only submit…」 | ✅ |
| 校验或存储失败 → 整单不写、保留表单 | 客户端校验阻断零发送；设备拒绝进 operationError，editAgain 保留草稿 | controller「client validation…」「device rejection…」 | ✅ |

## 过程修复

- **transport 清理链挂死（CRITICAL 级）**：broadcast 流投递过事件后，`subscription.cancel()` 的
  future 在部分事件循环（含 fake_async 测试时钟）永不完成；`transport.close()` awaiting 它导致
  会话收尾卡在 cleaning。本地最小复现（fakeAsync + 真实包链路）定位后，close() 改为确定性返回
  （取消即刻生效、teardown future 不阻塞清理链；真机慢 BLE 栈取消同样受益）。`737e2f0`。

## 偏差与后移

1. **NE101 实机用例后移**：固件 F2（config.set→NVS、Wi-Fi 扫描）未实现，M3 按 R1 缓解措施以
   fake transport 三形态验证；实机全用例在 F2 完成后回归（计划 §F2 验收即「NE101 实机通过 M3 全部用例」）。
2. **设备拒绝的字段级标注**：设备错误消息为自由文本，未解析定位到字段行；客户端未声明字段门控
   已使该路径在正常流程不可达，拒绝统一以横幅呈现。
3. **§13.5 数量门禁**（100 连发、断链三时点、日志审计）属 M6，不在本里程碑。
4. **apply 提示**：immediate/reconnect/reboot 仅展示（C-11 无事务模型），不据此等待或轮询。

## 结论

§13.3 四模式与 §13.4 服务节全部用例在 fake transport 双产品形态 + halow 扩展形态下通过；
M3-1（schema）～M3-4（流水线门禁）齐绿。M3 桌面端验收通过，实机回归挂起 F2。
