# [SPEC-13] v0.2：受支持文本内容搜索与匹配片段

## Problem Statement

名称之外的文本线索可以帮助用户定位文件，但不能把 Fsearch 的文本 grep 描述为任意文档全文检索。分页、预算和片段范围也不同于名称搜索。

## Solution

在已验证的客户端服务中开放 Fsearch 支持的文本内容查询，复用现有搜索范围与筛选，按文件展示匹配行，保留来源、继续位置和未完成语义。

## User Stories

1. As a content-search user, I want to enter a text pattern, so that I can find files by words inside them.
2. As a user, I want content search explicitly identified, so that it is distinct from name search.
3. As a user, I want supported text formats explained, so that I do not expect PDF or Office extraction.
4. As a user, I want existing scope and filters reused, so that I can narrow content candidates.
5. As a user, I want literal and regex modes identified, so that I choose the intended pattern behavior.
6. As a user, I want case behavior explained, so that matches are predictable.
7. As a user, I want results grouped by file, so that multiple matching lines do not inflate file counts.
8. As a user, I want matching lines and context, so that I can judge relevance before opening.
9. As a user, I want safe Unicode highlights, so that Chinese and emoji ranges render correctly.
10. As a user, I want index and direct-scan sources distinguished, so that coverage limitations remain understandable.
11. As a user, I want budget exhaustion shown as incomplete, so that found files are not presented as all matches.
12. As a user, I want a continue action, so that I can resume a partial content query.
13. As a user, I want content cursors kept separate from name offsets, so that paging does not skip or duplicate content results.
14. As a user, I want pattern errors preserved with my input, so that I can correct them.
15. As a user, I want existing file actions available, so that a content result can be opened or revealed.
16. As a user, I want diagnostics to exclude snippets, so that content search does not export my text.

## Implementation Decisions

- 在统一客户端引擎服务增加上游 Grep 的公开查询/响应契约，不复制 trigram、候选筛选或文本匹配算法。
- 复用已有范围和基础筛选；支持既有文档明确的字面/正则及大小写选项，错误保留输入。
- 内容查询的一文件一结果与正文匹配分开呈现；来源、候选/读取统计、complete、next 和预算状态保持上游语义。
- 内容继续位置不是名称 offset；分页完整性同时考虑 next 与预算，complete 不自动代表已显示所有匹配。
- UTF-8 字节范围转为安全的原生文本范围，处理截断片段与组合字符，不猜测名称模糊高亮。
- 只承诺符合 Fsearch 准入的文本；范围回退直接读取、大小/生成文件/忽略规则和云端缺失明确说明。
- 保留查询代次、快照隔离、选择和现有文件动作；片段和路径不默认进入诊断导出。

## Testing Decisions

- 从同一服务主接缝用真实受控文本测试 literal/regex、大小写、范围、过滤、匹配行、预算、继续位置及来源行为。
- 覆盖中文、emoji、NFC/NFD、CRLF、截断范围、无匹配、非法正则、修改内容和多行同文件。
- 独立核对文件数量与内容匹配数量，验证预算耗尽提示和 cursor 续查不混用名称分页。
- 参考上游 CRLF、非 ASCII 大小写内容匹配和 MCP cursor 测试；上游通过不替代 Swift 范围转换与 UI 结果验证。
- 原生冒烟验证内容入口、匹配片段、继续、打开/预览以及诊断脱敏；不能因 Quick Look 可预览 PDF 而声称引擎可搜其正文。

## Out of Scope

- PDF/Office 正文抽取、OCR、压缩包正文、自研内容索引、保存查询/历史、符号/Git 模式和未确认的 beta 扩展。

## Further Notes

- 总规格：Part of #1。
- 阻塞依赖：Blocked by: #12。
- Spec ID：SPEC-13。
- 阶段：M3 / v0.2 核心已定范围。
- 依据已确认选择：Q2、Q21、Q22。
- 前置规格：SPEC-12。
- 只拆已讨论并可由上游实现的内容核心；更细 beta 视觉设计按现有原生样式收敛，不借本规格扩大首版。

