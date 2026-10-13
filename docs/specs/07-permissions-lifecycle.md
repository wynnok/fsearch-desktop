# [SPEC-07] v0.1：权限引导、索引状态与窗口生命周期

## Problem Statement

用户可能在权限不完整或初次索引时得不到期望结果；关闭窗口和退出含义也不同。没有明确状态会让用户把覆盖限制当成搜索失效。

## Solution

实现可跳过的首次权限说明、诚实的索引与错误状态，以及关闭窗口继续运行、退出结束客户端的已确认生命周期。

## User Stories

1. As a new user, I want to understand why disk access matters, so that I can choose whether to grant it.
2. As a new user, I want to skip permission setup, so that I can try existing coverage first.
3. As a user, I want persistent restricted-coverage status, so that I know why some files are absent.
4. As a user, I want a later authorization entry, so that I can improve coverage when ready.
5. As a user, I want rechecking after authorization, so that new access is reflected honestly.
6. As a user, I want indexing distinguished from searching, so that I understand what the application is doing.
7. As a user, I want name-index readiness distinguished from content-index work, so that one status does not promise both.
8. As a user, I want errors distinguished from no matches, so that I can recover appropriately.
9. As a user, I want indexing progress without invented percentages, so that feedback remains credible.
10. As a user, I want closing the window to preserve indexing, so that returning is quick and fresh.
11. As a user, I want reopening to restore the window, so that the running application is accessible.
12. As a user, I want Quit to end the client, so that I can stop its work.
13. As a user, I want login startup off by default, so that background launch is my decision.
14. As a CLI user, I want external processes left alone, so that quitting the desktop app does not interrupt unrelated tools.
15. As a user, I want default content-index behavior explained, so that the name-only alpha's background activity is transparent.

## Implementation Decisions

- 首次说明完全磁盘访问能增加的覆盖，允许跳过；后续入口提供系统授权指引和重新检查，不程序化修改 TCC。
- 索引初始化、名称就绪、内容工作、查询/排序中、无结果、错误与受限覆盖为不同可见状态。
- 真实权限行为依据 M1 签名应用验证；full_disk_access 状态不能单独证明所有位置可读，动态 skip 限制按上游能力处理。
- 关闭窗口只隐藏/关闭窗口并继续引擎；重新打开恢复；⌘Q 完全退出自身应用，不结束外部 CLI。
- 开机启动默认关闭，不自动安装 LaunchAgent；后续启用能力只使用明确用户选择和原生机制。
- 对持续索引变更合并呈现，删除所选文件给出原因，状态更新不打断输入。

## Testing Decisions

- 从公开服务状态与原生窗口验证状态转换，不直接检查上游 OnceLock 或线程内部。
- 使用 M1 真实权限证据复核初始跳过、授权、撤销与重启；缺少正式测试环境不标记通过。
- 窗口关闭、重开、菜单退出、错误重试和外部 CLI 共存通过必要原生冒烟。
- 参考上游 follower 状态及当前交互状态清单；没有客户端状态测试先例，优先同一服务驱动的可见行为。
- 验收要求状态没有伪造百分比/完成时间，权限受限与无结果不会混用，后台与退出遵循已确认规则。

## Out of Scope

- 后台独立 daemon 安装、自动改变隐私权限、外接盘覆盖、全局快捷键和菜单栏模式。

## Further Notes

- 总规格：Part of #1。
- 阻塞依赖：Blocked by: #5、#6。
- Spec ID：SPEC-07。
- 阶段：M2 / v0.1。
- 依据已确认选择：Q5、Q9、Q10、Q11、Q17、Q22。
- 前置规格：SPEC-03、SPEC-05。
- 保持默认内容索引并不承诺首版开放内容查询入口。

