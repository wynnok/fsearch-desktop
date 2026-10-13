# [SPEC-08] v0.1：本地设置、主动诊断导出与手动更新入口

## Problem Statement

用户需要可控的本地数据、可用的排障信息和获取新客户端的入口。直接导出引擎日志可能泄露完整文件路径，自动记录历史也违背已确认的默认行为。

## Solution

保存必要本地设置，默认不持久保存查询历史；提供用户主动触发、脱敏的诊断导出，以及检查更新和下载安装链接。

## User Stories

1. As a user, I want settings stored locally, so that my preferences survive without an account.
2. As a user, I want search history not persisted by default, so that past queries are not silently retained.
3. As a user, I want current window state kept while the app runs, so that closing and reopening does not lose my work.
4. As a user, I want clear separation between settings and history, so that storing a preference does not store a query.
5. As a user, I want diagnostic export to be explicit, so that information is shared only by my action.
6. As a user, I want diagnostic contents described before export, so that I know what I am saving.
7. As a user, I want full paths removed from exported diagnostics, so that personal file locations are not included by default.
8. As a user, I want file contents excluded from diagnostics, so that document text is not exported.
9. As a maintainer, I want useful version and error categories, so that redacted diagnostics can still support debugging.
10. As a user, I want a check-for-updates entry, so that I can discover a newer client.
11. As a user, I want a release download link, so that I can update manually.
12. As a user, I want my installed application left unchanged until I update it, so that checking does not silently replace software.
13. As a user, I want client and engine versions displayed, so that I can relate an installation to release notes.

## Implementation Decisions

- 本地保存设置，默认不持久化查询历史；进程内输入/选择不视为跨启动历史，不引入账号或远程同步。
- 主动诊断导出说明可保留的版本、系统、架构和错误类别；默认剔除完整路径与文件正文。
- 上游 stderr 和错误信息在导出前处理，不原样打包；用户可见错误仍保留足以操作的说明，不以脱敏隐藏失败。
- 首版检查更新提供版本信息或可用下载入口，由用户从 Releases 手动安装；不实现运行时引擎替换。
- 数据与导出遵循项目隔离、索引独立和用户主动操作约定。

## Testing Decisions

- 重启受控应用验证设置恢复与查询历史默认不保存；不以私有存储格式作为断言。
- 导出含标点、Unicode、多行和引擎错误的诊断样本，检查完整路径与正文不会出现在最终产物中，同时可追溯版本。
- 原生冒烟验证主动导出、更新菜单和下载链接；检查更新失败不得替换安装或阻塞搜索。
- 仓库没有持久化/诊断先例；沿用公开应用行为与成品内容验证，避免额外底层接缝。
- 验收要求默认历史策略、脱敏输出和手动更新行为可由外部观察证明。

## Out of Scope

- 保存查询功能、自动上传诊断、账号同步、自动下载安装和自动替换引擎。

## Further Notes

- 总规格：Part of #1。
- 阻塞依赖：Blocked by: #6。
- Spec ID：SPEC-08。
- 阶段：M2 / v0.1。
- 依据已确认选择：Q20、Q21。
- 前置规格：SPEC-05。
- 无正式新版本时仍可打开项目 Releases；不能伪造存在的更新版本。

