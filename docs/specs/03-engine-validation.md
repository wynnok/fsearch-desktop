# [SPEC-03] M1：真实 Engine 生命周期、权限与资源验证

## Problem Statement

原生客户端常驻、授权变化和默认内容索引会影响覆盖与资源。仅编译桥接或跑合成查询不能证明实际应用生命周期和 macOS 权限正确。

## Solution

在专用验证环境中通过真实 Engine 和最小原生应用测量索引、退出恢复、重复实例、权限变化及后台资源，并明确每项已验证或未验证。

## User Stories

1. As a user, I want indexing to continue after closing the window, so that reopening preserves freshness.
2. As a user, I want quitting to end my client, so that I control its background work.
3. As a user, I want index recovery on restart, so that every launch does not start from nothing.
4. As a user, I want duplicate launches handled coherently, so that two clients do not corrupt the same index.
5. As a CLI user, I want my existing index preserved, so that desktop-client testing does not alter it.
6. As a user, I want permission restrictions distinguished from no matches, so that missing access is understandable.
7. As a user, I want granting access to change coverage after rechecking, so that protected files can become searchable.
8. As a user, I want revoking access handled honestly, so that the client does not retain a false coverage claim.
9. As a user, I want cloud placeholders left undownloaded during indexing, so that background work does not fetch my cloud files.
10. As a user, I want default text-index activity explained, so that name-only UI does not conceal background reads.
11. As a maintainer, I want initial and idle resource measurements, so that keeping upstream defaults is an informed choice.
12. As a maintainer, I want file-change and restart evidence, so that freshness is not assumed from API names.
13. As a tester, I want signed-app permission checks, so that terminal permissions are not mistaken for application permissions.
14. As a tester, I want unavailable credentials or hardware recorded, so that incomplete validation is not marked successful.

## Implementation Decisions

- 验证真实 Engine、客户端独立数据目录、关闭窗口/完全退出、保存与再启动恢复、同目录重复实例。
- 保留上游默认名称与内容索引机制，记录初建、峰值内存、索引体积、空闲 CPU 及后台资源成本。
- 在实际应用授权主体下验证跳过、允许、撤销与重启；状态字段不替代受保护位置的真实结果。
- Engine 无 root 参数，测试限制策略先证明或使用专用环境；不静默扫描真实用户磁盘。
- 签名身份、macOS 13 和测试设备是外部条件；缺失时继续独立开发验证，但相应门禁保持未验证。
- 资源不合格时优先提出上游控制选项；不未经决定拆复制内容索引实现，不擅自切换 helper。

## Testing Decisions

- 主接缝检查状态、搜索结果与变更通知；专用原生窗口执行关闭/退出/重开及目录增删改冒烟。
- 覆盖受保护目录授权前后、撤销、独立 CLI 共存、占位文件不物化、重复实例和索引格式恢复。
- 测量上游默认机制的真实成本，分开合成查询、真实初建和 idle 结果，不用 top-k 基准替代。
- 参考上游 follower、目录删除和挂载点测试；当前仓库没有生产 TCC 或生命周期先例。
- 交付逐项结果报告、设备/版本/命令与资源记录；缺少正式签名证据不标记权限门禁通过。

## Out of Scope

- 自动开机启动、外接盘扩展、杀掉外部 CLI 进程、修改系统隐私设置、正式公众发布。

## Further Notes

- 总规格：Part of #1。
- 阻塞依赖：Blocked by: #2、#4。
- Spec ID：SPEC-03。
- 阶段：M1。
- 依据已确认选择：Q5、Q9、Q11、Q17、Q19、Q21、Q22、Q23。
- 前置规格：SPEC-01、SPEC-04。
- 本规格依赖最小应用产物，不依赖完整 alpha 或正式 Release；签名验证在可用条件下进行。

