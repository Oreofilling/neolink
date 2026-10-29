# NeoLink 仓库约束

## 语言（C-L1）

- 项目主语言为英文：标识符、文件与目录名、提交信息、CI 配置、错误 reason 字符串一律英文
- 注释（`///` 文档注释、行内注释、黄金向量的 description 字段）一律用中文叙述，**不得出现英文叙述或英文单词代替中文**（写「请求」而非 request，写「响应」而非 response）
- 协议字段名、常量与既定术语按代码标识符原样引用、不翻译：MTU、UUID、AD Structure、payload_max、magic_version、packet_kind、op 名（`config.set` 等）、错误码（`BUSY` 等）、型号名（NE101/NE301）
- 字段取值枚举放代码/数据里（枚举值、向量 expect），不放注释里

## 由来

2026-10-29 用户约束：「代码约束——注释不要出现英文，该项目主语言是英文」。test_vectors 包为首个按此约束审查的代码。
