# [SPEC-05] v0.1：原生搜索配置与结果列表交互

## Problem Statement

普通用户需要直观输入、筛选和浏览结果，CLI 语法和静态界面不能交付真实搜索体验。延迟响应、全量排序与变化刷新还可能打断操作。

## Solution

实现 SwiftUI + AppKit 原生窗口，提供紧凑搜索配置、渐进展开筛选和真实分页结果列表，通过统一服务呈现异步查询与稳定选择。

## User Stories

1. As a user, I want a clear name-search input, so that I can start without learning query syntax.
2. As a user, I want case-insensitive containment by default, so that predictable matches appear.
3. As a user, I want an explicit fuzzy option, so that approximate names are searchable.
4. As a user, I want prefix, suffix, and whole-name modes, so that I can choose the intended match.
5. As a user, I want literal punctuation in normal mode, so that a colon or quote in a name does not change my filters.
6. As a user, I want internal-disk, home, and selected-folder scopes, so that I can control the search area.
7. As a user, I want kind, extension, size, and time filters, so that I can narrow a broad query.
8. As a user, I want individual and all-filter clearing, so that I can recover from overly narrow conditions.
9. As a user, I want an empty-search prompt, so that launch does not unexpectedly enumerate every file.
10. As a user, I want filter-only searches, so that I can find files without remembering a name.
11. As a user, I want name, location, indexed size, and modification columns, so that results are easy to compare.
12. As a user, I want click-to-sort columns, so that I can select the most useful global order.
13. As a user, I want visible sorting and partial-result states, so that ongoing work is not mistaken for completion.
14. As a user, I want hidden results visible by default with an explicit switch, so that files are not silently omitted.
15. As a user, I want later pages from the same snapshot, so that scrolling does not corrupt result order.
16. As a keyboard user, I want search focus and arrow selection, so that I can work without the mouse.
17. As a user, I want selection retained during file changes, so that refresh does not move me to an unrelated file.
18. As a VoiceOver user, I want named controls and sort announcements, so that I can operate the application.

## Implementation Decisions

- 原生三区域窗口：紧凑搜索配置、主要宽度的结果区、可调整并隐藏的检查器；保留底部所选文件路径，不复制参考应用视觉。
- SwiftUI 负责配置和窗口组合，AppKit 负责高密度列表等必要原生交互；不建设通用跨平台 UI 架构。
- 通过已验证的服务组合结构化普通查询与基础筛选；高级模式明确启用，不能自动解释普通输入。
- 包含默认名称自然升序，模糊默认关联性；用户选择排序后保留，列头切换升降序。
- 空输入无有效筛选时显示提示；默认范围和隐藏项设置不单独触发全量查询。
- 使用请求代次和快照防止旧响应覆盖；默认全部已索引结果可见，文件变化合并刷新并按路径恢复选择。
- 默认键盘入口包含聚焦搜索、上下结果选择和菜单可发现的动作；深浅模式、可读选中状态和可访问性遵循原生行为。

## Testing Decisions

- 主接缝验证查询/筛选/排序契约，并以少量窗口端到端测试验证输入、空态、列头和选中后的可见行为。
- 受控真实 fixture 覆盖中文、标点、仅筛选、隐藏项、未知值与跨页；不测试私有 View 结构或重复写查询算法。
- 注入快慢响应与目录变化，检查新查询不会被旧结果覆盖，当前页状态与完整性一致。
- 通过真实原生窗口验证键盘、VoiceOver、检查器隐藏/调整和深浅模式；当前仓库无既有 UI 测试先例。
- 验收包含每个模式/过滤组合、用户排序保留、无结果与错误区分、主线程交互可用及稳定选择。

## Out of Scope

- 检查器内部和系统文件动作的完整实现、内容搜索、网格/树形视图、全局快捷键、菜单栏模式。

## Further Notes

- 总规格：Part of #1。
- 阻塞依赖：Blocked by: #3、#5、#4。
- Spec ID：SPEC-05。
- 阶段：M2 / v0.1。
- 依据已确认选择：Q3、Q2、Q4、Q10、Q12、Q14、Q15、Q16、Q17。
- 前置规格：SPEC-02、SPEC-03、SPEC-04。
- M1 门禁未通过前可细化界面，不能把模拟数据窗口标成 alpha 完成。

