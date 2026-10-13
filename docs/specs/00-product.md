# [SPEC-00] Fsearch Desktop 产品总规格与阶段验收

## Problem Statement

普通 macOS 用户需要像 Everything 一样直接找到文件，并看清文件信息与所在位置。现有仓库尚无客户端，实现必须依托 Fsearch，同时满足原生交互、完整结果排序、两种芯片和持续跟进上游。

## Solution

交付独立的 SwiftUI + AppKit 搜索应用。先验证公开 Fsearch Engine 的薄桥接，再完成 v0.1 名称搜索与文件操作；v0.2 增加已明确范围的文本内容搜索。将实现、验收、安装和上游升级拆成有依赖的子规格。

## User Stories

1. As a macOS user, I want an independent search application, so that I can find files without first opening Finder.
2. As a macOS user, I want native windows and controls, so that the application fits familiar desktop interactions.
3. As a macOS user, I want case-insensitive name containment by default, so that ordinary searches behave predictably.
4. As a macOS user, I want an explicit fuzzy-search option, so that I can find files when I remember their names imperfectly.
5. As a macOS user, I want basic filters, so that I can narrow results by kind, extension, size, and modification time.
6. As a macOS user, I want to search covered internal-disk locations, so that I can locate files across my Mac.
7. As a macOS user, I want folder-scoped searches, so that I can focus on a known location.
8. As a macOS user, I want honest coverage information, so that permission limits are not mistaken for missing files.
9. As a macOS user, I want to skip initial permission setup, so that I can try the application before granting more access.
10. As a macOS user, I want global sorting, so that results outside the first page are ordered correctly.
11. As a macOS user, I want natural name ordering, so that file2 appears before file10.
12. As a macOS user, I want truthful counts and completion states, so that partial results are not presented as exhaustive.
13. As a macOS user, I want asynchronous searches and sorting, so that the interface remains usable.
14. As a macOS user, I want stable selection during refresh, so that file changes do not move me to an unrelated item.
15. As a macOS user, I want a file inspector, so that I can understand the selected file.
16. As a macOS user, I want Quick Look, so that I can preview a file before opening it.
17. As a macOS user, I want clickable path navigation, so that I can open an ancestor folder in Finder.
18. As a macOS user, I want open, reveal, and copy-path actions, so that I can use a search result immediately.
19. As a macOS user, I want indexing to continue after closing the window, so that reopening does not lose freshness.
20. As a macOS user, I want quitting to end the application, so that I retain control over background resource use.
21. As a macOS user, I want local settings and explicit diagnostic export, so that my file information is handled predictably.
22. As a macOS user, I want an update entry and download link, so that I can install a newer client.
23. As an Intel Mac user, I want the same features as Apple Silicon users, so that hardware choice does not change the product.
24. As a tester, I want reproducible development installers, so that I can verify the real application.
25. As a public user, I want signed and notarized releases, so that I can install a verified distribution.
26. As a maintainer, I want daily detection of upstream releases, so that Fsearch improvements can reach the client promptly.
27. As a maintainer, I want traceable temporary patches, so that upstream upgrades remain manageable.
28. As a future content-search user, I want supported text search, so that I can locate files from words inside them.

## Implementation Decisions

- 以 Fsearch 为唯一搜索与索引引擎；优先 Rust staticlib + 薄 C ABI 调用公开 Engine，保留独立依赖版本和客户端独立索引。
- v0.1 包含名称搜索、基础筛选、三字段全局排序、检查器、Quick Look、Finder 路径操作、窗口生命周期、手动更新入口和主动诊断导出。
- 首版覆盖内置磁盘已收录位置；默认包含匹配、隐藏项可见；空输入无有效筛选时不全量查询；完整排序可异步。
- 大小筛选与排序沿用索引大小，检查器提供实际大小；首版保留上游默认内容索引行为，公开说明并测量成本。
- 支持目标为 macOS 13+，两种芯片功能一致；普通 push 生成开发包，版本 tag 经发行门禁进入 Releases。
- 上游正式版每日检测，升级 PR 自动生成并验证，由维护者合并；每版客户端锁定引擎版本，临时补丁可撤销且有移除条件。
- 本总规格聚合进度与阶段门禁，实际开发执行子规格，避免将整个产品作为单个不可验收的大任务。

## Testing Decisions

- 主接缝为 Swift 侧引擎服务公开契约；使用真实 Fsearch 的受控样本，只断言外部查询、快照、分页、状态与通知行为。
- 系统文件操作、权限和安装发行使用必要的原生冒烟与成品验证，避免复制多套底层测试接缝。
- 仓库当前没有客户端代码或测试；上游已有大 limit、Unicode 内容、目录删除、挂载点和 follower 等测试作为参考，不把其通过等同于客户端通过。
- 验收包括超过 20,000 条完整匹配、自然排序、过期响应、刷新选择、权限前后、独立索引、两架构、最低系统和真实安装。
- 每项测试留存样本、版本、设备、命令与结果；当前无实现，所有门禁均未验证。

## Out of Scope

- Finder 增强插件、另一套搜索引擎、长期维护自有搜索内核。
- 首版外接盘/网络盘、PDF/Office/OCR 正文搜索、自动下载安装、Git/符号功能、网格/树形视图。
- 未确认的 v0.2 保存查询、完整预览和其他 P2 功能不借本次拆分扩大范围。

## Further Notes

- Spec ID：SPEC-00。
- 阶段：总规格。
- 依据已确认选择：Q1、Q2、Q3、Q4、Q5、Q6、Q7、Q8、Q9、Q10、Q11、Q12、Q13、Q14、Q15、Q16、Q17、Q18、Q19、Q20、Q21、Q22、Q23。
- 前置规格：无。
- 上游调查固定在 0.2.1 / 88e63fdf850cf7749deae8198b187accd21f8ba5；未来更新重新验证，不长期冻结。
- 设计访谈 23 项选择已确认；本次只产出并发布规格，不表示开始开发、配置自动化或已产生安装包。
- ready-for-agent 表示规格已整理，不免除前置依赖、真实技术门禁及签名/设备条件。

### 子规格与前置依赖

- [ ] #2 M1：可升级 Fsearch 集成与 Swift 引擎服务契约（无前置）
- [ ] #3 M1：完整结果快照、全局排序与分页（Blocked by: #2）
- [ ] #5 M1：真实 Engine 生命周期、权限与资源验证（Blocked by: #2、#4）
- [ ] #4 M1：双架构构建、链接与最低系统验证（Blocked by: #2）
- [ ] #6 v0.1：原生搜索配置与结果列表交互（Blocked by: #3、#5、#4）
- [ ] #7 v0.1：检查器、Quick Look 与 Finder 路径导航（Blocked by: #6）
- [ ] #8 v0.1：权限引导、索引状态与窗口生命周期（Blocked by: #5、#6）
- [ ] #9 v0.1：本地设置、主动诊断导出与手动更新入口（Blocked by: #6）
- [ ] #10 DevOps：可安装开发 DMG 与持续集成（Blocked by: #4、#6、#7、#8、#9）
- [ ] #13 Release：签名公证、版本 tag 与正式安装验收（Blocked by: #10、#12）
- [ ] #11 Maintenance：每日上游检测与升级 PR 兼容性门禁（Blocked by: #2、#3、#5、#4）
- [ ] #12 v0.1：端到端验收、用户文档与已知限制（Blocked by: #6、#7、#8、#9、#10、#11）
- [ ] #14 v0.2：受支持文本内容搜索与匹配片段（Blocked by: #12）

执行顺序从 #2 开始，按 GitHub 原生阻塞关系推进。总规格用于聚合，不重复实现子规格。签名凭据、最低系统与 Intel 实机等验收条件必须保留未验证状态，不能以标签代替证据。

