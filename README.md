# NeoLink

设备扫描与通讯配置工具（无设备库）。Windows 10/11 桌面端为 P0 首发平台。

- 技术基线与门禁：`lowpower_camera/docs/NEOLINK_TECH_SELECTION.md`
- 开发计划（M0–M6 / F1–F2）：`lowpower_camera/docs/NEOLINK_WINDOWS_DEV_PLAN.md`
- UI 原型：`lowpower_camera/docs/neolink_ui_mockup.html`

## 结构（M0）

```text
neolink/
├── apps/desktop_app/        # Windows 入口（参考实现）
├── packages/
│   ├── neolink_ui/          # NL 设计系统（OKLCH 令牌 + 基础组件）
│   ├── ct_prov_core/        # CT-Prov/1 编解码、分片、错误码（M1 填充）
│   ├── discovery_domain/    # 三路发现归一化（M2 填充）
│   ├── provisioning_session/# 配置会话状态机（M2 填充）
│   ├── communication_domain/# 节 schema 与校验（M3 填充）
│   └── test_vectors/        # CT-Prov/1 黄金向量（广播/分片/信封）
├── design/                  # 品牌标（链·N）：SVG 母版 / 概念稿 / PNG
├── tool/ci.sh               # CI 入口
├── tool/gen_tokens.py       # 设计令牌再生成（OKLCH→Dart）
└── tool/gen_app_icon.py     # 品牌标 → app_icon.ico + 多尺寸 PNG
```

## 中英双语（i18n）

- 方案：Flutter 官方 `gen-l10n`（ARB 文件 + 代码生成），zh 为模板语言，en 第二语言。
- 文案位置：`apps/desktop_app/lib/l10n/app_*.arb`；查表扩展 `lib/l10n/labels.dart`。
- 规则：**neolink_ui 组件不硬编码文案**（label 一律由应用层传入并本地化）；新增语言 = 新增一个 ARB 文件。
- 语言与主题同为工具设置项（允许持久化，M2 接入）。
- `windows/` runner 已入库（自定义 `app_icon.ico`），CI 不再引导生成。
- 本地改词后跑 `flutter gen-l10n`（apps/desktop_app，产出 `lib/l10n/app_localizations*.dart`，已 gitignore；CI 自动执行）。

## 命令

```bash
# 各包（或 apps/desktop_app）内：
flutter pub get && flutter analyze && flutter test
# 桌面端运行：
cd apps/desktop_app && flutter run -d windows
```

## 设计令牌

`packages/neolink_ui/lib/src/tokens.dart` 由 `tool/gen_tokens.py` 从原型
（NL 设计系统）的 OKLCH 令牌生成，亮/暗两套，经 `ThemeExtension` 注册；
Widget 内用 `context.nl.background` 等访问。修改设计时改原型后重新生成，勿手改。

## 品牌标（链·N）

- 母版 `design/logo.svg`（单墨 currentColor，随语境着色）；`design/logo-accent.svg`
  （accent 只出现在中心节点）；`design/logo-tile.svg`（elevated ink 圆角砖 + 反白标，
  App 图标基形）。概念与备选见 `design/logo-concepts.html`。
- App 图标与 PNG 由 `tool/gen_app_icon.py` 生成：
  `apps/desktop_app/windows/runner/resources/app_icon.ico`（16–256，
  ≤24px 用简化形：连续对角线）与 `design/png/` 多尺寸导出。
- UI 内一律用 `NLLogo` 组件（neolink_ui），不贴图；改几何时同步
  母版 / 组件 / 生成脚本三处（同为 0..96 坐标空间）。

## M0 状态

- [x] monorepo 结构（apps + packages，path 依赖）
- [x] neolink_ui：OKLCH 令牌 / 卡片 / 按钮 / 徽章 / 骨架屏 / 下划线 tabs / 亮暗主题
- [x] desktop_app 空壳：侧栏导航 + 顶栏主题/语言切换 + 页面占位
- [x] 中英双语：gen-l10n + ARB（zh 模板），文案全走 AppLocalizations
- [x] 品牌标：链·N 母版 + NLLogo 组件（侧栏已接） + app 图标
- [x] 字体内置：Plus Jakarta Sans / Noto Sans SC / JetBrains Mono（OFL，pubspec 静态注册）
- [x] windows/ runner 入库；Win 构建机本机 release 构建通过
- [x] CI：Windows runner analyze + test + build
- [x] CI 产物 Win10/11 真机验收（图标 / 字体 / 安装体验，2026-10-29 通过）

## M1 状态

- [x] test_vectors：广播/分片/信封三族黄金向量（MTU 23 极限 3825B、九错误码、NE101/NE301 两形态、四类非法输入）
- [x] ct_prov_core：分片重组/切片 + 信封编解码（2026-10-29，14 测试全绿，切片与黄金帧逐字节一致，BOM 在字节层拒绝）
- [x] ble_adapter：§4 广播/META 解析 + GATT 传输层（2026-10-29，14 测试全绿；CtGattChannel 端口就绪，universal_ble 具体适配器待真机 PoC 验证加密特征访问与 no-bonding 配对）
- [ ] F1 固件联调 roundtrip（待固件侧接入 CT-Prov/1）
