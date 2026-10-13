# Fsearch Desktop

基于 [noahdunnagan/fsearch](https://github.com/noahdunnagan/fsearch) 的 macOS 原生文件搜索客户端，使用 SwiftUI + AppKit，面向希望像 Windows Everything 一样快速定位文件的普通用户。

**当前阶段：引擎调查和四轮设计访谈的 23 项决策已拆成 1 个总规格、13 个子规格及 33 张执行 Tickets，并发布到 GitHub Issues。尚无客户端实现、构建工作流或可安装发行版。**

目标仓库：[wynnok/fsearch-desktop](https://github.com/wynnok/fsearch-desktop)。搜索、索引和文件系统变更跟踪使用 Fsearch；客户端负责界面、查询配置、结果呈现、检查器和 macOS 系统交互。

## 文档入口

| 文档 | 用途 |
| --- | --- |
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
- 本地 `origin` 已关联目标仓库；尚未提交或推送本轮新增文件。

## 开发与验证约束

依赖、构建、测试数据和缓存保存在项目目录内，不安装全局工具，不运行上游 `fsearch install`。
引擎调查固定到 `88e63fdf850cf7749deae8198b187accd21f8ba5`（0.2.1）。
本机已通过上游 22 项单元测试；尚未验证 Intel 实机、客户端性能、TCC 授权、完整磁盘覆盖或安装包。

当前没有应用构建命令。进入实现阶段后按发布方案补齐，不能把规划文件当成已交付应用。

