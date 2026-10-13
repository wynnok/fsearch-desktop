# Fsearch Desktop 执行 Tickets

33 张纵向切片已由用户确认并发布，覆盖现有 13 个子 Spec，包含 141 项验收条件和 55 条原生阻塞边。

- 所有 Ticket 均标记 `ready-for-agent`，归属对应 Spec 的原生子 Issue。
- [T01 / #15](https://github.com/wynnok/fsearch-desktop/issues/15) 是当前唯一无阻塞执行票；工作从其开始，随后只领取阻塞项都已完成的票。
- 执行状态以 GitHub 为准，本地保存正文副本；父 Spec 的标题、正文、标签和状态没有被本次拆分编辑或关闭。
- Spec 的整体依赖保留，Ticket 的前置只指向真正需要的能力，不把自身父 Spec 关闭设为前置。跨 Spec 验收关系写在各票 Parent 中，不能仅凭直接子票计数断言 Spec 全部满足。
- 尚未开始实现、执行索引扫描、创建构建工作流或发布安装包。本次授权为 Tickets 拆分与发布。

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

