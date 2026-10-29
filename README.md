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
│   ├── neolink_ui/          # NeoMind 设计系统（OKLCH 令牌 + 基础组件）
│   ├── ct_prov_core/        # CT-Prov/1 编解码、分片、错误码（M1 填充）
│   ├── discovery_domain/    # 三路发现归一化（M2 填充）
│   ├── provisioning_session/# 配置会话状态机（M2 填充）
│   ├── communication_domain/# 节 schema 与校验（M3 填充）
│   └── test_vectors/        # 协议黄金向量（M1 填充）
├── tool/ci.sh               # CI 入口
└── tool/gen_tokens.py       # 设计令牌再生成（OKLCH→Dart）
```

## 中英双语（i18n）

- 方案：Flutter 官方 `gen-l10n`（ARB 文件 + 代码生成），zh 为模板语言，en 第二语言。
- 文案位置：`apps/desktop_app/lib/l10n/app_*.arb`；查表扩展 `lib/l10n/labels.dart`。
- 规则：**neolink_ui 组件不硬编码文案**（label 一律由应用层传入并本地化）；新增语言 = 新增一个 ARB 文件。
- 语言与主题同为工具设置项（允许持久化，M2 接入）。

## 命令

```bash
# 各包（或 apps/desktop_app）内：
flutter pub get && flutter analyze && flutter test
# 桌面端运行：
cd apps/desktop_app && flutter run -d windows
```

## 设计令牌

`packages/neolink_ui/lib/src/tokens.dart` 由 `tool/gen_tokens.py` 从原型
（NeoMind 设计系统）的 OKLCH 令牌生成，亮/暗两套，经 `ThemeExtension` 注册；
Widget 内用 `context.nl.background` 等访问。修改设计时改原型后重新生成，勿手改。

## M0 状态

- [x] monorepo 结构（apps + packages，path 依赖）
- [x] neolink_ui：OKLCH 令牌 / 卡片 / 按钮 / 徽章 / 骨架屏 / 下划线 tabs / 亮暗主题
- [x] desktop_app 空壳：侧栏导航 + 顶栏主题/语言切换 + 页面占位
- [x] 中英双语：gen-l10n + ARB（zh 模板），文案全走 AppLocalizations
- [x] CI：Windows runner analyze + test + build
- [ ] Win10/Win11 本机构建验证（无 SDK 环境生成，首跑 CI 可能需小幅 API 适配）
