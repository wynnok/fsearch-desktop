# Fsearch Desktop 规格索引

基于四轮设计访谈的 23 项已确认选择，已发布 **1 个总规格 + 13 个子规格，共 217 条用户故事**。

- [GitHub 总规格 #1](https://github.com/wynnok/fsearch-desktop/issues/1) 为执行总入口。
- 所有 Issues 均标为 `ready-for-agent`，13 个子规格有原生父子关系，前置依赖采用原生 issue dependencies。
- 首个无阻塞子规格是 [SPEC-01 / #2](https://github.com/wynnok/fsearch-desktop/issues/2)；总规格只聚合，不作为单体实现任务。
- 需求执行状态以 GitHub Issues 为准；本地文件保留规格副本，修改时同步正文与依赖，避免出现两个不同任务入口。
- 当前没有开始实现、生成安装包或配置定时升级；本次授权为规格拆分和发布。

## 规格与执行依赖

| Spec | 阶段 | 本地规格 | GitHub Issue | 前置 Issues |
| --- | --- | --- | --- | --- |
| SPEC-00 | 总规格 | [Fsearch Desktop 产品总规格与阶段验收](./00-product.md) | [#1](https://github.com/wynnok/fsearch-desktop/issues/1) | 无 |
| SPEC-01 | M1 | [M1：可升级 Fsearch 集成与 Swift 引擎服务契约](./01-engine-service.md) | [#2](https://github.com/wynnok/fsearch-desktop/issues/2) | 无 |
| SPEC-02 | M1 | [M1：完整结果快照、全局排序与分页](./02-results-snapshots.md) | [#3](https://github.com/wynnok/fsearch-desktop/issues/3) | [#2](https://github.com/wynnok/fsearch-desktop/issues/2) |
| SPEC-03 | M1 | [M1：真实 Engine 生命周期、权限与资源验证](./03-engine-validation.md) | [#5](https://github.com/wynnok/fsearch-desktop/issues/5) | [#2](https://github.com/wynnok/fsearch-desktop/issues/2)、[#4](https://github.com/wynnok/fsearch-desktop/issues/4) |
| SPEC-04 | M1 | [M1：双架构构建、链接与最低系统验证](./04-dual-architecture.md) | [#4](https://github.com/wynnok/fsearch-desktop/issues/4) | [#2](https://github.com/wynnok/fsearch-desktop/issues/2) |
| SPEC-05 | M2 / v0.1 | [v0.1：原生搜索配置与结果列表交互](./05-native-search-ui.md) | [#6](https://github.com/wynnok/fsearch-desktop/issues/6) | [#3](https://github.com/wynnok/fsearch-desktop/issues/3)、[#5](https://github.com/wynnok/fsearch-desktop/issues/5)、[#4](https://github.com/wynnok/fsearch-desktop/issues/4) |
| SPEC-06 | M2 / v0.1 | [v0.1：检查器、Quick Look 与 Finder 路径导航](./06-inspector-actions.md) | [#7](https://github.com/wynnok/fsearch-desktop/issues/7) | [#6](https://github.com/wynnok/fsearch-desktop/issues/6) |
| SPEC-07 | M2 / v0.1 | [v0.1：权限引导、索引状态与窗口生命周期](./07-permissions-lifecycle.md) | [#8](https://github.com/wynnok/fsearch-desktop/issues/8) | [#5](https://github.com/wynnok/fsearch-desktop/issues/5)、[#6](https://github.com/wynnok/fsearch-desktop/issues/6) |
| SPEC-08 | M2 / v0.1 | [v0.1：本地设置、主动诊断导出与手动更新入口](./08-data-updates.md) | [#9](https://github.com/wynnok/fsearch-desktop/issues/9) | [#6](https://github.com/wynnok/fsearch-desktop/issues/6) |
| SPEC-09 | M2 / v0.1 | [DevOps：可安装开发 DMG 与持续集成](./09-development-packages.md) | [#10](https://github.com/wynnok/fsearch-desktop/issues/10) | [#4](https://github.com/wynnok/fsearch-desktop/issues/4)、[#6](https://github.com/wynnok/fsearch-desktop/issues/6)、[#7](https://github.com/wynnok/fsearch-desktop/issues/7)、[#8](https://github.com/wynnok/fsearch-desktop/issues/8)、[#9](https://github.com/wynnok/fsearch-desktop/issues/9) |
| SPEC-10 | M4 / 公众发行门禁 | [Release：签名公证、版本 tag 与正式安装验收](./10-public-release.md) | [#13](https://github.com/wynnok/fsearch-desktop/issues/13) | [#10](https://github.com/wynnok/fsearch-desktop/issues/10)、[#12](https://github.com/wynnok/fsearch-desktop/issues/12) |
| SPEC-11 | M1 基础 / 持续维护 | [Maintenance：每日上游检测与升级 PR 兼容性门禁](./11-upstream-upgrades.md) | [#11](https://github.com/wynnok/fsearch-desktop/issues/11) | [#2](https://github.com/wynnok/fsearch-desktop/issues/2)、[#3](https://github.com/wynnok/fsearch-desktop/issues/3)、[#5](https://github.com/wynnok/fsearch-desktop/issues/5)、[#4](https://github.com/wynnok/fsearch-desktop/issues/4) |
| SPEC-12 | M2 / alpha 完整验收 | [v0.1：端到端验收、用户文档与已知限制](./12-alpha-acceptance.md) | [#12](https://github.com/wynnok/fsearch-desktop/issues/12) | [#6](https://github.com/wynnok/fsearch-desktop/issues/6)、[#7](https://github.com/wynnok/fsearch-desktop/issues/7)、[#8](https://github.com/wynnok/fsearch-desktop/issues/8)、[#9](https://github.com/wynnok/fsearch-desktop/issues/9)、[#10](https://github.com/wynnok/fsearch-desktop/issues/10)、[#11](https://github.com/wynnok/fsearch-desktop/issues/11) |
| SPEC-13 | M3 / v0.2 核心已定范围 | [v0.2：受支持文本内容搜索与匹配片段](./13-text-content-search.md) | [#14](https://github.com/wynnok/fsearch-desktop/issues/14) | [#12](https://github.com/wynnok/fsearch-desktop/issues/12) |

M1：引擎服务 → 完整结果；双架构最小应用与真实 Engine 生命周期/权限验证形成门禁。门禁通过后进行 v0.1 界面、文件动作、状态与本地数据，再产出开发安装包和 alpha 验收。上游升级检查在既有服务和构建门禁上独立推进；公众发行在开发包与 alpha 验收之后追加签名公证门禁。v0.2 内容核心在 alpha 基础上实现，不扩大首版。

## 已确认测试接缝

主接缝：**Swift 侧引擎服务的公开契约**，覆盖查询、筛选、快照/分页、状态与变更通知，使用真实 Fsearch 的受控样本，断言外部行为。系统文件操作、权限与安装发行用必要的原生冒烟/成品检查补充，不另建多套底层接缝。此方案已在 to-spec 核对中获得用户确认。

仓库目前没有客户端代码或既有测试框架。上游 22 项测试的历史通过记录仅作为先例，不代替这些规格的执行证据。不得把 Query/Index 合成样本测试当成真实 Engine、TCC 或 Intel 实机通过。

## 访谈选择追踪

完整选择见 [产品需求](../product/requirements.md)，M1 测试条件见 [验证计划](../engineering/validation-plan.md)。下表列负责落实各项选择的子规格；[alpha 验收 #12](https://github.com/wynnok/fsearch-desktop/issues/12) 另对全部 23 项回归。

| 选择 | 负责落实的 Issues |
| --- | --- |
| Q1 | [#2](https://github.com/wynnok/fsearch-desktop/issues/2)、[#11](https://github.com/wynnok/fsearch-desktop/issues/11) |
| Q2 | [#6](https://github.com/wynnok/fsearch-desktop/issues/6)、[#7](https://github.com/wynnok/fsearch-desktop/issues/7)、[#14](https://github.com/wynnok/fsearch-desktop/issues/14) |
| Q3 | [#6](https://github.com/wynnok/fsearch-desktop/issues/6) |
| Q4 | [#6](https://github.com/wynnok/fsearch-desktop/issues/6) |
| Q5 | [#5](https://github.com/wynnok/fsearch-desktop/issues/5)、[#8](https://github.com/wynnok/fsearch-desktop/issues/8) |
| Q6 | [#4](https://github.com/wynnok/fsearch-desktop/issues/4)、[#10](https://github.com/wynnok/fsearch-desktop/issues/10)、[#13](https://github.com/wynnok/fsearch-desktop/issues/13) |
| Q7 | [#11](https://github.com/wynnok/fsearch-desktop/issues/11) |
| Q8 | [#11](https://github.com/wynnok/fsearch-desktop/issues/11) |
| Q9 | [#2](https://github.com/wynnok/fsearch-desktop/issues/2)、[#5](https://github.com/wynnok/fsearch-desktop/issues/5)、[#8](https://github.com/wynnok/fsearch-desktop/issues/8) |
| Q10 | [#6](https://github.com/wynnok/fsearch-desktop/issues/6)、[#8](https://github.com/wynnok/fsearch-desktop/issues/8) |
| Q11 | [#5](https://github.com/wynnok/fsearch-desktop/issues/5)、[#8](https://github.com/wynnok/fsearch-desktop/issues/8) |
| Q12 | [#3](https://github.com/wynnok/fsearch-desktop/issues/3)、[#6](https://github.com/wynnok/fsearch-desktop/issues/6) |
| Q13 | [#3](https://github.com/wynnok/fsearch-desktop/issues/3)、[#7](https://github.com/wynnok/fsearch-desktop/issues/7) |
| Q14 | [#3](https://github.com/wynnok/fsearch-desktop/issues/3)、[#6](https://github.com/wynnok/fsearch-desktop/issues/6) |
| Q15 | [#6](https://github.com/wynnok/fsearch-desktop/issues/6) |
| Q16 | [#6](https://github.com/wynnok/fsearch-desktop/issues/6) |
| Q17 | [#3](https://github.com/wynnok/fsearch-desktop/issues/3)、[#5](https://github.com/wynnok/fsearch-desktop/issues/5)、[#6](https://github.com/wynnok/fsearch-desktop/issues/6)、[#8](https://github.com/wynnok/fsearch-desktop/issues/8) |
| Q18 | [#10](https://github.com/wynnok/fsearch-desktop/issues/10)、[#13](https://github.com/wynnok/fsearch-desktop/issues/13)、[#11](https://github.com/wynnok/fsearch-desktop/issues/11) |
| Q19 | [#5](https://github.com/wynnok/fsearch-desktop/issues/5)、[#4](https://github.com/wynnok/fsearch-desktop/issues/4)、[#10](https://github.com/wynnok/fsearch-desktop/issues/10)、[#13](https://github.com/wynnok/fsearch-desktop/issues/13) |
| Q20 | [#9](https://github.com/wynnok/fsearch-desktop/issues/9)、[#13](https://github.com/wynnok/fsearch-desktop/issues/13) |
| Q21 | [#2](https://github.com/wynnok/fsearch-desktop/issues/2)、[#5](https://github.com/wynnok/fsearch-desktop/issues/5)、[#7](https://github.com/wynnok/fsearch-desktop/issues/7)、[#9](https://github.com/wynnok/fsearch-desktop/issues/9)、[#14](https://github.com/wynnok/fsearch-desktop/issues/14) |
| Q22 | [#2](https://github.com/wynnok/fsearch-desktop/issues/2)、[#5](https://github.com/wynnok/fsearch-desktop/issues/5)、[#8](https://github.com/wynnok/fsearch-desktop/issues/8)、[#11](https://github.com/wynnok/fsearch-desktop/issues/11)、[#14](https://github.com/wynnok/fsearch-desktop/issues/14) |
| Q23 | [#2](https://github.com/wynnok/fsearch-desktop/issues/2)、[#3](https://github.com/wynnok/fsearch-desktop/issues/3)、[#5](https://github.com/wynnok/fsearch-desktop/issues/5)、[#4](https://github.com/wynnok/fsearch-desktop/issues/4)、[#11](https://github.com/wynnok/fsearch-desktop/issues/11) |

## 规格约定

每个规格含 Problem Statement、Solution、长编号 User Stories、Implementation Decisions、Testing Decisions、Out of Scope 和 Further Notes。实施决策描述模块和契约，不固定源文件路径或代码片段。

`ready-for-agent` 表示规格可以按依赖执行，**不是技术验证或产品实现完成**。签名身份、测试设备和专用权限环境缺失时保留对应未验证状态；失败不通过限制结果、换搜索内核或伪造性能来关闭需求。

