# Fsearch Desktop

基于 [noahdunnagan/fsearch](https://github.com/noahdunnagan/fsearch) 的 macOS 原生文件搜索客户端，使用 SwiftUI + AppKit，面向希望像 Windows Everything 一样快速定位文件的普通用户。

**当前阶段：已有原生客户端、公开服务测试、两架构开发 DMG 及仓库工作流。默认开发包为受控样本验证模式；真实权限、Intel/macOS 13、完整 alpha 与签名公证门禁仍有未验证项，尚非公众正式发行。**

目标仓库：[wynnok/fsearch-desktop](https://github.com/wynnok/fsearch-desktop)。搜索、索引和文件系统变更跟踪使用 Fsearch；客户端负责界面、查询配置、结果呈现、检查器和 macOS 系统交互。

## 文档入口

| 文档 | 用途 |
| --- | --- |
| [开发验证版使用指南](docs/product/user-guide.md) | 实际模式、搜索/权限、文件动作、本地数据、诊断及手动更新 |
| [Wave 4 旅程验收](docs/implementation/Wave4.md) | T25/T26/T28 的证据、失败与未验证项 |
| [Tickets 索引](docs/tickets/README.md) | 33 张已批准的纵向执行切片、主 Spec 归属、原生阻塞边及认领顺序 |
| [Spec 索引](docs/specs/README.md) | 14 份已发布规格、原生父子/阻塞关系、执行顺序与 23 项选择追踪 |
| [引擎调查](docs/research/fsearch-engine.md) | 固定上游版本的算法、API、能力边界与验证证据 |
| [产品需求](docs/product/requirements.md) | 定位、版本范围、逐项验收标准 |
| [交互方案](docs/product/interaction.md) | 三个主要区域、路径导航、键盘操作和状态呈现 |
| [架构方案](docs/engineering/architecture.md) | SwiftUI / AppKit / Fsearch 边界与集成验证 |
| [M1 验证计划](docs/engineering/validation-plan.md) | 首选嵌入路线、全局排序、权限、生命周期、双架构与升级通路的验证清单 |
| [生命周期计划](docs/product/lifecycle.md) | 调研、实现、测试、发布、维护与文档产出 |
| [发布方案](docs/engineering/release.md) | 双架构构建、DMG、签名公证、Releases 门禁 |
| [领域术语](GLOSSARY.md) | 搜索范围、覆盖、全局排序等概念 |
| [ADR](docs/adr/) | 产品与架构的重要决策 |

## 已完成的仓库配置

- Issues：GitHub Issues；五个默认 triage 标签。
- Agent 约定：[AGENTS.md](AGENTS.md) 和 [docs/agents/](docs/agents/)。
- 领域文档：single-context。
- 本地 `origin` 已关联目标仓库。

## 开发与验证约束

依赖、构建、测试数据和缓存保存在项目目录内，不安装全局工具，不运行上游 `fsearch install`。
引擎调查固定到 `88e63fdf850cf7749deae8198b187accd21f8ba5`（0.2.1）。
现有本机受控服务、资源与安装证据见 [实施报告](docs/implementation/)。Intel 实机、macOS 13 实机、真实 TCC 和完整覆盖仍未验证，样本测量不代表个人磁盘性能。

项目根目录入口：`bash scripts/dev.sh check`、`bash scripts/dev.sh test`、`bash scripts/dev.sh run`。开发 DMG 使用 `bash scripts/package-dev-dmg.sh`；实际验收使用 `bash scripts/verify-dev-dmg.sh --dmg <path>`。开发包和用户指南不替代 alpha 或公众发行门禁。

