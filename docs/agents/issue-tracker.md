# Issue tracker: GitHub

仓库：wynnok/fsearch-desktop。需求、规格和缺陷使用 GitHub Issues。
使用 gh CLI，仓库由 git remote 推断；尚未关联时显式使用
`--repo wynnok/fsearch-desktop`。

- 创建：`gh issue create --title "..." --body-file <file>`
- 读取：`gh issue view <number> --json number,title,body,labels,comments`
- 列表：`gh issue list --state open --json number,title,body,labels`
- 评论：`gh issue comment <number> --body-file <file>`
- 标签：`gh issue edit <number> --add-label "..." / --remove-label "..."`
- 关闭：`gh issue close <number>`
- 子任务：使用 GitHub 原生 sub-issues；不可用时用 `Part of #<parent>`
  和父 Issue 的任务列表关联。
- 依赖：使用 GitHub 原生 issue dependencies；不可用时在正文记录
  `Blocked by: #<number>`。
- Wayfinder：用 `wayfinder:map` 标识规划 Issue，子任务使用
  `wayfinder:research/prototype/grilling/task`；处理前认领，完成后记录结论。

## Pull requests as a triage surface

**PRs as a request surface: no.**

技能要求 publish to the issue tracker 时创建 GitHub Issue；
要求 fetch the relevant ticket 时读取对应 Issue。

