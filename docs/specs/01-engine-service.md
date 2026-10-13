# [SPEC-01] M1：可升级 Fsearch 集成与 Swift 引擎服务契约

## Problem Statement

客户端需要真实调用 Fsearch，但没有现成的 Swift/C ABI；复制内部算法会让后续升级困难，未经验证的跨语言边界也无法支撑稳定搜索。

## Solution

建立可复现的上游依赖和最薄的 Rust/C/Swift 桥接，从 Swift 侧引擎服务公开契约发起真实查询、读取状态并接收变化通知，得到可以继续验证的原生骨架。

## User Stories

1. As a developer, I want a pinned upstream dependency, so that builds can be reproduced.
2. As a maintainer, I want upstream and adapter changes separated, so that Fsearch can be upgraded independently.
3. As a developer, I want Swift to call the public Engine, so that the client uses the real search engine.
4. As a developer, I want structured queries, so that ordinary names are not interpreted as advanced syntax.
5. As a user, I want Unicode names preserved, so that Chinese and emoji results remain usable.
6. As a user, I want useful query errors, so that I can correct invalid conditions.
7. As a developer, I want explicit result ownership, so that repeated searches do not leak resources.
8. As a developer, I want panic containment, so that a Rust failure cannot cross the language boundary unsafely.
9. As a user, I want an independent client index, so that upgrading does not alter my CLI index.
10. As a tester, I want controlled fixtures, so that integration tests do not silently scan my personal disk.
11. As a user, I want honest indexing status, so that readiness is not confused with complete coverage.
12. As a maintainer, I want upstream version and license metadata, so that installed builds remain traceable.
13. As a developer, I want change notifications through the same service, so that later UI refresh does not need another watcher.
14. As a tester, I want a minimal native verification window, so that the compiled bridge can be exercised from the actual client.

## Implementation Decisions

- 新增客户端引擎适配服务和薄 Rust C ABI；使用公开 Engine/Query 能力，独立版本固定和许可证告知，不复制评分或索引格式。
- 公开契约覆盖结构化请求、请求标识、结果、明确错误、索引状态与变更通知；明确编码、结果释放与引擎生命周期责任。
- 普通输入和高级查询语义分开；基本模式的冒号、空格、引号和换行保持名称数据含义。
- 所有缓存、依赖与测试数据项目内隔离；真实 Engine 无 root 选项，不把 home、数据目录或搜索范围冒充扫描限制。
- 先用受控上游查询样本验证，再在经证明受限的策略或专用环境中启动真实 Engine；未验证的路径不报告通过。
- 最小原生窗口仅服务验证，不扩展为完整 alpha；默认名称/内容索引行为保留，其资源成本由后续门禁测量。

## Testing Decisions

- 从 Swift 侧公开服务验证合法/非法请求、空值、UTF-8 和真实结果；测试输出而非 Rust 内部布局。
- 重复查询与释放观测资源增长，验证错误传播与 panic 边界，避免只测试序列化函数的实现镜像。
- 参考上游 huge-limit、follower 与 Unicode 测试；仓库尚无现成客户端接缝，此服务是统一主接缝。
- 验收：可复现编译和原生调用证据、契约说明、独立索引边界、无用户磁盘静默扫描；Searcher 通过不得代替 Engine 通过。

## Out of Scope

- 全局排序/分页的完整算法适配、完整 UI、helper 切换、自研搜索内核。

## Further Notes

- 总规格：Part of #1。
- 阻塞依赖：无。
- Spec ID：SPEC-01。
- 阶段：M1。
- 依据已确认选择：Q1、Q9、Q21、Q22、Q23。
- 前置规格：无。
- 适配路线来自 ADR-0004；失败时报告根因，再单独提出 helper 代价。

