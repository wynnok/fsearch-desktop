# [SPEC-11] Maintenance：每日上游检测与升级 PR 兼容性门禁

## Problem Statement

用户要求客户端及时继承 Fsearch 更新，长期固定旧版本或复制核心都会让产品逐渐脱离上游。无检查的升级又可能破坏 API、索引和两架构行为。

## Solution

在仓库 CI 建立每日正式版检测，生成可审查、去重的升级 PR，运行既有兼容检查，并追踪必要临时补丁的移除条件。

## User Stories

1. As a maintainer, I want daily upstream-release checks, so that new Fsearch versions are discovered promptly.
2. As a maintainer, I want only formal releases selected, so that rolling main changes do not silently enter the client.
3. As a maintainer, I want an automatic upgrade PR, so that dependency updates are concrete and reviewable.
4. As a maintainer, I want duplicate checks to reuse existing work, so that each release does not generate repeated PRs.
5. As a maintainer, I want an exact upstream commit recorded, so that an upgrade can be reproduced.
6. As a maintainer, I want bridge compilation checks, so that API incompatibilities are found.
7. As a maintainer, I want query and snapshot regression checks, so that behavior remains correct.
8. As a maintainer, I want architecture and minimum-system checks, so that an upstream update does not drop supported Macs.
9. As a maintainer, I want index recovery compatibility recorded, so that user data can be handled honestly.
10. As a maintainer, I want resource changes measured, so that updates do not conceal background-cost regressions.
11. As a maintainer, I want temporary patches reviewed for removal, so that the client avoids a growing private fork.
12. As a maintainer, I want failed upgrades retained for review without release, so that failure does not become silent deployment.
13. As a maintainer, I want human merge and tag decisions, so that public releases remain explicit.
14. As a user, I want the upgraded engine delivered with a client version, so that I can know which behavior I installed.

## Implementation Decisions

- 每日检测上游正式 Release/tag，固定候选 commit 并更新依赖/锁定记录，不直接追踪滚动 main 作为发行依赖。
- 未更新则保持无变更；发现同一候选时复用已存在升级 PR，不重复创建。暂时网络失败保留已用版本并可重试。
- 兼容门禁复用公开服务的真实查询、快照、生命周期、架构与资源验证；记录索引格式变化，不承诺上游迁移稳定。
- 临时补丁每项有来源、测试和移除条件，升级时逐项评估；功能扩展优先贡献上游。
- 升级 PR 检查通过后由维护者合并，版本 tag 才触发正式发行；检测作业不自动合并或发布 stable。
- 实现于项目仓库 CI，不创建无关 Codex 自动化；每版客户端固定引擎，保留失败候选与差异记录。

## Testing Decisions

- 对检测作业的公开输入/输出和版本选择使用受控发行列表，验证无更新、新更新、预发布、重复候选、网络失败及已存在 PR。
- 实际更新候选复用同一 Swift 引擎服务回归，并核验编译、索引恢复、两架构与资源证据。
- 模拟兼容失败必须阻止自动进入正式发布；临时补丁移除由对应回归证明而非只比较文件数。
- 参考上游现有正式 tag/Release 与客户端依赖固定决策；仓库此前没有升级机器人测试。
- 验收：真实仓库检测执行、候选 PR/无重复证据、可重跑兼容检查与维护者审核流程；本任务不能把检查配置当全部升级实测通过。

## Out of Scope

- 自有搜索内核、长期功能 fork、自动合并、无审核稳定发行、用户应用无感安装更新。

## Further Notes

- 总规格：Part of #1。
- 阻塞依赖：Blocked by: #2、#3、#5、#4。
- Spec ID：SPEC-11。
- 阶段：M1 基础 / 持续维护。
- 依据已确认选择：Q1、Q7、Q8、Q18、Q22、Q23。
- 前置规格：SPEC-01、SPEC-02、SPEC-03、SPEC-04。
- 为检测器新增网络依赖最小化；没有新正式版也能以受控列表验证选择逻辑，不伪造上游发行。

