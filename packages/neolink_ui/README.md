# neolink_ui

NeoMind 设计系统 for NeoLink：`tokens.dart` 由 `tool/gen_tokens.py` 从原型 OKLCH 令牌生成（勿手改），亮/暗两套经 ThemeExtension 注册（`context.nl.xxx`）。组件遵循：静态卡片仅边框、状态徽章带图标/点、骨架屏加载、下划线 tabs、单色 primary。

## i18n

组件不硬编码任何用户可见文案（`label` 等一律由应用层传入并本地化）；语言资源归应用层（见 desktop_app/lib/l10n）。
