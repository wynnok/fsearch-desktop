# Fsearch Desktop 执行 Tickets

33 张纵向切片已由用户确认并发布，覆盖现有 13 个子 Spec，包含 141 项验收条件和 55 条原生阻塞边。

- 所有 Ticket 均标记 `ready-for-agent`，归属对应 Spec 的原生子 Issue。
- [T01 / #15](https://github.com/wynnok/fsearch-desktop/issues/15) 是当前唯一无阻塞执行票；工作从其开始，随后只领取阻塞项都已完成的票。
- 执行状态以 GitHub 为准，本地保存正文副本；父 Spec 的标题、正文、标签和状态没有被本次拆分编辑或关闭。
- Spec 的整体依赖保留，Ticket 的前置只指向真正需要的能力，不把自身父 Spec 关闭设为前置。跨 Spec 验收关系写在各票 Parent 中，不能仅凭直接子票计数断言 Spec 全部满足。
- 本文件是拆分时的规划记录。实现进展与逐票证据见 [实施报告](../implementation/)；执行状态以 GitHub 为准，外部门禁未解除的票保持 OPEN。

## T 编号与 GitHub 编号

| Ticket | 本地正文 | GitHub Issue | 主 Spec | 原生阻塞 Tickets |
| --- | --- | --- | --- | --- |
| T01 | [最小原生窗口完成一次真实 Fsearch 样本查询](./01-native-query.md) | [#15](https://github.com/wynnok/fsearch-desktop/issues/15) | [#2](https://github.com/wynnok/fsearch-desktop/issues/2) | 无 |
| T02 | [普通名称、Unicode 与错误查询可安全往返](./02-query-safety.md) | [#16](https://github.com/wynnok/fsearch-desktop/issues/16) | [#2](https://github.com/wynnok/fsearch-desktop/issues/2) | [#15](https://github.com/wynnok/fsearch-desktop/issues/15) |
| T03 | [完整名称快照支持自然排序和跨页浏览](./03-name-snapshots.md) | [#17](https://github.com/wynnok/fsearch-desktop/issues/17) | [#3](https://github.com/wynnok/fsearch-desktop/issues/3) | [#15](https://github.com/wynnok/fsearch-desktop/issues/15) |
| T04 | [按索引大小与修改时间全局排序](./04-size-time-sort.md) | [#18](https://github.com/wynnok/fsearch-desktop/issues/18) | [#3](https://github.com/wynnok/fsearch-desktop/issues/3) | [#17](https://github.com/wynnok/fsearch-desktop/issues/17) |
| T05 | [长查询和排序期间输入仍可用](./05-query-responsiveness.md) | [#19](https://github.com/wynnok/fsearch-desktop/issues/19) | [#3](https://github.com/wynnok/fsearch-desktop/issues/3) | [#17](https://github.com/wynnok/fsearch-desktop/issues/17) |
| T06 | [最小查询应用在两芯片和最低系统运行](./06-dual-architecture.md) | [#20](https://github.com/wynnok/fsearch-desktop/issues/20) | [#4](https://github.com/wynnok/fsearch-desktop/issues/4) | [#15](https://github.com/wynnok/fsearch-desktop/issues/15) |
| T07 | [真实 Engine 完成独立索引、通知与退出恢复](./07-engine-recovery.md) | [#21](https://github.com/wynnok/fsearch-desktop/issues/21) | [#2](https://github.com/wynnok/fsearch-desktop/issues/2) | [#15](https://github.com/wynnok/fsearch-desktop/issues/15) |
| T08 | [实际签名应用验证授权前后的索引覆盖](./08-permission-validation.md) | [#22](https://github.com/wynnok/fsearch-desktop/issues/22) | [#5](https://github.com/wynnok/fsearch-desktop/issues/5) | [#21](https://github.com/wynnok/fsearch-desktop/issues/21) |
| T09 | [默认索引的初建与空闲资源可测量](./09-index-resources.md) | [#23](https://github.com/wynnok/fsearch-desktop/issues/23) | [#5](https://github.com/wynnok/fsearch-desktop/issues/5) | [#21](https://github.com/wynnok/fsearch-desktop/issues/21) |
| T10 | [原生主窗口提供名称模式和真实结果交互](./10-main-search-window.md) | [#24](https://github.com/wynnok/fsearch-desktop/issues/24) | [#6](https://github.com/wynnok/fsearch-desktop/issues/6) | [#16](https://github.com/wynnok/fsearch-desktop/issues/16)、[#18](https://github.com/wynnok/fsearch-desktop/issues/18)、[#19](https://github.com/wynnok/fsearch-desktop/issues/19)、[#20](https://github.com/wynnok/fsearch-desktop/issues/20)、[#22](https://github.com/wynnok/fsearch-desktop/issues/22)、[#23](https://github.com/wynnok/fsearch-desktop/issues/23) |
| T11 | [搜索范围与隐藏项可直观切换](./11-scope-hidden-items.md) | [#25](https://github.com/wynnok/fsearch-desktop/issues/25) | [#6](https://github.com/wynnok/fsearch-desktop/issues/6) | [#24](https://github.com/wynnok/fsearch-desktop/issues/24) |
| T12 | [类型、扩展名、大小和时间筛选可组合](./12-attribute-filters.md) | [#26](https://github.com/wynnok/fsearch-desktop/issues/26) | [#6](https://github.com/wynnok/fsearch-desktop/issues/6) | [#24](https://github.com/wynnok/fsearch-desktop/issues/24) |
| T13 | [文件变化自动刷新并保持选择](./13-live-refresh.md) | [#27](https://github.com/wynnok/fsearch-desktop/issues/27) | [#6](https://github.com/wynnok/fsearch-desktop/issues/6) | [#24](https://github.com/wynnok/fsearch-desktop/issues/24) |
| T14 | [可跳过权限引导与清楚的索引状态](./14-permission-onboarding.md) | [#28](https://github.com/wynnok/fsearch-desktop/issues/28) | [#8](https://github.com/wynnok/fsearch-desktop/issues/8) | [#24](https://github.com/wynnok/fsearch-desktop/issues/24) |
| T15 | [检查器联动当前选择显示真实文件信息](./15-file-inspector.md) | [#29](https://github.com/wynnok/fsearch-desktop/issues/29) | [#7](https://github.com/wynnok/fsearch-desktop/issues/7) | [#24](https://github.com/wynnok/fsearch-desktop/issues/24) |
| T16 | [打开文件、Finder 显示与逐级路径导航](./16-finder-path-actions.md) | [#30](https://github.com/wynnok/fsearch-desktop/issues/30) | [#7](https://github.com/wynnok/fsearch-desktop/issues/7) | [#24](https://github.com/wynnok/fsearch-desktop/issues/24) |
| T17 | [空格 Quick Look 可预览所选文件](./17-quick-look.md) | [#31](https://github.com/wynnok/fsearch-desktop/issues/31) | [#7](https://github.com/wynnok/fsearch-desktop/issues/7) | [#24](https://github.com/wynnok/fsearch-desktop/issues/24) |
| T18 | [主窗口关闭、重开与退出符合约定](./18-window-lifecycle.md) | [#32](https://github.com/wynnok/fsearch-desktop/issues/32) | [#8](https://github.com/wynnok/fsearch-desktop/issues/8) | [#24](https://github.com/wynnok/fsearch-desktop/issues/24) |
| T19 | [本地设置保留且查询历史默认不落盘](./19-local-settings.md) | [#33](https://github.com/wynnok/fsearch-desktop/issues/33) | [#9](https://github.com/wynnok/fsearch-desktop/issues/9) | [#32](https://github.com/wynnok/fsearch-desktop/issues/32) |
| T20 | [主动诊断导出默认剔除路径和正文](./20-diagnostic-export.md) | [#34](https://github.com/wynnok/fsearch-desktop/issues/34) | [#9](https://github.com/wynnok/fsearch-desktop/issues/9) | [#28](https://github.com/wynnok/fsearch-desktop/issues/28) |
| T21 | [显示客户端/引擎版本并提供手动更新入口](./21-manual-update.md) | [#35](https://github.com/wynnok/fsearch-desktop/issues/35) | [#9](https://github.com/wynnok/fsearch-desktop/issues/9) | [#24](https://github.com/wynnok/fsearch-desktop/issues/24) |
| T22 | [两架构开发 DMG 可经 push/PR 下载验证](./22-development-dmg.md) | [#36](https://github.com/wynnok/fsearch-desktop/issues/36) | [#10](https://github.com/wynnok/fsearch-desktop/issues/10) | [#20](https://github.com/wynnok/fsearch-desktop/issues/20) |
| T23 | [每日检测上游正式版并给出可追溯结果](./23-upstream-detection.md) | [#37](https://github.com/wynnok/fsearch-desktop/issues/37) | [#11](https://github.com/wynnok/fsearch-desktop/issues/11) | [#15](https://github.com/wynnok/fsearch-desktop/issues/15) |
| T24 | [新正式版生成去重的升级 PR 并跑兼容检查](./24-upgrade-pr.md) | [#38](https://github.com/wynnok/fsearch-desktop/issues/38) | [#11](https://github.com/wynnok/fsearch-desktop/issues/11) | [#16](https://github.com/wynnok/fsearch-desktop/issues/16)、[#18](https://github.com/wynnok/fsearch-desktop/issues/18)、[#19](https://github.com/wynnok/fsearch-desktop/issues/19)、[#22](https://github.com/wynnok/fsearch-desktop/issues/22)、[#23](https://github.com/wynnok/fsearch-desktop/issues/23)、[#36](https://github.com/wynnok/fsearch-desktop/issues/36)、[#37](https://github.com/wynnok/fsearch-desktop/issues/37) |
| T25 | [验收搜索到排序刷新的完整旅程并产出指南](./25-search-journey.md) | [#39](https://github.com/wynnok/fsearch-desktop/issues/39) | [#12](https://github.com/wynnok/fsearch-desktop/issues/12) | [#25](https://github.com/wynnok/fsearch-desktop/issues/25)、[#26](https://github.com/wynnok/fsearch-desktop/issues/26)、[#27](https://github.com/wynnok/fsearch-desktop/issues/27)、[#28](https://github.com/wynnok/fsearch-desktop/issues/28) |
| T26 | [验收文件操作和本地数据旅程并产出指南](./26-file-data-journey.md) | [#40](https://github.com/wynnok/fsearch-desktop/issues/40) | [#12](https://github.com/wynnok/fsearch-desktop/issues/12) | [#29](https://github.com/wynnok/fsearch-desktop/issues/29)、[#30](https://github.com/wynnok/fsearch-desktop/issues/30)、[#31](https://github.com/wynnok/fsearch-desktop/issues/31)、[#33](https://github.com/wynnok/fsearch-desktop/issues/33)、[#34](https://github.com/wynnok/fsearch-desktop/issues/34)、[#35](https://github.com/wynnok/fsearch-desktop/issues/35) |
| T27 | [从开发 DMG 完成两芯片 alpha 安装验收](./27-alpha-installation.md) | [#41](https://github.com/wynnok/fsearch-desktop/issues/41) | [#12](https://github.com/wynnok/fsearch-desktop/issues/12) | [#38](https://github.com/wynnok/fsearch-desktop/issues/38)、[#39](https://github.com/wynnok/fsearch-desktop/issues/39)、[#40](https://github.com/wynnok/fsearch-desktop/issues/40) |
| T28 | [开发安装包可完成签名、公证和最终校验](./28-signing-notarization.md) | [#42](https://github.com/wynnok/fsearch-desktop/issues/42) | [#13](https://github.com/wynnok/fsearch-desktop/issues/13) | [#36](https://github.com/wynnok/fsearch-desktop/issues/36) |
| T29 | [已批准版本 tag 发布可下载正式 Release](./29-tag-release.md) | [#43](https://github.com/wynnok/fsearch-desktop/issues/43) | [#13](https://github.com/wynnok/fsearch-desktop/issues/13) | [#41](https://github.com/wynnok/fsearch-desktop/issues/41)、[#42](https://github.com/wynnok/fsearch-desktop/issues/42) |
| T30 | [普通文本查询显示按文件分组的匹配行](./30-literal-content.md) | [#44](https://github.com/wynnok/fsearch-desktop/issues/44) | [#14](https://github.com/wynnok/fsearch-desktop/issues/14) | [#41](https://github.com/wynnok/fsearch-desktop/issues/41) |
| T31 | [内容范围、属性、正则与大小写选项可用](./31-content-options.md) | [#45](https://github.com/wynnok/fsearch-desktop/issues/45) | [#14](https://github.com/wynnok/fsearch-desktop/issues/14) | [#44](https://github.com/wynnok/fsearch-desktop/issues/44) |
| T32 | [内容预算续查和 Unicode 高亮保持正确](./32-content-pagination.md) | [#46](https://github.com/wynnok/fsearch-desktop/issues/46) | [#14](https://github.com/wynnok/fsearch-desktop/issues/14) | [#44](https://github.com/wynnok/fsearch-desktop/issues/44) |
| T33 | [验收 v0.2 文本旅程与边界说明](./33-content-acceptance.md) | [#47](https://github.com/wynnok/fsearch-desktop/issues/47) | [#14](https://github.com/wynnok/fsearch-desktop/issues/14) | [#45](https://github.com/wynnok/fsearch-desktop/issues/45)、[#46](https://github.com/wynnok/fsearch-desktop/issues/46) |

## 阶段与可并行路径

- T01–T09 建立最小原生查询及 M1 证据；T10 等待实际的契约、完整排序、异步、架构、权限与资源门禁。
- T11–T21 提供完整 alpha 的搜索、文件动作、状态与本地数据行为，相关功能每票都可演示/验证。
- T22 在双架构最小应用具备后即可建立开发 DMG 下载链路，不等待所有 UI 功能；早期包明确是验证/开发包。
- T23 可先检测上游正式版；T24 复用真实兼容与构建门禁生成升级 PR，不自动合并或发 stable。
- T25/T26 验收用户旅程并同步说明，T27 在开发包与升级路径上完成 alpha 安装验收。
- T28 可先验证签名公证链路，T29 同时等待 alpha 与签名门禁，再由已批准 tag 正式发行。
- T30–T33 在 alpha 后提供已确认范围内的 v0.2 文本内容搜索，不添加 PDF/Office/OCR 或未确认扩展。

## Spec 覆盖

| 原 Spec | 主子票及交叉验收票 |
| --- | --- |
| [#2](https://github.com/wynnok/fsearch-desktop/issues/2) | [T01](https://github.com/wynnok/fsearch-desktop/issues/15)、[T02](https://github.com/wynnok/fsearch-desktop/issues/16)、[T07](https://github.com/wynnok/fsearch-desktop/issues/21) |
| [#3](https://github.com/wynnok/fsearch-desktop/issues/3) | [T03](https://github.com/wynnok/fsearch-desktop/issues/17)、[T04](https://github.com/wynnok/fsearch-desktop/issues/18)、[T05](https://github.com/wynnok/fsearch-desktop/issues/19)、[T13](https://github.com/wynnok/fsearch-desktop/issues/27) |
| [#4](https://github.com/wynnok/fsearch-desktop/issues/4) | [T06](https://github.com/wynnok/fsearch-desktop/issues/20)、[T22](https://github.com/wynnok/fsearch-desktop/issues/36) |
| [#5](https://github.com/wynnok/fsearch-desktop/issues/5) | [T07](https://github.com/wynnok/fsearch-desktop/issues/21)、[T08](https://github.com/wynnok/fsearch-desktop/issues/22)、[T09](https://github.com/wynnok/fsearch-desktop/issues/23) |
| [#6](https://github.com/wynnok/fsearch-desktop/issues/6) | [T10](https://github.com/wynnok/fsearch-desktop/issues/24)、[T11](https://github.com/wynnok/fsearch-desktop/issues/25)、[T12](https://github.com/wynnok/fsearch-desktop/issues/26)、[T13](https://github.com/wynnok/fsearch-desktop/issues/27) |
| [#7](https://github.com/wynnok/fsearch-desktop/issues/7) | [T15](https://github.com/wynnok/fsearch-desktop/issues/29)、[T16](https://github.com/wynnok/fsearch-desktop/issues/30)、[T17](https://github.com/wynnok/fsearch-desktop/issues/31) |
| [#8](https://github.com/wynnok/fsearch-desktop/issues/8) | [T14](https://github.com/wynnok/fsearch-desktop/issues/28)、[T18](https://github.com/wynnok/fsearch-desktop/issues/32) |
| [#9](https://github.com/wynnok/fsearch-desktop/issues/9) | [T19](https://github.com/wynnok/fsearch-desktop/issues/33)、[T20](https://github.com/wynnok/fsearch-desktop/issues/34)、[T21](https://github.com/wynnok/fsearch-desktop/issues/35) |
| [#10](https://github.com/wynnok/fsearch-desktop/issues/10) | [T22](https://github.com/wynnok/fsearch-desktop/issues/36)、[T27](https://github.com/wynnok/fsearch-desktop/issues/41) |
| [#11](https://github.com/wynnok/fsearch-desktop/issues/11) | [T23](https://github.com/wynnok/fsearch-desktop/issues/37)、[T24](https://github.com/wynnok/fsearch-desktop/issues/38) |
| [#12](https://github.com/wynnok/fsearch-desktop/issues/12) | [T25](https://github.com/wynnok/fsearch-desktop/issues/39)、[T26](https://github.com/wynnok/fsearch-desktop/issues/40)、[T27](https://github.com/wynnok/fsearch-desktop/issues/41) |
| [#13](https://github.com/wynnok/fsearch-desktop/issues/13) | [T28](https://github.com/wynnok/fsearch-desktop/issues/42)、[T29](https://github.com/wynnok/fsearch-desktop/issues/43) |
| [#14](https://github.com/wynnok/fsearch-desktop/issues/14) | [T30](https://github.com/wynnok/fsearch-desktop/issues/44)、[T31](https://github.com/wynnok/fsearch-desktop/issues/45)、[T32](https://github.com/wynnok/fsearch-desktop/issues/46)、[T33](https://github.com/wynnok/fsearch-desktop/issues/47) |

详细用户批准的拆分记录见 [提案](proposal.md)，源规格见 [Spec 索引](../specs/README.md)。主测试接缝沿用已确认的 Swift 引擎服务；系统动作、权限、安装发行以必要原生/成品检查补充。

签名身份、Intel 实机、最低系统及专用权限环境缺失时，对应门禁保持未验证；其他无真实依赖的切片可推进。ready-for-agent 不是测试通过或产品完成。

## 2026-10-14 全票复核

GitHub 逐票核对：7 CLOSED、26 OPEN；本地实现不等于所有验收完成。源 Issue 正文与本地票据、实施报告、代码和回归逐项交叉检查。本次没有修改外部 Issue 状态。

| Ticket | 实施证据 | 当前验收结论或剩余项 |
| --- | --- | --- |
| T01 | [报告](../implementation/T01.md) | CLOSED，最小真实样本查询 |
| T02 | [报告](../implementation/T02.md) | CLOSED，Unicode、字面输入、错误与 panic 恢复 |
| T03 | [报告](../implementation/T03.md) | CLOSED，完整快照、自然排序、分页 |
| T04 | [报告](../implementation/T04.md) | CLOSED，索引大小与修改时间全局排序 |
| T05 | [报告](../implementation/T05.md) | CLOSED，异步、取消、过期响应 |
| T06 | [报告](../implementation/T06.md) | 两架构构建通过；Intel/macOS 13 实机未验证 |
| T07 | [报告](../implementation/T07.md) | CLOSED，受限真实 Engine、独立索引、通知及恢复 |
| T08 | [报告](../implementation/T08.md) | 权限探测链路已有；实际签名主体与 TCC 专用环境缺失 |
| T09 | [报告](../implementation/T09.md) | CLOSED，受控真实资源测量；不代表个人磁盘成本 |
| T10 | [报告](../implementation/T10.md) | 主窗口及样本原生旅程通过；M1 外部门禁未解除 |
| T11 | [Wave 3](../implementation/Wave3.md) | 范围/隐藏项已实现；个人磁盘覆盖未交付 |
| T12 | [Wave 3](../implementation/Wave3.md) | 组合属性筛选及公开服务回归通过；保留前置门禁 |
| T13 | [Wave 3](../implementation/Wave3.md) | 变化刷新、选择保持与晚返回回归；真实用户磁盘未验收 |
| T14 | [Wave 3](../implementation/Wave3.md) | 引导跳过与索引状态已实现；真实授权/撤销未验证 |
| T15 | [Wave 3](../implementation/Wave3.md) | 检查器、实际属性与过期详情回归通过；保留前置门禁 |
| T16 | [Wave 3](../implementation/Wave3.md) | 系统动作目标通过；Finder 可见选中状态待人工观察 |
| T17 | [Wave 3](../implementation/Wave3.md) | Quick Look 原生样本通过；保留前置门禁 |
| T18 | [Wave 3](../implementation/Wave3.md) | 关窗重开/退出样本通过；真实后台覆盖保留门禁 |
| T19 | [报告](../implementation/T19.md) | 偏好持久化与不保存查询回归；真正退出重启人工旅程待验 |
| T20 | [报告](../implementation/T20.md) | 诊断脱敏成品通过；保存面板完整交互待人工验收 |
| T21 | [Wave 3](../implementation/Wave3.md) | 版本/更新入口与响应回归；真实 Release 下载尚不存在 |
| T22 | [报告](../implementation/T22.md) | 本机 Universal DMG/安装通过；实际 CI 产物下载未验证 |
| T23 | [报告](../implementation/T23.md) | 每日检测及受控 fixtures 通过；实际 Actions 未验证 |
| T24 | [报告](../implementation/T24.md) | 升级 PR 实施及失败重试回归通过；真实云端候选路径未验证 |
| T25 | [Wave 4](../implementation/Wave4.md) | 样本搜索旅程与指南已有；真实覆盖及完整 alpha 门禁未通过 |
| T26 | [Wave 4](../implementation/Wave4.md) | 样本文件/数据旅程已有；Finder/保存面板/重启人工缺口保留 |
| T27 | [报告](../implementation/T27.md) | 完整 alpha 尚不可交付；实机、权限、CI 下载缺证据 |
| T28 | [报告](../implementation/T28.md) | 签名公证链路和失败门禁已有；缺开发者凭据，真实链路延期 |
| T29 | [报告](../implementation/T29.md) | tag 发行门禁已有；无合格批准/签名/实际 Release，不发行 |
| T30 | [报告](../implementation/T30.md) | 受控真实 Engine 内容入口已有；普通启动仍仅样本名称搜索 |
| T31 | [报告](../implementation/T31.md) | 受控内容范围、筛选、正则、大小写通过；保留 alpha 前置门禁 |
| T32 | [报告](../implementation/T32.md) | 预算、cursor 续查与 Unicode 高亮通过；保留 alpha 前置门禁 |
| T33 | [报告](../implementation/T33.md) | 受控正文原生旅程与边界说明已有；个人磁盘/完整发行未验收 |

本次用户决策：先运行样本界面；个人磁盘入口另行推进。Intel、macOS 13、干净账号首次安装保留未验证；本地 ad-hoc 签名不要求开发者账号，Developer ID、公证和正式发行延后。

本次修复：真实 Engine panic 验证的 CString 生命周期；T24 既有 PR 的候选/报告/draft 刷新及已验证基线保留；升级测试与构建记录的旧 pin 硬编码；结果表列宽适配与横向滚动，避免大小/时间列不可见。复核分别检查规范和规格；默认个人磁盘入口是明确延期的产品缺口，不能以样本通过标为完成。

本机验证：Rust check、Swift 构建、完整 XCTest（服务 56 + 应用 20 = 76 项，0 失败）、两架构构建/链接及最低部署目标核对通过。现有 shell 回归、T24 本地 Git 失败重试、shell/YAML 语法与 pin 一致性检查通过。原生样本名称旅程、文件动作/Quick Look、深浅模式、受限真实 Engine 生命周期/panic 恢复及受控正文旅程均通过。GUI 与 Engine Seatbelt 验证在外层执行沙箱之外运行，范围仍限制在项目内受控样本。未将这些结果外推为真实 TCC、Intel/macOS 13、CI 下载或正式发行验收。

规范复核：发现的实现问题已修复，最终无未修复项。规格复核：发现的 T24 重试错误已修复，剩余为上述用户明确延期的入口及外部验收条件。

