# [SPEC-06] v0.1：检查器、Quick Look 与 Finder 路径导航

## Problem Statement

用户找到名称后仍需确认文件属性和位置，并迅速打开文件或所在目录。异步元数据和预览可能晚返回，错误路径也不能被静默忽略。

## Solution

让结果选择联动原生检查器和底部路径导航，按需读取真实元数据，提供 Quick Look、打开、Finder 显示和复制路径操作。

## User Stories

1. As a user, I want the inspector to follow my selection, so that I can understand the current file.
2. As a user, I want a native file icon and type, so that I can recognize what I found.
3. As a user, I want actual file size in the inspector, so that compressed index precision does not mislead details.
4. As a user, I want creation and modification dates, so that I can judge file relevance.
5. As a user, I want unavailable attributes shown as unknown, so that failures are not presented as zero values.
6. As a user, I want stale metadata discarded, so that rapid selection never shows the previous file's details.
7. As a user, I want a readable complete location, so that identical names can be distinguished.
8. As a user, I want clickable ancestor folders, so that I can open the desired location in Finder.
9. As a user, I want long paths collapsed without losing access to ancestors, so that navigation remains usable.
10. As a user, I want Finder reveal, so that the found item is selected in its parent folder.
11. As a user, I want open by double-click or Return, so that I can act immediately.
12. As a user, I want copy path, so that I can use the location elsewhere.
13. As a user, I want Space to open Quick Look, so that I can preview before opening.
14. As a user, I want deleted or inaccessible files explained, so that a failed action has a clear cause.
15. As a user, I want packages and symbolic links identified, so that their behavior is not confused with ordinary files.
16. As a user, I want multi-selection shown honestly, so that the inspector does not invent a combined file.

## Implementation Decisions

- 检查器立即显示已知结果字段，元数据与预览惰性异步加载；返回时核验所选路径，限制图标/属性并发。
- 展示名称、图标、类型、实际大小、创建/修改时间和完整位置；未知/不可访问显示明确状态，文件夹大小不是递归占用。
- 使用 NSWorkspace 等原生能力打开、显示和导航；点击路径文件夹与显示文件本身为不同动作。
- 使用系统 Quick Look；可预览的格式不扩大 Fsearch 文本内容搜索能力，索引不通过预览自动下载云端文件。
- 符号链接和应用包明确呈现；用户动作交给系统，不在客户端新增文件遍历或索引。
- 多选先展示数量与共有位置，长路径折叠中间层级但保留完整访问和复制能力。
- 扩展属性属于按需客户端呈现，不改变名称搜索匹配或大小筛选算法。

## Testing Decisions

- 通过公开选择/详情状态和真实受控文件验证元数据结果；快速切换选择注入晚返回，不断言缓存内部结构。
- 用原生冒烟验证每级路径、根目录、长路径菜单、打开、Finder reveal、复制路径和 Quick Look。
- 覆盖不存在、权限失败、目录、应用包、符号链接、多选和索引大小/实际大小差异。
- 参考当前交互决策和上游 Found 字段边界；仓库没有既有原生文件动作测试，补充必要冒烟而非另建复杂测试框架。
- 验收要求所选对象一致、动作目标准确、错误可理解，预览支持不被描述成引擎正文支持。

## Out of Scope

- 重命名、删除、移动、批量文件管理，首版所有者/权限/访问时间扩展，独立文档解析或 OCR。

## Further Notes

- 总规格：Part of #1。
- 阻塞依赖：Blocked by: #6。
- Spec ID：SPEC-06。
- 阶段：M2 / v0.1。
- 依据已确认选择：Q2、Q13、Q21。
- 前置规格：SPEC-05。
- 诊断导出不得携带此检查器读取的完整路径或正文。

